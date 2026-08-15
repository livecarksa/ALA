/// التوكن الموقّع: وحدة القيمة التي تنتقل جهازاً لجهاز.
///
/// كل توكن يحمل hash سابقه ورقم تسلسل، فتتكوّن سلسلة توقيعات متتابعة
/// مرساتها آخر تسوية — أي تفرع (إنفاق مزدوج) يُكشف حتمياً عند التسوية.
///
/// التسلسل القانوني للتوقيع مطابق حرفياً لبرهان المفهوم المُصادق عليه
/// (JSON بمفاتيح مرتّبة بلا مسافات، UTF-8) — مثبت باختبار توافق متبادل.
library;

import 'dart:convert';

import 'errors.dart';
import 'identity.dart';

/// إصدار بروتوكول التوكن — أي تعديل على البنية يرفعه ويضيف اختبار توافق خلفي.
const int tokenProtocolVersion = 1;

/// الحد الأقصى لعمر التوكن — يفرضه المحرك ولا يثق بقيمة العميل.
const int maxTokenTtlSeconds = 72 * 3600;

/// هامش انحراف الساعات المقبول لطابع الإصدار (أجهزة أوف لاين تنحرف ساعتها).
const int clockSkewToleranceSeconds = 2 * 3600;

/// اليوم UTC بصيغة YYYY-MM-DD من طابع unix بالثواني.
String utcDayOf(int unixSeconds) {
  final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$m-$d';
}

/// توكن موقّع غير قابل للتغيير.
final class SignedToken {
  const SignedToken({
    required this.tokenId,
    required this.senderId,
    required this.senderPubkey,
    required this.recipientId,
    required this.amount,
    required this.currency,
    required this.seq,
    required this.prevHash,
    required this.issuedAt,
    required this.expiresAt,
    required this.signature,
  });

  /// معرّف فريد (32 حرف hex).
  final String tokenId;

  /// معرّف المرسل — مشتق من مفتاحه العام دائماً.
  final String senderId;

  /// المفتاح العام للمرسل (64 حرف hex).
  final String senderPubkey;

  /// معرّف جهاز المستلم (16 حرف hex).
  final String recipientId;

  /// المبلغ بالقرش — عدد صحيح موجب دائماً، لا كسور عشرية في مسار المال.
  final int amount;

  /// رمز العملة: 3 حروف لاتينية كبيرة (SDG).
  final String currency;

  /// رقم التسلسل في سلسلة المرسل منذ آخر تسوية.
  final int seq;

  /// hash التوكن السابق أو مرساة آخر تسوية (64 حرف hex).
  final String prevHash;

  /// طابع الإصدار unix بالثواني.
  final int issuedAt;

  /// طابع انتهاء الصلاحية unix بالثواني.
  final int expiresAt;

  /// توقيع Ed25519 على الحمولة القانونية (128 حرف hex).
  final String signature;

  static void _checkAmount(int amount) {
    if (amount <= 0) {
      throw const MalformedTokenException('المبلغ يجب أن يكون عدداً صحيحاً موجباً بالقرش');
    }
  }

  static void _checkCurrency(String currency) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const MalformedTokenException('رمز العملة: 3 حروف لاتينية كبيرة (مثل SDG)');
    }
  }

  /// الحمولة القانونية للتوقيع: JSON بمفاتيح مرتّبة بلا مسافات (UTF-8).
  ///
  /// مطابقة حرفياً لتسلسل برهان المفهوم — لا تُعدَّل دون رفع
  /// [tokenProtocolVersion] واختبار توافق خلفي.
  static String canonicalPayload({
    required String tokenId,
    required String senderId,
    required String senderPubkey,
    required String recipientId,
    required int amount,
    required String currency,
    required int seq,
    required String prevHash,
    required int issuedAt,
    required int expiresAt,
  }) {
    // المفاتيح مرتّبة أبجدياً يدوياً — ترتيب ثابت لا يعتمد على تنفيذ المكتبة.
    return '{'
        '"amount":$amount,'
        '"currency":${jsonEncode(currency)},'
        '"expires_at":$expiresAt,'
        '"issued_at":$issuedAt,'
        '"prev_hash":${jsonEncode(prevHash)},'
        '"recipient_id":${jsonEncode(recipientId)},'
        '"sender_id":${jsonEncode(senderId)},'
        '"sender_pubkey":${jsonEncode(senderPubkey)},'
        '"seq":$seq,'
        '"token_id":${jsonEncode(tokenId)}'
        '}';
  }

  /// الحمولة القانونية لهذا التوكن.
  String get payloadCanonical => canonicalPayload(
        tokenId: tokenId,
        senderId: senderId,
        senderPubkey: senderPubkey,
        recipientId: recipientId,
        amount: amount,
        currency: currency,
        seq: seq,
        prevHash: prevHash,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
      );

  /// hash التوكن: SHA-256 على الحمولة + التوقيع — يشمل التوقيع حتى
  /// يستحيل تركيب سلسلة بديلة على نفس الحمولة.
  ///
  /// أبجدياً يقع "signature" بين "seq" و"token_id"، فيُبنى الشكل
  /// القانوني مباشرة بلا إعادة تحليل.
  String get tokenHash {
    final canonical = '{'
        '"amount":$amount,'
        '"currency":${jsonEncode(currency)},'
        '"expires_at":$expiresAt,'
        '"issued_at":$issuedAt,'
        '"prev_hash":${jsonEncode(prevHash)},'
        '"recipient_id":${jsonEncode(recipientId)},'
        '"sender_id":${jsonEncode(senderId)},'
        '"sender_pubkey":${jsonEncode(senderPubkey)},'
        '"seq":$seq,'
        '"signature":${jsonEncode(signature)},'
        '"token_id":${jsonEncode(tokenId)}'
        '}';
    return sha256Hex(utf8.encode(canonical));
  }

  /// إنشاء توكن موقّع جديد. [ttlSeconds] لا يتجاوز [maxTokenTtlSeconds].
  static Future<SignedToken> create({
    required DeviceIdentity identity,
    required String recipientId,
    required int amount,
    required int seq,
    required String prevHash,
    required int issuedAt,
    int ttlSeconds = maxTokenTtlSeconds,
    String currency = 'SDG',
    String? tokenId,
  }) async {
    _checkAmount(amount);
    _checkCurrency(currency);
    if (ttlSeconds <= 0 || ttlSeconds > maxTokenTtlSeconds) {
      throw const MalformedTokenException('عمر التوكن خارج الحد المسموح');
    }
    final id = tokenId ?? _randomTokenId();
    final payload = canonicalPayload(
      tokenId: id,
      senderId: identity.deviceId,
      senderPubkey: identity.publicKeyHex,
      recipientId: recipientId,
      amount: amount,
      currency: currency,
      seq: seq,
      prevHash: prevHash,
      issuedAt: issuedAt,
      expiresAt: issuedAt + ttlSeconds,
    );
    final signature = await identity.signUtf8(payload);
    return SignedToken(
      tokenId: id,
      senderId: identity.deviceId,
      senderPubkey: identity.publicKeyHex,
      recipientId: recipientId,
      amount: amount,
      currency: currency,
      seq: seq,
      prevHash: prevHash,
      issuedAt: issuedAt,
      expiresAt: issuedAt + ttlSeconds,
      signature: signature,
    );
  }

  static String _randomTokenId() {
    final ms = DateTime.now().microsecondsSinceEpoch;
    final seed = utf8.encode('$ms:${identityHashCode(Object())}');
    return sha256Hex(seed).substring(0, 32);
  }

  /// تحقق ذاتي كامل: اشتقاق الهوية، صحة الحقول، التوقيع، والصلاحية إن مُرّر [now].
  Future<void> verify({int? now}) async {
    if (deviceIdFromPublicKey(bytesFromHex(senderPubkey)) != senderId) {
      throw const InvalidSignatureException('معرّف المرسل لا يطابق مفتاحه العام');
    }
    _checkAmount(amount);
    _checkCurrency(currency);
    final ok = await verifySignature(
      publicKeyHex: senderPubkey,
      signatureHex: signature,
      message: utf8.encode(payloadCanonical),
    );
    if (!ok) {
      throw const InvalidSignatureException('التوقيع لا يطابق الحمولة أو المفتاح');
    }
    if (now != null && now > expiresAt) {
      throw ExpiredTokenException('التوكن ${tokenId.substring(0, 8)} منتهي الصلاحية');
    }
  }

  /// نسخة معدَّلة (للاختبارات الهجومية فقط — التوقيع يصبح باطلاً).
  SignedToken copyWith({int? amount, String? recipientId, String? senderId}) =>
      SignedToken(
        tokenId: tokenId,
        senderId: senderId ?? this.senderId,
        senderPubkey: senderPubkey,
        recipientId: recipientId ?? this.recipientId,
        amount: amount ?? this.amount,
        currency: currency,
        seq: seq,
        prevHash: prevHash,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        signature: signature,
      );

  @override
  bool operator ==(Object other) =>
      other is SignedToken &&
      other.tokenId == tokenId &&
      other.senderId == senderId &&
      other.senderPubkey == senderPubkey &&
      other.recipientId == recipientId &&
      other.amount == amount &&
      other.currency == currency &&
      other.seq == seq &&
      other.prevHash == prevHash &&
      other.issuedAt == issuedAt &&
      other.expiresAt == expiresAt &&
      other.signature == signature;

  @override
  int get hashCode => Object.hash(tokenId, signature);
}
