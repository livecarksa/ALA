/// أدوات مشتركة للاختبارات: محرك تسوية مرجعي في الذاكرة فوق ChainVerifier.
library;

import 'dart:convert';

import 'package:wasla_core/wasla_core.dart';

/// طابع ثابت للاختبارات الحتمية.
const int t0 = 1750000000;

/// يوم كامل بالثواني.
const int oneDay = 24 * 3600;

/// محرك تسوية مرجعي في الذاكرة — يحمل الحالة التي ستحملها Postgres
/// في المرحلة B ويحقن ChainVerifier بها.
final class InMemorySettlement {
  final Map<String, ChainAccount> accounts = {};
  final Map<String, int> balances = {};
  final Set<String> settledTokenIds = {};
  final Map<String, String> spentPrev = {};
  final Map<String, int> spentByDay = {};
  final List<SignedToken> postings = [];

  /// تسجيل جهاز بمرساة مشتقة ورصيد محجوز ابتدائي.
  ChainAccount register(DeviceIdentity identity,
      {int reserved = 0, int dailyCap = defaultDailyCapPiasters}) {
    final anchor =
        sha256Hex(utf8.encode('anchor:${identity.deviceId}:${accounts.length}'));
    final account = ChainAccount(
      deviceId: identity.deviceId,
      pubkey: identity.publicKeyHex,
      dailyCap: dailyCap,
      chainAnchor: anchor,
    );
    accounts[identity.deviceId] = account;
    balances[identity.deviceId] = reserved;
    return account;
  }

  ChainVerifier get verifier => ChainVerifier(
        accounts: accounts,
        settledTokenIds: settledTokenIds,
        spentPrev: spentPrev,
        spentByDay: spentByDay,
        balanceOf: (id) => balances[id] ?? 0,
        onSettle: (token) {
          balances[token.senderId] = (balances[token.senderId] ?? 0) - token.amount;
          balances[token.recipientId] =
              (balances[token.recipientId] ?? 0) + token.amount;
          postings.add(token);
        },
      );

  Future<ChainReport> settle(List<SignedToken> tokens, {required int now}) =>
      verifier.verifyBatch(tokens, now: now);

  /// مجموع الأرصدة الصافي — صفر بعد تسوية داخلية متوازنة نسبةً للتمويل.
  int totalBalance() => balances.values.fold(0, (a, b) => a + b);
}

/// حجز مموَّل مسجَّل لدى المحرك.
Future<(OfflineReservation, InMemorySettlement)> fundedReservation({
  InMemorySettlement? engine,
  int reserved = 100000,
  int dailyCap = defaultDailyCapPiasters,
}) async {
  final settlement = engine ?? InMemorySettlement();
  final identity = await DeviceIdentity.generate();
  final account = settlement.register(identity, reserved: reserved, dailyCap: dailyCap);
  final reservation = OfflineReservation(
    identity: identity,
    reservedBalance: reserved,
    chainAnchor: account.chainAnchor,
    dailyCap: dailyCap,
  );
  return (reservation, settlement);
}

/// توكن مصنوع يدوياً بمفاتيح المرسل — يحاكي تطبيقاً معدَّلاً (المهاجم).
Future<SignedToken> craft(
  DeviceIdentity identity, {
  required String recipientId,
  required int amount,
  required int seq,
  required String prevHash,
  required int issuedAt,
  int ttl = maxTokenTtlSeconds,
}) =>
    SignedToken.create(
      identity: identity,
      recipientId: recipientId,
      amount: amount,
      seq: seq,
      prevHash: prevHash,
      issuedAt: issuedAt,
      ttlSeconds: ttl,
    );
