/// بوابات الخطة الإلزامية: قبول السلسلة السليمة، رفض التفرع (داخل
/// الدفعة وعبرها)، رفض المنتهي، رفض تجاوز السقف، رفض التوقيع التالف.
library;

import 'package:test/test.dart';
import 'package:wasla_core/wasla_core.dart';

import 'support.dart';

void main() {
  group('قبول سلسلة سليمة', () {
    test('سلسلة ثلاثية تُسوّى كاملة والأرصدة مضبوطة', () async {
      final engine = InMemorySettlement();
      final (alice, _) = await fundedReservation(engine: engine, reserved: 100000);
      final (bob, _) = await fundedReservation(engine: engine, reserved: 20000);
      final (shop, _) = await fundedReservation(engine: engine, reserved: 0);

      final tk1 = await alice.send(recipientId: bob.deviceId, amount: 30000, now: t0);
      await bob.receive(tk1, now: t0);
      final tk2 = await alice.send(recipientId: shop.deviceId, amount: 10000, now: t0 + 60);
      await shop.receive(tk2, now: t0 + 60);
      final tk3 = await bob.send(recipientId: shop.deviceId, amount: 5000, now: t0 + 120);
      await shop.receive(tk3, now: t0 + 120);

      // الطرفان يرفعان — المكرر يُسوّى مرة واحدة فقط.
      final batch = [
        ...alice.tokensForSettlement(),
        ...bob.tokensForSettlement(),
        ...shop.tokensForSettlement(),
      ];
      final report = await engine.settle(batch, now: t0 + 3600);

      expect(report.settled, hasLength(3));
      expect(report.fraudAlerts, isEmpty);
      expect(engine.balances[alice.deviceId], 60000);
      expect(engine.balances[bob.deviceId], 45000);
      expect(engine.balances[shop.deviceId], 15000);
      expect(engine.totalBalance(), 120000); // مجموع التمويل الابتدائي — لا خلق نقود.
      expect(
        report.rejected.where((r) => r.$2 == RejectReason.duplicate),
        hasLength(3),
      );
    });

    test('السلسلة تستأنف بعد التسوية بمرساة جديدة', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);

      final tk1 = await sender.send(recipientId: recipient.deviceId, amount: 10000, now: t0);
      final report1 = await engine.settle([tk1], now: t0 + 100);
      sender.applySettlement(
        newBalance: engine.balances[sender.deviceId]!,
        newAnchor: report1.newAnchors[sender.deviceId]!,
      );

      final tk2 = await sender.send(recipientId: recipient.deviceId, amount: 15000, now: t0 + 200);
      final report2 = await engine.settle([tk2], now: t0 + 300);
      expect(report2.settled.map((t) => t.tokenId), [tk2.tokenId]);
      expect(engine.balances[recipient.deviceId], 25000);
    });
  });

  group('رفض سلسلة متفرعة (إنفاق مزدوج)', () {
    test('تفرع داخل الدفعة: الأسبق يُسوّى والثاني يُرفض والحساب يُجمَّد', () async {
      final engine = InMemorySettlement();
      final (attacker, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (victimA, _) = await fundedReservation(engine: engine, reserved: 0);
      final (victimB, _) = await fundedReservation(engine: engine, reserved: 0);

      final legit = await attacker.send(recipientId: victimA.deviceId, amount: 30000, now: t0);
      final forged = await craft(
        attacker.identity,
        recipientId: victimB.deviceId,
        amount: 30000,
        seq: legit.seq,
        prevHash: legit.prevHash,
        issuedAt: t0 + 5,
      );
      final report = await engine.settle([legit, forged], now: t0 + 100);

      expect(report.settled.map((t) => t.tokenId), [legit.tokenId]);
      expect(
        report.rejected,
        contains(predicate<(SignedToken, RejectReason)>(
            (r) => r.$1.tokenId == forged.tokenId && r.$2 == RejectReason.doubleSpend)),
      );
      expect(report.fraudAlerts, [attacker.deviceId]);
      expect(engine.accounts[attacker.deviceId]!.frozen, isTrue);
      expect(engine.balances[victimB.deviceId], 0);
    });

    test('تفرع عبر دفعتين منفصلتين — الحالة الواقعية — يُكشف ويُجمَّد', () async {
      final engine = InMemorySettlement();
      final (attacker, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (victimA, _) = await fundedReservation(engine: engine, reserved: 0);
      final (victimB, _) = await fundedReservation(engine: engine, reserved: 0);

      final legit = await attacker.send(recipientId: victimA.deviceId, amount: 30000, now: t0);
      final forged = await craft(
        attacker.identity,
        recipientId: victimB.deviceId,
        amount: 30000,
        seq: legit.seq,
        prevHash: legit.prevHash,
        issuedAt: t0 + 5,
      );

      final report1 = await engine.settle([legit], now: t0 + 100);
      expect(report1.settled, hasLength(1));
      expect(report1.fraudAlerts, isEmpty); // لا دليل تفرع بعد.

      final report2 = await engine.settle([forged], now: t0 + 200);
      expect(report2.settled, isEmpty);
      expect(report2.rejected.single.$2, RejectReason.doubleSpend);
      expect(engine.accounts[attacker.deviceId]!.frozen, isTrue);
      expect(engine.balances[victimB.deviceId], 0);
    });

    test('ذيل الفرع الاحتيالي يسقط معه', () async {
      final engine = InMemorySettlement();
      final (attacker, _) = await fundedReservation(engine: engine, reserved: 100000);
      final (victim, _) = await fundedReservation(engine: engine, reserved: 0);

      final legit = await attacker.send(recipientId: victim.deviceId, amount: 10000, now: t0);
      final forged1 = await craft(attacker.identity,
          recipientId: victim.deviceId, amount: 10000,
          seq: legit.seq, prevHash: legit.prevHash, issuedAt: t0 + 5);
      final forged2 = await craft(attacker.identity,
          recipientId: victim.deviceId, amount: 20000,
          seq: 1, prevHash: forged1.tokenHash, issuedAt: t0 + 6);

      final report = await engine.settle([legit, forged1, forged2], now: t0 + 100);
      final reasons = {for (final r in report.rejected) r.$1.tokenId: r.$2};
      expect(reasons[forged1.tokenId], RejectReason.doubleSpend);
      expect(reasons[forged2.tokenId], RejectReason.doubleSpend);
      expect(engine.balances[victim.deviceId], 10000);
    });

    test('الحساب المجمّد تُرفض دفعاته اللاحقة كاملة', () async {
      final engine = InMemorySettlement();
      final (attacker, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (victim, _) = await fundedReservation(engine: engine, reserved: 0);

      final legit = await attacker.send(recipientId: victim.deviceId, amount: 10000, now: t0);
      final forged = await craft(attacker.identity,
          recipientId: victim.deviceId, amount: 10000,
          seq: legit.seq, prevHash: legit.prevHash, issuedAt: t0 + 5);
      final report = await engine.settle([legit, forged], now: t0 + 100);

      final later = await craft(attacker.identity,
          recipientId: victim.deviceId, amount: 1000,
          seq: 0, prevHash: report.newAnchors[attacker.deviceId]!, issuedAt: t0 + 200);
      final report2 = await engine.settle([later], now: t0 + 300);
      expect(report2.settled, isEmpty);
      expect(report2.rejected.single.$2, RejectReason.accountFrozen);
    });

    test('إعادة رفع توكن مسوّى تُرفض كمكرر بلا قيد مزدوج', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);

      final token = await sender.send(recipientId: recipient.deviceId, amount: 20000, now: t0);
      await engine.settle([token], now: t0 + 100);
      final replay = await engine.settle([token], now: t0 + 200);
      expect(replay.settled, isEmpty);
      expect(replay.rejected.single.$2, RejectReason.duplicate);
      expect(engine.balances[recipient.deviceId], 20000); // لم يتضاعف.
    });
  });

  group('رفض توكن منتهي الصلاحية (72 ساعة)', () {
    test('المنتهي لا يُسوّى وقيمته تبقى للمرسل والسلسلة تكمل بعده', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);

      final shortLived = await craft(sender.identity,
          recipientId: recipient.deviceId, amount: 5000,
          seq: 0, prevHash: sender.chainHead, issuedAt: t0, ttl: 10);
      final followUp = await craft(sender.identity,
          recipientId: recipient.deviceId, amount: 7000,
          seq: 1, prevHash: shortLived.tokenHash, issuedAt: t0 + 5);

      final report = await engine.settle([shortLived, followUp], now: t0 + 3600);
      expect(report.settled.map((t) => t.tokenId), [followUp.tokenId]);
      expect(
        report.rejected,
        contains(predicate<(SignedToken, RejectReason)>(
            (r) => r.$1.tokenId == shortLived.tokenId && r.$2 == RejectReason.expired)),
      );
      expect(engine.balances[sender.deviceId], 50000 - 7000);
      expect(engine.balances[recipient.deviceId], 7000);
    });

    test('التسوية بعد 72 ساعة كاملة ترفض التوكن', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);

      final token = await sender.send(recipientId: recipient.deviceId, amount: 20000, now: t0);
      final report =
          await engine.settle([token], now: t0 + maxTokenTtlSeconds + 1);
      expect(report.settled, isEmpty);
      expect(report.rejected.single.$2, RejectReason.expired);
      expect(engine.balances[sender.deviceId], 50000);
    });
  });

  group('رفض تجاوز السقف اليومي', () {
    test('توكنات مصنوعة تتجاوز السقف تُرفض عند التسوية', () async {
      final engine = InMemorySettlement();
      final (attacker, _) =
          await fundedReservation(engine: engine, reserved: 100000, dailyCap: 30000);
      final (victim, _) = await fundedReservation(engine: engine, reserved: 0);

      final tk1 = await craft(attacker.identity,
          recipientId: victim.deviceId, amount: 20000,
          seq: 0, prevHash: attacker.chainHead, issuedAt: t0);
      final tk2 = await craft(attacker.identity,
          recipientId: victim.deviceId, amount: 20000,
          seq: 1, prevHash: tk1.tokenHash, issuedAt: t0 + 1);

      final report = await engine.settle([tk1, tk2], now: t0 + 100);
      expect(report.settled.map((t) => t.tokenId), [tk1.tokenId]);
      final reasons = {for (final r in report.rejected) r.$1.tokenId: r.$2};
      expect(reasons[tk2.tokenId], RejectReason.dailyCap);
      expect(engine.balances[victim.deviceId], 20000);
    });

    test('عدّاد السقف يصمد عبر دفعتين في نفس اليوم', () async {
      final engine = InMemorySettlement();
      final (sender, _) =
          await fundedReservation(engine: engine, reserved: 100000, dailyCap: 30000);
      final (victim, _) = await fundedReservation(engine: engine, reserved: 0);

      final tk1 = await sender.send(recipientId: victim.deviceId, amount: 30000, now: t0);
      final report1 = await engine.settle([tk1], now: t0 + 100);

      final tk2 = await craft(sender.identity,
          recipientId: victim.deviceId, amount: 10000,
          seq: 0, prevHash: report1.newAnchors[sender.deviceId]!, issuedAt: t0 + 50);
      final report2 = await engine.settle([tk2], now: t0 + 200);
      expect(report2.settled, isEmpty);
      expect(report2.rejected.single.$2, RejectReason.dailyCap);
    });

    test('يوما إصدار مختلفان يُحسبان على سقفيهما', () async {
      final engine = InMemorySettlement();
      final (sender, _) =
          await fundedReservation(engine: engine, reserved: 100000, dailyCap: 30000);
      final (victim, _) = await fundedReservation(engine: engine, reserved: 0);

      final tk1 = await sender.send(recipientId: victim.deviceId, amount: 30000, now: t0);
      final tk2 = await sender.send(
          recipientId: victim.deviceId, amount: 30000, now: t0 + oneDay);
      final report = await engine.settle([tk1, tk2], now: t0 + oneDay + 100);
      expect(report.settled, hasLength(2));
      expect(engine.balances[victim.deviceId], 60000);
    });

    test('طابع إصدار مستقبلي يُرفض — لا تقسيم للسقف بالتأريخ', () async {
      final engine = InMemorySettlement();
      final (attacker, _) =
          await fundedReservation(engine: engine, reserved: 100000, dailyCap: 30000);
      final (victim, _) = await fundedReservation(engine: engine, reserved: 0);

      final future = await craft(attacker.identity,
          recipientId: victim.deviceId, amount: 30000,
          seq: 0, prevHash: attacker.chainHead,
          issuedAt: t0 + clockSkewToleranceSeconds + 3600);
      final report = await engine.settle([future], now: t0);
      expect(report.settled, isEmpty);
      expect(report.rejected.single.$2, RejectReason.futureDated);
    });

    test('عمر مفرط مُصنَّع خارج المحرك يُرفض BAD_TTL', () async {
      final engine = InMemorySettlement();
      final (attacker, _) = await fundedReservation(engine: engine, reserved: 100000);
      final (victim, _) = await fundedReservation(engine: engine, reserved: 0);

      // create يمنع ttl المفرط، فنبني التوقيع يدوياً على expires بعيد.
      final payload = SignedToken.canonicalPayload(
        tokenId: '00112233445566778899aabbccddee00',
        senderId: attacker.identity.deviceId,
        senderPubkey: attacker.identity.publicKeyHex,
        recipientId: victim.deviceId,
        amount: 10000,
        currency: 'SDG',
        seq: 0,
        prevHash: attacker.chainHead,
        issuedAt: t0,
        expiresAt: t0 + maxTokenTtlSeconds + oneDay,
      );
      final signature = await attacker.identity.signUtf8(payload);
      final crafted = SignedToken(
        tokenId: '00112233445566778899aabbccddee00',
        senderId: attacker.identity.deviceId,
        senderPubkey: attacker.identity.publicKeyHex,
        recipientId: victim.deviceId,
        amount: 10000,
        currency: 'SDG',
        seq: 0,
        prevHash: attacker.chainHead,
        issuedAt: t0,
        expiresAt: t0 + maxTokenTtlSeconds + oneDay,
        signature: signature,
      );
      final report = await engine.settle([crafted], now: t0 + 100);
      expect(report.settled, isEmpty);
      expect(report.rejected.single.$2, RejectReason.badTtl);
    });
  });

  group('رفض توقيع تالف', () {
    test('تعديل المبلغ بعد التوقيع يُرفض', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);

      final token = await sender.send(recipientId: recipient.deviceId, amount: 1000, now: t0);
      final inflated = token.copyWith(amount: 49000);
      final report = await engine.settle([inflated], now: t0 + 10);
      expect(report.settled, isEmpty);
      expect(report.rejected.single.$2, RejectReason.badSignature);
      expect(engine.balances[recipient.deviceId], 0);
    });

    test('تحويل الوجهة بعد التوقيع يُرفض', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);
      final (thief, _) = await fundedReservation(engine: engine, reserved: 0);

      final token = await sender.send(recipientId: recipient.deviceId, amount: 1000, now: t0);
      final redirected = token.copyWith(recipientId: thief.deviceId);
      final report = await engine.settle([redirected], now: t0 + 10);
      expect(report.settled, isEmpty);
      expect(report.rejected.single.$2, RejectReason.badSignature);
      expect(engine.balances[thief.deviceId], 0);
    });

    test('مفتاح لا يطابق المسجّل للحساب يُرفض بعد تدوير المفتاح', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);

      final token = await sender.send(recipientId: recipient.deviceId, amount: 1000, now: t0);
      // البنك دوّر مفتاح الحساب بعد بلاغ سرقة الجهاز.
      final rotated = await DeviceIdentity.generate();
      engine.accounts[sender.deviceId] = ChainAccount(
        deviceId: sender.deviceId,
        pubkey: rotated.publicKeyHex,
        dailyCap: defaultDailyCapPiasters,
        chainAnchor: engine.accounts[sender.deviceId]!.chainAnchor,
      );
      final report = await engine.settle([token], now: t0 + 10);
      expect(report.settled, isEmpty);
      expect(report.rejected.single.$2, RejectReason.keyMismatch);
    });

    test('مرسل غير مسجل يُرفض', () async {
      final engine = InMemorySettlement();
      final outsider = await DeviceIdentity.generate();
      final token = await craft(outsider,
          recipientId: 'aabbccddeeff0011', amount: 1000,
          seq: 0, prevHash: 'f' * 64, issuedAt: t0);
      final report = await engine.settle([token], now: t0 + 10);
      expect(report.rejected.single.$2, RejectReason.unregisteredSender);
    });
  });

  group('حماية المرساة والسلسلة', () {
    test('رفع توكن لا يُسوّى لا يدوّر مرساة الضحية (منع التعطيل)', () async {
      final engine = InMemorySettlement();
      final (victim, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);
      final anchor0 = engine.accounts[victim.deviceId]!.chainAnchor;

      final junk = await craft(victim.identity,
          recipientId: recipient.deviceId, amount: 1000,
          seq: 7, prevHash: 'f' * 64, issuedAt: t0);
      final report1 = await engine.settle([junk], now: t0 + 10);
      expect(report1.settled, isEmpty);
      expect(report1.rejected.single.$2, RejectReason.chainBroken);
      expect(engine.accounts[victim.deviceId]!.chainAnchor, anchor0);

      // توكن الضحية الشرعي المتصل بالمرساة الأصلية ما زال يُسوّى.
      final legit = await victim.send(recipientId: recipient.deviceId, amount: 1000, now: t0);
      final report2 = await engine.settle([legit], now: t0 + 20);
      expect(report2.settled, hasLength(1));
    });

    test('ما بعد حلقة مرفوضة رفضاً قاتلاً لا يُسوّى (SUPERSEDED)', () async {
      final engine = InMemorySettlement();
      final (attacker, _) = await fundedReservation(engine: engine, reserved: 5000);
      final (victim, _) = await fundedReservation(engine: engine, reserved: 0);

      final tk0 = await attacker.send(recipientId: victim.deviceId, amount: 5000, now: t0);
      final tk1 = await craft(attacker.identity,
          recipientId: victim.deviceId, amount: 5000,
          seq: 1, prevHash: tk0.tokenHash, issuedAt: t0 + 1); // رصيد صفر
      final tk2 = await craft(attacker.identity,
          recipientId: victim.deviceId, amount: 1000,
          seq: 2, prevHash: tk1.tokenHash, issuedAt: t0 + 2);

      final report = await engine.settle([tk0, tk1, tk2], now: t0 + 100);
      final reasons = {for (final r in report.rejected) r.$1.tokenId: r.$2};
      expect(report.settled.map((t) => t.tokenId), [tk0.tokenId]);
      expect(reasons[tk1.tokenId], RejectReason.insufficientFunds);
      expect(reasons[tk2.tokenId], RejectReason.superseded);
      expect(engine.balances[victim.deviceId], 5000);
    });

    test('تسلسل غير متطابق يُرفض BAD_SEQUENCE', () async {
      final engine = InMemorySettlement();
      final (sender, _) = await fundedReservation(engine: engine, reserved: 50000);
      final (recipient, _) = await fundedReservation(engine: engine, reserved: 0);

      final crafted = await craft(sender.identity,
          recipientId: recipient.deviceId, amount: 1000,
          seq: 5, prevHash: sender.chainHead, issuedAt: t0);
      final report = await engine.settle([crafted], now: t0 + 10);
      expect(report.rejected.single.$2, RejectReason.badSequence);
    });
  });
}
