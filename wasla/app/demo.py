"""العرض الحي — مُخرج البوابة الثانية حرفياً (القسم 10 من الدراسة):

«تحويل أوف لاين كامل بين جهازين وتسويته عبر بيئة الاختبار»

السيناريو: مغترب في السعودية حوّل لأمه في بورتسودان عبر وصلة،
رصيدها وصل قبل سقوط الشبكة. تسقط الشبكة أسبوعاً: تدفع للبقّال
بمسح QR، وترسل لأخيها صاحب الهاتف العادي عبر SMS. تعود الشبكة
فيُسوّى كل شيء داخل بيئة اختبار بنكك (HTTP + SQLite معمّرة)
ويُطابَق الدفتر.

التشغيل:  python3 -m app.demo
"""

from __future__ import annotations

import tempfile
import time
import uuid
from pathlib import Path

from gateway.client import GatewayClient
from gateway.sandbox import BankakSandbox
from token_engine.wallet import OfflineWallet
from transport import SmsReassembler, qr_payload, read_qr_payload, to_sms_segments


def sdg(piasters: int) -> str:
    return f"{piasters / 100:,.2f} جنيه"


def run_demo(verbose: bool = True, db_path: str | None = None) -> dict:
    log: list[str] = []

    def say(line: str = "") -> None:
        log.append(line)
        if verbose:
            print(line)

    if db_path is None:
        db_path = str(Path(tempfile.mkdtemp(prefix="wasla-demo-")) / "sandbox.db")
    now = int(time.time())

    say("═" * 64)
    say("وصلة — عرض البوابة الثانية: تحويل أوف لاين كامل وتسويته")
    say("═" * 64)

    active: list[BankakSandbox] = []  # لإغلاق أي خادم مفتوح مهما حدث

    try:
        return _run_demo_body(now, db_path, say, log, active)
    finally:
        for box in active:
            box.stop()


def _run_demo_body(now, db_path, say, log, active) -> dict:
    # ── [1] بيئة اختبار بنكك تعمل (HTTP + SQLite معمّرة)
    sandbox = BankakSandbox(db_path=db_path).start()
    active.append(sandbox)
    bank = GatewayClient(sandbox.base_url)
    say(f"\n[1] بيئة اختبار بنكك تعمل على {sandbox.base_url}")
    say(f"    قاعدة بيانات معمّرة: {db_path}")

    # ── [2] التسجيل والإيداع (الشبكة لا تزال حية)
    mother = OfflineWallet()  # الأم في بورتسودان — هاتف ذكي
    grocer = OfflineWallet()  # البقّال — هاتف ذكي يعرض QR
    brother = OfflineWallet()  # الأخ — هاتف عادي يستقبل SMS فقط

    for wallet, deposit, label in [
        (mother, 150_000, "الأم (وصلها تحويل الشتات: 1,500 جنيه)"),
        (grocer, 0, "البقّال"),
        (brother, 0, "الأخ (هاتف عادي)"),
    ]:
        info = bank.register(wallet.keys.public_key_hex, wallet.daily_cap)
        if deposit:
            bank.cash_in(wallet.device_id, deposit, f"remit-{uuid.uuid4().hex[:8]}")
        wallet.apply_settlement(deposit, info["chain_anchor"])
        say(f"    سُجّل {wallet.device_id} — {label}")

    # ── [3] سقوط الشبكة الكامل
    say("\n[2] ✗ سقطت شبكة الاتصالات بالكامل — لا إنترنت ولا GSM")

    # دفع للبقّال وجهاً لوجه عبر QR
    qr_token = mother.send(grocer.device_id, 35_000, now=now)
    payload = qr_payload(qr_token)
    say(f"\n[3] الأم تدفع للبقّال {sdg(35_000)} عبر QR (حمولة {len(payload)} حرفاً):")
    say(f"    {payload[:56]}…")
    scanned = read_qr_payload(payload)  # كاميرا البقّال
    grocer.receive(scanned, now=now)
    say("    البقّال مسح الرمز وتحقق من التوقيع محلياً ✓ — بلا أي شبكة")

    # تحويل للأخ عبر SMS (يصل لاحقاً عند عودة برج SMS قبل الإنترنت)
    sms_token = mother.send(brother.device_id, 20_000, now=now + 60)
    segments = to_sms_segments(sms_token)
    say(f"\n[4] الأم ترسل لأخيها {sdg(20_000)} عبر SMS ({len(segments)} مقاطع):")
    for segment in segments:
        say(f"    {segment[:64]}…")
    reassembler = SmsReassembler()
    received = None
    for segment in reversed(segments):  # الرسائل تصل بترتيب معكوس — لا يهم
        received = reassembler.feed(segment)
    brother.receive(received, now=now + 120)
    say("    هاتف الأخ جمّع المقاطع (وصلت معكوسة الترتيب) وتحقق ✓")

    say(f"\n    رصيد الأم الأوف لاين الآن: {sdg(mother.offline_balance)}"
        f" — أنفقت اليوم {sdg(mother.spent_today(now))} من سقف {sdg(mother.daily_cap)}")

    # ── [4] عودة الشبكة والتسوية
    say("\n[5] ✓ عادت الشبكة — الأجهزة الثلاثة ترفع توكناتها للتسوية:")
    wallets = {"الأم": mother, "البقّال": grocer, "الأخ": brother}
    for label, wallet in wallets.items():
        tokens = wallet.tokens_for_settlement()
        if not tokens:
            continue
        result = bank.settle(f"{wallet.device_id}-{uuid.uuid4().hex[:8]}", tokens, now=now + 3600)
        say(f"    {label}: رفع {len(tokens)} — سُوّي {len(result['settled'])}"
            f"، مكرر {sum(1 for r in result['rejected'] if r['reason'] == 'DUPLICATE')}")
        info = bank.balance(wallet.device_id)
        anchor = result["new_anchors"].get(wallet.device_id, info["chain_anchor"])
        wallet.apply_settlement(info["balance"], anchor)

    # ── [5] انقطاع كهرباء في البنك — الخادم يعاد تشغيله على نفس القاعدة
    say("\n[6] ⚡ انقطاع كهرباء: بيئة الاختبار تُعاد من قاعدة SQLite نفسها")
    sandbox.stop()
    active.remove(sandbox)
    sandbox2 = BankakSandbox(db_path=db_path).start()
    active.append(sandbox2)
    bank2 = GatewayClient(sandbox2.base_url)

    balances = {label: bank2.balance(w.device_id)["balance"] for label, w in wallets.items()}
    recon = bank2.reconciliation()
    say("    الأرصدة بعد إعادة التشغيل (لا فقد ولا تكرار):")
    for label, balance in balances.items():
        say(f"      {label}: {sdg(balance)}")
    say(f"\n[7] تقرير المطابقة اليومية: {recon['postings_count']} قيداً، "
        f"{recon['settled_tokens']} توكناً مسوّى، "
        f"ميزان المراجعة = {recon['trial_balance']} — "
        f"{'متوازن ✓' if recon['balanced'] else 'خلل ✗'}")
    say("═" * 64)

    return {
        "balances": balances,
        "reconciliation": recon,
        "qr_payload_chars": len(payload),
        "sms_segments": len(segments),
        "log": log,
    }


if __name__ == "__main__":
    run_demo()
