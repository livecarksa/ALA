"""التوكن الموقّع: وحدة القيمة التي تنتقل جهازاً لجهاز.

كل توكن يحمل hash التوكن السابق ورقم تسلسل، فتتكوّن سلسلة توقيعات
متتابعة مرساتها آخر تسوية — أي تفرع في السلسلة (إنفاق مزدوج)
يُكشف حتمياً عند التسوية.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from .crypto import canonical_json, sha256_hex, verify_signature
from .errors import ExpiredToken, InvalidSignature, WaslaError


class TokenError(WaslaError):
    """حمولة توكن غير صالحة بنيوياً."""


@dataclass(frozen=True)
class SignedToken:
    token_id: str
    sender_id: str
    sender_pubkey: str
    recipient_id: str
    amount: int  # بالقرش — أصغر وحدة، عدد صحيح دائماً
    currency: str
    seq: int  # رقم التسلسل في سلسلة المرسل منذ آخر تسوية
    prev_hash: str  # hash التوكن السابق، أو مرساة آخر تسوية
    issued_at: int  # unix seconds
    expires_at: int
    signature: str

    @staticmethod
    def _payload_dict(**fields) -> dict:
        return {
            "token_id": fields["token_id"],
            "sender_id": fields["sender_id"],
            "sender_pubkey": fields["sender_pubkey"],
            "recipient_id": fields["recipient_id"],
            "amount": fields["amount"],
            "currency": fields["currency"],
            "seq": fields["seq"],
            "prev_hash": fields["prev_hash"],
            "issued_at": fields["issued_at"],
            "expires_at": fields["expires_at"],
        }

    @classmethod
    def create(
        cls,
        keys,
        recipient_id: str,
        amount: int,
        seq: int,
        prev_hash: str,
        issued_at: int,
        ttl_seconds: int,
        currency: str = "SDG",
    ) -> "SignedToken":
        if not isinstance(amount, int) or amount <= 0:
            raise TokenError("المبلغ يجب أن يكون عدداً صحيحاً موجباً بالقرش")
        payload = cls._payload_dict(
            token_id=uuid.uuid4().hex,
            sender_id=keys.device_id,
            sender_pubkey=keys.public_key_hex,
            recipient_id=recipient_id,
            amount=amount,
            currency=currency,
            seq=seq,
            prev_hash=prev_hash,
            issued_at=issued_at,
            expires_at=issued_at + ttl_seconds,
        )
        signature = keys.sign(canonical_json(payload))
        return cls(**payload, signature=signature)

    def payload(self) -> dict:
        return self._payload_dict(**self.__dict__)

    @property
    def token_hash(self) -> str:
        # يشمل التوقيع حتى يستحيل تركيب سلسلة بديلة على نفس الحمولة
        return sha256_hex(canonical_json({**self.payload(), "signature": self.signature}))

    def verify(self, now: int | None = None) -> None:
        """تحقق ذاتي: التوقيع، اشتقاق المعرّف من المفتاح، الصلاحية."""
        if sha256_hex(bytes.fromhex(self.sender_pubkey))[:16] != self.sender_id:
            raise InvalidSignature("معرّف المرسل لا يطابق مفتاحه العام")
        if not isinstance(self.amount, int) or self.amount <= 0:
            raise TokenError("مبلغ غير صالح")
        verify_signature(self.sender_pubkey, self.signature, canonical_json(self.payload()))
        if now is not None and now > self.expires_at:
            raise ExpiredToken(f"التوكن {self.token_id[:8]} انتهت صلاحيته قبل التسوية")

    def to_dict(self) -> dict:
        return {**self.payload(), "signature": self.signature}

    @classmethod
    def from_dict(cls, data: dict) -> "SignedToken":
        return cls(**{k: data[k] for k in cls.__dataclass_fields__})
