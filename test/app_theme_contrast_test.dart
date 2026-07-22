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
  /// Tokens die de app als **tekst** op [AppTheme.paper] zet, met de gemeten
  /// verhouding in donkere modus.
  ///
  /// Niet elk kleurtoken staat hier: een vulkleur of een randkleur hoeft de
  /// tekstlat niet te halen. Wat hier staat is wat ergens als
  /// `TextStyle(color: …)` of als icoonkleur op het papieren oppervlak terecht
  /// komt.
  const measured = <String, int>{
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
    'accent': 0xFF2563EB,
    'severityHigh': 0xFFEA580C,
    'severityMedium': 0xFFD97706,
    'checklistNotTestable': 0xFFB45309,
    'scopeDeviation': 0xFFB45309,
    'navy': 0xFF1C2B47,
    'teal': 0xFF2E7D64,
  };

  /// De tokens die de AA-lat voor gewone tekst (4,5:1) niet halen, per modus.
  /// Schuld, geen vrijstelling: elke regel is een plek waar de app zichzelf niet
  /// houdt aan wat ze van jouw dia's eist.
  ///
  /// Dat de lichte modus óók twee regels heeft is niet wat #606 verwachtte —
  /// dat issue mat alleen tegen de donkere achtergrond en noemde licht impliciet
  /// in orde. Oranje op wit is dat niet: `severityHigh` (#EA580C) en
  /// `severityMedium` (#D97706) halen 3,6:1 en 3,3:1. Ze staan hier omdat een
  /// basislijn die alleen de helft opschrijft die je toevallig gemeten hebt,
  /// erger is dan geen basislijn.
  const baselineDark = <String>{
    'severityCritical',
    'danger700',
    'checklistAnomaly',
    'scopeUnreachable',
    'severityLow',
    'checklistTested',
    'scopeTested',
    'success700',
    'success800',
    'severityNone',
    'checklistNotTested',
    'scopeNotTested',
    'checklistNotTestable',
    'scopeDeviation',
    'accent',
    'navy',
    'teal',
  };
  const baselineLight = <String>{'severityHigh', 'severityMedium'};

  Set<String> failingAt({required bool dark}) {
    AppTheme.isDark = dark;
    final paper = AppTheme.paper;
    return {
      for (final entry in measured.entries)
        if (contrastRatio(Color(entry.value), paper) < kWcagAaNormalText)
          entry.key,
    };
  }

  tearDown(() => AppTheme.isDark = false);

  for (final (naam, dark, basislijn) in [
    ('donker', true, baselineDark),
    ('licht', false, baselineLight),
  ]) {
    test('$naam: geen contrastprobleem buiten de basislijn', () {
      expect(
        failingAt(dark: dark).difference(basislijn),
        isEmpty,
        reason:
            'nieuw contrastprobleem in de ${naam}e modus; repareer het token '
            'of verantwoord het bewust in de basislijn',
      );
    });

    test('$naam: een gerepareerd token verdwijnt ook uit de basislijn', () {
      // De andere richting, en die is even belangrijk: een basislijn die blijft
      // staan nadat het probleem weg is, is geen schuldadministratie meer maar
      // een lijst die niemand nog gelooft.
      expect(
        basislijn.difference(failingAt(dark: dark)),
        isEmpty,
        reason: 'dit token haalt de lat inmiddels — haal het uit de basislijn',
      );
    });
  }
}
