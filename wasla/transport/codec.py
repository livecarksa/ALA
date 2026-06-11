"""الترميز الثنائي المضغوط للتوكن — أساس كل قنوات النقل.

التوكن الموقّع = 188 بايت ثابتة، فيتسع في رمز QR واحد صغير
وفي مقطعي SMS بعد الترميز النصي. التوقيع يوقّع الحمولة القانونية
JSON نفسها، والترميز هنا مجرد تغليف نقل: فك الترميز يعيد بناء
الحمولة حرفياً فيُتحقق من التوقيع كأن التوكن وصل عبر أي قناة.
"""

from __future__ import annotations

import struct

from token_engine.crypto import sha256_hex
from token_engine.token import SignedToken, TokenError

MAGIC = b"WSL"
VERSION = 1

# magic 3s | version B | token_id 16s | pubkey 32s | recipient 8s | amount Q
# | currency 3s | seq I | prev_hash 32s | issued Q | expires Q | signature 64s
_FORMAT = ">3sB16s32s8sQ3sI32sQQ64s"
TOKEN_WIRE_SIZE = struct.calcsize(_FORMAT)  # 188 بايت


def encode_token(token: SignedToken) -> bytes:
    try:
        return struct.pack(
            _FORMAT,
            MAGIC,
            VERSION,
            bytes.fromhex(token.token_id),
            bytes.fromhex(token.sender_pubkey),
            bytes.fromhex(token.recipient_id),
            token.amount,
            token.currency.encode("ascii"),
            token.seq,
            bytes.fromhex(token.prev_hash),
            token.issued_at,
            token.expires_at,
            bytes.fromhex(token.signature),
        )
    except (struct.error, ValueError) as exc:
        raise TokenError(f"توكن غير قابل للترميز الثنائي: {exc}") from exc


def decode_token(wire: bytes) -> SignedToken:
    """فك الترميز وإعادة بناء التوكن. لا يتحقق من التوقيع —
    المستقبِل يستدعي token.verify() بعد الفك دائماً."""
    if len(wire) != TOKEN_WIRE_SIZE:
        raise TokenError(f"حجم غير متوقع: {len(wire)} بدل {TOKEN_WIRE_SIZE} بايت")
    (
        magic,
        version,
        token_id,
        pubkey,
        recipient,
        amount,
        currency,
        seq,
        prev_hash,
        issued_at,
        expires_at,
        signature,
    ) = struct.unpack(_FORMAT, wire)
    if magic != MAGIC or version != VERSION:
        raise TokenError("ترويسة غير معروفة — ليست حمولة وصلة")
    return SignedToken(
        token_id=token_id.hex(),
        sender_id=sha256_hex(pubkey)[:16],  # المعرّف مشتق من المفتاح دائماً
        sender_pubkey=pubkey.hex(),
        recipient_id=recipient.hex(),
        amount=amount,
        currency=_decode_currency(currency),
        seq=seq,
        prev_hash=prev_hash.hex(),
        issued_at=issued_at,
        expires_at=expires_at,
        signature=signature.hex(),
    )


def _decode_currency(raw: bytes) -> str:
    # العملة 3 بايت ثابتة؛ نزيل أي حشو أصفار فلا يتسرب اختلاف بين الموقّع والمفكوك
    try:
        return raw.rstrip(b"\x00").decode("ascii")
    except UnicodeDecodeError as exc:
        raise TokenError("رمز عملة غير صالح في الحمولة") from exc
