"""مصادقة طلبات البوابة — توقيع Ed25519 لكل طلب بمفتاح الجهاز.

يثبت أن مُرسِل الطلب يملك المفتاح الخاص للجهاز المسجَّل (إثبات حيازة)،
فيمنع أي طرف على الشبكة من رفع دفعات أو تمويل حساب أو الاستعلام عن
رصيد نيابةً عن غيره — الثغرة التي رصدها مجلس المراجعة في النموذج الأولي.

نعتمد نافذة زمنية ضد إعادة الإرسال؛ التسوية idempotent بمعرّف الدفعة
والإيداع بمرجعه، فإعادة طلب موقّع داخل النافذة بلا أثر مزدوج. الاستعلام
عن الرصيد للقراءة فقط. لذا لا حاجة لمخزن nonce في هذا النموذج.
"""

from __future__ import annotations

from token_engine.crypto import sha256_hex, verify_signature
from token_engine.errors import InvalidSignature, WaslaError

# سقف انحراف الطابع الزمني المقبول بين الجهاز والخادم (ثوانٍ)
MAX_REQUEST_SKEW = 300


class Unauthorized(WaslaError):
    """طلب غير موقّع أو توقيع لا يطابق جهازاً مسجلاً."""


def _signing_string(method: str, path: str, timestamp: int, body: bytes) -> bytes:
    # يغطي الفعل والمسار والوقت وبصمة الجسم — أي عبث بأيٍّ منها يُبطل التوقيع
    return f"{method}\n{path}\n{timestamp}\n{sha256_hex(body)}".encode("utf-8")


def sign_request(keys, method: str, path: str, timestamp: int, body: bytes) -> str:
    return keys.sign(_signing_string(method, path, timestamp, body))


def verify_request(
    pubkey_hex: str,
    signature_hex: str,
    method: str,
    path: str,
    timestamp: int,
    body: bytes,
    now: int,
    max_skew: int = MAX_REQUEST_SKEW,
) -> None:
    """يرفع InvalidSignature إن كان الطابع خارج النافذة أو التوقيع لا يطابق."""
    if abs(now - timestamp) > max_skew:
        raise InvalidSignature("طابع زمني خارج النافذة المسموحة")
    verify_signature(pubkey_hex, signature_hex, _signing_string(method, path, timestamp, body))
