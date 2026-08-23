import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
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
  test('documentprofiel kleurt papier, tekst, accent en koppen', () {
    const scheme = ColorScheme.dark();
    final theme = MarkdownEditorTheme.documentSurface(
      scheme: scheme,
      profile: ThemeProfile.vigilis,
      fontFamily: ThemeProfile.vigilis.fontFamily,
    );
    final styles = defaultStylesFor(theme);

    expect(theme.surface, const Color(0xFFFFFFFF));
    expect(theme.text, const Color(0xFF111318));
    expect(theme.link, const Color(0xFFFFB800));
    expect(theme.codeBackground, const Color(0xFF111318));
    expect(styles.h1!.style.color, const Color(0xFF111318));
    expect(styles.h2!.style.color, const Color(0xFFFFB800));
  });

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
          ...GlobalMaterialLocalizations.delegates,
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

  // De visuele stand hoort er gelijk uit te zien als de weergave naast de bron.
  // Quill's standaard-citaat is een grijze streep met vervaagde tekst; Quill's
  // standaard-codeblok is een licht vlak met blauwe tekst. Beide lezen als een
  // ander ontwerp. Deze toets bewaakt dat de schrijfstand dezelfde gestileerde
  // containers draagt als de lezer.
  test(
    'documentprofiel: citaat en codeblok dragen dezelfde styling als de lezer',
    () {
      const scheme = ColorScheme.light();
      final theme = MarkdownEditorTheme.documentSurface(
        scheme: scheme,
        profile: ThemeProfile.vigilis,
        fontFamily: ThemeProfile.vigilis.fontFamily,
        documentTypography: true,
      );
      final styles = defaultStylesFor(theme);

      // Citaat: gekleurde balk links, getinte achtergrond, citaattekst.
      expect(styles.quote, isNotNull);
      final quoteDeco = styles.quote!.decoration as BoxDecoration;
      expect(
        quoteDeco.color,
        isNot(Colors.transparent),
        reason: 'citaat heeft een achtergrondkleur',
      );
      final border = quoteDeco.border as Border;
      final leftBorder = border.left;
      expect(leftBorder.width, 3, reason: 'citaatbalk is 3px breed');
      expect(
        leftBorder.color,
        theme.quoteBar,
        reason: 'citaatbalk volgt het accent',
      );

      // Codeblok: omrand vlak met monospace, afgeronde hoeken.
      expect(styles.code, isNotNull);
      expect(styles.code!.style.fontFamily, 'monospace');
      expect(styles.code!.style.fontSize, 13.5);
      final codeDeco = styles.code!.decoration as BoxDecoration;
      expect(
        codeDeco.color,
        isNot(Colors.transparent),
        reason: 'codeblok heeft een achtergrondkleur',
      );
      expect(codeDeco.border, isNotNull, reason: 'codeblok heeft een rand');
      expect(codeDeco.borderRadius, BorderRadius.circular(8));
    },
  );

  // Een profiel met een eigen kopkleur moet die op élk kopniveau dragen —
  // net als in de lezer en de export. Zonder deze fix gebruikte de visuele
  // stand altijd tekstkleur voor h1 en accent voor h2+, ook wanneer het
  // profiel één kleur voor alle koppen koos.
  test('profiel met documentHeadingColor kleurt h1 en h2 hetzelfde', () {
    const scheme = ColorScheme.light();
    final profile = ThemeProfile.vigilis.copyWith(
      documentHeadingColor: '#003399',
    );
    final theme = MarkdownEditorTheme.documentSurface(
      scheme: scheme,
      profile: profile,
      fontFamily: profile.fontFamily,
    );
    final styles = defaultStylesFor(theme);

    expect(styles.h1!.style.color, const Color(0xFF003399));
    expect(
      styles.h2!.style.color,
      const Color(0xFF003399),
      reason:
          'h2 volgt effectiveDocumentSubheadingColor, die met een '
          'gezamenlijke kopkleur gelijk is aan h1',
    );
  });

  // Zonder profiel valt h1 terug op de tekstkleur en h2+ op het accent —
  // dezelfde verdeling als de lezer.
  test('zonder profiel: h1 op tekstkleur, h2 op accent', () {
    const scheme = ColorScheme.light();
    final theme = MarkdownEditorTheme.documentSurface(scheme: scheme);
    final styles = defaultStylesFor(theme);

    expect(styles.h1!.style.color, scheme.onSurface);
    expect(styles.h2!.style.color, scheme.primary);
  });
}
