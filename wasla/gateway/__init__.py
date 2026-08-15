"""بوابة التسوية — التكامل التجريبي مع بيئة اختبار بنكك.

في الإنتاج تستبدل هذه الوحدة بواجهات بنكك الفعلية (البند التعاقدي
في اتفاقية الاستثمار). هنا محاكاة كاملة السلوك: خادم HTTP بواجهة
REST، قاعدة SQLite معمّرة تنجو من إعادة التشغيل، وتسوية idempotent
بمعرّف دفعة، وتقرير مطابقة يومية — متطلبات الشراكة الثلاثة
في القسم 5.3 من الدراسة.
"""

from .client import GatewayClient
from .sandbox import BankakSandbox
from .service import GatewayService

__all__ = ["GatewayService", "BankakSandbox", "GatewayClient"]
