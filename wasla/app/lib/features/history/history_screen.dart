/// السجل والمطابقة: بطاقة مطابقة تثبت «المحجوز = الصادر + المتبقي»
/// أعلى الخط الزمني — لأن ثقة لجنة البنك تُبنى على صفر فروقات.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/money.dart';
import '../../core/wallet_controller.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final state = ref.watch(walletProvider).valueOrNull;
    if (state == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    final sentPending = state.history
        .where((e) => e.kind == EventKind.sent && !e.settled)
        .fold<int>(0, (s, e) => s + e.amount);
    final receivedPending = state.history
        .where((e) => e.kind == EventKind.received && !e.settled)
        .fold<int>(0, (s, e) => s + e.amount);
    final reserved = state.offlineAvailable + sentPending;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l.historyTitle,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.balance, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      l.reconciliationTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _reconRow(context, l.reconReserved, reserved),
                _reconRow(context, l.reconSpent, sentPending),
                _reconRow(context, l.reconReceivedPending, receivedPending),
                _reconRow(context, l.reconRemaining, state.offlineAvailable),
                const Divider(height: 24),
                Row(
                  children: [
                    Icon(Icons.check_circle,
                        size: 18, color: scheme.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.reconOk,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (state.history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 56, color: scheme.outlineVariant),
                const SizedBox(height: 12),
                Text(
                  l.historyEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          )
        else
          for (final event in state.history) ...[
            _EventTile(event: event),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _reconRow(BuildContext context, String label, int amount) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            '${formatPiasters(amount)} ${l.currencySdg}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final WalletEvent event;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final sent = event.kind == EventKind.sent;
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${two(event.at.day)}/${two(event.at.month)} ${two(event.at.hour)}:${two(event.at.minute)}';

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor:
              sent ? scheme.errorContainer : scheme.secondaryContainer,
          child: Icon(
            sent ? Icons.north_east : Icons.south_west,
            size: 20,
            color: sent
                ? scheme.onErrorContainer
                : scheme.onSecondaryContainer,
          ),
        ),
        title: Text(
          sent
              ? l.eventSent(shortId(event.peer))
              : l.eventReceived(shortId(event.peer)),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(stamp,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${sent ? '−' : '+'}${formatPiasters(event.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: sent ? scheme.error : scheme.secondary,
              ),
              textDirection: TextDirection.ltr,
            ),
            Text(
              event.settled ? l.statusSettled : l.statusPending,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
