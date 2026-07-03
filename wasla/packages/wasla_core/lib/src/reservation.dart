/// الحجز المسبق والسقف اليومي — محفظة الجهاز بين تسويتين.
///
/// العميل يحجز جزءاً من رصيده في بنكك رصيداً أوف لاين قابلاً للإنفاق،
/// والسقف اليومي يحدّ الخسارة القصوى لأي اختراق فردي. الفحص هنا يحمي
/// المستخدم الشريف؛ التسوية تعيد كل الفحوص لأن جهاز المهاجم قد
/// يتجاوز كود المحفظة.
library;

import 'errors.dart';
import 'identity.dart';
import 'token.dart';

/// السقف اليومي الافتراضي بالقرش (5,000 جنيه) — قابل للضبط من البنك.
const int defaultDailyCapPiasters = 500000;

/// حجز أوف لاين نشط لجهاز واحد منذ آخر تسوية.
final class OfflineReservation {
  OfflineReservation({
    required this.identity,
    required int reservedBalance,
    required String chainAnchor,
    this.dailyCap = defaultDailyCapPiasters,
    this.tokenTtlSeconds = maxTokenTtlSeconds,
  })  : _balance = reservedBalance,
        _chainHead = chainAnchor {
    if (reservedBalance < 0) {
      throw ArgumentError('الرصيد المحجوز لا يكون سالباً');
    }
  }

  /// هوية الجهاز الموقِّعة.
  final DeviceIdentity identity;

  /// السقف اليومي بالقرش.
  final int dailyCap;

  /// عمر التوكنات الصادرة.
  final int tokenTtlSeconds;

  int _balance;
  String _chainHead;
  int _nextSeq = 0;
  final List<SignedToken> _sent = [];
  final List<SignedToken> _received = [];
  final Map<String, int> _spentByDay = {};

  /// معرّف الجهاز.
  String get deviceId => identity.deviceId;

  /// الرصيد الأوف لاين المتاح الآن بالقرش.
  int get availableBalance => _balance;

  /// رأس سلسلة التوقيعات الحالي.
  String get chainHead => _chainHead;

  /// رقم التسلسل التالي.
  int get nextSeq => _nextSeq;

  /// التوكنات الصادرة منذ آخر تسوية (نسخة للقراءة).
  List<SignedToken> get sentTokens => List.unmodifiable(_sent);

  /// التوكنات المستلمة بانتظار التسوية (نسخة للقراءة).
  List<SignedToken> get receivedTokens => List.unmodifiable(_received);

  /// المُنفق في يوم [now] UTC بالقرش.
  int spentOn(int now) => _spentByDay[utcDayOf(now)] ?? 0;

  /// إنشاء توكن موقّع لمستلم — يعمل بلا أي شبكة.
  ///
  /// يرمي [InsufficientReservationException] أو [DailyCapExceededException].
  Future<SignedToken> send({
    required String recipientId,
    required int amount,
    required int now,
  }) async {
    if (amount > _balance) {
      throw InsufficientReservationException(
          'المطلوب $amount قرشاً والمحجوز المتاح $_balance');
    }
    final day = utcDayOf(now);
    final spentToday = _spentByDay[day] ?? 0;
    if (spentToday + amount > dailyCap) {
      throw DailyCapExceededException(
          'السقف اليومي $dailyCap قرشاً — أُنفق اليوم $spentToday');
    }
    final token = await SignedToken.create(
      identity: identity,
      recipientId: recipientId,
      amount: amount,
      seq: _nextSeq,
      prevHash: _chainHead,
      issuedAt: now,
      ttlSeconds: tokenTtlSeconds,
    );
    // تقدّم السلسلة قبل أي تسليم: التوكن التالي يرتبط بهذا حتمياً.
    _chainHead = token.tokenHash;
    _nextSeq += 1;
    _balance -= amount;
    _spentByDay[day] = spentToday + amount;
    _sent.add(token);
    return token;
  }

  /// استلام توكن وارد: تحقق كامل ثم تخزين حتى التسوية.
  ///
  /// المستلَم لا يصبح قابلاً للإنفاق أوف لاين إلا بعد تسويته —
  /// يمنع سلاسل قيمة متعددة القفزات يستحيل التحقق منها أوف لاين.
  Future<void> receive(SignedToken token, {required int now}) async {
    await token.verify(now: now);
    if (token.recipientId != deviceId) {
      throw const WrongRecipientException('التوكن موجّه لجهاز آخر');
    }
    if (_received.any((t) => t.tokenId == token.tokenId)) {
      return; // إعادة إرسال — لا أثر مزدوج.
    }
    _received.add(token);
  }

  /// كل ما يُرفع للتسوية عند عودة الاتصال: الصادر والمستلَم معاً.
  List<SignedToken> tokensForSettlement() => [..._sent, ..._received];

  /// بعد تسوية ناجحة: رصيد محجوز جديد ومرساة جديدة وتصفير السلسلة المحلية.
  void applySettlement({required int newBalance, required String newAnchor}) {
    if (newBalance < 0) {
      throw ArgumentError('رصيد التسوية لا يكون سالباً');
    }
    _balance = newBalance;
    _chainHead = newAnchor;
    _nextSeq = 0;
    _sent.clear();
    _received.clear();
  }
}
