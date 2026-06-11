"""محرك التسوية — قضبان وصلة فوق بيئة اختبار بنكك.

عند عودة الاتصال تُرفع سلاسل التوكنات، فيتحقق المحرك من التوقيعات
واتصال السلاسل ويكشف أي تفرع (إنفاق مزدوج) ويطبّق السقوف والصلاحية،
ثم يقيّد النتيجة في دفتر مزدوج القيد.
"""

from .engine import SettlementEngine, RejectReason
from .ledger import Ledger

__all__ = ["SettlementEngine", "RejectReason", "Ledger"]
