/// ثبات الترميز ذهاباً وإياباً (CBOR/Base45) — بوابة إلزامية،
/// مع متجهات RFC 9285 وحالات التلف والبتر وإصدار البروتوكول.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:wasla_core/wasla_core.dart';

import 'support.dart';

void main() {
  group('Base45 (RFC 9285)', () {
    test('متجهات المعيار القياسية', () {
      expect(base45Encode(utf8.encode('AB')), 'BB8');
      expect(base45Encode(utf8.encode('Hello!!')), '%69 VD92EX0');
      expect(base45Encode(utf8.encode('base-45')), 'UJCLQE7W581');
      expect(utf8.decode(base45Decode('QED8WEX0')), 'ietf!');
    });

    test('ذهاب وإياب لأطوال زوجية وفردية وحواف', () {
      for (final data in [
        <int>[],
        [0],
        [255],
        [0, 0],
        [255, 255],
        List.generate(187, (i) => i % 256),
        List.generate(188, (i) => (i * 7) % 256),
      ]) {
        expect(base45Decode(base45Encode(data)), data);
      }
    });

    test('رفض المحارف الغريبة والأطوال والقيم غير الصالحة', () {
      expect(() => base45Decode('ab'), throwsA(isA<MalformedTokenException>()));
      expect(() => base45Decode('A'), throwsA(isA<MalformedTokenException>()));
      expect(() => base45Decode('::'), throwsA(isA<MalformedTokenException>()));
      expect(() => base45Decode('ZZZ'), throwsA(isA<MalformedTokenException>()));
    });
  });

  group('ترميز التوكن CBOR+Base45', () {
    test('ذهاب وإياب يحفظ كل الحقول والتوقيع يصمد', () async {
      final identity = await DeviceIdentity.generate();
      final token = await craft(identity,
          recipientId: 'aabbccddeeff0011', amount: 123456789,
          seq: 3, prevHash: 'c' * 64, issuedAt: t0);

      final payload = encodeToken(token);
      expect(payload, startsWith(transferPrefix));
      final decoded = decodeToken(payload);
      expect(decoded, token);
      await decoded.verify(now: t0 + 10); // التوقيع يصمد عبر الترميز.
    });

    test('الحمولة قصيرة بما يكفي لرمز QR سهل المسح ولمقاطع SMS', () async {
      final identity = await DeviceIdentity.generate();
      final token = await craft(identity,
          recipientId: 'aabbccddeeff0011', amount: 35000,
          seq: 0, prevHash: 'a' * 64, issuedAt: t0);
      final payload = encodeToken(token);
      // Base45 يضخم بمعدل 1.5: ~170 بايت CBOR → ~260 حرفاً.
      expect(payload.length, lessThanOrEqualTo(300));
      // كل المحارف من أبجدية QR الأبجدية الرقمية + البادئة.
      expect(
        RegExp(r'^W1:[0-9A-Z $%*+\-./:]+$').hasMatch(payload),
        isTrue,
      );
    });

    test('قلب محرف واحد يكسر الفك أو التوقيع — لا قبول صامت', () async {
      final identity = await DeviceIdentity.generate();
      final token = await craft(identity,
          recipientId: 'aabbccddeeff0011', amount: 35000,
          seq: 0, prevHash: 'b' * 64, issuedAt: t0);
      final payload = encodeToken(token);

      final index = payload.length ~/ 2;
      final flipped = payload[index] == 'A' ? 'B' : 'A';
      final corrupted =
          payload.substring(0, index) + flipped + payload.substring(index + 1);

      var rejected = false;
      try {
        final decoded = decodeToken(corrupted);
        await decoded.verify();
      } on WaslaException {
        rejected = true;
      }
      expect(rejected, isTrue);
    });

    test('البتر والبايتات الزائدة والبادئة الغريبة تُرفض', () async {
      final identity = await DeviceIdentity.generate();
      final token = await craft(identity,
          recipientId: 'aabbccddeeff0011', amount: 1000,
          seq: 0, prevHash: 'd' * 64, issuedAt: t0);
      final payload = encodeToken(token);

      expect(() => decodeToken(payload.substring(0, payload.length - 6)),
          throwsA(isA<MalformedTokenException>()));
      expect(() => decodeToken('${payload}AAA'),
          throwsA(isA<MalformedTokenException>()));
      expect(() => decodeToken('X9:${payload.substring(3)}'),
          throwsA(isA<MalformedTokenException>()));
      expect(() => decodeToken('نص عشوائي'),
          throwsA(isA<MalformedTokenException>()));
    });

    test('إصدار بروتوكول غير مدعوم يُرفض صراحة', () async {
      final identity = await DeviceIdentity.generate();
      final token = await craft(identity,
          recipientId: 'aabbccddeeff0011', amount: 1000,
          seq: 0, prevHash: 'e' * 64, issuedAt: t0);
      final wire = base45Decode(encodeToken(token).substring(transferPrefix.length));
      // ترويسة المصفوفة (0x8b) ثم uint الإصدار = 1 — نرفعه إلى 2.
      expect(wire[1], 0x01);
      final tampered = [...wire]..[1] = 0x02;
      expect(
        () => decodeToken(transferPrefix + base45Encode(tampered)),
        throwsA(predicate((e) =>
            e is MalformedTokenException && e.message.contains('إصدار'))),
      );
    });

    test('المعرّف المنقول لا يُصدَّق: الهوية تُشتق من المفتاح دائماً', () async {
      final identity = await DeviceIdentity.generate();
      final token = await craft(identity,
          recipientId: 'aabbccddeeff0011', amount: 1000,
          seq: 0, prevHash: 'f' * 64, issuedAt: t0);
      final decoded = decodeToken(encodeToken(token));
      expect(decoded.senderId,
          deviceIdFromPublicKey(bytesFromHex(decoded.senderPubkey)));
    });
  });
}
