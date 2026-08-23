import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/utils/color_contrast.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';

/// De leesbaarheid van de notitie-editor (`MarkdownEditorTheme.editorPanel`),
/// in beide modi.
///
/// Deze factory bouwt de chrome van het notitieveld: de gebalkte werkbalk boven
/// het veld en de tekst erin. Zijn achtergrond stond vast op `Colors.white` —
/// een vierde manier om een kleur te kiezen die geen enkele contrastpoort ziet,
/// naast `Color(0xFF…)`, `Colors.white38` en `Colors.red.shade700`. Hier is het
/// geen kleur op de verkeerde achtergrond maar een achtergrond zelf: wit,
/// terwijl de tekst mode-afhankelijk binnenkomt en in donkere modus licht is.
/// Het veld werd daarmee een wit vlak met bijna onzichtbare tekst (#821).
///
/// De toets meet het paar dat de factory oplevert. De invoer is de tekstkleur
/// van het notitieblok — die is mode-afhankelijk, dus in beide modi gemeten met
/// de kleur die het blok daar werkelijk gebruikt.
void main() {
  tearDown(() => AppTheme.isDark = false);

  /// De twee notitieblokken en hun tekstkleur (mode-afhankelijk).
  Color notesText() => AppTheme.notesText; // amber (sprekersnotities)
  Color userNotesText() => AppTheme.userNotesText; // blauw (gebruikersnotities)

  for (final (modus, dark) in [('donker', true), ('licht', false)]) {
    group('$modus thema', () {
      for (final (blok, kleur) in [
        ('sprekersnotities', notesText),
        ('gebruikersnotities', userNotesText),
      ]) {
        test('$blok — tekst en werkbalk op de veldachtergrond', () {
          AppTheme.isDark = dark;
          final theme = MarkdownEditorTheme.editorPanel(
            text: kleur(),
            link: AppTheme.accentFg,
            accent: AppTheme.accentFg,
            codeBackground: AppTheme.notesCodeBg,
            border: AppTheme.notesBorder,
          );

          final tekst = contrastRatio(theme.text, theme.surface);
          expect(
            tekst,
            greaterThanOrEqualTo(kWcagAaNormalText),
            reason:
                '$blok-tekst haalt ${tekst.toStringAsFixed(2)}:1 op de '
                'veldachtergrond',
          );

          // De werkbalkiconen zijn `text` op 75%: grafische onderdelen, 3:1.
          final icoon = contrastRatio(theme.toolbarIcon, theme.surface);
          expect(
            icoon,
            greaterThanOrEqualTo(kWcagAaLargeText),
            reason:
                'de werkbalkiconen halen ${icoon.toStringAsFixed(2)}:1 — onder '
                '3:1 is een uitgeschakeld icoon niet meer te onderscheiden',
          );
        });
      }
    });
  }

  // ── De bronwacht ──────────────────────────────────────────────────────────
  //
  // De rekensom hierboven bewaakt het paar. Deze bewaakt de vierde
  // ontsnappingsroute: een `Colors.white`-*oppervlak* waar mode-afhankelijke
  // tekst op landt. Een achtergrond die niet meebeweegt is net zo onzichtbaar
  // voor de tokentoets als een tekstkleur die dat niet doet, en hier viel het
  // extra hard op omdat de tekst in donkere modus juist licht is.
  //
  // De zusterfactory `presenterOverlay` doet het al goed: die kiest zijn
  // oppervlak met een luminantietoets. Dat deze het niet deed, was het gat.
  test('editorPanel schildert geen vast wit oppervlak', () {
    final bron = File(
      'lib/widgets/markdown_editor/markdown_editor_theme.dart',
    ).readAsStringSync();
    final factory = bron.substring(
      bron.indexOf('factory MarkdownEditorTheme.editorPanel'),
    );
    final eind = factory.indexOf(
      'factory MarkdownEditorTheme.presenterOverlay',
    );
    final body = eind >= 0 ? factory.substring(0, eind) : factory;
    expect(
      body.contains('surface: Colors.white'),
      isFalse,
      reason:
          'het oppervlak van het notitieveld hoort het thema te volgen '
          '(AppTheme.paper), niet vast wit te zijn — anders staat er in donkere '
          'modus lichte tekst op een wit vlak',
    );
  });
}
