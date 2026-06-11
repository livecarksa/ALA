"""محاكي يوم تسوية كامل: انقطاع شبكة، تحويلات جهاز-لجهاز، ثم عودة الاتصال.

يحاكي السيناريو الجوهري في دراسة الجدوى: مدينة تسقط شبكتها، يتبادل
الناس توكنات موقّعة بالبلوتوث وQR، وبينهم مهاجم يحاول إنفاقاً مزدوجاً
بتفريع سلسلته، ثم تعود الشبكة فتُسوّى الدفعة ويُكشف الاحتيال.

التشغيل:  python3 -m settlement.simulator [--seed N] [--users N]
"""

from __future__ import annotations

import argparse
import random
import time

from token_engine.token import SignedToken
from token_engine.wallet import OfflineWallet

from .engine import ARABIC_REASONS, SettlementEngine


def fmt_sdg(piasters: int) -> str:
    return f"{piasters / 100:,.2f} جنيه"


def run_simulation(seed: int = 7, users: int = 8, verbose: bool = True) -> dict:
    rng = random.Random(seed)
    now = int(time.time())
    engine = SettlementEngine()
    log: list[str] = []

    def say(line: str) -> None:
        log.append(line)
        if verbose:
            print(line)

    say("═" * 62)
    say("محاكي تسوية وصلة — يوم انقطاع كامل للشبكة")
    say("═" * 62)

    # 1) التسجيل والإيداع عبر الوكلاء (قبل سقوط الشبكة)
    wallets: list[OfflineWallet] = []
    for i in range(users):
        wallet = OfflineWallet()
        account = engine.register_device(wallet.keys.public_key_hex, wallet.daily_cap)
        deposit = rng.randrange(50_000, 300_000, 5_000)  # 500 – 3,000 جنيه
        engine.cash_in(wallet.device_id, deposit, f"deposit-u{i}")
        wallet.apply_settlement(deposit, account.chain_anchor)
        wallets.append(wallet)
    merchant = wallets[0]  # التاجر: يستقبل ولا يرسل في هذا اليوم
    say(f"\n[1] سُجّل {users} أجهزة وأودعت أرصدة عبر الوكلاء — التاجر: {merchant.device_id}")

    # 2) سقوط الشبكة: تحويلات جهاز-لجهاز عبر بلوتوث/QR
    say("\n[2] الشبكة ساقطة — تحويلات أوف لاين موقّعة:")
    transfers = 0
    for _ in range(users * 3):
        sender = rng.choice(wallets[1:])
        recipient = merchant if rng.random() < 0.5 else rng.choice(wallets)
        if recipient.device_id == sender.device_id:
            continue
        amount = rng.randrange(1_000, 20_000, 500)
        if amount > sender.offline_balance or sender.spent_today(now) + amount > sender.daily_cap:
            continue
        token = sender.send(recipient.device_id, amount, now=now)
        recipient.receive(token, now=now)
        transfers += 1
        say(f"    {sender.device_id} ← {fmt_sdg(amount)} → {recipient.device_id}")

    # 3) المهاجم: يفرّع سلسلته — نفس prev_hash لتوكنين مختلفين (إنفاق مزدوج)
    attacker = wallets[-1]
    victim_a, victim_b = wallets[1], wallets[2]
    fork_amount = min(10_000, attacker.offline_balance)
    legit = attacker.send(victim_a.device_id, fork_amount, now=now)
    victim_a.receive(legit, now=now)
    forged = SignedToken.create(  # يتجاوز المحفظة ويوقّع فرعاً ثانياً من نفس النقطة
        keys=attacker.keys,
        recipient_id=victim_b.device_id,
        amount=fork_amount,
        seq=legit.seq,
        prev_hash=legit.prev_hash,
        issued_at=now + 1,
        ttl_seconds=72 * 3600,
    )
    victim_b.receive(forged, now=now + 1)
    say(f"\n[3] هجوم إنفاق مزدوج: {attacker.device_id} فرّع سلسلته نحو "
        f"{victim_a.device_id} و{victim_b.device_id} بمبلغ {fmt_sdg(fork_amount)} لكل فرع")

    # 4) عودة الشبكة: كل الأجهزة ترفع توكناتها للتسوية
    batch: list[dict] = []
    for wallet in wallets:
        batch.extend(wallet.tokens_for_settlement())
    report = engine.settle_batch(batch, now=now + 3600)

    say(f"\n[4] عادت الشبكة — رُفع {len(batch)} سجل توكن للتسوية")
    say("─" * 62)
    say(f"    سُوّي نهائياً : {len(report.settled)} توكن بقيمة {fmt_sdg(report.settled_amount)}")
    dup = sum(1 for _, r in report.rejected if r == "DUPLICATE")
    say(f"    مكرر (رفعه الطرفان): {dup} — سُوّي مرة واحدة فقط")
    real_rejects = [(t, r) for t, r in report.rejected if r != "DUPLICATE"]
    say(f"    مرفوض        : {len(real_rejects)}")
    for token, reason in real_rejects:
        say(f"      • {token.token_id[:8]} ({fmt_sdg(token.amount)}): {ARABIC_REASONS[reason]}")
    for device_id in report.fraud_alerts:
        say(f"    ⚠ جُمّد الحساب {device_id} — إنفاق مزدوج مكشوف بسلسلة التوقيعات")

    trial = engine.ledger.trial_balance()
    say("─" * 62)
    say(f"    ميزان المراجعة (مزدوج القيد): {trial} — {'متوازن ✓' if trial == 0 else 'خلل ✗'}")
    say(f"    رصيد التاجر بعد التسوية: {fmt_sdg(engine.balance(merchant.device_id))}")
    say("═" * 62)

    return {
        "transfers": transfers,
        "settled": len(report.settled),
        "rejected": len(real_rejects),
        "fraud_alerts": list(report.fraud_alerts),
        "trial_balance": trial,
        "log": log,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="محاكي تسوية وصلة")
    parser.add_argument("--seed", type=int, default=7, help="بذرة عشوائية لإعادة إنتاج السيناريو")
    parser.add_argument("--users", type=int, default=8, help="عدد الأجهزة في المحاكاة")
    args = parser.parse_args()
    run_simulation(seed=args.seed, users=args.users)


if __name__ == "__main__":
    main()
