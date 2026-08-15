/// الحجز المسبق والسقف اليومي + تحقق المستقبِل أوف لاين + الهوية.
library;

import 'package:test/test.dart';
import 'package:wasla_core/wasla_core.dart';

import 'support.dart';

void main() {
  group('الحجز المسبق (reservation)', () {
    test('الإرسال يخصم من المحجوز ويقدّم السلسلة', () async {
      final (reservation, _) = await fundedReservation(reserved: 50000);
      final head0 = reservation.chainHead;
      final token = await reservation.send(
          recipientId: 'aabbccddeeff0011', amount: 20000, now: t0);
      expect(reservation.availableBalance, 30000);
      expect(reservation.nextSeq, 1);
      expect(reservation.chainHead, token.tokenHash);
      expect(reservation.chainHead, isNot(head0));
      expect(token.prevHash, head0);
    });

    test('رفض تجاوز الرصيد المحجوز', () async {
      final (reservation, _) = await fundedReservation(reserved: 10000);
      expect(
        () => reservation.send(recipientId: 'aabbccddeeff0011', amount: 10001, now: t0),
        throwsA(isA<InsufficientReservationException>()),
      );
    });

    test('رفض تجاوز السقف اليومي محفظياً ثم السماح في اليوم التالي', () async {
      final (reservation, _) =
          await fundedReservation(reserved: 100000, dailyCap: 30000);
      await reservation.send(recipientId: 'aabbccddeeff0011', amount: 20000, now: t0);
      expect(
        () => reservation.send(recipientId: 'aabbccddeeff0011', amount: 15000, now: t0),
        throwsA(isA<DailyCapExceededException>()),
      );
      expect(reservation.spentOn(t0), 20000);
      final nextDay = await reservation.send(
          recipientId: 'aabbccddeeff0011', amount: 15000, now: t0 + oneDay);
      expect(nextDay.amount, 15000);
    });

    test('الاستلام يتحقق ويرفض وجهة غيره ويهمل التكرار', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);
      final (other, _) = await fundedReservation(engine: engine, reserved: 0);

      final token = await sender.send(
          recipientId: recipient.deviceId, amount: 5000, now: t0);
      await recipient.receive(token, now: t0);
      await recipient.receive(token, now: t0); // تكرار — بلا أثر.
      expect(recipient.receivedTokens, hasLength(1));

      expect(
        () => other.receive(token, now: t0),
        throwsA(isA<WrongRecipientException>()),
      );
    });

    test('استلام منتهي الصلاحية يُرفض فوراً', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);
      final token = await sender.send(
          recipientId: recipient.deviceId, amount: 5000, now: t0);
      expect(
        () => recipient.receive(token, now: token.expiresAt + 1),
        throwsA(isA<ExpiredTokenException>()),
      );
    });

    test('applySettlement يصفّر السلسلة ويرفض رصيداً سالباً', () async {
      final (reservation, _) = await fundedReservation(reserved: 50000);
      await reservation.send(recipientId: 'aabbccddeeff0011', amount: 5000, now: t0);
      reservation.applySettlement(newBalance: 45000, newAnchor: 'a' * 64);
      expect(reservation.availableBalance, 45000);
      expect(reservation.nextSeq, 0);
      expect(reservation.sentTokens, isEmpty);
      expect(() => reservation.applySettlement(newBalance: -1, newAnchor: 'b' * 64),
          throwsA(isA<ArgumentError>()));
    });

    test('رفض مبلغ صفري أو سالب وعملة غير قياسية عند الإنشاء', () async {
      final identity = await DeviceIdentity.generate();
      for (final bad in [0, -5000]) {
        expect(
          () => SignedToken.create(
              identity: identity, recipientId: 'aabbccddeeff0011',
              amount: bad, seq: 0, prevHash: 'a' * 64, issuedAt: t0),
          throwsA(isA<MalformedTokenException>()),
        );
      }
      expect(
        () => SignedToken.create(
            identity: identity, recipientId: 'aabbccddeeff0011',
            amount: 100, seq: 0, prevHash: 'a' * 64, issuedAt: t0,
            currency: 'sd'),
        throwsA(isA<MalformedTokenException>()),
      );
    });
  });

  group('تحقق المستقبِل أوف لاين (verify)', () {
    test('حمولة سليمة تمر بكل الفحوص', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);
      final token = await sender.send(
          recipientId: recipient.deviceId, amount: 35000, now: t0);

      final received = await verifyIncomingPayload(
        payload: encodeToken(token),
        recipientDeviceId: recipient.deviceId,
        now: t0 + 60,
      );
      expect(received.amount, 35000);
      expect(received.senderId, sender.deviceId);
    });

    test('كل مسار رفض يرمي نوعه الدقيق', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);
      final token = await sender.send(
          recipientId: recipient.deviceId, amount: 1000, now: t0);
      final payload = encodeToken(token);

      expect(
        () => verifyIncomingPayload(
            payload: 'حمولة تالفة', recipientDeviceId: recipient.deviceId, now: t0),
        throwsA(isA<MalformedTokenException>()),
      );
      expect(
        () => verifyIncomingPayload(
            payload: payload,
            recipientDeviceId: 'ffffffffffffffff',
            now: t0),
        throwsA(isA<WrongRecipientException>()),
      );
      expect(
        () => verifyIncomingPayload(
            payload: payload,
            recipientDeviceId: recipient.deviceId,
            now: token.expiresAt + 1),
        throwsA(isA<ExpiredTokenException>()),
      );
    });
  });

  group('الهوية (identity)', () {
    test('الاستعادة من البذرة تعيد نفس الهوية والتوقيع حتمي', () async {
      final original = await DeviceIdentity.generate();
      final seed = await original.extractSeed();
      final restored = await DeviceIdentity.fromSeed(seed);
      expect(restored.deviceId, original.deviceId);
      expect(restored.publicKeyHex, original.publicKeyHex);
      expect(await restored.signUtf8('وصلة'), await original.signUtf8('وصلة'));
    });

    test('انتحال المعرّف يفشل: الاشتقاق من المفتاح إلزامي', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);
      final token = await sender.send(
          recipientId: recipient.deviceId, amount: 1000, now: t0);
      final impersonated = token.copyWith(senderId: recipient.deviceId);
      expect(impersonated.verify(), throwsA(isA<InvalidSignatureException>()));
    });

    test('بذرة بطول خاطئ تُرفض وhex تالف يُرفض', () async {
      expect(() => DeviceIdentity.fromSeed([1, 2, 3]), throwsA(isA<ArgumentError>()));
      expect(() => bytesFromHex('zz'), throwsA(isA<FormatException>()));
      expect(() => bytesFromHex('abc'), throwsA(isA<FormatException>()));
    });
  });
}
