"""طبقات النقل: كيف ينتقل التوكن الموقّع جهازاً لجهاز بلا شبكة.

- codec: ترميز ثنائي مضغوط واحد لكل القنوات (188 بايت للتوكن).
- sms: تقسيم متعدد المقاطع للهواتف العادية (مسار الرسائل النصية).
- qr: حمولة نصية واحدة تُعرض كرمز QR للهواتف الذكية.

البلوتوث منخفض الطاقة يستخدم نفس الترميز الثنائي مباشرة — لا يحتاج وحدة خاصة هنا.
"""

from .codec import decode_token, encode_token
from .qr import qr_payload, read_qr_payload
from .sms import SmsReassembler, to_sms_segments

__all__ = [
    "encode_token",
    "decode_token",
    "to_sms_segments",
    "SmsReassembler",
    "qr_payload",
    "read_qr_payload",
]
