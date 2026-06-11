"""مسار SMS — التحويل للهواتف العادية بلا إنترنت ولا تطبيق ذكي.

التوكن الثنائي (188 بايت) يُرمَّز Base64 (~252 حرفاً) ويُقسَّم مقاطع
نصية قصيرة تصلح للرسائل المتسلسلة. كل مقطع يحمل معرّف رسالة مشتقاً
من hash الحمولة، فأي تلف أو خلط بين رسائل يُكشف عند إعادة التجميع
قبل حتى فحص التوقيع.

شكل المقطع:  WSL1|<msg_id>|<idx>/<total>|<chunk>
"""

from __future__ import annotations

import base64

from token_engine.crypto import sha256_hex
from token_engine.token import SignedToken, TokenError

from .codec import decode_token, encode_token

HEADER = "WSL1"
# 153 حرفاً سعة مقطع SMS متسلسل (GSM-7)؛ الترويسة ~18 حرفاً،
# و130 تجعل التوكن (252 حرف Base64) مقطعين بالضبط
DEFAULT_CHUNK_SIZE = 130


def to_sms_segments(token: SignedToken, chunk_size: int = DEFAULT_CHUNK_SIZE) -> list[str]:
    """توكن ← قائمة رسائل نصية جاهزة للإرسال بالتسلسل."""
    wire = encode_token(token)
    text = base64.b64encode(wire).decode("ascii")
    msg_id = sha256_hex(wire)[:8]  # بصمة الحمولة — تكشف أي تلف عند التجميع
    chunks = [text[i : i + chunk_size] for i in range(0, len(text), chunk_size)]
    total = len(chunks)
    return [f"{HEADER}|{msg_id}|{i + 1}/{total}|{chunk}" for i, chunk in enumerate(chunks)]


class SmsReassembler:
    """يجمّع مقاطع رسائل واردة (بأي ترتيب، من عدة تحويلات متداخلة)
    ويعيد التوكنات المكتملة. صالح للهاتف العادي حيث تصل الرسائل متفرقة."""

    def __init__(self):
        self._partial: dict[str, dict[int, str]] = {}
        self._totals: dict[str, int] = {}

    def feed(self, segment: str) -> SignedToken | None:
        """مقطع وارد. يعيد التوكن إذا اكتمل وإلا None."""
        try:
            header, msg_id, position, chunk = segment.strip().split("|", 3)
            idx_str, total_str = position.split("/")
            idx, total = int(idx_str), int(total_str)
        except ValueError as exc:
            raise TokenError("مقطع SMS مشوه البنية") from exc
        if header != HEADER or not (1 <= idx <= total):
            raise TokenError("مقطع SMS بترويسة أو ترقيم غير صالح")

        known_total = self._totals.setdefault(msg_id, total)
        if known_total != total:
            raise TokenError("مقاطع متضاربة لنفس معرّف الرسالة")
        parts = self._partial.setdefault(msg_id, {})
        parts[idx] = chunk  # التكرار (إعادة إرسال) يحلّ محل نفسه بلا ضرر

        if len(parts) < total:
            return None

        text = "".join(parts[i] for i in range(1, total + 1))
        try:
            wire = base64.b64decode(text.encode("ascii"), validate=True)
        except Exception as exc:
            raise TokenError("حمولة SMS تالفة — فك Base64 فشل") from exc
        if sha256_hex(wire)[:8] != msg_id:
            raise TokenError("بصمة الحمولة لا تطابق معرّف الرسالة — تلف أو تلاعب")
        token = decode_token(wire)
        del self._partial[msg_id], self._totals[msg_id]
        return token

    def pending(self) -> dict[str, str]:
        """الرسائل الناقصة: معرّف الرسالة ← حالة الاكتمال (للعرض للمستخدم)."""
        return {
            msg_id: f"{len(parts)}/{self._totals[msg_id]}"
            for msg_id, parts in self._partial.items()
        }
