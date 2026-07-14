/// عقد التسوية من منظور التطبيق — تنفيذان خلف واجهة واحدة:
/// محاكاة محلية للديمو الأوف لاين الكامل، وHTTP نحو دوال Supabase
/// الطرفية (register/settle) حين يُضبط العنوان وقت البناء:
///
///   flutter build ... \
///     --dart-define=WASLA_SETTLE_URL=https://PROJECT.supabase.co \
///     --dart-define=WASLA_ANON_KEY=ANON_KEY
///
/// لا أسرار في الكود — القيم من بيئة البناء حصراً (قرار حاكم).
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:wasla_core/wasla_core.dart';

/// نتيجة تسجيل جهاز لدى طبقة التسوية.
final class WalletRegistration {
  const WalletRegistration({
    required this.chainAnchor,
    required this.epoch,
    required this.remaining,
    required this.balance,
    required this.dailyCap,
  });

  final String chainAnchor;
  final int epoch;

  /// المتبقي القابل للإنفاق من الحجز المفتوح بالقرش.
  final int remaining;

  /// رصيد دفتر البنك بالقرش.
  final int balance;
  final int dailyCap;
}

/// نتيجة تسوية دفعة.
final class SettleOutcome {
  const SettleOutcome({
    required this.settledIds,
    required this.rejected,
    required this.chainAnchor,
    required this.epoch,
    required this.remaining,
    required this.balance,
  });

  final List<String> settledIds;

  /// (معرّف التوكن، سبب الرفض) لما لم يُسوَّ — المكرر لا يُعد رفضاً.
  final List<(String, String)> rejected;
  final String chainAnchor;
  final int epoch;
  final int remaining;
  final int balance;
}

/// خطأ طبقة التسوية برسالة قابلة للعرض.
final class SettlementApiException implements Exception {
  const SettlementApiException(this.message);
  final String message;
  @override
  String toString() => 'SettlementApiException: $message';
}

abstract interface class SettlementApi {
  Future<WalletRegistration> register({
    required String deviceId,
    required String pubkey,
    required int reservePiasters,
    required int dailyCapPiasters,
  });

  Future<SettleOutcome> settle({
    required String deviceId,
    required List<SignedToken> batch,
  });
}

/// حمولة توكن على السلك — نفس أسماء حقول دالة settle الطرفية.
Map<String, Object?> tokenWireJson(SignedToken t) => {
      'token_id': t.tokenId,
      'sender_id': t.senderId,
      'sender_pubkey': t.senderPubkey,
      'recipient_id': t.recipientId,
      'amount': t.amount,
      'currency': t.currency,
      'seq': t.seq,
      'prev_hash': t.prevHash,
      'issued_at': t.issuedAt,
      'expires_at': t.expiresAt,
      'signature': t.signature,
    };

// ---------------------------------------------------------------------------
// المحاكاة المحلية — سلوك بنك مبسّط داخل الجهاز للديمو بلا أي شبكة.
// ---------------------------------------------------------------------------

/// رصيد الديمو على دفتر البنك بالقرش.
const int demoBankBalancePiasters = 2543075;

final class _DemoWallet {
  _DemoWallet(this.anchor);
  String anchor;
  int epoch = 0;
  int balance = demoBankBalancePiasters;
}

final class LocalDemoSettlement implements SettlementApi {
  final Map<String, _DemoWallet> _wallets = {};

  String _anchor(String deviceId, int epoch) =>
      sha256Hex(utf8.encode('anchor:$deviceId:$epoch'));

  @override
  Future<WalletRegistration> register({
    required String deviceId,
    required String pubkey,
    required int reservePiasters,
    required int dailyCapPiasters,
  }) async {
    final wallet =
        _wallets.putIfAbsent(deviceId, () => _DemoWallet(_anchor(deviceId, 0)));
    return WalletRegistration(
      chainAnchor: wallet.anchor,
      epoch: wallet.epoch,
      remaining: reservePiasters,
      balance: wallet.balance,
      dailyCap: dailyCapPiasters,
    );
  }

  @override
  Future<SettleOutcome> settle({
    required String deviceId,
    required List<SignedToken> batch,
  }) async {
    // زمن ذهاب وإياب واقعي للعرض.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final wallet =
        _wallets.putIfAbsent(deviceId, () => _DemoWallet(_anchor(deviceId, 0)));
    final receivedSum = batch
        .where((t) => t.recipientId == deviceId)
        .fold<int>(0, (s, t) => s + t.amount);
    wallet.balance += receivedSum;
    wallet.epoch += 1;
    wallet.anchor = _anchor(deviceId, wallet.epoch);
    return SettleOutcome(
      settledIds: [for (final t in batch) t.tokenId],
      rejected: const [],
      chainAnchor: wallet.anchor,
      epoch: wallet.epoch,
      remaining: -1, // المحاكاة لا تتعقب الحجز — المتحكم يبقي رقمه المحلي.
      balance: wallet.balance,
    );
  }
}

// ---------------------------------------------------------------------------
// HTTP نحو دوال Supabase الطرفية.
// ---------------------------------------------------------------------------

final class HttpSettlementApi implements SettlementApi {
  HttpSettlementApi({
    required this.baseUrl,
    required this.anonKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// جذر المشروع (…supabase.co) أو أي بوابة تطبّق العقد نفسه.
  final String baseUrl;
  final String anonKey;
  final http.Client _client;

  Uri _fn(String name) =>
      Uri.parse('$baseUrl/functions/v1/$name');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        if (anonKey.isNotEmpty) 'Authorization': 'Bearer $anonKey',
        if (anonKey.isNotEmpty) 'apikey': anonKey,
      };

  Future<Map<String, dynamic>> _post(String fn, Object body) async {
    final http.Response response;
    try {
      response = await _client
          .post(_fn(fn), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw SettlementApiException('تعذر الاتصال بالتسوية: $e');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
      throw SettlementApiException(
          'فشل $fn (${response.statusCode}): ${response.body}');
    }
    return decoded;
  }

  @override
  Future<WalletRegistration> register({
    required String deviceId,
    required String pubkey,
    required int reservePiasters,
    required int dailyCapPiasters,
  }) async {
    final data = await _post('register', {
      'device_id': deviceId,
      'pubkey': pubkey,
      'reserve': reservePiasters,
      'daily_cap': dailyCapPiasters,
    });
    final wallet = data['wallet'] as Map<String, dynamic>;
    return WalletRegistration(
      chainAnchor: wallet['chain_anchor'] as String,
      epoch: wallet['epoch'] as int,
      remaining: wallet['remaining'] as int,
      balance: wallet['balance'] as int,
      dailyCap: wallet['daily_cap'] as int,
    );
  }

  @override
  Future<SettleOutcome> settle({
    required String deviceId,
    required List<SignedToken> batch,
  }) async {
    final data = await _post('settle', {
      'device_id': deviceId,
      'renew': true,
      'batch': [for (final t in batch) tokenWireJson(t)],
    });
    final results = (data['results'] as List).cast<Map<String, dynamic>>();
    final wallet = data['wallet'] as Map<String, dynamic>;
    return SettleOutcome(
      settledIds: [
        for (final r in results)
          if (r['status'] == 'settled' || r['status'] == 'duplicate')
            r['token_id'] as String,
      ],
      rejected: [
        for (final r in results)
          if (r['status'] != 'settled' && r['status'] != 'duplicate')
            (r['token_id'] as String, r['status'] as String),
      ],
      chainAnchor: wallet['chain_anchor'] as String,
      epoch: wallet['epoch'] as int,
      remaining: wallet['remaining'] as int,
      balance: wallet['balance'] as int,
    );
  }
}

// ---------------------------------------------------------------------------
// المزوّد: HTTP إن ضُبط العنوان وقت البناء، وإلا المحاكاة المحلية.
// ---------------------------------------------------------------------------

const String _settleUrl = String.fromEnvironment('WASLA_SETTLE_URL');
const String _anonKey = String.fromEnvironment('WASLA_ANON_KEY');

final settlementApiProvider = Provider<SettlementApi>((ref) {
  if (_settleUrl.isEmpty) return LocalDemoSettlement();
  return HttpSettlementApi(baseUrl: _settleUrl, anonKey: _anonKey);
});
