/// تسليم التوكن: قناتان بلا شبكة — QR للمواجهة، ومقاطع SMS للهواتف
/// العادية. كل مقطع بطاقة برقمه وزر نسخ، والترتيب موضّح صراحة.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wasla_core/wasla_core.dart';

import '../../app.dart';
import '../../core/money.dart';
import '../../core/wallet_controller.dart';

class SendResultScreen extends ConsumerStatefulWidget {
  const SendResultScreen({super.key, required this.token});

  final SignedToken token;

  @override
  ConsumerState<SendResultScreen> createState() => _SendResultScreenState();
}

class _SendResultScreenState extends ConsumerState<SendResultScreen> {
  int _channel = 0; // 0 = QR، 1 = SMS

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final wallet = ref.read(walletProvider.notifier);
    final payload = wallet.payloadOf(widget.token);
    final segments = wallet.smsSegmentsOf(widget.token);
    final expiry = DateTime.fromMillisecondsSinceEpoch(
        widget.token.expiresAt * 1000);

    return Scaffold(
      appBar: AppBar(title: Text(l.tokenReadyTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.verified_outlined,
                      size: 40, color: scheme.onSecondaryContainer),
                  const SizedBox(height: 8),
                  Text(
                    '${formatPiasters(widget.token.amount)} ${l.currencySdg}',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSecondaryContainer,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.expiresIn(_formatStamp(expiry)),
                    style: TextStyle(
                      color: scheme.onSecondaryContainer.withValues(alpha: .8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l.tokenReadySubtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                icon: const Icon(Icons.qr_code_2),
                label: Text(l.deliverByQr),
              ),
              ButtonSegment(
                value: 1,
                icon: const Icon(Icons.sms_outlined),
                label: Text(l.deliverBySms),
              ),
            ],
            selected: {_channel},
            onSelectionChanged: (s) => setState(() => _channel = s.first),
          ),
          const SizedBox(height: 16),
          if (_channel == 0) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: 260,
                  gapless: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l.qrInstruction,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ] else ...[
            Text(
              l.smsInstruction(segments.length),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < segments.length; i++) ...[
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsetsDirectional.only(
                      start: 20, end: 8, top: 4, bottom: 4),
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  title: Text(
                    l.smsPartLabel(i + 1, segments.length),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  subtitle: Text(
                    '${segments[i].substring(0, segments[i].length > 28 ? 28 : segments[i].length)}…',
                    style: const TextStyle(
                        letterSpacing: 1.2, fontSize: 12),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: l.copyPart,
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: segments[i]));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.copied)));
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.done),
          ),
        ],
      ),
    );
  }
}

String _formatStamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}
