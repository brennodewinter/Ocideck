import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'l10n/app_localizations.dart';
import 'state/settings_provider.dart';
import 'state/consent_provider.dart';
import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';
import 'widgets/dialogs/consent_dialog.dart';

class OciDeckApp extends ConsumerWidget {
  const OciDeckApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languageCode = ref.watch(
      settingsProvider.select((s) => s.languageCode),
    );
    final appearance = ref.watch(
      settingsProvider.select((s) => s.appAppearanceProfile),
    );
    final uiTextScale = ref.watch(
      settingsProvider.select((s) => s.uiTextScale),
    );
    AppLocalizations.setActiveLanguageCode(languageCode);
    return MaterialApp(
      title: 'OciDeck',
      theme: AppTheme.fromProfile(appearance),
      debugShowCheckedModeBanner: false,
      // Interface text scaling (WCAG 1.4.4): the user's setting multiplies
      // whatever the OS already asks for. Slides themselves opt out — they
      // are a fixed design canvas (see SlidePreviewWidget).
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(
              (media.textScaler.scale(1.0) * uiTextScale).clamp(1.0, 2.0),
            ),
          ),
          child: child!,
        );
      },
      locale: AppLocalizations.materialLocaleFor(languageCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: const _ConsentGate(),
    );
  }
}

class _ConsentGate extends ConsumerWidget {
  const _ConsentGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(consentProvider);

    if (consent.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!consent.hasAccepted) {
      // Plain Scaffold inside the app's existing MaterialApp — that one already
      // supplies the theme and the AppLocalizations delegate, so context.l10n
      // resolves here. A nested MaterialApp would start a fresh Localizations
      // scope without our delegate and the consent text would render blank.
      return const Scaffold(
        body: Center(child: ConsentDialog()),
      );
    }

    return const AppShell();
  }
}
