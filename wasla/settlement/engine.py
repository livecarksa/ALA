"""محرك التسوية: التحقق النهائي وكشف الإنفاق المزدوج.

المبدأ الحاكم: لا ثقة بالعميل. كل فحص تجريه المحفظة يُعاد هنا
(التوقيع، السلسلة، السقف اليومي، الصلاحية، الرصيد) لأن جهاز
المهاجم قد يتجاوز كود المحفظة ويصنع توكنات يدوياً.

سياسة التفرع (الإنفاق المزدوج): الفرع القانوني هو الأسبق إصداراً،
يُسوّى لحماية مستلمه، ويُرفض الفرع الآخر بكل ذيله ويُجمَّد حساب
المرسل حتى المراجعة.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from datetime import datetime, timezone

from token_engine.crypto import sha256_hex
from token_engine.errors import ExpiredToken, InvalidSignature
from token_engine.token import SignedToken, TokenError

from .ledger import Ledger

# حساب النظام الذي تُموَّل منه الإيداعات النقدية عبر الوكلاء
AGENT_CASH_ACCOUNT = "AGENT_CASH"


class RejectReason:
    DOUBLE_SPEND = "DOUBLE_SPEND"  # تفرع في سلسلة التوقيعات
    BAD_SIGNATURE = "BAD_SIGNATURE"
    EXPIRED = "EXPIRED"
    CHAIN_BROKEN = "CHAIN_BROKEN"  # prev_hash لا يصل بمرساة آخر تسوية
    BAD_SEQUENCE = "BAD_SEQUENCE"
    DAILY_CAP = "DAILY_CAP"
    INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS"
    DUPLICATE = "DUPLICATE"  # توكن سُوّي سابقاً (رفعه الطرفان) — ليس احتيالاً
    ACCOUNT_FROZEN = "ACCOUNT_FROZEN"
    UNREGISTERED_SENDER = "UNREGISTERED_SENDER"
    KEY_MISMATCH = "KEY_MISMATCH"  # المفتاح العام لا يطابق المسجل للحساب

ARABIC_REASONS = {
    RejectReason.DOUBLE_SPEND: "إنفاق مزدوج — تفرع في سلسلة التوقيعات",
    RejectReason.BAD_SIGNATURE: "توقيع غير صالح أو حمولة معدَّلة",
    RejectReason.EXPIRED: "انتهت صلاحية التوكن قبل التسوية",
    RejectReason.CHAIN_BROKEN: "سلسلة غير متصلة بمرساة آخر تسوية",
    RejectReason.BAD_SEQUENCE: "رقم تسلسل غير متطابق",
    RejectReason.DAILY_CAP: "تجاوز السقف اليومي للإنفاق الأوف لاين",
    RejectReason.INSUFFICIENT_FUNDS: "الرصيد المسوّى لا يغطي المبلغ",
    RejectReason.DUPLICATE: "توكن مكرر سُوّي سابقاً",
    RejectReason.ACCOUNT_FROZEN: "الحساب مجمّد بانتظار مراجعة احتيال",
    RejectReason.UNREGISTERED_SENDER: "مرسل غير مسجل في المنظومة",
    RejectReason.KEY_MISMATCH: "المفتاح العام لا يطابق المسجل للحساب",
}


@dataclass
class DeviceAccount:
    device_id: str
    pubkey: str
    daily_cap: int
    chain_anchor: str
    frozen: bool = False


@dataclass
class SettlementReport:
    settled: list[SignedToken] = field(default_factory=list)
    rejected: list[tuple[SignedToken, str]] = field(default_factory=list)
    fraud_alerts: list[str] = field(default_factory=list)  # حسابات جُمّدت لإنفاق مزدوج
    new_anchors: dict[str, str] = field(default_factory=dict)

    @property
    def settled_amount(self) -> int:
        return sum(t.amount for t in self.settled)


def _day(ts: int) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d")


class SettlementEngine:
    """يمثل نواة التسوية فوق بيئة اختبار بنكك: حسابات، دفتر، وكشف تفرع."""

    def __init__(self):
        self.ledger = Ledger()
        self.accounts: dict[str, DeviceAccount] = {}
        self._settled_token_ids: set[str] = set()
        self._spent_by_day: dict[tuple[str, str], int] = {}  # (device, day) -> قرش

    # ---------- إدارة الحسابات ----------

    def register_device(self, pubkey_hex: str, daily_cap: int) -> DeviceAccount:
        device_id = sha256_hex(bytes.fromhex(pubkey_hex))[:16]
        anchor = sha256_hex(f"anchor:{device_id}:{len(self.accounts)}".encode())
        account = DeviceAccount(device_id, pubkey_hex, daily_cap, anchor)
        self.accounts[device_id] = account
        self.ledger.open_account(device_id)
        return account

    def cash_in(self, device_id: str, amount: int, reference: str = "agent-deposit") -> None:
        """إيداع نقدي عبر وكيل — يموّل الرصيد الأوف لاين القابل للإنفاق."""
        self.ledger.post(AGENT_CASH_ACCOUNT, device_id, amount, reference, "إيداع وكيل")

    def balance(self, device_id: str) -> int:
        return self.ledger.balance(device_id)

    # ---------- التسوية ----------

    def settle_batch(self, raw_tokens: list[dict], now: int | None = None) -> SettlementReport:
        """تسوية دفعة توكنات مرفوعة من أي عدد من الأجهزة عند عودة الاتصال."""
        now = now or int(time.time())
        report = SettlementReport()

        tokens: list[SignedToken] = []
        seen_in_batch: set[str] = set()
        for raw in raw_tokens:
            try:
                token = SignedToken.from_dict(raw)
            except (KeyError, TypeError):
                continue  # حمولة مشوهة بنيوياً — لا يمكن حتى نسبتها لمرسل
            # نفس التوكن قد يرفعه المرسل والمستلم معاً — يُسوّى مرة واحدة فقط
            if token.token_id in seen_in_batch or token.token_id in self._settled_token_ids:
                report.rejected.append((token, RejectReason.DUPLICATE))
                continue
            seen_in_batch.add(token.token_id)
            tokens.append(token)

        by_sender: dict[str, list[SignedToken]] = {}
        for token in tokens:
            by_sender.setdefault(token.sender_id, []).append(token)

        for sender_id, chain_tokens in by_sender.items():
            self._settle_sender_chain(sender_id, chain_tokens, now, report)

        return report

    def _settle_sender_chain(
        self, sender_id: str, tokens: list[SignedToken], now: int, report: SettlementReport
    ) -> None:
        account = self.accounts.get(sender_id)
        if account is None:
            report.rejected.extend((t, RejectReason.UNREGISTERED_SENDER) for t in tokens)
            return
        if account.frozen:
            report.rejected.extend((t, RejectReason.ACCOUNT_FROZEN) for t in tokens)
            return

        # السير في السلسلة من مرساة آخر تسوية: عند كل خطوة نبحث عن التوكنات
        # التي تشير إلى الرأس الحالي — أكثر من واحد يعني تفرعاً (إنفاق مزدوج)
        by_prev: dict[str, list[SignedToken]] = {}
        for token in tokens:
            by_prev.setdefault(token.prev_hash, []).append(token)

        head = account.chain_anchor
        expected_seq = 0
        processed: set[str] = set()
        double_spend = False

        while head in by_prev:
            candidates = sorted(by_prev[head], key=lambda t: (t.issued_at, t.token_id))
            canonical = candidates[0]
            if len(candidates) > 1:
                # تفرع مكشوف: الفرع الأسبق يُسوّى لحماية مستلمه، والباقي احتيال
                double_spend = True
                for forked in candidates[1:]:
                    self._reject_subtree(forked, by_prev, processed, report)

            processed.add(canonical.token_id)
            reason = self._validate_token(canonical, account, expected_seq, now)
            if reason is None:
                self._post_settlement(canonical)
                report.settled.append(canonical)
            else:
                report.rejected.append((canonical, reason))
            head = canonical.token_hash
            expected_seq = canonical.seq + 1

        # ما تبقى لا يصل بالمرساة إطلاقاً — سلسلة مبتورة أو مفبركة
        for token in tokens:
            if token.token_id not in processed:
                report.rejected.append((token, RejectReason.CHAIN_BROKEN))

        if double_spend:
            account.frozen = True
            report.fraud_alerts.append(sender_id)

        # مرساة جديدة للجهاز: رأس السلسلة المسوّاة يبدأ منها بعد التصفير
        new_anchor = sha256_hex(f"anchor:{sender_id}:{head}:{now}".encode())
        account.chain_anchor = new_anchor
        report.new_anchors[sender_id] = new_anchor

    def _reject_subtree(
        self,
        root: SignedToken,
        by_prev: dict[str, list[SignedToken]],
        processed: set[str],
        report: SettlementReport,
    ) -> None:
        """رفض فرع الإنفاق المزدوج وكل التوكنات المبنية فوقه."""
        stack = [root]
        while stack:
            token = stack.pop()
            if token.token_id in processed:
                continue
            processed.add(token.token_id)
            report.rejected.append((token, RejectReason.DOUBLE_SPEND))
            stack.extend(by_prev.get(token.token_hash, []))

    def _validate_token(
        self, token: SignedToken, account: DeviceAccount, expected_seq: int, now: int
    ) -> str | None:
        """إعادة كل فحوص المحفظة على الخادم. يعيد سبب الرفض أو None للقبول."""
        if token.sender_pubkey != account.pubkey:
            return RejectReason.KEY_MISMATCH
        try:
            token.verify()
        except ExpiredToken:
            return RejectReason.EXPIRED
        except (InvalidSignature, TokenError):
            return RejectReason.BAD_SIGNATURE
        if now > token.expires_at:
            # توكن منتهٍ لا يُسوّى: القيمة تعود للمرسل ولا تُخصم
            return RejectReason.EXPIRED
        if token.seq != expected_seq:
            return RejectReason.BAD_SEQUENCE
        day_key = (account.device_id, _day(token.issued_at))
        if self._spent_by_day.get(day_key, 0) + token.amount > account.daily_cap:
            return RejectReason.DAILY_CAP
        if token.amount > self.ledger.balance(account.device_id):
            return RejectReason.INSUFFICIENT_FUNDS

        self._spent_by_day[day_key] = self._spent_by_day.get(day_key, 0) + token.amount
        return None

    def _post_settlement(self, token: SignedToken) -> None:
        # الاستلام بلا حساب مسبق مدعوم: يُفتح حساب للمستلم عند أول تسوية له
        self.ledger.open_account(token.recipient_id)
        self.ledger.post(
            token.sender_id,
            token.recipient_id,
            token.amount,
            token.token_id,
            f"تسوية توكن أوف لاين seq={token.seq}",
        )
        self._settled_token_ids.add(token.token_id)
