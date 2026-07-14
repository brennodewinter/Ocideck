import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Zoeken door de instellingen. De echte waarde zit in de sprong: typ "youtube"
/// en je staat bij "Online media" — zonder te weten dat die onder Beveiliging
/// hangt.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openSettings(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pumpAndSettle();
  }

  // De tabbladen blijven achter de resultatenlijst in de boom staan (de
  // IndexedStack bouwt ze alle twaalf — dát is wat de ankers laat werken), dus
  // een label komt twee keer voor. Het kruimelpad onder een treffer bestaat
  // alleen in de resultatenlijst: dáár toetsen we op.
  testWidgets('a synonym finds the setting it belongs to', (tester) async {
    await openSettings(tester);
    // "youtube" staat nergens op het scherm — het is een keyword.
    await search(tester, 'youtube');

    expect(find.text('Beveiliging › Online media'), findsOneWidget);
    expect(find.text('Geen instelling gevonden'), findsNothing);
  });

  testWidgets('search matches on the visible label too', (tester) async {
    await openSettings(tester);
    await search(tester, 'contrastverhouding');
    expect(find.textContaining('› Toegankelijkheid'), findsOneWidget);
  });

  testWidgets('a query that matches nothing says so', (tester) async {
    await openSettings(tester);
    await search(tester, 'zoiets bestaat niet');
    expect(find.text('Geen instelling gevonden'), findsOneWidget);
  });

  testWidgets('tapping a hit jumps to the tab holding that setting', (
    tester,
  ) async {
    await openSettings(tester);
    await search(tester, 'youtube');

    await tester.tap(find.text('Beveiliging › Online media'));
    await tester.pumpAndSettle();
    // De oplichting van de sectie dooft na 3 seconden; laat die timer aflopen.
    await tester.pump(const Duration(seconds: 4));

    // De resultatenlijst is weg (geen kruimelpad meer) en het Beveiliging-
    // tabblad staat open, met zijn eigen schakelaars in beeld.
    expect(find.text('Beveiliging › Online media'), findsNothing);
    expect(find.text('CVE opzoeken (online)'), findsOneWidget);
    expect(find.text('Herstelbestanden nu wissen'), findsOneWidget);
  });

  // De registry dupliceert de bronstrings van de tabbladen. Dat mag, maar dan
  // moet hij ook meebewegen: een sectiekop die nergens meer door _sectionTitle
  // gaat, is een anker dat nooit meer aanslaat — en dat merk je anders pas als
  // een gebruiker op een treffer klikt en er niets gebeurt.
  test('every indexed section title still exists in the settings parts', () {
    final sources = Directory('lib/widgets/dialogs')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    // Een sectiekop komt op drie manieren binnen: rechtstreeks, als kale string,
    // of via _presentationStyleDivider — die zijn titel doorgeeft aan
    // _sectionTitle en dus hetzelfde anker registreert.
    final missing = <String>[];
    for (final entry in kSettingsSearchIndex) {
      final section = entry.section;
      if (section == null) continue;
      final escaped = section.replaceAll("'", r"\'");
      final rendered = [
        "_sectionTitle(l10n.d('$escaped')",
        "_sectionTitle('$escaped')",
        "_presentationStyleDivider(l10n.d('$escaped')",
      ];
      if (!rendered.any(sources.contains)) missing.add(section);
    }

    expect(
      missing,
      isEmpty,
      reason:
          'Deze sectiekoppen staan in kSettingsSearchIndex maar worden nergens '
          'meer door _sectionTitle gerenderd, dus hun anker grijpt mis: '
          '${missing.join(', ')}',
    );
  });
}
