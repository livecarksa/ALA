/// تحقق تكاملي لعقد HTTP: عميل التطبيق ← بوابة محلية ← settle_accept
/// الحقيقية على Postgres. يعمل فقط حين تُضبط WASLA_E2E_URL (انظر
/// supabase/tests/local_gateway.py) — يُتخطى في CI العادي.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasla_app/core/settlement_api.dart';
import 'package:wasla_core/wasla_core.dart';

final String? _e2eUrl = Platform.environment['WASLA_E2E_URL'];

void main() {
  test(
    'تسجيل ← إرسال موقّع ← تسوية حقيقية ← أرقام محفظة من القاعدة',
    () async {
      final api = HttpSettlementApi(baseUrl: _e2eUrl!, anonKey: '');

      final alice = await DeviceIdentity.generate();
      final bob = await DeviceIdentity.generate();

      final aliceReg = await api.register(
        deviceId: alice.deviceId,
        pubkey: alice.publicKeyHex,
        reservePiasters: 100000,
        dailyCapPiasters: 500000,
      );
      await api.register(
        deviceId: bob.deviceId,
        pubkey: bob.publicKeyHex,
        reservePiasters: 50000,
        dailyCapPiasters: 500000,
      );
      expect(aliceReg.remaining, 100000);
      expect(aliceReg.chainAnchor, hasLength(64));

      final reservation = OfflineReservation(
        identity: alice,
        reservedBalance: aliceReg.remaining,
        chainAnchor: aliceReg.chainAnchor,
        dailyCap: aliceReg.dailyCap,
      );
      const amount = 12345;
      final token = await reservation.send(
        recipientId: bob.deviceId,
        amount: amount,
        now: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final outcome = await api.settle(
        deviceId: alice.deviceId,
        batch: [token],
      );
      expect(outcome.settledIds, [token.tokenId]);
      expect(outcome.rejected, isEmpty);
      expect(outcome.remaining, 100000 - amount,
          reason: 'المتبقي بعد التجديد يخصم المسوّى فقط');
      expect(outcome.epoch, 1, reason: 'التجديد يفتح حقبة جديدة');
      expect(outcome.chainAnchor, isNot(aliceReg.chainAnchor));

      // رصيد بوب على دفتر البنك ازداد بالمبلغ — من القاعدة لا من العميل.
      final bobAgain = await api.register(
        deviceId: bob.deviceId,
        pubkey: bob.publicKeyHex,
        reservePiasters: 50000,
        dailyCapPiasters: 500000,
      );
      expect(bobAgain.balance, amount);

      // إعادة رفع نفس التوكن idempotent: يُحسب مسوّى ولا يتكرر أثره.
      final replay = await api.settle(
        deviceId: alice.deviceId,
        batch: [token],
      );
      expect(replay.settledIds, [token.tokenId]);
      expect(replay.remaining, 100000 - amount);
    },
    skip: _e2eUrl == null
        ? 'يتطلب WASLA_E2E_URL — بوابة محلية فوق Postgres (local_gateway.py)'
        : false,
  );
}
