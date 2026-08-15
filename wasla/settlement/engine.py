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

# الحد الأقصى لعمر التوكن يفرضه المحرك ولا يثق بقيمة العميل (يطابق سقف المحفظة)
MAX_TOKEN_TTL = 72 * 3600
# هامش انحراف الساعات المسموح به لطابع الإصدار (الأجهزة الأوف لاين قد تنحرف ساعتها)
CLOCK_SKEW_TOLERANCE = 2 * 3600


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
    FUTURE_DATED = "FUTURE_DATED"  # طابع إصدار في المستقبل — تلاعب بالسقف
    BAD_TTL = "BAD_TTL"  # عمر التوكن يتجاوز الحد الذي يفرضه المحرك
    SUPERSEDED = "SUPERSEDED"  # حلقة بعد توكن مرفوض رفضاً قاتلاً في السلسلة

# أسباب رفض «قاتلة» توقف السلسلة: ما بعدها لا يُسوّى لأن الحلقة المرفوضة
# كسرت تسلسل القيمة. الانتهاء (EXPIRED) ليس منها — قيمته تعود للمرسل والسلسلة تكمل.
FATAL_REJECTIONS = frozenset({
    RejectReason.BAD_SIGNATURE,
    RejectReason.KEY_MISMATCH,
    RejectReason.BAD_SEQUENCE,
    RejectReason.DAILY_CAP,
    RejectReason.INSUFFICIENT_FUNDS,
    RejectReason.FUTURE_DATED,
    RejectReason.BAD_TTL,
})

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
    RejectReason.FUTURE_DATED: "طابع إصدار في المستقبل — يُرفض منعاً للتلاعب بالسقف",
    RejectReason.BAD_TTL: "عمر التوكن يتجاوز الحد المسموح",
    RejectReason.SUPERSEDED: "حلقة تابعة لتوكن مرفوض في السلسلة",
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
    malformed: list[dict] = field(default_factory=list)  # حمولات لا تُنسب لمرسل — للتدقيق

    @property
    def settled_amount(self) -> int:
        return sum(t.amount for t in self.settled)

    def to_dict(self) -> dict:
        return {
            "settled": [t.to_dict() for t in self.settled],
            "rejected": [{"token": t.to_dict(), "reason": r} for t, r in self.rejected],
            "malformed": list(self.malformed),
            "fraud_alerts": list(self.fraud_alerts),
            "new_anchors": dict(self.new_anchors),
            "settled_amount": self.settled_amount,
        }


def _day(ts: int) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d")


class SettlementEngine:
    """يمثل نواة التسوية فوق بيئة اختبار بنكك: حسابات، دفتر، وكشف تفرع."""

    def __init__(self):
        self.ledger = Ledger()
        self.accounts: dict[str, DeviceAccount] = {}
        self._settled_token_ids: set[str] = set()
        self._spent_by_day: dict[tuple[str, str], int] = {}  # (device, day) -> قرش
        # (sender, prev_hash) -> token_id الذي سُوّي منها: يكشف تفرعاً يصل عبر دفعات
        # منفصلة (مستلمان يتصلان في أوقات مختلفة) لا في نفس الدفعة
        self._spent_prev: dict[tuple[str, str], str] = {}

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
                # حمولة مشوهة بنيوياً — تُسجَّل للتدقيق فلا يضيع أثرها
                report.malformed.append(raw if isinstance(raw, dict) else {"raw": repr(raw)})
                continue
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
        last_settled_head = account.chain_anchor  # المرساة لا تتقدم إلا بتسوية فعلية
        expected_seq = 0
        processed: set[str] = set()
        double_spend = False

        while head in by_prev:
            candidates = sorted(by_prev[head], key=lambda t: (t.issued_at, t.token_id))
            canonical = candidates[0]
            if len(candidates) > 1:
                # تفرع مكشوف داخل الدفعة: الفرع الأسبق يُسوّى، والباقي احتيال
                double_spend = True
                for forked in candidates[1:]:
                    self._reject_subtree(forked, by_prev, processed, report, RejectReason.DOUBLE_SPEND)

            processed.add(canonical.token_id)
            reason = self._validate_token(canonical, account, expected_seq, now)
            if reason is None:
                self._post_settlement(canonical)
                report.settled.append(canonical)
                last_settled_head = canonical.token_hash
                head = canonical.token_hash
                expected_seq = canonical.seq + 1
            elif reason == RejectReason.EXPIRED:
                # حلقة منتهية: قيمتها تعود للمرسل، لكن السلسلة تبقى متصلة فنُكمل
                report.rejected.append((canonical, reason))
                head = canonical.token_hash
                expected_seq = canonical.seq + 1
            else:
                # رفض قاتل: الحلقة كسرت تسلسل القيمة فلا يُسوّى ما بُني فوقها
                report.rejected.append((canonical, reason))
                for child in by_prev.get(canonical.token_hash, []):
                    self._reject_subtree(child, by_prev, processed, report, RejectReason.SUPERSEDED)
                break

        # ما تبقى لا يصل برأس السلسلة الحالي. إن كان prev_hash نقطةً سُوّي منها
        # توكن آخر سابقاً فهذا تفرع عبر الدفعات (إنفاق مزدوج)، وإلا سلسلة مبتورة.
        for token in tokens:
            if token.token_id in processed:
                continue
            prior = self._spent_prev.get((sender_id, token.prev_hash))
            if prior is not None and prior != token.token_id:
                double_spend = True
                report.rejected.append((token, RejectReason.DOUBLE_SPEND))
            else:
                report.rejected.append((token, RejectReason.CHAIN_BROKEN))

        if double_spend:
            account.frozen = True
            report.fraud_alerts.append(sender_id)

        if last_settled_head != account.chain_anchor:
            # مرساة جديدة مشتقة من رأس آخر توكن سُوّي فعلاً — لا تتقدم على رفض أو عبث
            new_anchor = sha256_hex(f"anchor:{sender_id}:{last_settled_head}:{now}".encode())
            account.chain_anchor = new_anchor
        report.new_anchors[sender_id] = account.chain_anchor

    def _reject_subtree(
        self,
        root: SignedToken,
        by_prev: dict[str, list[SignedToken]],
        processed: set[str],
        report: SettlementReport,
        reason: str,
    ) -> None:
        """رفض توكن وكل ما بُني فوقه بنفس السبب (تفرع احتيالي أو حلقة تابعة لمرفوض)."""
        stack = [root]
        while stack:
            token = stack.pop()
            if token.token_id in processed:
                continue
            processed.add(token.token_id)
            report.rejected.append((token, reason))
            stack.extend(by_prev.get(token.token_hash, []))

    def _validate_token(
        self, token: SignedToken, account: DeviceAccount, expected_seq: int, now: int
    ) -> str | None:
        """إعادة كل فحوص المحفظة على الخادم — دالة فحص خالصة (لا تُعدّل الحالة).

        يعيد سبب الرفض أو None للقبول. تحديث عدّاد السقف يتم في _post_settlement
        ذرياً مع القيد، حتى لا يُستهلك السقف لتوكن لم يُسوَّ.
        """
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
        # طابع الإصدار حقل موقّع لكن يختاره العميل — لا يُوثق به لتقسيم السقف:
        # نرفض المستقبل (تلاعب بحاوية اليوم) ونفرض حد العمر بدل قيمة العميل
        if token.issued_at > now + CLOCK_SKEW_TOLERANCE:
            return RejectReason.FUTURE_DATED
        if token.expires_at - token.issued_at > MAX_TOKEN_TTL:
            return RejectReason.BAD_TTL
        if token.seq != expected_seq:
            return RejectReason.BAD_SEQUENCE
        day_key = (account.device_id, _day(token.issued_at))
        if self._spent_by_day.get(day_key, 0) + token.amount > account.daily_cap:
            return RejectReason.DAILY_CAP
        if token.amount > self.ledger.balance(account.device_id):
            return RejectReason.INSUFFICIENT_FUNDS
        return None

    # ---------- حفظ واستعادة الحالة (للبوابة المعمّرة) ----------

    def to_state(self) -> dict:
        from dataclasses import asdict

        return {
            "accounts": {d: asdict(a) for d, a in self.accounts.items()},
            "balances": dict(self.ledger.balances),
            "postings": [asdict(p) for p in self.ledger.postings],
            "settled_token_ids": sorted(self._settled_token_ids),
            "spent_by_day": {f"{d}|{day}": v for (d, day), v in self._spent_by_day.items()},
            "spent_prev": {f"{s}|{prev}": tid for (s, prev), tid in self._spent_prev.items()},
        }

    @classmethod
    def from_state(cls, state: dict) -> "SettlementEngine":
        from .ledger import Posting

        engine = cls()
        engine.accounts = {d: DeviceAccount(**a) for d, a in state["accounts"].items()}
        engine.ledger.balances = dict(state["balances"])
        engine.ledger.postings = [Posting(**p) for p in state["postings"]]
        engine._settled_token_ids = set(state["settled_token_ids"])
        engine._spent_by_day = {
            tuple(key.split("|", 1)): value for key, value in state["spent_by_day"].items()
        }
        engine._spent_prev = {
            tuple(key.split("|", 1)): value for key, value in state.get("spent_prev", {}).items()
        }
        return engine

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
        # عدّاد السقف ونقطة الاستهلاك يُحدَّثان ذرياً مع القيد لا في الفحص:
        # «السقف مُستهلَك ⟺ التوكن مُسوّى» تبقى ثابتة مهما تغيّر الفحص لاحقاً
        day_key = (token.sender_id, _day(token.issued_at))
        self._spent_by_day[day_key] = self._spent_by_day.get(day_key, 0) + token.amount
        self._spent_prev[(token.sender_id, token.prev_hash)] = token.token_id
