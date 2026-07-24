import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/utils/color_contrast.dart';
import 'package:ocideck/widgets/panels/slide_quality_panel.dart';

/// Het contrast van het kwaliteitspaneel zelf, in beide modi.
///
/// Dit paneel is het oppervlak dat de gebruiker over contrast vertelt: het
/// rekent zijn dia's na en meldt wat onder de WCAG-lat zakt. Tot #780 was de
/// eigen tekst van dat paneel nergens gemeten — niet het paar `fg` op `bg`, en
/// vooral niet de verzwakte varianten daarvan.
///
/// Dáár zat het defect. De vier staten hadden hun tekst op 100, 85 en 70 procent
/// van dezelfde voorgrondkleur. Een tokentoets ziet zo'n verzwakking niet: het
/// token is goed, de dekking maakt hem stuk. In donkere modus zakte de foutstaat
/// naar 3,68:1; in **lichte** modus zakten alle vier de staten op 70% naar
/// 2,99-3,44:1 — het lichte thema was hier dus erger dan het donkere, en dat is
/// precies de omgekeerde rondgang waar #780 om vroeg.
void main() {
  /// De vier staten die [slideQualityColors] onderscheidt, elk opgeroepen met
  /// een resultaat dat die staat werkelijk oplevert. Niet de kleuren losweg
  /// opsommen: dan bewaakt de test een lijst en niet de functie die kiest.
  final staten = <String, SlideQualityResult>{
    'geen problemen': const SlideQualityResult([]),
    'fout': SlideQualityResult([_issue(MarkdownValidationSeverity.error)]),
    'waarschuwing': SlideQualityResult([
      _issue(MarkdownValidationSeverity.warning),
    ]),
    'informatief': SlideQualityResult([
      _issue(MarkdownValidationSeverity.informational),
    ]),
  };

  tearDown(() => AppTheme.isDark = false);

  for (final (modus, dark) in [('donker', true), ('licht', false)]) {
    group('$modus thema', () {
      staten.forEach((naam, result) {
        test('staat "$naam" — tekst op de eigen achtergrond', () {
          AppTheme.isDark = dark;
          final (:bg, :fg) = slideQualityColors(result);
          final ratio = contrastRatio(fg, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(kWcagAaNormalText),
            reason:
                'de staat "$naam" zet ${_hex(fg)} op ${_hex(bg)} en haalt '
                '${ratio.toStringAsFixed(2)}:1',
          );
        });
      });
    });
  }

  // ── De bronwacht ──────────────────────────────────────────────────────────
  //
  // De rekensom hierboven bewaakt het paar. Deze bewaakt dat er geen dekking
  // meer over de voorgrond komt: dan verschuift de gemeten kleur en meet de
  // test iets wat niet meer op het scherm staat.
  //
  // Rangorde binnen dit paneel hoort in het gewicht en de schuinte te zitten —
  // vet, normaal, cursief — niet in de dekking. Dat is even leesbaar en het
  // blijft op de verhouding staan die hierboven is nagerekend.
  test('de voorgrond van het paneel wordt niet verzwakt met een alpha', () {
    final bron = File(
      'lib/widgets/panels/slide_quality_panel.dart',
    ).readAsLinesSync();
    final overtreders = <String>[];
    for (var i = 0; i < bron.length; i++) {
      final regel = bron[i];
      if (regel.trimLeft().startsWith('//')) continue;
      if (!regel.contains('withValues(alpha:')) continue;
      // Een tint áchter de tekst (een vulling, een randstreep) mag wel: die
      // draagt geen letters. Het gaat om de voorgrond — `iconColor`, `fg`,
      // `color` — die de tekst en de iconen schildert.
      if (!RegExp(
        r'\b(iconColor|fg|color)\.withValues\(alpha:',
      ).hasMatch(regel)) {
        continue;
      }
      overtreders.add('regel ${i + 1}: ${regel.trim()}');
    }
    expect(
      overtreders,
      isEmpty,
      reason:
          'Een verzwakte voorgrond is een kleur die niemand heeft nagerekend, '
          'en de tokentoets ziet hem niet. Gebruik gewicht of schuinte voor de '
          'rangorde:\n${overtreders.join('\n')}',
    );
  });
}

SlideQualityIssue _issue(MarkdownValidationSeverity severity) =>
    SlideQualityIssue(
      slideIndex: 0,
      kind: SlideQualityIssueKind.missingAltCaption,
      category: SlideQualityCategory.altText,
      severity: severity,
    );

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';
