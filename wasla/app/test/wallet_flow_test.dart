/// دورة الديمو كاملة على مستوى المتحكم: محفظتان حقيقيتان (محرك
/// wasla_core فعلي) — إرسال ← مقاطع SMS مخلوطة ← تجميع وتحقق ← قبول ←
/// تسوية بعد عودة الاتصال. هذا اختبار قبول المرحلة D الأدنى.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasla_app/core/wallet_controller.dart';

ProviderContainer freshWallet() => ProviderContainer(
      overrides: [seedStoreProvider.overrideWithValue(MemorySeedStore())],
    );

void main() {
  test('إرسال عبر SMS ثم استقبال وتسوية — الدورة كاملة', () async {
    final sender = freshWallet();
    final receiver = freshWallet();
    addTearDown(sender.dispose);
    addTearDown(receiver.dispose);

    final senderState = await sender.read(walletProvider.future);
    final receiverState = await receiver.read(walletProvider.future);
    expect(senderState.deviceId, isNot(receiverState.deviceId));
    expect(senderState.offlineAvailable, demoReservedPiasters);

    // 1) المرسل يوقّع تحويلاً ويقسّمه مقاطع SMS.
    const amount = 75000; // 750 جنيه بالقرش
    final senderCtrl = sender.read(walletProvider.notifier);
    final token = await senderCtrl.send(
      recipientId: receiverState.deviceId,
      amount: amount,
    );
    expect(sender.read(walletProvider).requireValue.offlineAvailable,
        demoReservedPiasters - amount);
    final segments = senderCtrl.smsSegmentsOf(token)..shuffle();
    expect(segments.length, greaterThan(1));

    // 2) المستقبل يجمع المقاطع مخلوطة ويتحقق ويقبل.
    final receiverCtrl = receiver.read(walletProvider.notifier);
    String? payload;
    for (final s in segments) {
      payload = receiverCtrl.addSmsSegment(s) ?? payload;
    }
    expect(payload, isNotNull);
    final received = await receiverCtrl.verifyPayload(payload!);
    expect(received.amount, amount);
    expect(received.senderId, senderState.deviceId);
    await receiverCtrl.accept(received);

    var rState = receiver.read(walletProvider).requireValue;
    expect(rState.pendingCount, 1);
    expect(rState.history.single.kind, EventKind.received);
    expect(rState.history.single.settled, isFalse);

    // 3) عودة الاتصال والتسوية: الوارد يُقيَّد على دفتر البنك وتفتح حقبة.
    receiverCtrl.toggleOnline();
    final settledCount = await receiverCtrl.settle();
    expect(settledCount, 1);
    rState = receiver.read(walletProvider).requireValue;
    expect(rState.bankBalance, demoBankBalancePiasters + amount);
    expect(rState.epoch, 1);
    expect(rState.pendingCount, 0);
    expect(rState.history.single.settled, isTrue);

    // 4) القبول idempotent: نفس التوكن لا يتكرر في السجل.
    await receiverCtrl.accept(received);
    expect(
      receiver
          .read(walletProvider)
          .requireValue
          .history
          .where((e) => e.tokenId == token.tokenId)
          .length,
      1,
    );
  });

  test('التحقق يرفض حمولة موجهة لجهاز آخر ولا يغيّر شيئاً', () async {
    final sender = freshWallet();
    final eavesdropper = freshWallet();
    addTearDown(sender.dispose);
    addTearDown(eavesdropper.dispose);

    await sender.read(walletProvider.future);
    await eavesdropper.read(walletProvider.future);

    final senderCtrl = sender.read(walletProvider.notifier);
    final token = await senderCtrl.send(
      recipientId: 'fedcba9876543210', // ليس المتنصت
      amount: 1000,
    );
    final payload = senderCtrl.payloadOf(token);

    final thief = eavesdropper.read(walletProvider.notifier);
    await expectLater(thief.verifyPayload(payload), throwsException);
    expect(
        eavesdropper.read(walletProvider).requireValue.pendingCount, 0);
  });

  test('هوية الجهاز تثبت عبر إعادة البناء من نفس البذرة', () async {
    final store = MemorySeedStore();
    final first = ProviderContainer(
        overrides: [seedStoreProvider.overrideWithValue(store)]);
    final id1 = (await first.read(walletProvider.future)).deviceId;
    first.dispose();
    final second = ProviderContainer(
        overrides: [seedStoreProvider.overrideWithValue(store)]);
    final id2 = (await second.read(walletProvider.future)).deviceId;
    second.dispose();
    expect(id2, id1, reason: 'نفس البذرة نفس الهوية — استمرارية المحفظة');
  });
}
