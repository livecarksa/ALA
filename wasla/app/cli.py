"""وصلة — التطبيق المبسط (سطر أوامر، عربي أولاً).

    python3 -m app.cli انشئ   --اسم ali --ايداع 1500
    python3 -m app.cli ارسل   --من ali --الى <device_id> --مبلغ 50 --قناة sms
    python3 -m app.cli استلم  --اسم omer --حمولة "WSLQR1:..." | --مقطع "WSL1|..." ...
    python3 -m app.cli سوّ    --اسم ali
    python3 -m app.cli رصيد   --اسم ali

المحافظ تُخزن كملفات JSON في WASLA_HOME (افتراضياً ./.wasla)،
والبوابة على WASLA_GATEWAY (افتراضياً http://127.0.0.1:8980).
تحذير نموذج أولي: المفتاح الخاص في الملف نصاً صريحاً — في الإنتاج
يبقى داخل البيئة الآمنة للجهاز.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import uuid
from pathlib import Path

from gateway.client import GatewayClient
from token_engine.errors import WaslaError
from token_engine.wallet import OfflineWallet
from transport import SmsReassembler, qr_payload, read_qr_payload, to_sms_segments

DEFAULT_GATEWAY = "http://127.0.0.1:8980"


def wasla_home() -> Path:
    home = Path(os.environ.get("WASLA_HOME", ".wasla"))
    home.mkdir(parents=True, exist_ok=True)
    return home


def wallet_path(name: str) -> Path:
    if not name.replace("_", "").replace("-", "").isalnum():
        raise WaslaError("اسم المحفظة: حروف وأرقام و- و_ فقط")
    return wasla_home() / f"{name}.wallet.json"


def load_wallet(name: str) -> OfflineWallet:
    path = wallet_path(name)
    if not path.exists():
        raise WaslaError(f"لا محفظة باسم «{name}» — أنشئها أولاً بأمر: انشئ")
    return OfflineWallet.from_dict(json.loads(path.read_text(encoding="utf-8")))


def save_wallet(name: str, wallet: OfflineWallet) -> None:
    path = wallet_path(name)
    path.write_text(
        json.dumps(wallet.to_dict(), ensure_ascii=False, indent=1), encoding="utf-8"
    )
    path.chmod(0o600)  # المفتاح الخاص داخله — لصاحب الملف فقط


def client(args) -> GatewayClient:
    return GatewayClient(args.gateway)


def sdg(piasters: int) -> str:
    return f"{piasters / 100:,.2f} جنيه"


def parse_amount(text: str) -> int:
    """مبلغ بالجنيه (يقبل كسور القروش) ← قرش صحيح."""
    from decimal import Decimal, InvalidOperation

    try:
        piasters = int(Decimal(text) * 100)
    except InvalidOperation as exc:
        raise WaslaError(f"مبلغ غير مفهوم: {text}") from exc
    if piasters <= 0:
        raise WaslaError("المبلغ يجب أن يكون موجباً")
    return piasters


# ---------- الأوامر ----------

def cmd_create(args) -> None:
    path = wallet_path(args.name)
    if path.exists():
        raise WaslaError(f"المحفظة «{args.name}» موجودة")
    wallet = OfflineWallet()
    info = client(args).register(wallet.keys.public_key_hex, wallet.daily_cap)
    wallet.apply_settlement(0, info["chain_anchor"])
    if args.deposit:
        amount = parse_amount(args.deposit)
        client(args).cash_in(wallet.device_id, amount, f"deposit-{uuid.uuid4().hex[:8]}")
        wallet.offline_balance = amount
    save_wallet(args.name, wallet)
    print(f"أُنشئت محفظة «{args.name}» — معرّف الجهاز: {wallet.device_id}")
    if args.deposit:
        print(f"أُودع {sdg(wallet.offline_balance)} عبر الوكيل — متاح للإنفاق الأوف لاين")


def cmd_send(args) -> None:
    wallet = load_wallet(args.sender)
    amount = parse_amount(args.amount)
    token = wallet.send(args.recipient, amount)
    save_wallet(args.sender, wallet)
    print(f"وُقّع توكن بمبلغ {sdg(amount)} إلى {args.recipient}")
    if args.channel == "qr":
        print("\nاعرض هذه الحمولة كرمز QR للمستلم:\n")
        print(f"  {qr_payload(token)}")
    else:
        segments = to_sms_segments(token)
        print(f"\nأرسل هذه الرسائل النصية ({len(segments)} مقاطع) لهاتف المستلم:\n")
        for segment in segments:
            print(f"  {segment}")
    print(f"\nالمتبقي أوف لاين: {sdg(wallet.offline_balance)}"
          f" — أُنفق اليوم {sdg(wallet.spent_today())} من سقف {sdg(wallet.daily_cap)}")


def cmd_receive(args) -> None:
    wallet = load_wallet(args.name)
    if args.payload:
        token = read_qr_payload(args.payload)
    else:
        reassembler = SmsReassembler()
        token = None
        for segment in args.segments:
            token = reassembler.feed(segment)
        if token is None:
            print(f"مقاطع ناقصة — الحالة: {reassembler.pending()}")
            sys.exit(1)
    wallet.receive(token)
    save_wallet(args.name, wallet)
    print(f"استُلم توكن {sdg(token.amount)} من {token.sender_id} — التوقيع سليم ✓")
    print("القيمة تصبح رصيداً نهائياً بعد التسوية عند عودة الشبكة (أمر: سوّ)")


def cmd_settle(args) -> None:
    wallet = load_wallet(args.name)
    tokens = wallet.tokens_for_settlement()
    if not tokens:
        print("لا توكنات بانتظار التسوية")
        return
    gateway = client(args)
    batch_id = f"{wallet.device_id}-{uuid.uuid4().hex[:12]}"
    result = gateway.settle(batch_id, tokens, now=int(time.time()))
    info = gateway.balance(wallet.device_id)
    new_anchor = result["new_anchors"].get(wallet.device_id, info["chain_anchor"])
    wallet.apply_settlement(info["balance"], new_anchor)
    save_wallet(args.name, wallet)

    print(f"رُفعت دفعة {batch_id} ({len(tokens)} سجل):")
    print(f"  سُوّي: {len(result['settled'])} — مرفوض: {len(result['rejected'])}")
    for item in result["rejected"]:
        if item["reason"] != "DUPLICATE":
            print(f"    • {item['token']['token_id'][:8]}: {item['reason']}")
    if result["fraud_alerts"]:
        print(f"  ⚠ حسابات جُمّدت لإنفاق مزدوج: {', '.join(result['fraud_alerts'])}")
    print(f"الرصيد المسوّى الجديد: {sdg(info['balance'])}")


def cmd_balance(args) -> None:
    wallet = load_wallet(args.name)
    print(f"محفظة «{args.name}» — جهاز {wallet.device_id}")
    print(f"  متاح أوف لاين : {sdg(wallet.offline_balance)}")
    print(f"  أُنفق اليوم    : {sdg(wallet.spent_today())} من سقف {sdg(wallet.daily_cap)}")
    print(f"  بانتظار تسوية : {len(wallet.sent_tokens)} مرسل، {len(wallet.received_tokens)} مستلم")
    try:
        info = client(args).balance(wallet.device_id)
        frozen = " (مجمّد ⚠)" if info["frozen"] else ""
        print(f"  مسوّى في البنك : {sdg(info['balance'])}{frozen}")
    except WaslaError:
        print("  مسوّى في البنك : البوابة غير متاحة (أوف لاين)")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="wasla", description="وصلة — محفظة أوف لاين (نموذج أولي)")
    parser.add_argument("--gateway", default=os.environ.get("WASLA_GATEWAY", DEFAULT_GATEWAY))
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("انشئ", aliases=["create"], help="إنشاء محفظة وتسجيلها في البوابة")
    p.add_argument("--اسم", "--name", dest="name", required=True)
    p.add_argument("--ايداع", "--deposit", dest="deposit", help="إيداع ابتدائي بالجنيه")
    p.set_defaults(func=cmd_create)

    p = sub.add_parser("ارسل", aliases=["send"], help="توقيع توكن وإخراجه عبر QR أو SMS")
    p.add_argument("--من", "--from", dest="sender", required=True)
    p.add_argument("--الى", "--to", dest="recipient", required=True, help="معرّف جهاز المستلم")
    p.add_argument("--مبلغ", "--amount", dest="amount", required=True, help="بالجنيه")
    p.add_argument("--قناة", "--via", dest="channel", choices=["qr", "sms"], default="qr")
    p.set_defaults(func=cmd_send)

    p = sub.add_parser("استلم", aliases=["receive"], help="استلام توكن من حمولة QR أو مقاطع SMS")
    p.add_argument("--اسم", "--name", dest="name", required=True)
    p.add_argument("--حمولة", "--payload", dest="payload", help="حمولة QR ممسوحة")
    p.add_argument("--مقطع", "--segment", dest="segments", action="append", default=[],
                   help="مقطع SMS وارد (يتكرر)")
    p.set_defaults(func=cmd_receive)

    p = sub.add_parser("سوّ", aliases=["settle"], help="رفع التوكنات للتسوية عند عودة الشبكة")
    p.add_argument("--اسم", "--name", dest="name", required=True)
    p.set_defaults(func=cmd_settle)

    p = sub.add_parser("رصيد", aliases=["balance"], help="عرض الأرصدة والحالة")
    p.add_argument("--اسم", "--name", dest="name", required=True)
    p.set_defaults(func=cmd_balance)
    return parser


def main(argv: list[str] | None = None) -> None:
    args = build_parser().parse_args(argv)
    if hasattr(args, "payload") and not args.payload and not args.segments:
        print("حدد --حمولة (QR) أو --مقطع (SMS) واحداً على الأقل")
        sys.exit(2)
    try:
        args.func(args)
    except WaslaError as exc:
        print(f"خطأ: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
