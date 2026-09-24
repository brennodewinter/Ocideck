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

/// Datzelfde deck, met de acceptatievlag.
const _acceptedDeck = '''
---
marp: true
theme: default
ocideck_marp_compat_accepted: true
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
    expect(find.text('Marp-compatibel'), findsOneWidget);
    expect(find.text('Accepteren voor dit deck'), findsNothing);
  });

  testWidgets('gedegradeerd deck toont oranje balk met acceptatieknop', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_degradedDeck));
    await _settle(tester);
    expect(find.textContaining('aandachtspunt'), findsOneWidget);
    expect(find.text('Accepteren voor dit deck'), findsOneWidget);
  });

  testWidgets('accepteren schrijft de vlag in de front matter', (tester) async {
    await tester.pumpWidget(_host(_degradedDeck));
    await _settle(tester);

    await tester.tap(find.text('Accepteren voor dit deck'));
    await _settle(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.controller?.text,
      contains('ocideck_marp_compat_accepted: true'),
    );
    // De balk toont meteen de geaccepteerde staat.
    expect(find.textContaining('geaccepteerd'), findsOneWidget);
    expect(find.text('Acceptatie terugnemen'), findsOneWidget);
  });

  testWidgets('terugnemen haalt de vlag weg en de oranje keert terug', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_acceptedDeck));
    await _settle(tester);
    expect(find.textContaining('geaccepteerd'), findsOneWidget);

    await tester.tap(find.text('Acceptatie terugnemen'));
    await _settle(tester);

    expect(find.textContaining('aandachtspunt'), findsOneWidget);
    expect(find.textContaining('geaccepteerd'), findsNothing);
  });

  testWidgets('rood deck biedt geen acceptatie aan', (tester) async {
    await tester.pumpWidget(_host(_brokenDeck));
    await _settle(tester);
    expect(find.textContaining('Niet Marp-compatibel'), findsOneWidget);
    expect(find.text('Accepteren voor dit deck'), findsNothing);
  });

  testWidgets('uitgeklapte bevindingen springen naar de regel', (tester) async {
    await tester.pumpWidget(_host(_degradedDeck));
    await _settle(tester);
    await tester.tap(find.textContaining('aandachtspunt'));
    await _settle(tester);
    // De chart-fence en de class-token staan als bevindingen in de lijst.
    expect(find.textContaining('codeblok'), findsWidgets);
  });

  testWidgets('controle uit in instellingen → geen balk', (tester) async {
    SharedPreferences.setMockInitialValues({
      'marpCompatChecksEnabled': false,
    });
    await tester.pumpWidget(_host(_degradedDeck));
    // De instelling laadt asynchroon; geef _load de kans te ronden.
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MarkdownDeckEditor)),
    );
    expect(
      container.read(settingsProvider).marpCompatChecksEnabled,
      isFalse,
    );
    await _settle(tester);
    expect(find.textContaining('aandachtspunt'), findsNothing);
    expect(find.text('Marp-compatibel'), findsNothing);
  });
}
