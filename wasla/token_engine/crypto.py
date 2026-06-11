"""التشفير: مفاتيح Ed25519 داخل الجهاز وتسلسل قانوني للحمولة.

لا تشفير مبتكر — Ed25519 وSHA-256 فقط، وفق النمط المثبت في
UPI Lite X وتجارب العملات الرقمية للبنوك المركزية.
"""

from __future__ import annotations

import hashlib
import json

from cryptography.exceptions import InvalidSignature as _CryptoInvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)

from .errors import InvalidSignature


def canonical_json(payload: dict) -> bytes:
    # تسلسل حتمي: مفاتيح مرتبة وبلا مسافات، حتى يتطابق ما يُوقَّع مع ما يُتحقق منه
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class DeviceKeys:
    """زوج مفاتيح الجهاز. في الإنتاج يولَّد ويُخزَّن داخل البيئة الآمنة
    للجهاز (Secure Enclave / StrongBox) ولا يغادرها — هنا في الذاكرة للنموذج الأولي."""

    def __init__(self, private_key: Ed25519PrivateKey | None = None):
        self._private = private_key or Ed25519PrivateKey.generate()
        self._public = self._private.public_key()

    @classmethod
    def from_private_hex(cls, private_hex: str) -> "DeviceKeys":
        return cls(Ed25519PrivateKey.from_private_bytes(bytes.fromhex(private_hex)))

    @property
    def private_key_hex(self) -> str:
        """للنموذج الأولي فقط: تخزين ملفي. في الإنتاج المفتاح لا يغادر البيئة الآمنة."""
        from cryptography.hazmat.primitives import serialization

        return self._private.private_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PrivateFormat.Raw,
            encryption_algorithm=serialization.NoEncryption(),
        ).hex()

    @property
    def public_key_hex(self) -> str:
        from cryptography.hazmat.primitives import serialization

        raw = self._public.public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        return raw.hex()

    @property
    def device_id(self) -> str:
        # معرّف الجهاز مشتق من المفتاح العام — لا يمكن انتحاله دون المفتاح الخاص
        return sha256_hex(bytes.fromhex(self.public_key_hex))[:16]

    def sign(self, message: bytes) -> str:
        return self._private.sign(message).hex()


def verify_signature(public_key_hex: str, signature_hex: str, message: bytes) -> None:
    """يرفع InvalidSignature إن لم يطابق التوقيع الحمولة والمفتاح."""
    try:
        public = Ed25519PublicKey.from_public_bytes(bytes.fromhex(public_key_hex))
        public.verify(bytes.fromhex(signature_hex), message)
    except (_CryptoInvalidSignature, ValueError) as exc:
        raise InvalidSignature("التوقيع لا يطابق الحمولة أو المفتاح") from exc
