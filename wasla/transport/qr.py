"""مسار QR — للهواتف الذكية وجهاً لوجه: المرسل يعرض، المستلم يمسح.

حمولة نصية واحدة (~260 حرفاً) تتسع في رمز QR صغير يُقرأ بكاميرا
متواضعة. توليد صورة الرمز نفسها شأن طبقة الواجهة (Flutter لاحقاً) —
هنا الحمولة النصية القياسية فقط.
"""

from __future__ import annotations

import base64

from token_engine.token import SignedToken, TokenError

from .codec import decode_token, encode_token

PREFIX = "WSLQR1:"


def qr_payload(token: SignedToken) -> str:
    return PREFIX + base64.b64encode(encode_token(token)).decode("ascii")


def read_qr_payload(payload: str) -> SignedToken:
    """حمولة ممسوحة ← توكن. المستقبِل يستدعي token.verify() بعدها دائماً."""
    payload = payload.strip()
    if not payload.startswith(PREFIX):
        raise TokenError("ليست حمولة QR لوصلة")
    try:
        wire = base64.b64decode(payload[len(PREFIX) :].encode("ascii"), validate=True)
    except Exception as exc:
        raise TokenError("حمولة QR تالفة") from exc
    return decode_token(wire)
