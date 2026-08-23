import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/utils/color_contrast.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';

/// De leesbaarheid van een `code`-stuk **midden in een alinea**.
///
/// De zesde ontsnappingsroute langs de contrastpoorten: geen kleur op een
/// verkeerde achtergrond en geen achtergrond die niet meebeweegt, maar een paar
/// dat niemand als paar zag. De achtergrond kwam uit `codeBackgroundColor` (het
/// paneel van een codeblok, in elk ingebouwd profiel bijna zwart) en de letter
/// hield de kleur van de alinea. In het profiel LibreKAT werd dat `#003399` op
/// `#111827`: 1,4:1, een zwart blokje waarin het woord niet meer te lezen was.
/// De poorten zagen het niet, want beide kleuren op zichzelf deugen — de tekst
/// leest prima op het papier, en het codeblok leest prima met zijn eigen
/// codekleur. Alleen samen deugden ze niet.
///
/// Deze toets meet dus het paar zoals het op het scherm belandt: de alineakleur
/// op de inline-code-achtergrond, over het papier van het profiel. En hij meet
/// het voor de twee weergaven die gelijk moeten lopen (#1567), zodat "ze zijn
/// gelijk" nooit meer "ze zijn allebei onleesbaar" kan betekenen.
void main() {
  /// Elk ingebouwd profiel plus het uiterste geval: donker papier.
  const profielen = <ThemeProfile>[
    ...ThemeProfile.builtIns,
    ThemeProfile(
      name: 'donker',
      slideBackgroundColor: '#0F172A',
      textColor: '#E2E8F0',
      accentColor: '#60A5FA',
    ),
  ];

  for (final profiel in profielen) {
    test('${profiel.name}: inline code blijft leesbaar', () {
      final papier = AppTheme.parseHexColor(profiel.slideBackgroundColor);
      final inkt = AppTheme.parseHexColor(profiel.textColor);
      // Zoals het scherm het samenstelt: het vlakje ligt op het papier, en de
      // letter ligt op het vlakje.
      final vlak = Color.alphaBlend(
        AppTheme.inlineCodeBackground(inkt),
        papier,
      );
      final ratio = contrastRatio(inkt, vlak);
      expect(
        ratio,
        greaterThanOrEqualTo(kWcagAaNormalText),
        reason:
            'een `code`-woord haalt ${ratio.toStringAsFixed(2)}:1 op zijn eigen '
            'vlakje in ${profiel.name}',
      );

      // En het vlakje is wél te zien: anders zou de toets hierboven ook slagen
      // door er helemaal geen achtergrond te tekenen.
      expect(
        contrastRatio(vlak, papier),
        greaterThan(1.03),
        reason: 'het vlakje moet zichtbaar zijn, niet alleen leesbaar',
      );
    });

    test('${profiel.name}: de bronmodus-melding is te lezen', () {
      // Dezelfde vergissing, vierde plek: de balk die vertelt dát je in de bron
      // staat lag op het codeblok-vlak met de alineakleur erop. In Vigilis waren
      // dat twee keer `#111318` — de melding stond er, en zei niets.
      final papier = AppTheme.parseHexColor(profiel.slideBackgroundColor);
      final inkt = AppTheme.parseHexColor(profiel.textColor);
      final thema = MarkdownEditorTheme.documentSurface(
        scheme: const ColorScheme.light(),
        profile: profiel,
      );
      final balk = Color.alphaBlend(thema.inlineCodeBackground, papier);
      final tekst = contrastRatio(thema.text, balk);
      expect(
        tekst,
        greaterThanOrEqualTo(kWcagAaNormalText),
        reason:
            'de meldingstekst haalt ${tekst.toStringAsFixed(2)}:1 in '
            '${profiel.name}',
      );
      // Het icoon draagt betekenis en is een grafisch onderdeel: 3:1.
      expect(
        contrastRatio(inkt, balk),
        greaterThanOrEqualTo(kWcagAaLargeText),
        reason: 'het icoon in de balk moet te onderscheiden zijn',
      );
    });

    test('${profiel.name}: schrijfvlak en documentweergave rekenen gelijk', () {
      // De belofte van #1567 is dat de twee weergaven van dezelfde tekst er
      // hetzelfde uitzien. Ze rekenen daarom met dezelfde som, en die staat op
      // één plek.
      final editorThema = MarkdownEditorTheme.documentSurface(
        scheme: const ColorScheme.light(),
        profile: profiel,
      );
      expect(
        editorThema.inlineCodeBackground,
        AppTheme.inlineCodeBackground(
          AppTheme.parseHexColor(profiel.textColor),
        ),
      );
      // En níet het codeblok-vlak — dat was de vergissing.
      expect(
        editorThema.inlineCodeBackground,
        isNot(AppTheme.parseHexColor(profiel.codeBackgroundColor)),
      );
    });
  }
}
