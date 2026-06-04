import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'l10n/app_localizations.dart';
import 'state/settings_provider.dart';
import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';

class OciDeckApp extends ConsumerWidget {
  const OciDeckApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languageCode = ref.watch(
      settingsProvider.select((s) => s.languageCode),
    );
    AppLocalizations.setActiveLanguageCode(languageCode);
    return MaterialApp(
      title: 'OciDeck',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      locale: AppLocalizations.materialLocaleFor(languageCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: const AppShell(),
    );
  }
}
