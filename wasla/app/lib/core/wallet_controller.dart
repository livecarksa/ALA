/// حالة المحفظة ومتحكمها — الجسر الوحيد بين الواجهة ومحرك wasla_core.
///
/// المفتاح الخاص لا يلمس حالة التطبيق أبداً: البذرة تُحفظ في التخزين
/// الآمن للنظام وتُحمَّل لبناء [DeviceIdentity] داخل المحرك فقط.
/// التسوية هنا محاكاة محلية بواجهة قابلة للاستبدال بنداء دالة settle
/// الطرفية (Supabase) دون مساس بالواجهة.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wasla_core/wasla_core.dart';

/// رصيد الديمو على دفتر البنك بالقرش (لا يمس المحرك).
const int demoBankBalancePiasters = 2543075;

/// الحجز الأوف لاين الابتدائي للديمو بالقرش.
const int demoReservedPiasters = 500000;

// ---------------------------------------------------------------------------
// مخزن البذرة — تجريد يسمح ببديل ذاكرة للاختبارات وللمنصات بلا تخزين آمن.
// ---------------------------------------------------------------------------

/// مخزن بذرة الهوية (32 بايت).
abstract interface class SeedStore {
  Future<Uint8List?> load();
  Future<void> save(Uint8List seed);
}

/// تخزين النظام الآمن (Keystore/Keychain)؛ أي فشل يهبط لذاكرة الجلسة
/// حتى لا يُحجب الديمو على منصات لا تدعمه (الويب التجريبي مثلاً).
final class SecureSeedStore implements SeedStore {
  SecureSeedStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'wasla_identity_seed_v1';
  final FlutterSecureStorage _storage;
  Uint8List? _sessionFallback;

  @override
  Future<Uint8List?> load() async {
    try {
      final stored = await _storage.read(key: _key);
      if (stored != null) return base64Decode(stored);
    } catch (_) {
      return _sessionFallback;
    }
    return _sessionFallback;
  }

  @override
  Future<void> save(Uint8List seed) async {
    _sessionFallback = seed;
    try {
      await _storage.write(key: _key, value: base64Encode(seed));
    } catch (_) {
      // بقيت في ذاكرة الجلسة — مقبول للديمو، لا للإنتاج.
    }
  }
}

/// مخزن ذاكرة للاختبارات.
final class MemorySeedStore implements SeedStore {
  Uint8List? _seed;
  @override
  Future<Uint8List?> load() async => _seed;
  @override
  Future<void> save(Uint8List seed) async => _seed = seed;
}

final seedStoreProvider = Provider<SeedStore>((ref) => SecureSeedStore());

// ---------------------------------------------------------------------------
// نموذج الحالة المعروض للواجهة — لقطة غير قابلة للتعديل.
// ---------------------------------------------------------------------------

enum EventKind { sent, received }

/// حركة في سجل المحفظة.
final class WalletEvent {
  const WalletEvent({
    required this.kind,
    required this.peer,
    required this.amount,
    required this.at,
    required this.tokenId,
    required this.settled,
  });

  final EventKind kind;
  final String peer;
  final int amount;
  final DateTime at;
  final String tokenId;
  final bool settled;

  WalletEvent asSettled() => WalletEvent(
        kind: kind,
        peer: peer,
        amount: amount,
        at: at,
        tokenId: tokenId,
        settled: true,
      );
}

/// لقطة حالة المحفظة.
final class WalletState {
  const WalletState({
    required this.deviceId,
    required this.bankBalance,
    required this.offlineAvailable,
    required this.dailyCap,
    required this.spentToday,
    required this.epoch,
    required this.online,
    required this.settling,
    required this.pendingCount,
    required this.history,
    required this.smsPending,
  });

  final String deviceId;
  final int bankBalance;
  final int offlineAvailable;
  final int dailyCap;
  final int spentToday;
  final int epoch;
  final bool online;
  final bool settling;

  /// توكنات (صادرة ومستلمة) بانتظار الرفع للتسوية.
  final int pendingCount;
  final List<WalletEvent> history;
  final List<SmsInboxStatus> smsPending;

  int get dailyRemaining => dailyCap - spentToday;
}

// ---------------------------------------------------------------------------
// المتحكم.
// ---------------------------------------------------------------------------

final walletProvider =
    AsyncNotifierProvider<WalletController, WalletState>(WalletController.new);

class WalletController extends AsyncNotifier<WalletState> {
  late OfflineReservation _reservation;
  final SmsInbox _inbox = SmsInbox();
  final List<WalletEvent> _history = [];
  int _bankBalance = demoBankBalancePiasters;
  int _epoch = 0;
  bool _online = false;
  bool _settling = false;

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  String _anchorFor(String deviceId, int epoch) =>
      sha256Hex(utf8.encode('anchor:$deviceId:$epoch'));

  @override
  Future<WalletState> build() async {
    final store = ref.read(seedStoreProvider);
    var seed = await store.load();
    DeviceIdentity identity;
    if (seed == null) {
      identity = await DeviceIdentity.generate();
      seed = await identity.extractSeed();
      await store.save(seed);
    } else {
      identity = await DeviceIdentity.fromSeed(seed);
    }
    _reservation = OfflineReservation(
      identity: identity,
      reservedBalance: demoReservedPiasters,
      chainAnchor: _anchorFor(identity.deviceId, _epoch),
    );
    return _snapshot();
  }

  WalletState _snapshot() => WalletState(
        deviceId: _reservation.deviceId,
        bankBalance: _bankBalance,
        offlineAvailable: _reservation.availableBalance,
        dailyCap: _reservation.dailyCap,
        spentToday: _reservation.spentOn(_now()),
        epoch: _epoch,
        online: _online,
        settling: _settling,
        pendingCount: _reservation.tokensForSettlement().length,
        history: List.unmodifiable(_history.reversed),
        smsPending: _inbox.pending,
      );

  void _publish() => state = AsyncData(_snapshot());

  /// توقيع تحويل أوف لاين. يرمي أخطاء المحرك المصنّفة كما هي.
  Future<SignedToken> send({
    required String recipientId,
    required int amount,
  }) async {
    final token = await _reservation.send(
      recipientId: recipientId,
      amount: amount,
      now: _now(),
    );
    _history.add(WalletEvent(
      kind: EventKind.sent,
      peer: recipientId,
      amount: amount,
      at: DateTime.now(),
      tokenId: token.tokenId,
      settled: false,
    ));
    _publish();
    return token;
  }

  /// حمولة QR للتوكن.
  String payloadOf(SignedToken token) => encodeToken(token);

  /// مقاطع SMS جاهزة للإرسال بالترتيب.
  List<String> smsSegmentsOf(SignedToken token) =>
      splitTokenPayloadForSms(encodeToken(token));

  /// تحقق حمولة كاملة (QR أو SMS مجمَّعة) دون إضافتها للمحفظة.
  Future<ReceivedToken> verifyPayload(String payload) =>
      verifyIncomingPayload(
        payload: payload,
        recipientDeviceId: _reservation.deviceId,
        now: _now(),
      );

  /// قبول توكن موثّق في المحفظة (بانتظار التسوية).
  Future<void> accept(ReceivedToken received) async {
    await _reservation.receive(received.token, now: _now());
    final id = received.token.tokenId;
    if (!_history.any((e) => e.tokenId == id)) {
      _history.add(WalletEvent(
        kind: EventKind.received,
        peer: received.senderId,
        amount: received.amount,
        at: DateTime.now(),
        tokenId: id,
        settled: false,
      ));
    }
    _publish();
  }

  /// إضافة مقطع SMS. تعيد الحمولة الكاملة عند اكتمال رسالتها.
  /// ترمي أخطاء المقاطع المصنّفة (تحقق/بنية/تعارض) كما هي.
  String? addSmsSegment(String text) {
    try {
      return _inbox.add(text);
    } finally {
      _publish();
    }
  }

  /// إسقاط رسالة قيد التجميع.
  void forgetSms(String msgId) {
    _inbox.forget(msgId);
    _publish();
  }

  /// تبديل محاكاة الاتصال (شارة أوف لاين ✈ / متصل).
  void toggleOnline() {
    _online = !_online;
    _publish();
  }

  /// التسوية عند عودة الاتصال — محاكاة محلية لدالة settle الطرفية:
  /// الوارد يُقيَّد على دفتر البنك، وتُفتح حقبة جديدة بمرساة جديدة.
  Future<int> settle() async {
    if (!_online || _settling) return 0;
    final batch = _reservation.tokensForSettlement();
    if (batch.isEmpty) return 0;
    _settling = true;
    _publish();
    // زمن ذهاب وإياب واقعي للعرض.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final receivedSum = _reservation.receivedTokens
        .fold<int>(0, (sum, t) => sum + t.amount);
    _bankBalance += receivedSum;
    _epoch += 1;
    _reservation.applySettlement(
      newBalance: _reservation.availableBalance,
      newAnchor: _anchorFor(_reservation.deviceId, _epoch),
    );
    for (var i = 0; i < _history.length; i++) {
      _history[i] = _history[i].asSettled();
    }
    _settling = false;
    _publish();
    return batch.length;
  }
}
