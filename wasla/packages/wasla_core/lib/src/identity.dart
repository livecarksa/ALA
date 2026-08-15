/// هوية الجهاز: مفاتيح Ed25519 ومعرّف مشتق من المفتاح العام.
///
/// المعرّف = أول 16 حرف hex من SHA-256 للمفتاح العام، فلا انتحال هوية
/// دون حيازة المفتاح الخاص. تخزين المفتاح مسؤولية طبقة التطبيق
/// (flutter_secure_storage) — النواة لا تلمس أي تخزين.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// SHA-256 كسلسلة hex صغيرة الحروف.
String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

/// bytes ← hex (صارم: طول زوجي وأحرف صالحة فقط).
Uint8List bytesFromHex(String hex) {
  if (hex.length.isOdd || !RegExp(r'^[0-9a-f]*$').hasMatch(hex)) {
    throw FormatException('hex غير صالح: $hex');
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// hex ← bytes.
String hexFromBytes(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// اشتقاق معرّف الجهاز من المفتاح العام الخام (32 بايت).
String deviceIdFromPublicKey(List<int> publicKeyBytes) =>
    sha256Hex(publicKeyBytes).substring(0, 16);

/// زوج مفاتيح الجهاز مع عمليات التوقيع والتحقق.
final class DeviceIdentity {
  DeviceIdentity._(this._keyPair, this.publicKeyHex, this.deviceId);

  final SimpleKeyPair _keyPair;

  /// المفتاح العام hex (64 حرفاً / 32 بايت).
  final String publicKeyHex;

  /// معرّف الجهاز المشتق (16 حرف hex).
  final String deviceId;

  static final Ed25519 _algorithm = Ed25519();

  /// توليد هوية جديدة (المفتاح داخل الذاكرة — التخزين شأن التطبيق).
  static Future<DeviceIdentity> generate() async {
    final keyPair = await _algorithm.newKeyPair();
    return _fromKeyPair(keyPair);
  }

  /// استعادة هوية من بذرة المفتاح الخاص (32 بايت) المخزنة بأمان.
  static Future<DeviceIdentity> fromSeed(List<int> seed32) async {
    if (seed32.length != 32) {
      throw ArgumentError('بذرة Ed25519 يجب أن تكون 32 بايت');
    }
    final keyPair = await _algorithm.newKeyPairFromSeed(seed32);
    return _fromKeyPair(keyPair);
  }

  static Future<DeviceIdentity> _fromKeyPair(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    final pubHex = hexFromBytes(publicKey.bytes);
    return DeviceIdentity._(keyPair, pubHex, deviceIdFromPublicKey(publicKey.bytes));
  }

  /// بذرة المفتاح الخاص للتخزين الآمن فقط — لا تُسجَّل ولا تُرسَل أبداً.
  Future<Uint8List> extractSeed() async =>
      Uint8List.fromList(await _keyPair.extractPrivateKeyBytes());

  /// توقيع رسالة، يعيد التوقيع hex (128 حرفاً / 64 بايت).
  Future<String> sign(List<int> message) async {
    final signature = await _algorithm.sign(message, keyPair: _keyPair);
    return hexFromBytes(signature.bytes);
  }

  /// توقيع نص UTF-8 مباشرة.
  Future<String> signUtf8(String message) => sign(utf8.encode(message));
}

/// تحقق توقيع Ed25519. يعيد true/false ولا يرمي إلا على hex تالف البنية.
Future<bool> verifySignature({
  required String publicKeyHex,
  required String signatureHex,
  required List<int> message,
}) async {
  final publicKey = SimplePublicKey(
    bytesFromHex(publicKeyHex),
    type: KeyPairType.ed25519,
  );
  return Ed25519().verify(
    message,
    signature: Signature(bytesFromHex(signatureHex), publicKey: publicKey),
  );
}
