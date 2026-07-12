/// الإرسال: مهمة واحدة — مبلغ ومستلم ثم تأكيد صريح قبل التوقيع.
/// المبلغ حقل بطل كبير، والتحقق فوري، والأخطاء بمبالغها الفعلية.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/error_text.dart';
import '../../core/money.dart';
import '../../core/wallet_controller.dart';
import 'send_result_screen.dart';

final _hex16 = RegExp(r'^[0-9a-fA-F]{16}$');

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _recipient = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _recipient.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final amount = parsePiasters(_amount.text)!;
    final recipient = _recipient.text.trim().toLowerCase();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ConfirmSheet(amount: amount, recipient: recipient),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final wallet = ref.read(walletProvider.notifier);
    final state = ref.read(walletProvider).requireValue;
    try {
      final token = await wallet.send(recipientId: recipient, amount: amount);
      if (!mounted) return;
      _amount.clear();
      _recipient.clear();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SendResultScreen(token: token),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(describeSendError(
          context,
          e,
          available: state.offlineAvailable,
          dailyRemaining: state.dailyRemaining,
        )),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final state = ref.watch(walletProvider).valueOrNull;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l.sendTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Text(l.amountLabel,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amount,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: l.amountHint,
                suffixText: l.currencySdg,
              ),
              validator: (v) {
                final p = parsePiasters(v ?? '');
                if (p == null) return l.amountRequired;
                if (p < 1) return l.amountTooSmall;
                return null;
              },
            ),
            if (state != null) ...[
              const SizedBox(height: 6),
              Text(
                l.dailyRemaining(formatPiasters(state.dailyRemaining)),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 20),
            Text(l.recipientLabel,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _recipient,
              textDirection: TextDirection.ltr,
              maxLength: 16,
              style: const TextStyle(letterSpacing: 1.5),
              decoration: InputDecoration(
                helperText: l.recipientHelper,
                counterText: '',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    final text = data?.text?.trim();
                    if (text != null) _recipient.text = text;
                  },
                ),
              ),
              validator: (v) =>
                  _hex16.hasMatch((v ?? '').trim()) ? null : l.recipientInvalid,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Icon(Icons.lock_outline),
              label: Text(l.reviewTransfer),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.amount, required this.recipient});

  final int amount;
  final String recipient;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              value,
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.confirmTransferTitle,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          row(
            l.confirmAmount,
            Text(
              '${formatPiasters(amount)} ${l.currencySdg}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          row(
            l.confirmRecipient,
            Text(
              shortId(recipient),
              style: const TextStyle(letterSpacing: 1.2),
              textDirection: TextDirection.ltr,
            ),
          ),
          row(l.confirmFees, Text(l.feesFree)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.airplanemode_active,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.confirmOfflineNote,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.confirmAndSign),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
        ],
      ),
    );
  }
}
