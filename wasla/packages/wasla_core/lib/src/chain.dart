/// بناء السلسلة وكشف التفرع — قلب التسوية.
///
/// المبدأ الحاكم: لا ثقة بالعميل. كل فحص تجريه المحفظة يُعاد هنا
/// (التوقيع، السلسلة، السقف، الصلاحية، الرصيد) لأن جهاز المهاجم قد
/// يصنع توكنات يدوياً.
///
/// سياسة التفرع: الفرع الأسبق إصداراً يُسوّى لحماية مستلمه البريء،
/// ويُرفض الفرع الآخر بكل ذيله ويُجمَّد الحساب. التفرع يُكشف داخل
/// الدفعة الواحدة **وعبر الدفعات المنفصلة** (فهرس نقاط الاستهلاك) —
/// لأن المستلمَين يتصلان في أوقات مختلفة في الواقع.
library;

// المعلمات مسماة عامة والحقول خاصة — initializing formals غير ممكنة هنا.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'identity.dart';
import 'token.dart';

/// أسباب رفض توكن عند التسوية.
enum RejectReason {
  /// إنفاق مزدوج — تفرع في سلسلة التوقيعات.
  doubleSpend,

  /// توقيع غير صالح أو حمولة معدَّلة.
  badSignature,

  /// انتهت الصلاحية قبل التسوية — القيمة تعود للمرسل.
  expired,

  /// السلسلة لا تصل بمرساة آخر تسوية.
  chainBroken,

  /// رقم تسلسل غير متطابق.
  badSequence,

  /// تجاوز السقف اليومي.
  dailyCap,

  /// الرصيد المحجوز لا يغطي المبلغ.
  insufficientFunds,

  /// توكن سُوّي سابقاً (رفعه الطرفان) — ليس احتيالاً.
  duplicate,

  /// الحساب مجمّد بانتظار مراجعة احتيال.
  accountFrozen,

  /// مرسل غير مسجل.
  unregisteredSender,

  /// المفتاح العام لا يطابق المسجّل للحساب.
  keyMismatch,

  /// طابع إصدار في المستقبل — تلاعب بحاوية السقف اليومي.
  futureDated,

  /// عمر التوكن يتجاوز حد المحرك.
  badTtl,

  /// حلقة بعد توكن مرفوض رفضاً قاتلاً — لا تُسوّى.
  superseded,
}

/// حساب جهاز لدى محقق السلسلة.
final class ChainAccount {
  ChainAccount({
    required this.deviceId,
    required this.pubkey,
    required this.dailyCap,
    required this.chainAnchor,
    this.frozen = false,
  });

  /// معرّف الجهاز.
  final String deviceId;

  /// المفتاح العام المسجّل.
  final String pubkey;

  /// السقف اليومي بالقرش.
  final int dailyCap;

  /// مرساة السلسلة — تتقدم فقط عند تسوية فعلية.
  String chainAnchor;

  /// مجمّد لإنفاق مزدوج مكشوف.
  bool frozen;
}

/// نتيجة تحقق دفعة.
final class ChainReport {
  final List<SignedToken> settled = [];
  final List<(SignedToken, RejectReason)> rejected = [];
  final List<String> fraudAlerts = [];
  final Map<String, String> newAnchors = {};

  /// مجموع المبالغ المسوّاة بالقرش.
  int get settledAmount => settled.fold(0, (sum, t) => sum + t.amount);
}

/// دالة رصيد المرسل الحالي — تُحقن من طبقة التسوية (Supabase لاحقاً).
typedef BalanceOf = int Function(String deviceId);

/// دالة قيد التسوية — تُستدعى لكل توكن يُقبل، بترتيب القبول.
typedef PostSettlement = void Function(SignedToken token);

/// محقق سلسلة التوقيعات — منطق نقي بلا تخزين؛ الحالة الدائمة
/// (الحسابات، المسوّى، نقاط الاستهلاك، السقف) تُحقن وتُحدَّث عبره
/// حتى تحملها طبقة التسوية أينما كانت (ذاكرة أو Postgres).
final class ChainVerifier {
  ChainVerifier({
    required Map<String, ChainAccount> accounts,
    required Set<String> settledTokenIds,
    required Map<String, String> spentPrev,
    required Map<String, int> spentByDay,
    required BalanceOf balanceOf,
    required PostSettlement onSettle,
  })  : _accounts = accounts,
        _settledTokenIds = settledTokenIds,
        _spentPrev = spentPrev,
        _spentByDay = spentByDay,
        _balanceOf = balanceOf,
        _onSettle = onSettle;

  final Map<String, ChainAccount> _accounts;
  final Set<String> _settledTokenIds;

  /// "sender|prevHash" ← tokenId الذي استهلكها: يكشف التفرع عبر الدفعات.
  final Map<String, String> _spentPrev;

  /// "device|YYYY-MM-DD" ← المُنفق بالقرش (بيوم الإصدار).
  final Map<String, int> _spentByDay;

  final BalanceOf _balanceOf;
  final PostSettlement _onSettle;

  /// تحقق دفعة كاملة من أي عدد من المرسلين.
  Future<ChainReport> verifyBatch(List<SignedToken> rawTokens, {required int now}) async {
    final report = ChainReport();

    // نفس التوكن قد يرفعه المرسل والمستلم معاً — يُسوّى مرة واحدة فقط.
    final tokens = <SignedToken>[];
    final seenInBatch = <String>{};
    for (final token in rawTokens) {
      if (seenInBatch.contains(token.tokenId) ||
          _settledTokenIds.contains(token.tokenId)) {
        report.rejected.add((token, RejectReason.duplicate));
        continue;
      }
      seenInBatch.add(token.tokenId);
      tokens.add(token);
    }

    final bySender = <String, List<SignedToken>>{};
    for (final token in tokens) {
      bySender.putIfAbsent(token.senderId, () => []).add(token);
    }
    for (final entry in bySender.entries) {
      await _verifySenderChain(entry.key, entry.value, now, report);
    }
    return report;
  }

  Future<void> _verifySenderChain(
    String senderId,
    List<SignedToken> tokens,
    int now,
    ChainReport report,
  ) async {
    final account = _accounts[senderId];
    if (account == null) {
      for (final t in tokens) {
        report.rejected.add((t, RejectReason.unregisteredSender));
      }
      return;
    }
    if (account.frozen) {
      for (final t in tokens) {
        report.rejected.add((t, RejectReason.accountFrozen));
      }
      return;
    }

    // السير من المرساة: عند كل خطوة نبحث عمّن يشير إلى الرأس الحالي —
    // أكثر من واحد يعني تفرعاً (إنفاق مزدوج).
    final byPrev = <String, List<SignedToken>>{};
    for (final token in tokens) {
      byPrev.putIfAbsent(token.prevHash, () => []).add(token);
    }

    void rejectSubtree(SignedToken root, RejectReason reason, Set<String> processed) {
      final stack = [root];
      while (stack.isNotEmpty) {
        final token = stack.removeLast();
        if (!processed.add(token.tokenId)) continue;
        report.rejected.add((token, reason));
        stack.addAll(byPrev[token.tokenHash] ?? const []);
      }
    }

    var head = account.chainAnchor;
    var lastSettledHead = account.chainAnchor;
    var expectedSeq = 0;
    var doubleSpend = false;
    final processed = <String>{};

    while (byPrev.containsKey(head)) {
      final candidates = [...byPrev[head]!]..sort((a, b) {
          final byTime = a.issuedAt.compareTo(b.issuedAt);
          return byTime != 0 ? byTime : a.tokenId.compareTo(b.tokenId);
        });
      final canonical = candidates.first;
      if (candidates.length > 1) {
        // تفرع داخل الدفعة: الأسبق يُسوّى لحماية مستلمه، والباقي احتيال.
        doubleSpend = true;
        for (final forked in candidates.skip(1)) {
          rejectSubtree(forked, RejectReason.doubleSpend, processed);
        }
      }
      processed.add(canonical.tokenId);
      final reason = await _validate(canonical, account, expectedSeq, now);
      if (reason == null) {
        _spentByDay.update(
          '${account.deviceId}|${utcDayOf(canonical.issuedAt)}',
          (v) => v + canonical.amount,
          ifAbsent: () => canonical.amount,
        );
        _spentPrev['$senderId|${canonical.prevHash}'] = canonical.tokenId;
        _settledTokenIds.add(canonical.tokenId);
        _onSettle(canonical);
        report.settled.add(canonical);
        lastSettledHead = canonical.tokenHash;
        head = canonical.tokenHash;
        expectedSeq = canonical.seq + 1;
      } else if (reason == RejectReason.expired) {
        // حلقة منتهية: قيمتها تعود للمرسل والسلسلة تبقى متصلة فنُكمل.
        report.rejected.add((canonical, reason));
        head = canonical.tokenHash;
        expectedSeq = canonical.seq + 1;
      } else {
        // رفض قاتل: الحلقة كسرت تسلسل القيمة فلا يُسوّى ما بُني فوقها.
        report.rejected.add((canonical, reason));
        for (final child in byPrev[canonical.tokenHash] ?? const <SignedToken>[]) {
          rejectSubtree(child, RejectReason.superseded, processed);
        }
        break;
      }
    }

    // ما تبقى لا يصل بالرأس. إن كان prev نقطةً استُهلكت سابقاً فهو تفرع
    // عبر الدفعات (إنفاق مزدوج)، وإلا سلسلة مبتورة.
    for (final token in tokens) {
      if (processed.contains(token.tokenId)) continue;
      final prior = _spentPrev['$senderId|${token.prevHash}'];
      if (prior != null && prior != token.tokenId) {
        doubleSpend = true;
        report.rejected.add((token, RejectReason.doubleSpend));
      } else {
        report.rejected.add((token, RejectReason.chainBroken));
      }
    }

    if (doubleSpend) {
      account.frozen = true;
      report.fraudAlerts.add(senderId);
    }
    if (lastSettledHead != account.chainAnchor) {
      // المرساة تتقدم فقط بتسوية فعلية — رفع توكنات لا تُسوّى لا يحرّكها
      // (يمنع تعطيل أموال الضحية بتدوير مرساتها).
      account.chainAnchor =
          sha256Hex(utf8.encode('anchor:$senderId:$lastSettledHead:$now'));
    }
    report.newAnchors[senderId] = account.chainAnchor;
  }

  Future<RejectReason?> _validate(
    SignedToken token,
    ChainAccount account,
    int expectedSeq,
    int now,
  ) async {
    if (token.senderPubkey != account.pubkey) {
      return RejectReason.keyMismatch;
    }
    try {
      await token.verify();
    } catch (_) {
      return RejectReason.badSignature;
    }
    if (now > token.expiresAt) return RejectReason.expired;
    // طابع الإصدار موقّع لكن العميل يختاره — لا يُوثق به لتقسيم السقف.
    if (token.issuedAt > now + clockSkewToleranceSeconds) {
      return RejectReason.futureDated;
    }
    if (token.expiresAt - token.issuedAt > maxTokenTtlSeconds) {
      return RejectReason.badTtl;
    }
    if (token.seq != expectedSeq) return RejectReason.badSequence;
    final dayKey = '${account.deviceId}|${utcDayOf(token.issuedAt)}';
    if ((_spentByDay[dayKey] ?? 0) + token.amount > account.dailyCap) {
      return RejectReason.dailyCap;
    }
    if (token.amount > _balanceOf(account.deviceId)) {
      return RejectReason.insufficientFunds;
    }
    return null;
  }
}

