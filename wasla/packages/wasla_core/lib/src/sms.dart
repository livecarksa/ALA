/// قناة SMS للهواتف العادية (المرحلة C): تقسيم حمولة التوكن إلى مقاطع
/// تتسع كلٌّ منها في رسالة SMS واحدة (160 محرف GSM-7)، وإعادة تجميعها
/// الصارمة عند المستقبِل — بما يخدم الإدخال اليدوي حرفاً حرفاً.
///
/// بنية المقطع قبل الدرع: `W1S#معرف#جزء#إجمالي#تحقق#شريحة` حيث المعرف
/// 6 محارف Base45 من تجزئة الحمولة كاملة (يجمع الأجزاء ويثبت سلامة
/// الرسالة المجمَّعة معاً)، والتحقق محرفان لكل مقطع يلتقطان أخطاء
/// الإدخال اليدوي في الجزء المصاب وحده.
///
/// الدرع: المسافة (من أبجدية Base45) تُستبدل بـ `(` فلا يحوي المقطع
/// المرسَل أي فراغ — ففك التجميع يتسامح مع فراغات وأسطر وحروف صغيرة
/// يدخلها المستخدم، دون أي لبس مع محارف الحمولة.
///
/// هذه سلامة إدخال لا أمن تشفيري: الأمن من توقيع Ed25519 داخل التوكن
/// نفسه، والتحقق النهائي دوماً عبر فك الحمولة ثم verify.dart.
///
/// بادئة المقطع `W1S` مرتبطة بإصدار بروتوكول التوكن — أي تغيير في بنية
/// المقاطع يرقّيها (W2S) مع حالة توافق خلفي.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;

import 'codec.dart';
import 'errors.dart';

/// بادئة مقطع SMS (الحقل الأول قبل الفاصل).
const String smsSegmentPrefix = 'W1S';

/// سعة رسالة SMS واحدة بمحارف GSM-7 الأساسية.
const int maxSmsChars = 160;

/// أقصى عدد مقاطع لرسالة واحدة — يحدّ الذاكرة ويكفي أضعاف حجم التوكن.
const int maxSmsSegments = 20;

/// فاصل الحقول — خارج أبجدية Base45 وداخل GSM-7 الأساسية.
const String _fieldSeparator = '#';

/// درع المسافة — المسافة من أبجدية Base45 فتُستبدل كي يخلو المقطع من الفراغ.
const String _spaceArmor = '(';

const int _msgIdChars = 6;
const int _checksumChars = 2;

/// سعة شريحة الحمولة في المقطع الواحد: 160 ناقص أسوأ ترويسة
/// (`W1S#` + معرف 6 + `#` + جزء 2 + `#` + إجمالي 2 + `#` + تحقق 2 + `#`).
const int smsChunkChars =
    maxSmsChars - (smsSegmentPrefix.length + _msgIdChars + _checksumChars + 4 + 4 + 4);

/// معرّف الرسالة: أول 6 محارف Base45 من SHA-256 للحمولة كاملة —
/// حتمي (نفس التوكن ← نفس المقاطع) ويثبت سلامة التجميع النهائي.
String _messageId(String payload) =>
    base45Encode(sha256.convert(ascii.encode(payload)).bytes).substring(0, _msgIdChars);

/// تحقق المقطع: محرفان يربطان الشريحة بموضعها ورسالتها.
String _segmentChecksum(String msgId, int part, int total, String chunk) =>
    base45Encode(sha256.convert(utf8.encode('$msgId#$part#$total#$chunk')).bytes)
        .substring(0, _checksumChars);

final Set<int> _base45CodeUnits = base45Alphabet.codeUnits.toSet();

bool _isBase45(String s) => s.codeUnits.every(_base45CodeUnits.contains);

/// عدد عشري قانوني: أرقام فقط بلا أصفار بادئة — يرفض «01» حتى لا يمرّ
/// شكلان لنفس القيمة بتحققين مختلفين.
int _canonicalInt(String field, String label) {
  final value = int.tryParse(field);
  if (value == null || value.toString() != field) {
    throw MalformedSmsSegmentException('حقل $label غير قانوني: «$field»');
  }
  return value;
}

/// مقطع SMS واحد — قيمة محضة قابلة للتركيب والفك.
final class SmsSegment {
  SmsSegment({
    required this.msgId,
    required this.part,
    required this.total,
    required this.chunk,
  }) {
    if (msgId.length != _msgIdChars || !_isBase45(msgId)) {
      throw const MalformedSmsSegmentException('معرّف رسالة غير صالح');
    }
    if (total < 1 || total > maxSmsSegments) {
      throw MalformedSmsSegmentException('إجمالي أجزاء خارج النطاق: $total');
    }
    if (part < 1 || part > total) {
      throw MalformedSmsSegmentException('رقم جزء خارج النطاق: $part من $total');
    }
    if (chunk.isEmpty || chunk.length > smsChunkChars || !_isBase45(chunk)) {
      throw const MalformedSmsSegmentException('شريحة حمولة غير صالحة');
    }
  }

  final String msgId;
  final int part;
  final int total;
  final String chunk;

  /// تحقق هذا المقطع (محسوب لا مخزَّن — لا يمكن أن يتناقض).
  String get checksum => _segmentChecksum(msgId, part, total, chunk);

  /// النص الجاهز للإرسال في رسالة واحدة — مدروع بلا أي فراغ.
  String get text =>
      '$smsSegmentPrefix#$msgId#$part#$total#$checksum#$chunk'
          .replaceAll(' ', _spaceArmor);

  /// فك نص مقطع مُدخل يدوياً: يتسامح مع الفراغات والأسطر والحروف
  /// الصغيرة، ويرفض البنية التالفة، ويكشف أخطاء الإدخال بالتحقق.
  static SmsSegment parse(String raw) {
    final normalized = raw
        .replaceAll(RegExp(r'\s'), '')
        .toUpperCase()
        .replaceAll(_spaceArmor, ' ');
    final fields = normalized.split(_fieldSeparator);
    if (fields.length != 6 || fields[0] != smsSegmentPrefix) {
      throw const MalformedSmsSegmentException('ليست مقطع SMS وصلة');
    }
    final part = _canonicalInt(fields[2], 'الجزء');
    final total = _canonicalInt(fields[3], 'الإجمالي');
    final segment =
        SmsSegment(msgId: fields[1], part: part, total: total, chunk: fields[5]);
    if (fields[4] != segment.checksum) {
      throw SmsChecksumException(
        'تحقق الجزء $part لا يطابق — أعد إدخال هذا الجزء',
        part: part,
      );
    }
    return segment;
  }
}

/// حمولة توكن (W1:…) ← نصوص مقاطع جاهزة للإرسال بالترتيب.
List<String> splitTokenPayloadForSms(String payload) {
  if (!payload.startsWith(transferPrefix)) {
    throw const MalformedTokenException('ليست حمولة تحويل وصلة');
  }
  if (!_isBase45(payload)) {
    throw const MalformedTokenException('محرف خارج أبجدية الحمولة');
  }
  final total = (payload.length + smsChunkChars - 1) ~/ smsChunkChars;
  if (total > maxSmsSegments) {
    throw const MalformedTokenException('حمولة أكبر من سعة قناة SMS');
  }
  final msgId = _messageId(payload);
  return [
    for (var part = 1; part <= total; part++)
      SmsSegment(
        msgId: msgId,
        part: part,
        total: total,
        chunk: payload.substring(
          (part - 1) * smsChunkChars,
          part * smsChunkChars > payload.length ? payload.length : part * smsChunkChars,
        ),
      ).text,
  ];
}

/// حالة رسالة قيد التجميع — للواجهة: «وصل 2 من 3، ينقص الجزء 1».
final class SmsInboxStatus {
  const SmsInboxStatus({
    required this.msgId,
    required this.total,
    required this.receivedParts,
  });

  final String msgId;
  final int total;
  final List<int> receivedParts;

  List<int> get missingParts =>
      [for (var p = 1; p <= total; p++) if (!receivedParts.contains(p)) p];
}

final class _Partial {
  _Partial(this.total);
  final int total;
  final Map<int, String> chunks = {};
}

/// أقصى رسائل قيد التجميع يحفظها الصندوق — الأقدم يُخلى عند التجاوز
/// (يصدّ إغراق الذاكرة بمقاطع لا تكتمل أبداً).
const int maxPendingSmsMessages = 8;

/// كم رسالة مكتملة يتذكرها الصندوق ليصدّ مكرراتها المتأخرة بصمت.
const int _completedMemory = 32;

/// صندوق تجميع مقاطع واردة — يدير رسائل متداخلة من مرسلين مختلفين
/// ويعيد الحمولة الكاملة فور اكتمال رسالتها وثبوت سلامتها.
final class SmsInbox {
  final Map<String, _Partial> _partials = {};

  /// آخر الرسائل المكتملة — المكرر الواصل بعد الاكتمال يُتجاهل بدل أن
  /// يفتح «رسالة شبح» عالقة أو يعيد الحمولة مرة ثانية.
  final Set<String> _completed = {};

  /// إضافة مقطع (نص مُدخل يدوياً أو وارد آلياً). تعيد الحمولة الكاملة
  /// عند اكتمال رسالتها، وإلا null. المكرر المطابق يُتجاهل بصمت.
  String? add(String rawSegment) {
    final segment = SmsSegment.parse(rawSegment);
    if (_completed.contains(segment.msgId)) return null;
    var partial = _partials[segment.msgId];
    if (partial == null) {
      while (_partials.length >= maxPendingSmsMessages) {
        _partials.remove(_partials.keys.first); // الأقدم إدخالاً يُخلى.
      }
      partial = _Partial(segment.total);
      _partials[segment.msgId] = partial;
    }
    if (partial.total != segment.total) {
      _partials.remove(segment.msgId); // إسقاط ذاتي — الإرسال التالي يبدأ نظيفاً.
      throw SmsReassemblyException(
          'إجمالي متناقض للرسالة ${segment.msgId}: ${segment.total} بدل ${partial.total} — أُسقطت الرسالة');
    }
    final existing = partial.chunks[segment.part];
    if (existing != null && existing != segment.chunk) {
      _partials.remove(segment.msgId); // حالة مسمومة — تُسقط ويعاد الإرسال كاملاً.
      throw SmsReassemblyException(
          'الجزء ${segment.part} وصل مرتين بمحتوى مختلف — أُسقطت الرسالة');
    }
    partial.chunks[segment.part] = segment.chunk;

    if (partial.chunks.length < partial.total) return null;

    final payload =
        [for (var p = 1; p <= partial.total; p++) partial.chunks[p]!].join();
    _partials.remove(segment.msgId);
    if (_messageId(payload) != segment.msgId) {
      // لا تُسجَّل مكتملةً: إعادة إدخال الأجزاء الصحيحة يجب أن تُقبل.
      throw const SmsChecksumException(
          'سلامة الرسالة المجمَّعة لا تثبت — أعد إدخال الأجزاء كلها');
    }
    _completed.add(segment.msgId);
    while (_completed.length > _completedMemory) {
      _completed.remove(_completed.first);
    }
    return payload;
  }

  /// الرسائل الناقصة قيد التجميع.
  List<SmsInboxStatus> get pending => [
        for (final entry in _partials.entries)
          SmsInboxStatus(
            msgId: entry.key,
            total: entry.value.total,
            receivedParts: entry.value.chunks.keys.toList()..sort(),
          ),
      ];

  /// إسقاط رسالة قيد التجميع (إلغاء من المستخدم).
  void forget(String msgId) => _partials.remove(msgId);
}
