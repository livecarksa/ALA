/// التوافق المتبادل مع برهان المفهوم (Python): نفس البذرة ونفس الحمولة
/// يجب أن يعطيا نفس المعرّف والتوقيع والـhash حرفياً — Ed25519 حتمي.
///
/// البذرة مولَّدة بسكربت Python من نواة الـPoC المصادَق عليها بـ70 اختباراً.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wasla_core/wasla_core.dart';

void main() {
  late Map<String, dynamic> fixture;

  setUpAll(() {
    final path = '${Directory.current.path}/test/interop_fixture.json';
    fixture = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  });

  test('نفس البذرة ← نفس المعرّف والمفتاح العام', () async {
    final identity =
        await DeviceIdentity.fromSeed(bytesFromHex(fixture['seed_hex'] as String));
    expect(identity.deviceId, fixture['device_id']);
    expect(identity.publicKeyHex, fixture['public_key_hex']);
  });

  test('الحمولة القانونية مطابقة حرفياً لتسلسل الـPoC', () {
    final t = fixture['token'] as Map<String, dynamic>;
    final canonical = SignedToken.canonicalPayload(
      tokenId: t['token_id'] as String,
      senderId: t['sender_id'] as String,
      senderPubkey: t['sender_pubkey'] as String,
      recipientId: t['recipient_id'] as String,
      amount: t['amount'] as int,
      currency: t['currency'] as String,
      seq: t['seq'] as int,
      prevHash: t['prev_hash'] as String,
      issuedAt: t['issued_at'] as int,
      expiresAt: t['expires_at'] as int,
    );
    expect(canonical, fixture['canonical_payload']);
  });

  test('نفس البذرة والحمولة ← نفس التوقيع بالبايت (Ed25519 حتمي)', () async {
    final identity =
        await DeviceIdentity.fromSeed(bytesFromHex(fixture['seed_hex'] as String));
    final signature =
        await identity.signUtf8(fixture['canonical_payload'] as String);
    expect(signature, (fixture['token'] as Map)['signature']);
  });

  test('توكن الـPoC يتحقق في Dart والـhash مطابق', () async {
    final t = fixture['token'] as Map<String, dynamic>;
    final token = SignedToken(
      tokenId: t['token_id'] as String,
      senderId: t['sender_id'] as String,
      senderPubkey: t['sender_pubkey'] as String,
      recipientId: t['recipient_id'] as String,
      amount: t['amount'] as int,
      currency: t['currency'] as String,
      seq: t['seq'] as int,
      prevHash: t['prev_hash'] as String,
      issuedAt: t['issued_at'] as int,
      expiresAt: t['expires_at'] as int,
      signature: t['signature'] as String,
    );
    await token.verify(now: t['issued_at'] as int); // توقيع Python يصمد في Dart.
    expect(token.tokenHash, fixture['token_hash']); // نفس hash السلسلة.
  });
}
