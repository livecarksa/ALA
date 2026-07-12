/// دخان الواجهة: التطبيق يقلع عربياً RTL، الوجهات الأربع تعمل،
/// وشارة «أوف لاين ✈» ظاهرة وتتبدل — فحص بصري آلي لكل شاشة جديدة.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasla_app/app.dart';
import 'package:wasla_app/core/wallet_controller.dart';
import 'package:wasla_app/l10n/app_localizations.dart';

Widget testApp() => ProviderScope(
      overrides: [seedStoreProvider.overrideWithValue(MemorySeedStore())],
      child: const WaslaApp(),
    );

Future<AppLocalizations> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(testApp());
  // توليد الهوية غير متزامن — ندفع الإطارات حتى تحميل المحفظة.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  final context = tester.element(find.byType(NavigationBar));
  return AppLocalizations.of(context)!;
}

/// نقرة وجهة في شريط التنقل — الأسماء تتكرر كأزرار سريعة في المحفظة.
Finder navDestination(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

void main() {
  testWidgets('يقلع عربياً RTL بشارة أوف لاين والمحفظة ظاهرة', (tester) async {
    final l = await pumpApp(tester);

    final navContext = tester.element(find.byType(NavigationBar));
    expect(Directionality.of(navContext), TextDirection.rtl,
        reason: 'العربية أولاً — RTL إلزامي');
    expect(find.text(l.offlineBadge), findsOneWidget);
    expect(find.text(l.bankBalanceTitle), findsOneWidget);
    expect(find.text(l.offlineWalletTitle), findsOneWidget);
  });

  testWidgets('التنقل بين الوجهات الأربع يعمل', (tester) async {
    final l = await pumpApp(tester);

    await tester.tap(navDestination(l.navSend));
    await tester.pumpAndSettle();
    expect(find.text(l.sendTitle), findsOneWidget);

    await tester.tap(navDestination(l.navReceive));
    await tester.pumpAndSettle();
    expect(find.text(l.receiveTitle), findsOneWidget);

    await tester.tap(navDestination(l.navHistory));
    await tester.pumpAndSettle();
    expect(find.text(l.historyTitle), findsOneWidget);
    expect(find.text(l.historyEmpty), findsOneWidget);
  });

  testWidgets('شارة الاتصال تتبدل بالمحاكاة', (tester) async {
    final l = await pumpApp(tester);

    await tester.tap(find.text(l.offlineBadge));
    await tester.pump();
    expect(find.text(l.onlineBadge), findsOneWidget);

    await tester.tap(find.text(l.onlineBadge));
    await tester.pump();
    expect(find.text(l.offlineBadge), findsOneWidget);
  });

  testWidgets('إدخال مقطع SMS تالف يعرض رسالة الخطأ الدقيقة', (tester) async {
    final l = await pumpApp(tester);

    await tester.tap(navDestination(l.navReceive));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.receiveModeSms));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, l.smsFieldLabel), 'garbage');
    await tester.tap(find.text(l.addSegment));
    await tester.pump();
    expect(find.text(l.errMalformedSegment), findsOneWidget);
  });
}
