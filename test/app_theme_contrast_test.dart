import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/utils/color_contrast.dart';

/// Het contrast van de **app zelf**, in beide modi.
///
/// `theme_profile_contrast_warning_test.dart` en `title_contrast_test.dart`
/// gaan over het deck van de gebruiker. Over de eigen chrome ging niets — en
/// dat is de asymmetrie die #606 opsomde: OciDeck rekent het contrast van jouw
/// dia's na en meldt wat zakt, terwijl 21 van de 25 vaste kleurtokens in donkere
/// modus zelf onder de lat lagen. De rekensom kost een reviewer vijf minuten.
///
/// Deze test zet dat getal in de repository in plaats van in een notitieboekje
/// van een criticus. Hij is een **ratchet**: elke pijnpunt staat met naam en
/// gemeten waarde in [_baseline], en de test faalt in twee richtingen — een
/// nieuw geval erbij, én een geval dat gerepareerd is maar in de lijst blijft
/// staan. Zo kan de lijst alleen maar korter worden.
void main() {
  /// De vaste tokens en de achtergrond waarop ze werkelijk gelezen worden:
  /// **het diacanvas**, dat wit is.
  ///
  /// Tot #606 werden deze tegen [AppTheme.paper] gemeten — het oppervlak van de
  /// interface. Dat was een categoriefout die de helft van de basislijn vulde:
  /// een ernstkleur van een bevinding staat op een dia, niet op een dialoog, en
  /// tegen een donker chrome-oppervlak meten zegt niets over waar hij gelezen
  /// wordt. Ze zijn `const` met een reden — een dia moet in een headless
  /// export-isolate identiek renderen aan de preview (PENTEST_MIAUW §11) — dus
  /// mode-afhankelijk maken kón hier ook niet.
  ///
  /// De interface gebruikt ze sinds #606 niet meer als tekst; dat bewaakt
  /// [_geenVasteKleurAlsChromeTekst] hieronder. Wat hier gemeten wordt is of ze
  /// op hun eigen achtergrond deugen.
  const slideCanvas = Color(0xFFFFFFFF);

  /// Vaste tokens die als **gewone tekst** op een dia staan: statuslabels in een
  /// checklist, een scope-matrix, een scorecard. Lat: 4,5:1 (WCAG 1.4.3).
  const alsTekstOpDia = <String, int>{
    'severityCritical': 0xFFB91C1C,
    'danger700': 0xFFB91C1C,
    'checklistAnomaly': 0xFFB91C1C,
    'scopeUnreachable': 0xFFB91C1C,
    'severityLow': 0xFF15803D,
    'checklistTested': 0xFF15803D,
    'scopeTested': 0xFF15803D,
    'success700': 0xFF15803D,
    'success800': 0xFF166534,
    'severityNone': 0xFF475569,
    'checklistNotTested': 0xFF64748B,
    'scopeNotTested': 0xFF64748B,
    'checklistNotTestable': 0xFFB45309,
    'scopeDeviation': 0xFFB45309,
  };

  /// De twee ernstbanden die **nooit** gewone tekst zijn. Ze verschijnen als een
  /// tint van 6% achter de kopkaart, als randstreep ernaast, en als vulling van
  /// een badge met wit vet label van ~30px op een dia van 1280 — dat laatste is
  /// grote tekst.
  ///
  /// Voor alle drie geldt 3:1, niet 4,5:1: WCAG 1.4.11 voor grafische objecten
  /// en 1.4.3 voor grote tekst. Ze stonden tot #606 in de basislijn als schuld,
  /// gemeten tegen de lat voor bodytekst die op hen niet van toepassing is.
  /// Dat was geen defect maar een verkeerd paar — en een basislijn die schuld
  /// opschrijft die er niet is, maakt de rest van de lijst ongeloofwaardig.
  const alsAccentOpDia = <String, int>{
    'severityHigh': 0xFFEA580C,
    'severityMedium': 0xFFD97706,
  };

  /// De mode-afhankelijke tegenhangers, gemeten in de modus die ze schilderen.
  ///
  /// Deze horen de lat wél te halen — daar zijn ze voor. Ze staan apart omdat
  /// [measured] const-kleuren bevat en deze getters zijn: hun waarde hangt van
  /// [AppTheme.isDark] af en is dus pas in de test te lezen.
  const modeAware = <String>[
    'accentFg',
    'brandFg',
    'tealFg',
    'successFg',
    'dangerFg',
    'warningFg',
  ];

  Color modeAwareColor(String naam) => switch (naam) {
    'accentFg' => AppTheme.accentFg,
    'brandFg' => AppTheme.brandFg,
    'tealFg' => AppTheme.tealFg,
    'successFg' => AppTheme.successFg,
    'dangerFg' => AppTheme.dangerFg,
    'warningFg' => AppTheme.warningFg,
    _ => throw ArgumentError(naam),
  };

  tearDown(() => AppTheme.isDark = false);

  test('de vaste dia-tokens zijn leesbaar als tekst op het diacanvas', () {
    // Hun eigen achtergrond, in beide modi dezelfde: een dia is een wit vlak.
    final tekort = <String, double>{};
    alsTekstOpDia.forEach((naam, waarde) {
      final ratio = contrastRatio(Color(waarde), slideCanvas);
      if (ratio < kWcagAaNormalText) tekort[naam] = ratio;
    });
    expect(
      tekort,
      isEmpty,
      reason:
          'deze kleuren staan als tekst op een dia en horen daar 4,5:1 te '
          'halen — mode-afhankelijk maken kan niet (export-isolate): $tekort',
    );
  });

  test('de accent-only dia-tokens halen de lat voor grafische objecten', () {
    // 3:1, want vulling, randstreep en groot vet badge-label — geen bodytekst.
    final tekort = <String, double>{};
    alsAccentOpDia.forEach((naam, waarde) {
      final ratio = contrastRatio(Color(waarde), slideCanvas);
      if (ratio < kWcagAaLargeText) tekort[naam] = ratio;
    });
    expect(
      tekort,
      isEmpty,
      reason:
          'wordt dit token alsnog bodytekst, verhuis het dan naar '
          'alsTekstOpDia — dan is 3:1 niet meer genoeg: $tekort',
    );
  });

  group('de mode-afhankelijke tekstkleuren halen de lat wél', () {
    // Daar zijn ze voor. Zonder deze toets kan iemand een Fg-token invoeren dat
    // net zo onleesbaar is als de merkkleur die het verving — dan is de
    // verhuizing kosmetiek geweest.
    for (final (naam, dark) in [('donker', true), ('licht', false)]) {
      test(naam, () {
        AppTheme.isDark = dark;
        final paper = AppTheme.paper;
        final tekort = <String, double>{};
        for (final token in modeAware) {
          final ratio = contrastRatio(modeAwareColor(token), paper);
          if (ratio < kWcagAaNormalText) tekort[token] = ratio;
        }
        expect(
          tekort,
          isEmpty,
          reason:
              'Deze tokens bestaan juist om leesbaar te zijn in de modus die ze '
              'schilderen: $tekort',
        );
      });
    }
  });

  // ── De bronwacht ──────────────────────────────────────────────────────────
  //
  // De rekensom hierboven bewaakt de kleuren; deze bewaakt waar ze landen. Dat
  // is wat #606 werkelijk vroeg: elk van de ~200 gebruiken lezen als dia-inhoud
  // (vast laten) of als chrome (mode-afhankelijk maken). Zonder deze wacht komt
  // de volgende `AppTheme.navy` in een dialoog er ongemerkt weer in, en dan is
  // de audit eenmalig geweest in plaats van vastgezet.
  //
  // Alleen `color:`-toekenningen tellen — dat is tekst of een icoon. Een
  // vulling (`backgroundColor:`), een tint (`withValues(alpha:`), een
  // gradiëntstop of een `Container(color:)` valt er bewust buiten: daar geldt
  // de bodytekst-lat niet, en de merkkleur is daar juist gewenst.
  test('geen vaste merk- of ernstkleur als tekstkleur in de chrome', () {
    const vast = [
      'accent', 'navy', 'teal', 'danger700', 'success700', 'success800',
      'severityCritical', 'severityLow', 'scopeTested', //
    ];
    // Waar een dia gerenderd wordt. Daar hóórt de vaste kleur, want een export
    // draait in een isolate zonder AppTheme.isDark (PENTEST_MIAUW §11).
    bool rendertEenDia(String pad) =>
        pad.contains('/slides/') ||
        pad.contains('/marp_html_service') ||
        pad.endsWith('finding_severity_palette.dart') ||
        pad.endsWith('signature_draw_dialog.dart');

    final overtreders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (rendertEenDia(entity.path)) continue;
      final regels = entity.readAsLinesSync();
      for (var i = 0; i < regels.length; i++) {
        final regel = regels[i];
        if (regel.contains('withValues(') ||
            regel.contains('backgroundColor')) {
          continue;
        }
        // `color:` betekent tekst óf een vlak, en dat verschil staat een regel
        // hoger: `Container(` en `BoxDecoration(` maken er een vulling van, en
        // daar is de merkkleur juist goed — het label erop draagt het contrast.
        final context = regels.sublist(i >= 2 ? i - 2 : 0, i).join(' ');
        if (context.contains('BoxDecoration(') ||
            context.contains('Container(') ||
            context.contains('decoration:')) {
          continue;
        }
        for (final token in vast) {
          if (RegExp('color:\\s*AppTheme\\.$token\\b').hasMatch(regel)) {
            overtreders.add('${entity.path}:${i + 1}  $token');
          }
        }
      }
    }
    expect(
      overtreders,
      isEmpty,
      reason:
          'gebruik in de interface de mode-afhankelijke variant (accentFg, '
          'brandFg, tealFg, dangerFg, successFg); de vaste kleur is voor wat '
          'een dia wordt:\n${overtreders.join('\n')}',
    );
  });

  // ── De dia volgt het thema niet ────────────────────────────────────────────
  //
  // De diepste vorm van wat #606 aanwees, en de enige die de gebruiker in zijn
  // éigen werk ziet: de previews schilderden hun grijstinten met de
  // mode-afhankelijke slate-schaal, op een canvas dat wit blijft. In donkere
  // modus werd `slate700` daarmee 1,3:1 — de tekst van een checklist, een
  // scope-matrix en een bevindingenoverzicht verdween zo goed als helemaal.
  //
  // Erger dan onleesbaar: het week af van de export. De HTML-export draait
  // zonder thema en schrijft altijd de lichte waarden, terwijl het
  // exportdialoog belooft dat de export exact de weergave uit de editor
  // gebruikt. In donkere modus was die belofte onwaar.
  test('de dia-inkt is leesbaar op wit en beweegt niet met het thema', () {
    const inkt = <String, Color>{
      'slideInk': AppTheme.slideInk,
      'slideInkMuted': AppTheme.slideInkMuted,
      'slideInkSoft': AppTheme.slideInkSoft,
    };
    final tekort = <String, double>{};
    inkt.forEach((naam, kleur) {
      final ratio = contrastRatio(kleur, slideCanvas);
      if (ratio < kWcagAaNormalText) tekort[naam] = ratio;
    });
    expect(tekort, isEmpty, reason: 'dia-tekst op een wit canvas: $tekort');

    // En dit is de eigenlijke invariant: dezelfde waarde in beide modi.
    AppTheme.isDark = true;
    final donker = [AppTheme.slideInk, AppTheme.slideInkSoft];
    AppTheme.isDark = false;
    final licht = [AppTheme.slideInk, AppTheme.slideInkSoft];
    expect(
      donker,
      licht,
      reason:
          'een dia is in beide thema\'s hetzelfde witte vlak; inkt die met de '
          'app meebeweegt laat de preview van de export afwijken',
    );
  });

  test('geen mode-afhankelijk grijs meer in de dia-previews', () {
    // De bronwacht voor dezelfde regel. `lib/widgets/slides/previews/` rendert
    // wat een dia wordt; de slate-schaal daar is per definitie fout, ook als
    // hij vandaag toevallig leesbaar uitvalt.
    final overtreders = <String>[];
    for (final entity in Directory(
      'lib/widgets/slides/previews',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final regels = entity.readAsLinesSync();
      for (var i = 0; i < regels.length; i++) {
        if (RegExp(r'AppTheme\.(slate|gray)\d').hasMatch(regels[i])) {
          overtreders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(
      overtreders,
      isEmpty,
      reason:
          'gebruik op een dia de vaste inkt (slideInk, slideInkMuted, '
          'slideInkSoft, slideInkFaint, slideRule, slideRuleSoft):\n'
          '${overtreders.join('\n')}',
    );
  });
}
