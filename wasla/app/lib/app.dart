/// جذر التطبيق: عربي RTL أولاً، ثيم بنكك، ولا نصوص صلبة — كله من intl.
library;

import 'package:flutter/material.dart';

import 'features/home/home_shell.dart';
import 'l10n/app_localizations.dart';
import 'theme/wasla_theme.dart';

class WaslaApp extends StatelessWidget {
  const WaslaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        onGenerateTitle: (context) => context.l10n.appTitle,
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: waslaTheme(Brightness.light),
        darkTheme: waslaTheme(Brightness.dark),
        home: const HomeShell(),
      );
}

/// وصول مختصر للترجمات.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
