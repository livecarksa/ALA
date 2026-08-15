/// تحقق المستقبِل أوف لاين — كل ما يجريه جهاز المستلم لحظة المسح
/// بلا أي شبكة: فك الترميز، التوقيع، اشتقاق الهوية، الصلاحية، والوجهة.
///
/// هذا التحقق يحمي المستلم من حمولة مزوّرة أو معدَّلة أو موجّهة لغيره؛
/// الحسم النهائي (التفرع، السقف، الرصيد) يبقى للتسوية.
library;

import 'codec.dart';
import 'errors.dart';
import 'token.dart';

/// نتيجة تحقق مستلم ناجحة.
final class ReceivedToken {
  const ReceivedToken(this.token);

  /// التوكن المتحقق منه.
  final SignedToken token;

  /// المبلغ بالقرش.
  int get amount => token.amount;

  /// معرّف المرسل المشتق من مفتاحه.
  String get senderId => token.senderId;
}

/// تحقق كامل لحمولة واردة (QR أو SMS مجمَّعة) على جهاز المستلم.
///
/// يرمي نوع الخطأ الدقيق: [MalformedTokenException] لحمولة تالفة،
/// [InvalidSignatureException] لتوقيع لا يصمد، [ExpiredTokenException]
/// لصلاحية منتهية، [WrongRecipientException] لتوكن موجّه لجهاز آخر.
Future<ReceivedToken> verifyIncomingPayload({
  required String payload,
  required String recipientDeviceId,
  required int now,
}) async {
  final token = decodeToken(payload);
  await token.verify(now: now);
  if (token.recipientId != recipientDeviceId) {
    throw const WrongRecipientException('التوكن موجّه لجهاز آخر');
  }
  return ReceivedToken(token);
}
