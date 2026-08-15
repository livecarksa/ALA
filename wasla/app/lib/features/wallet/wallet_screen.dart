/// المحفظة: بطاقة رصيد البنك، بطاقة المحفظة الأوف لاين بسقفها اليومي،
/// لافتة التسوية عند عودة الاتصال، وإجراءان سريعان. تسلسل بصري واحد:
/// الرصيد ← ما يمكن فعله الآن.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/money.dart';
import '../../core/wallet_controller.dart';
import '../../theme/wasla_theme.dart';
import '../home/home_shell.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final state = ref.watch(walletProvider).valueOrNull;
    if (state == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _BankBalanceCard(state: state),
        const SizedBox(height: 12),
        _OfflineWalletCard(state: state),
        if (state.online && state.pendingCount > 0) ...[
          const SizedBox(height: 12),
          _SettleBanner(state: state),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    ref.read(homeTabProvider.notifier).state = 1,
                icon: const Icon(Icons.north_east),
                label: Text(l.quickSend),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    ref.read(homeTabProvider.notifier).state = 2,
                icon: const Icon(Icons.south_west),
                label: Text(l.quickReceive),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            leading: Icon(Icons.badge_outlined, color: scheme.primary),
            title: Text(l.deviceIdLabel,
                style: Theme.of(context).textTheme.labelMedium),
            subtitle: Text(
              state.deviceId,
              style: const TextStyle(fontSize: 15, letterSpacing: 1.2),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.right,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: state.deviceId));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l.copied)));
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.offline_bolt_outlined, color: waslaGold),
                    const SizedBox(width: 8),
                    Text(
                      l.howItWorksTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l.howItWorksBody,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BankBalanceCard extends StatelessWidget {
  const _BankBalanceCard({required this.state});

  final WalletState state;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [scheme.primary, Color.lerp(scheme.primary, Colors.black, .25)!],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.bankBalanceTitle,
            style: TextStyle(color: scheme.onPrimary.withValues(alpha: .85)),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: formatPiasters(state.bankBalance),
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 40,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
              children: [
                TextSpan(
                  text: ' ${l.currencySdg}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: scheme.onPrimary.withValues(alpha: .85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l.serviceTagline,
            style: TextStyle(
              color: scheme.onPrimary.withValues(alpha: .7),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineWalletCard extends StatelessWidget {
  const _OfflineWalletCard({required this.state});

  final WalletState state;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final capUsed = state.dailyCap == 0
        ? 0.0
        : (state.spentToday / state.dailyCap).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.airplanemode_active,
                    size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.offlineWalletTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: scheme.surfaceContainerHighest,
                  label: Text(
                    l.chainEpoch(state.epoch),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l.offlineAvailable,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(
                text: formatPiasters(state.offlineAvailable),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                children: [
                  TextSpan(
                    text: ' ${l.currencySdg}',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.dailyCapUsage,
                    style: Theme.of(context).textTheme.labelMedium),
                Text(
                  l.dailyRemaining(formatPiasters(state.dailyRemaining)),
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: capUsed,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l.pendingSettlement(state.pendingCount),
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettleBanner extends ConsumerWidget {
  const _SettleBanner({required this.state});

  final WalletState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_done_outlined,
                    color: scheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Text(
                  l.settleBannerTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onTertiaryContainer,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l.settleBannerBody,
              style: TextStyle(color: scheme.onTertiaryContainer),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: state.settling
                  ? null
                  : () async {
                      final count =
                          await ref.read(walletProvider.notifier).settle();
                      if (context.mounted && count > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.settleSuccess(count))),
                        );
                      }
                    },
              icon: state.settling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Icon(Icons.sync),
              label: Text(state.settling ? l.settling : l.settleNow),
            ),
          ],
        ),
      ),
    );
  }
}
