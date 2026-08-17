import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';

import '../tool/check_l10n_orphans.dart';

/// Toetst de wezenpoort zelf, in TWEE richtingen.
///
/// Alleen "meldt niets op een gebruikte sleutel" is de helft die een kapotte
/// poort ook haalt: een analyse die stilvalt meldt nooit iets en is dus altijd
/// groen. Elke richtingstest hieronder heeft daarom een tegenhanger die een
/// wees PLANT en eist dat hij gevonden wordt.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('l10n_orphans'));
  tearDown(() => root.deleteSync(recursive: true));

  /// Schrijft een mini-repo: een vertaaltabel plus de bestanden eromheen.
  void give({
    required Map<String, String> table,
    Map<String, String> files = const {},
  }) {
    final entries = table.entries
        .map((e) => "  '${e.key}': '${e.value}',")
        .join('\n');
    _write(
      root,
      'lib/l10n/translations/en.dart',
      "part of '../app_localizations.dart';\n\nconst _stringsEn = {\n$entries\n};\n",
    );
    files.forEach((path, content) => _write(root, path, content));
  }

  List<String> orphans() =>
      findOrphanKeys(root.path).map((o) => o.key).toList();

  group('een sleutel die wél wordt opgehaald', () {
    test('via een letterlijke d() blijft buiten de melding', () {
      give(
        table: {'Opslaan': 'Save'},
        files: {'lib/ui.dart': "Widget b() => Text(l10n.d('Opslaan'));"},
      );
      expect(orphans(), isEmpty);
    });

    test('via een letterlijke t() blijft buiten de melding', () {
      give(
        table: {'saveButton': 'Save'},
        files: {'lib/ui.dart': "Widget b() => Text(l10n.t('saveButton'));"},
      );
      expect(orphans(), isEmpty);
    });

    test('via een doorgeefluik (een literal in een register) blijft stil', () {
      // `EditorField(label: 'Titel')` gaat verderop door `l10n.d(widget.label)`.
      // De literal staat er, dus de sleutel is in gebruik.
      give(
        table: {'Titel': 'Title'},
        files: {'lib/ui.dart': "const veld = EditorField(label: 'Titel');"},
      );
      expect(orphans(), isEmpty);
    });

    test('als aaneengeschakelde literal blijft stil', () {
      // Dit is de valse-alarmbron die een grep niet aankan: in de bron staat de
      // zin nergens als één stuk tekst.
      give(
        table: {'Een lange zin over twee regels': 'A long sentence'},
        files: {
          'lib/ui.dart':
              "final s = l10n.d('Een lange zin '\n    'over twee regels');",
        },
      );
      expect(orphans(), isEmpty);
    });

    test('als label in asset-gegevens blijft stil', () {
      // De derde ophaalweg: `AppLocalizations.sourceFor(lang, labelNl)` met een
      // label dat uit een sjabloonbestand komt, niet uit een Dart-literal.
      give(
        table: {'Bedreigingen': 'Threats'},
        files: {
          'assets/improvement/templates/swot.json': '{"nl": "Bedreigingen"}',
        },
      );
      expect(orphans(), isEmpty);
    });
  });

  group('een geplante wees', () {
    test('wordt gemeld, met tabel en regelnummer', () {
      give(
        table: {
          'Opslaan': 'Save',
          'Niemand roept dit aan': 'Nobody calls this',
        },
        files: {'lib/ui.dart': "Widget b() => Text(l10n.d('Opslaan'));"},
      );

      final found = findOrphanKeys(root.path);
      expect(found.map((o) => o.key), ['Niemand roept dit aan']);
      expect(found.single.table, '_stringsEn');
      expect(found.single.line, 5);
    });

    test('blijft een wees als alleen de documentatie hem noemt', () {
      // Proza is geen gebruik. Zonder deze regel poetst één CHANGELOG-regel de
      // wees weg die je zoekt.
      give(
        table: {'Niemand roept dit aan': 'Nobody calls this'},
        files: {
          'docs/CHANGELOG.md': '- knop "Niemand roept dit aan" toegevoegd',
        },
      );
      expect(orphans(), ['Niemand roept dit aan']);
    });

    test('blijft een wees als alleen zijn eigen l10n-spec hem noemt', () {
      // `tool/*_l10n_spec.json` is de INVOER van `make add-l10n`: dat bestand
      // heeft de sleutel gemaakt, het gebruikt hem niet.
      give(
        table: {'Niemand roept dit aan': 'Nobody calls this'},
        files: {'tool/knop_l10n_spec.json': '{"nl": "Niemand roept dit aan"}'},
      );
      expect(orphans(), ['Niemand roept dit aan']);
    });

    test('blijft een wees als alleen de vertaaltabellen hem noemen', () {
      give(
        table: {'Niemand roept dit aan': 'Nobody calls this'},
        files: {
          'lib/l10n/translations/de.dart':
              "const _stringsDe = {'Niemand roept dit aan': 'Niemand ruft'};",
        },
      );
      expect(orphans(), ['Niemand roept dit aan']);
    });
  });

  group('op de echte boom', () {
    // Één meting over de repo zelf, zodat de poort niet alleen op speelgoed
    // bewezen is. Dit is de duurste test in dit bestand (hij leest lib/, test/,
    // tool/, assets/ en web/), dus hij draait eenmalig en deelt zijn uitkomst.
    late final List<OrphanKey> found;
    setUpAll(() => found = findOrphanKeys('.'));

    test('vindt de met de hand bevestigde wezen', () {
      final keys = found.map((o) => o.key).toSet();
      expect(keys, contains('Logo tonen op deze slide'));
      expect(keys, contains('Verstreken tijd resetten'));
      expect(keys, contains('settingsLogo'));
    });

    test('meldt geen sleutel die overduidelijk in gebruik is', () {
      final keys = found.map((o) => o.key).toSet();
      expect(keys, isNot(contains('Opslaan')));
      expect(keys, isNot(contains('Instellingen')));
      // Via de gegevensweg (`sourceFor` op een sjabloonlabel uit assets/).
      expect(keys, isNot(contains('Bedreigingen')));
    });

    test('blijft onder de ratchet', () {
      expect(found.length, lessThanOrEqualTo(orphanBaseline));
    });

    test('meldt alleen sleutels die echt in de tabel staan', () {
      // Een melding moet naar iets wijzen wat je kunt opruimen.
      for (final orphan in found) {
        expect(
          AppLocalizations.hasTranslationKey('en', orphan.key) ||
              AppLocalizations.hasDirectDutchSourceTranslation(
                'en',
                orphan.key,
              ),
          isTrue,
          reason: '${orphan.key} staat niet in de Engelse tabel',
        );
      }
    });
  });
}

void _write(Directory root, String path, String content) {
  final file = File('${root.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}
