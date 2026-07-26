// De sneltoetsaanduiding (lib/utils/shortcut_label.dart) en de regel dat er maar
// ÉÉN manier is waarop er een op het scherm komt.
//
// #803: er leefden twee patronen naast elkaar. Het commandopalet droeg losse
// literals (`shortcut: 'Ctrl/Cmd+S'`) en het ⋮-menu een achtervoegsel buiten
// `d()` om, terwijl de vertaalbestanden de sneltoets juist ÍN de vertaalde tekst
// hadden staan (`'undo': 'Rückgängig (Strg/Cmd+Z)'`). Wie de app in het Duits
// gebruikte, zag daardoor twee spellingen door elkaar: Strg in de werkbalk en
// Ctrl in het menu ernaast. Deze tests leggen de gekozen kant vast — samenstellen
// uit een vertaald deel en een identifier — en bewaken dat er geen nieuwe losse
// sneltoetsliteral bijkomt.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/shortcut_label.dart';
import 'package:ocideck/l10n/app_localizations.dart';

void main() {
  // De actieve taal is een STATISCHE in AppLocalizations; de Locale in de
  // constructor kiest hem niet. Wie dat over het hoofd ziet, schrijft een test
  // die altijd Nederlands meet en dus nooit iets bewijst.
  const l10n = AppLocalizations(Locale('nl'));
  AppLocalizations in_(String code) {
    AppLocalizations.setActiveLanguageCode(code);
    return l10n;
  }

  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  test('de toets blijft staan, de modificatietoets wordt vertaald', () {
    expect(shortcutLabel(in_('nl'), 'S'), 'Ctrl/Cmd+S');
    // Het Duitse toetsenbord draagt Strg. Dit is de reden dat een sneltoets
    // tekst is en geen identifier: de bestaande vertalingen deden dit al.
    expect(shortcutLabel(in_('de'), 'S'), 'Strg/Cmd+S');
    expect(shortcutLabel(in_('fr'), 'S'), 'Ctrl/Cmd+S');
  });

  test('Shift is óók een opschrift en volgt de taal', () {
    expect(shortcutLabel(in_('nl'), 'Z', shift: true), 'Ctrl/Cmd+Shift+Z');
    expect(shortcutLabel(in_('de'), 'Z', shift: true), 'Strg/Cmd+Umschalt+Z');
    expect(shortcutLabel(in_('fr'), 'Z', shift: true), 'Ctrl/Cmd+Maj+Z');
  });

  test('label en sneltoets komen uit één aanroep', () {
    expect(
      labelWithShortcut(in_('nl'), 'Opslaan', 'S'),
      'Opslaan  (Ctrl/Cmd+S)',
    );
    // Beide helften vertaald, in één regel — dit was de "half vertaalde regel"
    // uit het issue.
    expect(
      labelWithShortcut(in_('de'), 'Opslaan', 'S'),
      'Speichern  (Strg/Cmd+S)',
    );
  });

  test('de werkbalk en het commandopalet spellen hem gelijk', () {
    // De concrete regressie: de tooltip van de opslaanknop en de sneltoetshint
    // in het palet kwamen uit twee verschillende bronnen. Nu uit dezelfde, dus
    // kunnen ze niet meer uiteenlopen.
    final de = in_('de');
    expect(
      labelWithShortcut(de, 'Opslaan', 'S'),
      contains(shortcutLabel(de, 'S')),
    );
  });

  test('geen enkel bestand in lib/ schrijft een sneltoets zelf', () {
    // De poort naast de reparatie. tool/check_hardcoded_text.dart ziet sinds
    // #803 het achtervoegsel in een interpolatie, maar de veldsprong in
    // `PaletteCommand.shortcut` ontsnapt hem nog (zie de kop van dat bestand),
    // dus draagt deze test dát halve gat.
    //
    // Een sneltoets ín een vertaalde ZIN mag wel — "plak met Cmd/Ctrl+V een
    // tabel uit je spreadsheet" is proza dat een vertaler zelf aanpast, en
    // samenstellen kan daar niet. Het onderscheid is dus niet "komt Ctrl erin
    // voor", maar: blijft er een woord staan als je de notatie wegstreept? Zo
    // niet, dan wás de literal een sneltoets en hoort hij uit shortcutLabel te
    // komen.
    // De toetsopschriften horen bij de notatie, niet bij de zin. Zonder Esc en
    // Home erin las `'Esc · Ctrl+W'` als proza en glipte er een echte
    // overtreding doorheen — die stond er nog terwijl deze test al groen was.
    final notation = RegExp(
      r'Ctrl|Cmd|Strg|Umschalt|Shift|Maj|Alt|Option|Esc|Enter|Home|End|Tab|'
      r'Del|Space|[-+/()·\s]|\b[A-Z0-9]\b',
    );
    final aWord = RegExp('[A-Za-z]');
    final literals = RegExp(r"'((?:\\.|[^'\n])*)'");

    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      // Naar '/' normaliseren: op Windows geeft listSync backslashes, waardoor
      // de startsWith/endsWith-uitsluitingen hieronder niet matchten en de
      // vertaaltabellen ten onrechte gescand werden.
      final pad = file.path.replaceAll(r'\', '/');
      // De vertaaltabellen dragen de vertaalde opschriften, en de helper zelf
      // is per definitie de plek waar de notatie mag staan.
      if (pad.startsWith('lib/l10n/') ||
          pad.endsWith('utils/shortcut_label.dart')) {
        continue;
      }
      for (final line in file.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        for (final match in literals.allMatches(line)) {
          final text = match.group(1)!;
          if (!text.contains('Ctrl') &&
              !text.contains('Cmd') &&
              !text.contains('Strg')) {
            continue;
          }
          if (aWord.hasMatch(text.replaceAll(notation, ''))) continue;
          offenders.add('${file.path}: $text');
        }
      }
    }

    expect(offenders, isEmpty);
  });
}
