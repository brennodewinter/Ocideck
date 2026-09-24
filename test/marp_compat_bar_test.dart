import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/editors/markdown_deck_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Een schoon Marp-deck: groene balk.
const _cleanDeck = '''
---
marp: true
theme: default
---

# Titel

- een
- twee
''';

/// Een deck dat Marp rendert maar met verlies (grafiek → codeblok).
const _degradedDeck = '''
---
marp: true
theme: default
---

<!-- _class: chart -->

```chart
{"kind":"bar"}
```
''';

/// Geen Marp: geen front matter.
const _brokenDeck = '# Titel\n\nGeen front matter.';

Widget _host(String content) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 1000,
        height: 1600,
        child: MarkdownDeckEditor(
          initialContent: content,
          onApply: (_) => true,
          parseError: false,
          onExitMarkdown: () {},
          onScopeChanged: (_) {},
        ),
      ),
    ),
  ),
);

/// De validatie-debounce is een echte Timer; `pumpAndSettle` laat hem niet
/// lopen zolang er geen frames gepland zijn — dus expliciet tijd verderzetten.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('schoon deck toont groene Marp-compatibel-balk', (tester) async {
    await tester.pumpWidget(_host(_cleanDeck));
    await _settle(tester);
    expect(find.text('Marp · Geen syntaxproblemen gevonden'), findsOneWidget);
    expect(find.text('Accepteren voor dit deck'), findsNothing);
  });

  testWidgets('gedegradeerd deck toont oranje balk', (tester) async {
    await tester.pumpWidget(_host(_degradedDeck));
    await _settle(tester);
    expect(find.textContaining('waarschuwing'), findsOneWidget);
    expect(find.textContaining('geaccepteerd'), findsNothing);
  });

  testWidgets('rood deck biedt geen acceptatie aan', (tester) async {
    await tester.pumpWidget(_host(_brokenDeck));
    await _settle(tester);
    expect(find.textContaining('Marp · Probleem'), findsOneWidget);
    expect(find.text('Accepteren voor dit deck'), findsNothing);
  });

  testWidgets('uitgeklapte bevindingen springen naar de regel', (tester) async {
    await tester.pumpWidget(_host(_degradedDeck));
    await _settle(tester);
    await tester.tap(find.textContaining('waarschuwing'));
    await _settle(tester);
    expect(find.textContaining('Niet overgenomen'), findsWidgets);
  });

  testWidgets('controle uit in instellingen → geen balk', (tester) async {
    SharedPreferences.setMockInitialValues({'marpCompatChecksEnabled': false});
    await tester.pumpWidget(_host(_degradedDeck));
    // De instelling laadt asynchroon; geef _load de kans te ronden.
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MarkdownDeckEditor)),
    );
    expect(container.read(settingsProvider).marpCompatChecksEnabled, isFalse);
    await _settle(tester);
    expect(find.textContaining('waarschuwing'), findsNothing);
    expect(find.text('Marp · Geen syntaxproblemen gevonden'), findsNothing);
  });

  testWidgets('live inschakelen toont de balk zonder tekstwijziging', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'marpCompatChecksEnabled': false});
    await tester.pumpWidget(_host(_cleanDeck));
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MarkdownDeckEditor)),
    );
    expect(find.text('Marp · Geen syntaxproblemen gevonden'), findsNothing);

    await container
        .read(settingsProvider.notifier)
        .setMarpCompatChecksEnabled(true);
    await _settle(tester);

    expect(find.text('Marp · Geen syntaxproblemen gevonden'), findsOneWidget);
  });

  testWidgets('lopende hercontrole kondigt niet de oude uitslag aan', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(_cleanDeck));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), '$_cleanDeck\n');
    await tester.pump();

    expect(find.bySemanticsLabel(RegExp('Controleren…')), findsWidgets);
    expect(
      find.bySemanticsLabel('Marp · Geen syntaxproblemen gevonden'),
      findsNothing,
    );
    semantics.dispose();
  });
}
