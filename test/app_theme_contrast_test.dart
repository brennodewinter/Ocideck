import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/theme/appearance_contrast.dart';
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

  // ── De derde ontsnappingsroute: Material's eigen kleuren ──────────────────
  //
  // Er zijn drie manieren om een kleur op te schrijven die niemand meet, en er
  // stond pas een poort op twee ervan:
  //
  //   1. `Color(0xFF…)`      — `check_conventions`, basislijn nul.
  //   2. `Colors.white38`    — `standalone_palette_contrast_test` (#780).
  //   3. `Colors.red.shade700` — deze. Stond nergens op.
  //
  // De derde was in #821 goed voor vijftien plekken, en het patroon was
  // eenduidig: bijna elke vindplaats was de *foutkant* van een ernst-switch
  // waarvan de waarschuwingskant al lang een mode-afhankelijk token had. De
  // tokenmigratie van #606 heeft die ene tak stelselmatig overgeslagen —
  // `result.isValid ? AppTheme.warningFg : Colors.red.shade700` stond zo in vier
  // bestanden. Gemeten haalde `red.shade700` op een donkere dialoog 2,94:1 en
  // `green.shade700` 3,55:1; in lichte modus zakte `Colors.green` als icoon naar
  // 2,78:1. Alle drie onder hun lat, jarenlang, in code die er verzorgd uitzag.
  //
  // Alleen tekst en iconen. Een vulling (`backgroundColor:`) mag: daar draagt
  // het label het contrast, en dát meet je aan het label. De drie vullingen die
  // na #821 nog een Material-kleur gebruiken halen hun lat ruim (4,98 tot
  // 9,42:1); zodra er een onder zakt, is dat een meting en geen naamregel.
  test('geen kale Material-kleur als tekst- of icoonkleur in lib/', () {
    // `white`/`black` en hun alpha-varianten hebben hun eigen poort; hier gaat
    // het om de benoemde kleuren (`red`, `green`, `grey`, `orangeAccent`, …).
    final materialKleur = RegExp(
      r'Colors\.(?!white|black|transparent)(\w+)(\.shade\d+|\[\d+\])?',
    );
    final overtreders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final regels = entity.readAsLinesSync();
      for (var i = 0; i < regels.length; i++) {
        final match = materialKleur.firstMatch(regels[i]);
        if (match == null) continue;
        // Een vulling draagt geen letters; het label erop wel, en dat staat in
        // de tabellen hierboven.
        if (regels[i].contains('backgroundColor:')) continue;
        final venster = regels.sublist(i >= 4 ? i - 4 : 0, i + 1).join(' ');
        final isTekstOfIcoon =
            venster.contains('TextStyle(') ||
            venster.contains('Icon(') ||
            venster.contains('IconThemeData(') ||
            venster.contains('foregroundColor:');
        // `BoxDecoration`/`Container` is een vlak, ook als er `color:` staat.
        final isVlak =
            venster.contains('BoxDecoration(') ||
            venster.contains('Container(');
        if (!isTekstOfIcoon || isVlak) continue;
        final pad = entity.path.replaceAll(r'\', '/');
        overtreders.add('$pad:${i + 1}  ${match[0]}');
      }
    }

    expect(
      overtreders,
      isEmpty,
      reason:
          'Een kale Material-kleur beweegt niet mee met de modus en staat in '
          'geen enkele tabel, dus niemand rekent hem na. Neem een token: '
          'AppTheme.dangerFg/successFg/warningFg voor chrome, of een vast '
          'token (danger700, …) voor wat een dia wordt:\n'
          '${overtreders.join('\n')}',
    );
  });

  // ── Dia-inkt op een eigen tint, niet op het witte canvas ──────────────────
  //
  // De tabellen bovenaan meten tegen wit, want dat is waar dia-inkt meestal
  // staat. De mediaplaatshouders zijn de uitzondering: die vullen hun eigen vlak
  // met `slideRuleSoft` en zetten er tekst op. Daar werd tegen wit gemeten wat
  // op grijs gelezen wordt, en het gat is groot — `slideInkFaint` haalt 4,4:1
  // op wit en **2,08:1** op deze tint (#780).
  //
  // Wat er staat is bovendien een storingsmelding: "Bestand niet gevonden",
  // "Online media staat uit". Het enige wat vertelt waarom er een grijs vlak op
  // de dia zit, en het reist mee de export in.
  test('de tekst van een mediaplaatshouder is leesbaar op zijn eigen tint', () {
    const tint = AppTheme.slideRuleSoft;
    expect(
      contrastRatio(AppTheme.slideInkMuted, tint),
      greaterThanOrEqualTo(kWcagAaNormalText),
      reason: 'het label van de plaatshouder is bodytekst op deze tint',
    );
    expect(
      contrastRatio(AppTheme.slideInkSoft, tint),
      greaterThanOrEqualTo(kWcagAaLargeText),
      reason: 'het pictogram ernaast is een grafisch object (WCAG 1.4.11)',
    );
    // De bronwacht: `slideInkFaint` is op deze tint 2,08:1 en hoort er dus niet
    // te staan. Zonder deze regel bewaakt de test twee tokens die niemand meer
    // hoeft te gebruiken.
    final bron = File(
      'lib/widgets/slides/previews/media_previews_image.dart',
    ).readAsLinesSync();
    final overtreders = <String>[];
    for (var i = 0; i < bron.length; i++) {
      if (bron[i].contains('AppTheme.slideInkFaint')) {
        overtreders.add('regel ${i + 1}: ${bron[i].trim()}');
      }
    }
    expect(
      overtreders,
      isEmpty,
      reason:
          'slideInkFaint haalt op slideRuleSoft 2,08:1; gebruik slideInkMuted '
          'voor tekst en slideInkSoft voor een pictogram:\n'
          '${overtreders.join('\n')}',
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

  // ── Wat ThemeData zélf uitdeelt ───────────────────────────────────────────
  //
  // De toetsen hierboven meten losse tokens. Deze meten de kleuren die een
  // widget krijgt zónder dat iemand er een token voor koos — en dat is het gat
  // waar #744 doorheen viel: Material geeft een TextButton standaard
  // `colorScheme.primary` als voorgrond, en `primary` was in het profiel Donker
  // de mérkkleur `#111827`. Op zijn eigen oppervlak `#1E293B` is dat 1,21:1.
  //
  // Niemand had een fout gemaakt; er was alleen nooit een `textButtonTheme`
  // geweest, terwijl de omlijnde knop ernaast de regel wél had. Precies zo'n
  // gat vindt geen tokenlijst, want er staat geen token in de code.
  //
  // De rékensom staat sinds #750 in `lib/theme/appearance_contrast.dart`, want
  // de profielbewerker toont hem nu aan de gebruiker. Eén som: liep de toets
  // naast wat het scherm meldt, dan bewaakt de eerste niet meer wat de tweede
  // belooft.
  group('elk ingebouwd profiel is in zijn geheel leesbaar', () {
    for (final profile in AppAppearanceProfile.builtIns) {
      test(profile.name, () {
        final tekort = {
          for (final f in appearanceContrastProblems(profile))
            f.pair.name: f.ratio,
        };
        expect(
          tekort,
          isEmpty,
          reason:
              'in het profiel "${profile.name}" haalt dit de eigen norm niet: '
              '$tekort',
        );
      });
    }
  });

  group('de rollen die Material anders zelf invult, zijn expliciet gezet', () {
    // De rekensom hierboven vindt een slechte kleur. Deze vindt een ontbrékende
    // kleur — en dát was #744: er stond geen `textButtonTheme`, dus viel Flutter
    // terug op `colorScheme.primary`. Een verhoudingstoets alleen zou de dag dat
    // iemand zo'n thema weer weghaalt niet per se rood worden; deze wel.
    for (final profile in AppAppearanceProfile.builtIns) {
      test(profile.name, () {
        final theme = AppTheme.fromProfile(profile);
        for (final (naam, style) in [
          ('TextButton', theme.textButtonTheme.style),
          ('OutlinedButton', theme.outlinedButtonTheme.style),
        ]) {
          expect(
            style?.foregroundColor?.resolve(<WidgetState>{}),
            isNotNull,
            reason:
                '$naam heeft geen expliciete voorgrond in het thema en valt '
                'dus terug op colorScheme.primary — dat is de fout uit #744',
          );
        }
        expect(
          theme.textSelectionTheme.cursorColor,
          isNotNull,
          reason:
              'geen expliciete cursorkleur: Flutter valt dan terug op '
              'colorScheme.primary',
        );
      });
    }
  });

  group('de bovenbalk houdt de merkkleur van het profiel', () {
    // De keerzijde van de reparatie in #744, en de reden dat die niet "geef het
    // profiel gewoon een lichte primaryColor" was: `appBarTheme` schildert de
    // bovenbalk met diezelfde waarde. Licht maken zou het contrastprobleem niet
    // oplossen maar verplaatsen — naar een lichte balk in donkere modus. Deze
    // toets houdt die uitweg dicht; de leesbaarheid van de titel erop zit in de
    // eerste groep (`appBarTitleOnBar`).
    for (final profile in AppAppearanceProfile.builtIns) {
      test(profile.name, () {
        final theme = AppTheme.fromProfile(profile);
        expect(
          theme.appBarTheme.backgroundColor,
          AppTheme.parseHexColor(profile.primaryColor),
          reason: 'de bovenbalk hoort de merkkleur van het profiel te zijn',
        );
      });
    }
  });

  test('geen colorScheme.primary als tekst- of icoonkleur', () {
    // De bronwacht erbij. Het thema repareren helpt niets als de volgende
    // widget `theme.colorScheme.primary` weer rechtstreeks als `color:` pakt —
    // en dat deden er zes, waaronder de link in de documentatielezer.
    // Een vulling of een rand mág de merkkleur zijn; hier gaat het om inkt.
    final overtreders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final regels = entity.readAsLinesSync();
      for (var i = 0; i < regels.length; i++) {
        if (RegExp(
          r'(color|link|marker|quoteBar)\s*[:=]\s*'
          r'theme\.colorScheme\.primary\b',
        ).hasMatch(regels[i])) {
          overtreders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(
      overtreders,
      isEmpty,
      reason:
          'gebruik AppPalette.accentInk — die volgt de modus, primary is in '
          'een donker profiel de donkere merkkleur:\n${overtreders.join('\n')}',
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
