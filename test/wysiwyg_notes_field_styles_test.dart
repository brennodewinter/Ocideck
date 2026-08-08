import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';

/// De blok-stijlen van de WYSIWYG-schrijflaag (`defaultStylesFor`).
///
/// Quill legt onze `customStyles` over zijn eigen `DefaultStyles.getInstance`,
/// dus élk bloktype dat we tonen moet hier staan: een ontbrekend veld valt terug
/// op de omgevings-`DefaultTextStyle`, en die kleurt tekst op het documentvlak
/// als een link-kleur in het lichte thema. Zo werden opsommingsitems ooit blauw
/// terwijl koppen en alinea's op `onSurface` bleven — `lists` ontbrak simpelweg.
/// Deze toets bewaakt dat opsommingen (en genummerde lijsten) dezelfde
/// tekstkleur als een alinea houden, in licht én donker — zowel de itemtekst
/// (`lists`) als de marker/bullet-dot (`leading`), want Quill kleurt die twee uit
/// aparte velden. De marker bleef anders op de omgevingskleur (EU-blauw onder
/// Europa) hangen terwijl zijn eigen itemtekst al on-surface was.
void main() {
  for (final (label, scheme) in [
    ('licht', const ColorScheme.light()),
    ('donker', const ColorScheme.dark()),
  ]) {
    test('$label thema: lijsttekst én -marker krijgen de body-tekstkleur', () {
      final theme = MarkdownEditorTheme.documentSurface(scheme: scheme);
      final styles = defaultStylesFor(theme);

      // Itemtekst: `lists` bleef ongezet → Quill's omgevingsdefault (link-achtig
      // in licht). Nu volgt de lijst dezelfde kleur als een alinea.
      expect(styles.lists, isNotNull);
      expect(styles.lists!.style.color, theme.bodyStyle.color);
      expect(styles.lists!.style.color, scheme.onSurface);
      expect(styles.lists!.style.color, styles.paragraph!.style.color);

      // Marker/bullet-dot: die volgt `leading.style.color`, niet `lists`. Ook
      // die moet op de body-kleur staan, anders blijft de dot op de ambient blauw.
      expect(styles.leading, isNotNull);
      expect(styles.leading!.style.color, theme.bodyStyle.color);
      expect(styles.leading!.style.color, styles.lists!.style.color);
    });
  }

  // End-to-end: bewijs dat Quill de bullet-dot écht met onze `leading`-kleur
  // tekent, niet met de omgevingskleur. De schil dwingt een fel afwijkende
  // ambient tekstkleur (rood) af; vóór de fix erfde de dot díe kleur. De dot moet
  // nu de on-surface body-kleur zijn, niet het rood.
  testWidgets('de gerenderde bullet-dot volgt de body-kleur, niet de ambient', (
    tester,
  ) async {
    const scheme = ColorScheme.light();
    final editorTheme = MarkdownEditorTheme.documentSurface(scheme: scheme);
    final controller = QuillController(
      document: MarkdownQuillCodec.documentFromMarkdown(
        '- Punt een\n- Punt twee',
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFFFF0000), fontSize: 16),
            child: SizedBox(
              width: 600,
              height: 400,
              child: WysiwygNotesField(
                controller: controller,
                scrollController: ScrollController(),
                focusNode: FocusNode(),
                editorTheme: editorTheme,
                hintText: '',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final dots = tester.widgetList<Text>(find.text('•'));
    expect(dots, isNotEmpty, reason: 'de opsomming moet bullet-dots renderen');
    for (final dot in dots) {
      expect(
        dot.style?.color,
        scheme.onSurface,
        reason: 'de bullet-dot hoort on-surface te zijn, niet het ambient rood',
      );
    }
  });
}
