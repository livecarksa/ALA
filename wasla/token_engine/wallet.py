"""المحفظة الأوف لاين: الرصيد المحلي، السقف اليومي، ورأس سلسلة التوقيعات.

السقف اليومي هو طبقة الدفاع الأولى — يحدّ الخسارة القصوى لأي اختراق فردي.
الفحص هنا لحماية المستخدم الشريف؛ محرك التسوية يعيد الفحص ذاته
لأن جهاز المهاجم قد يتجاوز كود المحفظة.
"""

from __future__ import annotations

import time
from collections import defaultdict
from datetime import datetime, timezone

from .crypto import DeviceKeys
from .errors import DailyCapExceeded, InsufficientOfflineBalance
from .token import SignedToken, TokenError

DEFAULT_DAILY_CAP = 500_000  # 5,000 جنيه بالقرش — قيمة استرشادية قابلة للضبط
DEFAULT_TOKEN_TTL = 72 * 3600  # صلاحية التوكن غير المسوّى: 72 ساعة


def _day_key(ts: int) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d")


class OfflineWallet:
    """محفظة جهاز واحد بين تسويتين.

    الرصيد الأوف لاين يُحمَّل من التسوية (settled_balance) ومرساة السلسلة
    هي hash آخر تسوية. التوكنات المستلمة لا تصبح قابلة للإنفاق الأوف لاين
    إلا بعد تسويتها — نمط UPI Lite X نفسه.
    """

    def __init__(
        self,
        keys: DeviceKeys | None = None,
        offline_balance: int = 0,
        chain_anchor: str = "",
        daily_cap: int = DEFAULT_DAILY_CAP,
        token_ttl: int = DEFAULT_TOKEN_TTL,
    ):
        self.keys = keys or DeviceKeys()
        self.offline_balance = offline_balance
        self.daily_cap = daily_cap
        self.token_ttl = token_ttl
        self.chain_head = chain_anchor  # hash آخر توكن أصدرناه (أو مرساة التسوية)
        self.next_seq = 0
        self.sent_tokens: list[SignedToken] = []
        self.received_tokens: list[SignedToken] = []
        self._spent_by_day: dict[str, int] = defaultdict(int)

    @property
    def device_id(self) -> str:
        return self.keys.device_id

    def spent_today(self, now: int | None = None) -> int:
        return self._spent_by_day[_day_key(now or int(time.time()))]

    def send(self, recipient_id: str, amount: int, now: int | None = None) -> SignedToken:
        """إنشاء توكن موقّع لمستلم — يعمل بلا أي شبكة."""
        now = now or int(time.time())
        day = _day_key(now)
        if amount > self.offline_balance:
            raise InsufficientOfflineBalance(
                f"المطلوب {amount} قرشاً والمتاح أوف لاين {self.offline_balance}"
            )
        if self._spent_by_day[day] + amount > self.daily_cap:
            raise DailyCapExceeded(
                f"السقف اليومي {self.daily_cap} قرشاً — أُنفق اليوم {self._spent_by_day[day]}"
            )
        token = SignedToken.create(
            keys=self.keys,
            recipient_id=recipient_id,
            amount=amount,
            seq=self.next_seq,
            prev_hash=self.chain_head,
            issued_at=now,
            ttl_seconds=self.token_ttl,
        )
        # تقدم السلسلة قبل أي تسليم: التوكن التالي يرتبط بهذا حتمياً
        self.chain_head = token.token_hash
        self.next_seq += 1
        self.offline_balance -= amount
        self._spent_by_day[day] += amount
        self.sent_tokens.append(token)
        return token

    def receive(self, token: SignedToken, now: int | None = None) -> None:
        """استلام توكن عبر بلوتوث/QR/SMS: تحقق محلي ثم تخزين حتى التسوية."""
        now = now or int(time.time())
        token.verify(now=now)
        if token.recipient_id != self.device_id:
            raise TokenError("التوكن موجّه لجهاز آخر")
        if any(t.token_id == token.token_id for t in self.received_tokens):
            return  # إعادة إرسال عبر SMS مثلاً — لا أثر مزدوج
        self.received_tokens.append(token)

    def tokens_for_settlement(self) -> list[dict]:
        """كل ما يُرفع للمحرك عند عودة الاتصال: المرسَل والمستلَم معاً."""
        return [t.to_dict() for t in self.sent_tokens + self.received_tokens]

    def apply_settlement(self, new_balance: int, new_anchor: str) -> None:
        """بعد تسوية ناجحة: رصيد جديد ومرساة سلسلة جديدة وتصفير السلسلة المحلية."""
        self.offline_balance = new_balance
        self.chain_head = new_anchor
        self.next_seq = 0
        self.sent_tokens.clear()
        self.received_tokens.clear()

    # ---------- حفظ واستعادة حالة المحفظة (للتطبيق المبسط) ----------

    def to_dict(self) -> dict:
        """حالة المحفظة كاملة للتخزين الملفي.

        تحذير نموذج أولي: المفتاح الخاص يُخزن نصاً صريحاً — في الإنتاج
        يبقى داخل البيئة الآمنة للجهاز ولا يُصدَّر إطلاقاً.
        """
        return {
            "private_key": self.keys.private_key_hex,
            "offline_balance": self.offline_balance,
            "daily_cap": self.daily_cap,
            "token_ttl": self.token_ttl,
            "chain_head": self.chain_head,
            "next_seq": self.next_seq,
            "spent_by_day": dict(self._spent_by_day),
            "sent_tokens": [t.to_dict() for t in self.sent_tokens],
            "received_tokens": [t.to_dict() for t in self.received_tokens],
        }

    @classmethod
    def from_dict(cls, data: dict) -> "OfflineWallet":
        wallet = cls(
            keys=DeviceKeys.from_private_hex(data["private_key"]),
            offline_balance=data["offline_balance"],
            chain_anchor=data["chain_head"],
            daily_cap=data["daily_cap"],
            token_ttl=data["token_ttl"],
        )
        wallet.next_seq = data["next_seq"]
        wallet._spent_by_day.update(data["spent_by_day"])
        wallet.sent_tokens = [SignedToken.from_dict(t) for t in data["sent_tokens"]]
        wallet.received_tokens = [SignedToken.from_dict(t) for t in data["received_tokens"]]
        return wallet
