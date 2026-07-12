/// الترميز المضغوط للنقل: CBOR (مجموعة جزئية قانونية) + Base45.
///
/// التوكن يُرمَّز مصفوفة CBOR بترتيب حقول ثابت يبدأ برقم إصدار
/// البروتوكول، ثم Base45 (RFC 9285) الملائم لوضع QR الأبجدي الرقمي
/// ولحمولات SMS. فك الترميز يعيد بناء الحمولة الموقَّعة حرفياً،
/// فيصمد التوقيع عبر أي قناة.
///
/// أي تعديل على البنية يرفع [tokenProtocolVersion] مع اختبار توافق خلفي.
library;

import 'dart:typed_data';

import 'errors.dart';
import 'identity.dart';
import 'token.dart';

/// بادئة حمولة التحويل في QR/SMS.
const String transferPrefix = 'W1:';

// ---------------------------------------------------------------------------
// CBOR — مجموعة جزئية قانونية صارمة: أعداد غير سالبة، بايتات، نص، مصفوفة.
// الترميز الأدنى طولاً إلزامي ذهاباً وإياباً (canonical CBOR).
// ---------------------------------------------------------------------------

final class _CborWriter {
  final BytesBuilder _out = BytesBuilder();

  Uint8List take() => _out.takeBytes();

  void _head(int major, int value) {
    assert(value >= 0);
    final m = major << 5;
    if (value < 24) {
      _out.addByte(m | value);
    } else if (value <= 0xff) {
      _out.addByte(m | 24);
      _out.addByte(value);
    } else if (value <= 0xffff) {
      _out.addByte(m | 25);
      _out.add([value >> 8, value & 0xff]);
    } else if (value <= 0xffffffff) {
      _out.addByte(m | 26);
      _out.add([value >> 24 & 0xff, value >> 16 & 0xff, value >> 8 & 0xff, value & 0xff]);
    } else {
      _out.addByte(m | 27);
      _out.add([
        value >> 56 & 0xff, value >> 48 & 0xff, value >> 40 & 0xff, value >> 32 & 0xff,
        value >> 24 & 0xff, value >> 16 & 0xff, value >> 8 & 0xff, value & 0xff,
      ]);
    }
  }

  void uint(int value) => _head(0, value);

  void bytes(List<int> value) {
    _head(2, value.length);
    _out.add(value);
  }

  void text(String value) {
    final encoded = value.codeUnits; // ASCII فقط في مخططنا (رمز العملة).
    _head(3, encoded.length);
    _out.add(encoded);
  }

  void arrayHeader(int length) => _head(4, length);
}

final class _CborReader {
  _CborReader(this._data);
  final Uint8List _data;
  int _pos = 0;

  bool get done => _pos >= _data.length;

  int _byte() {
    if (_pos >= _data.length) {
      throw const MalformedTokenException('حمولة CBOR مبتورة');
    }
    return _data[_pos++];
  }

  (int major, int value) _headOf() {
    final initial = _byte();
    final major = initial >> 5;
    final info = initial & 0x1f;
    int value;
    if (info < 24) {
      value = info;
    } else if (info == 24) {
      value = _byte();
      if (value < 24) {
        throw const MalformedTokenException('ترميز CBOR غير قانوني (طول غير أدنى)');
      }
    } else if (info == 25) {
      value = (_byte() << 8) | _byte();
      if (value <= 0xff) {
        throw const MalformedTokenException('ترميز CBOR غير قانوني (طول غير أدنى)');
      }
    } else if (info == 26) {
      value = (_byte() << 24) | (_byte() << 16) | (_byte() << 8) | _byte();
      if (value <= 0xffff) {
        throw const MalformedTokenException('ترميز CBOR غير قانوني (طول غير أدنى)');
      }
    } else if (info == 27) {
      value = 0;
      for (var i = 0; i < 8; i++) {
        value = (value << 8) | _byte();
      }
      if (value <= 0xffffffff) {
        throw const MalformedTokenException('ترميز CBOR غير قانوني (طول غير أدنى)');
      }
    } else {
      throw const MalformedTokenException('بنية CBOR غير مدعومة');
    }
    return (major, value);
  }

  int uint() {
    final (major, value) = _headOf();
    if (major != 0) throw const MalformedTokenException('توقعت عدداً في CBOR');
    return value;
  }

  Uint8List bytes(int expectedLength) {
    final (major, length) = _headOf();
    if (major != 2) throw const MalformedTokenException('توقعت بايتات في CBOR');
    if (length != expectedLength) {
      throw MalformedTokenException('طول بايتات غير متوقع: $length بدل $expectedLength');
    }
    if (_pos + length > _data.length) {
      throw const MalformedTokenException('حمولة CBOR مبتورة');
    }
    final out = Uint8List.sublistView(_data, _pos, _pos + length);
    _pos += length;
    return out;
  }

  String text(int expectedLength) {
    final (major, length) = _headOf();
    if (major != 3) throw const MalformedTokenException('توقعت نصاً في CBOR');
    if (length != expectedLength) {
      throw MalformedTokenException('طول نص غير متوقع: $length بدل $expectedLength');
    }
    final chars = <int>[];
    for (var i = 0; i < length; i++) {
      chars.add(_byte());
    }
    return String.fromCharCodes(chars);
  }

  int arrayHeader() {
    final (major, length) = _headOf();
    if (major != 4) throw const MalformedTokenException('توقعت مصفوفة CBOR');
    return length;
  }
}

// ---------------------------------------------------------------------------
// Base45 — RFC 9285: كل بايتين → 3 محارف، والبايت المفرد → محرفان.
// الأبجدية ملائمة لوضع QR الأبجدي الرقمي (رموز أصغر وأسهل مسحاً).
// ---------------------------------------------------------------------------

/// أبجدية Base45 (RFC 9285) — عامة لفحوص القنوات (QR/SMS) على الحمولة.
const String base45Alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:';

final Map<int, int> _base45Reverse = {
  for (var i = 0; i < base45Alphabet.length; i++) base45Alphabet.codeUnitAt(i): i,
};

/// ترميز بايتات إلى Base45.
String base45Encode(List<int> data) {
  final sb = StringBuffer();
  for (var i = 0; i + 1 < data.length; i += 2) {
    var v = data[i] * 256 + data[i + 1];
    sb.write(base45Alphabet[v % 45]);
    v ~/= 45;
    sb.write(base45Alphabet[v % 45]);
    sb.write(base45Alphabet[v ~/ 45]);
  }
  if (data.length.isOdd) {
    final v = data.last;
    sb.write(base45Alphabet[v % 45]);
    sb.write(base45Alphabet[v ~/ 45]);
  }
  return sb.toString();
}

/// فك Base45 — صارم: يرفض المحارف الغريبة والأطوال والقيم غير الصالحة.
Uint8List base45Decode(String text) {
  if (text.length % 3 == 1) {
    throw const MalformedTokenException('طول Base45 غير صالح');
  }
  final out = BytesBuilder();
  for (var i = 0; i < text.length; i += 3) {
    final c0 = _base45Reverse[text.codeUnitAt(i)];
    final c1 = i + 1 < text.length ? _base45Reverse[text.codeUnitAt(i + 1)] : null;
    if (c0 == null || c1 == null) {
      throw const MalformedTokenException('محرف Base45 غير صالح');
    }
    if (i + 2 < text.length) {
      final c2 = _base45Reverse[text.codeUnitAt(i + 2)];
      if (c2 == null) {
        throw const MalformedTokenException('محرف Base45 غير صالح');
      }
      final v = c0 + c1 * 45 + c2 * 2025;
      if (v > 0xffff) {
        throw const MalformedTokenException('قيمة Base45 خارج النطاق');
      }
      out.add([v ~/ 256, v % 256]);
    } else {
      final v = c0 + c1 * 45;
      if (v > 0xff) {
        throw const MalformedTokenException('قيمة Base45 خارج النطاق');
      }
      out.addByte(v);
    }
  }
  return out.takeBytes();
}

// ---------------------------------------------------------------------------
// ترميز التوكن: مصفوفة CBOR بترتيب ثابت ثم Base45 ثم البادئة.
// ---------------------------------------------------------------------------

/// توكن ← حمولة نصية جاهزة لـ QR أو مقاطع SMS.
String encodeToken(SignedToken token) {
  final writer = _CborWriter()
    ..arrayHeader(11)
    ..uint(tokenProtocolVersion)
    ..bytes(bytesFromHex(token.tokenId))
    ..bytes(bytesFromHex(token.senderPubkey))
    ..bytes(bytesFromHex(token.recipientId))
    ..uint(token.amount)
    ..text(token.currency)
    ..uint(token.seq)
    ..bytes(bytesFromHex(token.prevHash))
    ..uint(token.issuedAt)
    ..uint(token.expiresAt)
    ..bytes(bytesFromHex(token.signature));
  return transferPrefix + base45Encode(writer.take());
}

/// حمولة نصية ← توكن. لا يتحقق من التوقيع — المستقبل يستدعي
/// [SignedToken.verify] بعد الفك دائماً (انظر verify.dart).
SignedToken decodeToken(String payload) {
  final trimmed = payload.trim();
  if (!trimmed.startsWith(transferPrefix)) {
    throw const MalformedTokenException('ليست حمولة تحويل وصلة');
  }
  final reader = _CborReader(base45Decode(trimmed.substring(transferPrefix.length)));
  final length = reader.arrayHeader();
  if (length != 11) {
    throw const MalformedTokenException('بنية حمولة غير متوقعة');
  }
  final version = reader.uint();
  if (version != tokenProtocolVersion) {
    throw MalformedTokenException('إصدار بروتوكول غير مدعوم: $version');
  }
  final tokenId = hexFromBytes(reader.bytes(16));
  final senderPubkeyBytes = reader.bytes(32);
  final senderPubkey = hexFromBytes(senderPubkeyBytes);
  final recipientId = hexFromBytes(reader.bytes(8));
  final amount = reader.uint();
  final currency = reader.text(3);
  final seq = reader.uint();
  final prevHash = hexFromBytes(reader.bytes(32));
  final issuedAt = reader.uint();
  final expiresAt = reader.uint();
  final signature = hexFromBytes(reader.bytes(64));
  if (!reader.done) {
    throw const MalformedTokenException('بايتات زائدة بعد الحمولة');
  }
  return SignedToken(
    tokenId: tokenId,
    // المعرّف يُشتق من المفتاح دائماً — لا يُنقل ولا يُصدَّق من الحمولة.
    senderId: deviceIdFromPublicKey(senderPubkeyBytes),
    senderPubkey: senderPubkey,
    recipientId: recipientId,
    amount: amount,
    currency: currency,
    seq: seq,
    prevHash: prevHash,
    issuedAt: issuedAt,
    expiresAt: expiresAt,
    signature: signature,
  );
}
