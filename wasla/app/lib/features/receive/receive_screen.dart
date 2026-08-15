/// الاستقبال أوف لاين: لصق حمولة QR كاملة، أو إدخال مقاطع SMS واحداً
/// واحداً مع تقدم حي «وصل n من m» وتسمية الجزء الناقص — ثم بطاقة تحقق
/// خضراء بمبلغ ضخم وزر إضافة صريح. الأخطاء دقيقة وقابلة للتصرف.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wasla_core/wasla_core.dart';

import '../../app.dart';
import '../../core/error_text.dart';
import '../../core/money.dart';
import '../../core/wallet_controller.dart';
import 'scan_screen.dart';

class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  int _mode = 0; // 0 = لصق حمولة، 1 = مقاطع SMS
  final _payloadField = TextEditingController();
  final _segmentField = TextEditingController();
  ReceivedToken? _verified;
  bool _accepted = false;

  @override
  void dispose() {
    _payloadField.dispose();
    _segmentField.dispose();
    super.dispose();
  }

  void _showError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(describeWaslaError(context, e))),
    );
  }

  Future<void> _verify(String payload) async {
    try {
      final received =
          await ref.read(walletProvider.notifier).verifyPayload(payload);
      setState(() {
        _verified = received;
        _accepted = false;
      });
    } catch (e) {
      _showError(e);
    }
  }

  void _addSegment() {
    final text = _segmentField.text.trim();
    if (text.isEmpty) return;
    final l = context.l10n;
    try {
      final payload =
          ref.read(walletProvider.notifier).addSmsSegment(text);
      _segmentField.clear();
      if (payload != null) {
        _verify(payload);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.segmentAccepted),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _accept() async {
    final received = _verified;
    if (received == null) return;
    final l = context.l10n;
    try {
      await ref.read(walletProvider.notifier).accept(received);
      setState(() => _accepted = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.acceptedIntoWallet)),
        );
      }
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final smsPending =
        ref.watch(walletProvider).valueOrNull?.smsPending ?? const [];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l.receiveTitle,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(l.receiveModeQr),
              ),
              ButtonSegment(
                value: 1,
                icon: const Icon(Icons.sms_outlined),
                label: Text(l.receiveModeSms),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          if (_mode == 0) ...[
            FilledButton.icon(
              onPressed: () async {
                final payload = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const ScanScreen()),
                );
                if (payload != null && mounted) await _verify(payload);
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l.scanWithCamera),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _payloadField,
              minLines: 3,
              maxLines: 6,
              textDirection: TextDirection.ltr,
              style: const TextStyle(letterSpacing: 1.2, fontSize: 13),
              decoration: InputDecoration(
                labelText: l.payloadFieldLabel,
                hintText: l.payloadFieldHint,
                hintTextDirection: TextDirection.rtl,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                final text = _payloadField.text.trim();
                if (text.isNotEmpty) _verify(text);
              },
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(l.verifyPayload),
            ),
          ] else ...[
            TextField(
              controller: _segmentField,
              minLines: 2,
              maxLines: 4,
              textDirection: TextDirection.ltr,
              style: const TextStyle(letterSpacing: 1.2, fontSize: 13),
              decoration: InputDecoration(
                labelText: l.smsFieldLabel,
                hintText: l.smsFieldHint,
                hintTextDirection: TextDirection.rtl,
              ),
              onSubmitted: (_) => _addSegment(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _addSegment,
              icon: const Icon(Icons.add),
              label: Text(l.addSegment),
            ),
            for (final status in smsPending) ...[
              const SizedBox(height: 12),
              _AssemblyCard(status: status),
            ],
          ],
          if (_verified != null) ...[
            const SizedBox(height: 16),
            _VerifiedCard(
              received: _verified!,
              accepted: _accepted,
              onAccept: _accept,
            ),
          ],
        ],
      ),
    );
  }
}

/// تقدم تجميع رسالة SMS — شريط وحبيبات للأجزاء الناقصة وزر إسقاط.
class _AssemblyCard extends ConsumerWidget {
  const _AssemblyCard({required this.status});

  final SmsInboxStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final received = status.receivedParts.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.forward_to_inbox_outlined,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.assemblyProgress(received, status.total),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: () => ref
                      .read(walletProvider.notifier)
                      .forgetSms(status.msgId),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: received / status.total,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            if (status.missingParts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                l.missingParts(status.missingParts.join('، ')),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// بطاقة التحويل الموثّق — النتيجة قبل القبول الصريح.
class _VerifiedCard extends StatelessWidget {
  const _VerifiedCard({
    required this.received,
    required this.accepted,
    required this.onAccept,
  });

  final ReceivedToken received;
  final bool accepted;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final expiry = DateTime.fromMillisecondsSinceEpoch(
        received.token.expiresAt * 1000);
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${two(expiry.day)}/${two(expiry.month)} ${two(expiry.hour)}:${two(expiry.minute)}';

    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              accepted ? Icons.task_alt : Icons.verified,
              size: 44,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(height: 8),
            Text(
              l.verifiedTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSecondaryContainer,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '${formatPiasters(received.amount)} ${l.currencySdg}',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSecondaryContainer,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              l.fromSender(shortId(received.senderId)),
              style: TextStyle(
                color: scheme.onSecondaryContainer.withValues(alpha: .8),
              ),
            ),
            Text(
              l.expiresIn(stamp),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSecondaryContainer.withValues(alpha: .7),
              ),
            ),
            const SizedBox(height: 16),
            if (!accepted)
              FilledButton.icon(
                onPressed: onAccept,
                icon: const Icon(Icons.download_done),
                label: Text(l.acceptIntoWallet),
              ),
          ],
        ),
      ),
    );
  }
}
