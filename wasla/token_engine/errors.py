"""أخطاء محرك التوكنات."""


class WaslaError(Exception):
    """الخطأ الأساس لكل أخطاء وصلة."""


class InvalidSignature(WaslaError):
    """توقيع غير صالح أو حمولة معدَّلة."""


class ExpiredToken(WaslaError):
    """توكن تجاوز صلاحيته الزمنية قبل التسوية."""


class DailyCapExceeded(WaslaError):
    """تجاوز السقف اليومي للإنفاق الأوف لاين."""


class InsufficientOfflineBalance(WaslaError):
    """الرصيد الأوف لاين المتاح لا يغطي المبلغ."""


class ChainBroken(WaslaError):
    """سلسلة التوقيعات غير متصلة (hash سابق أو تسلسل غير متطابق)."""
