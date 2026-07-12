/// الصدفة الرئيسية: شريط علوي بهوية الخدمة داخل بنكك وشارة الاتصال،
/// وتنقّل سفلي بأربع وجهات — كل وجهة مهمة واحدة واضحة.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/wallet_controller.dart';
import '../history/history_screen.dart';
import '../receive/receive_screen.dart';
import '../send/send_screen.dart';
import '../wallet/wallet_screen.dart';

/// الوجهة المختارة — مزوّد ليقفز إليها أي زر إجراء سريع.
final homeTabProvider = StateProvider<int>((ref) => 0);

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final tab = ref.watch(homeTabProvider);
    final wallet = ref.watch(walletProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                l.appTitle.characters.first,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.appTitle),
                Text(
                  l.bankBrand,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: _ConnectivityPill(online: wallet.valueOrNull?.online ?? false),
          ),
        ],
      ),
      body: switch (wallet) {
        AsyncData() => IndexedStack(
            index: tab,
            children: const [
              WalletScreen(),
              SendScreen(),
              ReceiveScreen(),
              HistoryScreen(),
            ],
          ),
        AsyncError(:final error) => Center(child: Text(error.toString())),
        _ => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l.walletLoading),
              ],
            ),
          ),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) =>
            ref.read(homeTabProvider.notifier).state = i,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet),
            label: l.navWallet,
          ),
          NavigationDestination(
            icon: const Icon(Icons.north_east),
            label: l.navSend,
          ),
          NavigationDestination(
            icon: const Icon(Icons.south_west),
            label: l.navReceive,
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: l.navHistory,
          ),
        ],
      ),
    );
  }
}

/// شارة الاتصال — «أوف لاين ✈» هي البطل، والضغط يبدّل المحاكاة.
class _ConnectivityPill extends ConsumerWidget {
  const _ConnectivityPill({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: l.toggleConnectivityHint,
      child: Material(
        color: online
            ? scheme.secondaryContainer
            : scheme.inverseSurface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => ref.read(walletProvider.notifier).toggleOnline(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  online ? Icons.wifi : Icons.airplanemode_active,
                  size: 16,
                  color: online
                      ? scheme.onSecondaryContainer
                      : scheme.onInverseSurface,
                ),
                const SizedBox(width: 6),
                Text(
                  online ? l.onlineBadge : l.offlineBadge,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: online
                        ? scheme.onSecondaryContainer
                        : scheme.onInverseSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
