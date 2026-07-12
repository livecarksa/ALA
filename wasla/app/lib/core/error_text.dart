/// تحويل أخطاء المحرك المصنّفة إلى رسائل مستخدم دقيقة معرّبة —
/// كل نوع خطأ رسالة قابلة للتصرف، لا «حدث خطأ ما».
library;

import 'package:flutter/widgets.dart';
import 'package:wasla_core/wasla_core.dart';

import '../app.dart';
import 'money.dart';

String describeWaslaError(BuildContext context, Object error) {
  final l = context.l10n;
  return switch (error) {
    SmsChecksumException(part: final p?) => l.errSegmentChecksum(p),
    SmsChecksumException() => l.errWholeChecksum,
    MalformedSmsSegmentException() => l.errMalformedSegment,
    SmsReassemblyException() => l.errReassembly,
    InvalidSignatureException() => l.errBadSignature,
    ExpiredTokenException() => l.errExpired,
    WrongRecipientException() => l.errWrongRecipient,
    MalformedTokenException() => l.errMalformed,
    InsufficientReservationException() => l.insufficientOffline(''),
    DailyCapExceededException() => l.dailyCapExceeded(''),
    _ => error.toString(),
  };
}

/// نسختا الرصيد/السقف بمبالغهما الفعلية (تُستدعى من شاشة الإرسال حيث
/// تتوفر الحالة).
String describeSendError(
  BuildContext context,
  Object error, {
  required int available,
  required int dailyRemaining,
}) {
  final l = context.l10n;
  return switch (error) {
    InsufficientReservationException() =>
      l.insufficientOffline(formatPiasters(available)),
    DailyCapExceededException() =>
      l.dailyCapExceeded(formatPiasters(dailyRemaining)),
    _ => describeWaslaError(context, error),
  };
}
