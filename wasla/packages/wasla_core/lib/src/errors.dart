/// أخطاء المحرك — كل خطأ نوع مستقل حتى تعالجه الواجهة برسالة دقيقة.
library;

/// الخطأ الأساس لكل أخطاء وصلة.
sealed class WaslaException implements Exception {
  const WaslaException(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

/// توقيع غير صالح أو حمولة معدَّلة أو هوية لا تطابق المفتاح.
final class InvalidSignatureException extends WaslaException {
  const InvalidSignatureException(super.message);
}

/// توكن تجاوز صلاحيته الزمنية قبل التسوية.
final class ExpiredTokenException extends WaslaException {
  const ExpiredTokenException(super.message);
}

/// حمولة أو بنية توكن غير صالحة (ترميز، حقول، حجم).
final class MalformedTokenException extends WaslaException {
  const MalformedTokenException(super.message);
}

/// تجاوز السقف اليومي للإنفاق الأوف لاين.
final class DailyCapExceededException extends WaslaException {
  const DailyCapExceededException(super.message);
}

/// الرصيد المحجوز أوف لاين لا يغطي المبلغ.
final class InsufficientReservationException extends WaslaException {
  const InsufficientReservationException(super.message);
}

/// التوكن موجّه لجهاز آخر.
final class WrongRecipientException extends WaslaException {
  const WrongRecipientException(super.message);
}

/// مقطع SMS ببنية غير صالحة (بادئة، حقول، محارف).
final class MalformedSmsSegmentException extends WaslaException {
  const MalformedSmsSegmentException(super.message);
}

/// مجموع تحقق SMS لا يطابق — خطأ إدخال يدوي على الأغلب. حين يُعرف
/// [part] يُعاد إدخال ذلك الجزء وحده؛ وحين يكون null فسلامة الرسالة
/// المجمَّعة كلها لم تثبت وتُعاد الأجزاء جميعاً.
/// (سلامة إدخال لا أمن — الأمن من توقيع التوكن.)
final class SmsChecksumException extends WaslaException {
  const SmsChecksumException(super.message, {this.part});

  /// رقم الجزء المصاب إن عُرف؛ null تعني الرسالة المجمَّعة كلها.
  final int? part;
}

/// تعارض أثناء إعادة تجميع مقاطع SMS: إجمالي متناقض لنفس الرسالة أو
/// جزء يصل مرتين بمحتوى مختلف.
final class SmsReassemblyException extends WaslaException {
  const SmsReassemblyException(super.message);
}
