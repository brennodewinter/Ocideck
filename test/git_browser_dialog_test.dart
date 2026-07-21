import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/state/git_provider.dart';
import 'package:ocideck/widgets/dialogs/git_browser_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De deckkiezer over een git-repository. Alleen kiezen: het ophalen en de
/// security-gate leven bij de aanroeper, dus wat hier telt is welke deknaam
/// eruit komt en wat het scherm zegt als er niets te kiezen valt.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  const connectionId = 'git-1';

  Future<String?> open(
    WidgetTester tester, {
    Map<String, String>? decks,
    Object? error,
    bool viaShow = true,
  }) async {
    String? chosen;
    final overrides = [
      gitDeckListProvider.overrideWith((ref, key) async {
        if (error != null) throw error;
        return decks ?? const {};
      }),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Scaffold(
            body: viaShow
                ? Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () async =>
                          chosen = await GitBrowserDialog.show(
                            context,
                            connectionId: connectionId,
                          ),
                      child: const Text('open'),
                    ),
                  )
                : const GitBrowserDialog(connectionId: connectionId),
          ),
        ),
      ),
    );
    if (viaShow) await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return chosen;
  }

  testWidgets('de decks staan op alfabet, niet op repo-volgorde', (
    tester,
  ) async {
    await open(
      tester,
      viaShow: false,
      decks: const {
        'zomerplan': 'decks/zomerplan',
        'auditrapport': 'decks/auditrapport',
        'kwartaal': 'decks/kwartaal',
      },
    );

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title! as Text).data)
        .toList();
    expect(titles, ['auditrapport', 'kwartaal', 'zomerplan']);
  });

  testWidgets('een gekozen deck levert zijn map op, niet zijn naam', (
    tester,
  ) async {
    String? chosen;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitDeckListProvider.overrideWith(
            (ref, key) async => const {'kwartaal': 'decks/kwartaal'},
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => chosen = await GitBrowserDialog.show(
                  context,
                  connectionId: connectionId,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('kwartaal'));
    await tester.pumpAndSettle();

    // De aanroeper opent op pad; de naam alleen zou hem laten raden.
    expect(chosen, 'decks/kwartaal');
  });

  testWidgets('een lege repo zegt dat er niets in staat', (tester) async {
    await open(tester, viaShow: false, decks: const {});

    expect(find.text('Geen presentaties in deze repository.'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('een forge-fout wordt vertaald, niet ruw doorgegeven', (
    tester,
  ) async {
    await open(
      tester,
      viaShow: false,
      // De ruwe tekst is Nederlands en onvertaald; bij een onbekende status
      // stond er letterlijk "Onverwachte status 418" op het scherm.
      error: const GitForgeException(GitForgeError.auth, 'Onverwachte status'),
    );

    expect(find.textContaining('Onverwachte status'), findsNothing);
    expect(find.textContaining('Aanmelden bij de'), findsOneWidget);
  });

  testWidgets('annuleren geeft niets terug', (tester) async {
    final chosen = await open(
      tester,
      decks: const {'kwartaal': 'decks/kwartaal'},
    );
    expect(chosen, isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();
    expect(find.byType(GitBrowserDialog), findsNothing);
  });

  testWidgets('zonder ingestelde repo meldt het scherm dat, en blijft niet '
      'eeuwig laden', (tester) async {
    // Bewust zonder override: de echte provider gooit hier een
    // GitForgeException. Riverpod 3 zou die uit zichzelf blijven herhalen, en
    // een herhalende provider staat in AsyncLoading — dan draait de
    // laadindicator door en komt de uitleg nooit in beeld.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: GitBrowserDialog(connectionId: 'onbekend')),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('git'), findsWidgets);
  });
}
