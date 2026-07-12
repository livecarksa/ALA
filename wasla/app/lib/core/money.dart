/// المبالغ بالقرش (int) داخلياً، وتُعرض جنيهاً سودانياً بأرقام غربية —
/// قرار حاكم من الخطة: «أرقام غربية في المبالغ».
library;

import 'package:intl/intl.dart';

final NumberFormat _sdg = NumberFormat('#,##0.##', 'en');

/// قرش ← نص مبلغ بالجنيه بأرقام غربية (بلا رمز العملة).
String formatPiasters(int piasters) => _sdg.format(piasters / 100);

const _easternZero = 0x0660; // ٠
const _extendedZero = 0x06F0; // ۰

/// إدخال مستخدم ← قرش. يقبل الأرقام العربية الشرقية ويحوّلها،
/// ويعيد null لمدخل غير صالح أو غير موجب.
int? parsePiasters(String raw) {
  final buffer = StringBuffer();
  for (final code in raw.trim().replaceAll('٫', '.').replaceAll(',', '').codeUnits) {
    if (code >= _easternZero && code <= _easternZero + 9) {
      buffer.writeCharCode('0'.codeUnitAt(0) + (code - _easternZero));
    } else if (code >= _extendedZero && code <= _extendedZero + 9) {
      buffer.writeCharCode('0'.codeUnitAt(0) + (code - _extendedZero));
    } else {
      buffer.writeCharCode(code);
    }
  }
  final value = double.tryParse(buffer.toString());
  if (value == null || value <= 0 || !value.isFinite) return null;
  final piasters = (value * 100).round();
  return piasters > 0 ? piasters : null;
}

/// اختصار معرّف جهاز للعرض: 4 + … + 4.
String shortId(String id) =>
    id.length <= 10 ? id : '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
