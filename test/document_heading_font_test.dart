import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/docx/document_docx_export.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/odt/document_odt_export.dart';
import 'package:ocideck/services/pdf/document_pdf_fonts.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';

/// De kopletter en de gewenste letters van een documentstijl (#2119), op elk
/// oppervlak waar een documentkop gezet wordt.
///
/// Wat hier bewaakt wordt is dat de twee begrippen elk op hun eigen plek
/// aankomen: de *kopletter* op het scherm (lezer en schrijfvlak) en in de
/// HTML, en de *gewenste* letter — de naam die de huisstijl écht vraagt — in
/// wat een ander programma opent: de CSS-stapel vooraan, `w:rFonts` in Word,
/// `style:font-name` in LibreOffice, en in de PDF de klasse. Eén oppervlak
/// overslaan is een document dat op het ene blad anders staat dan op het
/// andere — precies de fout die de kopkleur eerder maakte.
const _md = '''
---
marp: true
theme: ocideck
---

# Kop

Een alinea.

### Subkop
''';

const _profile = ThemeProfile(
  name: 'Huisstijl',
  fontFamily: 'Calibri',
  preferredFontFamily: 'Aptos Light',
  documentHeadingFontFamily: 'Georgia',
  preferredDocumentHeadingFontFamily: 'Aptos',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lezer', () {
    List<String?> blockFonts(WidgetTester tester) => tester
        .widgetList<InlineMarkdownText>(find.byType(InlineMarkdownText))
        .take(3)
        .map((w) => w.style.fontFamily)
        .toList();

    Future<void> pump(WidgetTester tester, ThemeProfile profile) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentMarkdownView(
              '# Kop\n\nEen alinea.\n\n### Subkop\n',
              maxTextWidth: null,
              themeProfile: profile,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('koppen dragen de kopletter, de alinea de bodyletter', (
      tester,
    ) async {
      await pump(tester, _profile);
      final fonts = blockFonts(tester);
      expect(fonts[0], 'Georgia', reason: 'kop');
      expect(fonts[1], 'Calibri', reason: 'alinea');
      expect(fonts[2], 'Georgia', reason: 'subkop');
    });

    testWidgets('zonder kopletter volgen de koppen de bodyletter', (
      tester,
    ) async {
      await pump(tester, const ThemeProfile(fontFamily: 'Verdana'));
      expect(blockFonts(tester), ['Verdana', 'Verdana', 'Verdana']);
    });

    testWidgets('de gewenste letter komt níét op het scherm', (tester) async {
      await pump(
        tester,
        const ThemeProfile(fontFamily: 'Calibri', preferredFontFamily: 'Aptos'),
      );
      expect(blockFonts(tester), ['Calibri', 'Calibri', 'Calibri']);
    });
  });

  group('schrijfvlak', () {
    test('de Quill-kopstijl draagt de kopletter in de documentmodus', () {
      final theme = MarkdownEditorTheme.documentSurface(
        scheme: const ColorScheme.light(),
        fontFamily: _profile.fontFamily,
        profile: _profile,
        documentTypography: true,
      );
      final styles = defaultStylesFor(theme);
      expect(styles.h1!.style.fontFamily, 'Georgia');
      expect(styles.h3!.style.fontFamily, 'Georgia');
      expect(styles.paragraph!.style.fontFamily, 'Calibri');
    });

    test('in de notitiemodus blijft de kop bij de bodyletter', () {
      final theme = MarkdownEditorTheme.documentSurface(
        scheme: const ColorScheme.light(),
        fontFamily: _profile.fontFamily,
        profile: _profile,
      );
      expect(defaultStylesFor(theme).h1!.style.fontFamily, 'Calibri');
    });
  });

  group('html', () {
    Future<String> html(ThemeProfile theme) => MarpHtmlService(
      loadAsset: (asset) => File(asset).readAsString(),
    ).build(_md, continuous: true, theme: theme);

    test(
      'de gewenste letter staat vooraan in de stapel, de kop apart',
      () async {
        final out = await html(_profile);
        expect(
          out,
          contains("font-family:'Aptos Light', 'Calibri', sans-serif"),
        );
        // De generieke terugval volgt de gewenste letter (Aptos is
        // schreefloos), niet de plaatsvervanger Georgia.
        expect(
          out,
          contains(
            '.document h1,.document h2,.document h3,.document h4,.document h5,'
            ".document h6{font-family:'Aptos', 'Georgia', sans-serif}",
          ),
        );
      },
    );

    test('zonder kopletter en voorkeur verandert er niets', () async {
      final out = await html(const ThemeProfile(fontFamily: 'Arial'));
      expect(out, contains("font-family:'Arial', sans-serif"));
      expect(out, isNot(contains('.document h6{font-family')));
    });

    test('de klasse van de stapel volgt de gewenste letter', () async {
      // Cambria is een schreefletter; de plaatsvervanger Arial niet. De
      // generieke terugval hoort bij wat de huisstijl vraagt.
      final out = await html(
        const ThemeProfile(fontFamily: 'Arial', preferredFontFamily: 'Cambria'),
      );
      expect(out, contains("font-family:'Cambria', 'Arial', serif"));
    });
  });

  group('pdf', () {
    test('de klasse van de koppen volgt de gewenste kopletter', () {
      final fonts = DocumentPdfFonts.forFamily(
        _profile.exportFontFamily,
        headingFamily: _profile.exportDocumentHeadingFontFamily,
      );
      expect(fonts.base.fontName, 'Helvetica');
      // 'Aptos' is schreefloos, dus ook de kop — de gezette 'Georgia' is
      // alleen de plaatsvervanger op het scherm.
      expect(fonts.headingBold.fontName, 'Helvetica-Bold');

      final serifHeadings = DocumentPdfFonts.forFamily(
        'Arial',
        headingFamily: 'Cambria',
      );
      expect(serifHeadings.base.fontName, 'Helvetica');
      expect(serifHeadings.headingBold.fontName, 'Times-Bold');
      expect(serifHeadings.headingBase.fontName, 'Times-Roman');
    });

    test('zonder kopletter zijn de kopsneden die van de tekst', () {
      final fonts = DocumentPdfFonts.forFamily('EB Garamond');
      expect(fonts.headingBold.fontName, fonts.bold.fontName);
      expect(fonts.headingBase.fontName, fonts.base.fontName);
    });
  });

  group('office', () {
    Future<ExportBundle> bundle(ThemeProfile theme) =>
        buildDocumentExportBundle(
          '# Kop\n\nEen alinea.\n',
          projectPath: null,
          profile: PrivacyExportProfile.full,
          ownIdentity: OwnIdentity.empty,
          regions: defaultPrivacyRegions,
          disabledRules: const {},
          markdownService: MarkdownService(),
          title: 'Rapport',
          tlp: TlpLevel.none,
          theme: theme,
        );

    String part(List<int> zip, String name) =>
        utf8.decode(ZipDecoder().decodeBytes(zip).find(name)!.content);

    /// De inhoud van het Heading1-stijlelement, en niets erbuiten.
    String headingStyle(String styles) => RegExp(
      r'w:styleId="Heading1">(.*?)</w:style>',
    ).firstMatch(styles)!.group(1)!;

    test('Word krijgt de gewenste letters in docDefaults en de koppen', () async {
      final styles = part(
        await buildDocumentExportDocx(await bundle(_profile)),
        'word/styles.xml',
      );
      expect(
        styles,
        contains(
          '<w:rFonts w:ascii="Aptos Light" w:hAnsi="Aptos Light" w:cs="Aptos Light"/>',
        ),
      );
      expect(
        headingStyle(styles),
        contains('<w:rFonts w:ascii="Aptos" w:hAnsi="Aptos" w:cs="Aptos"/>'),
      );
      // Niet meer het vaste Calibri van vroeger.
      expect(styles, isNot(contains('w:ascii="Calibri"')));
    });

    test(
      'zonder voorkeur schrijft Word de schermletter, koppen erven',
      () async {
        final styles = part(
          await buildDocumentExportDocx(
            await bundle(const ThemeProfile(fontFamily: 'Georgia')),
          ),
          'word/styles.xml',
        );
        expect(styles, contains('w:ascii="Georgia"'));
        expect(headingStyle(styles), isNot(contains('<w:rFonts')));
      },
    );

    test('LibreOffice krijgt de letterdeclaraties en style:font-name', () async {
      final content = part(
        await buildDocumentExportOdt(await bundle(_profile)),
        'content.xml',
      );
      expect(
        content,
        contains(
          '<style:font-face style:name="Aptos Light" svg:font-family="&apos;Aptos Light&apos;"/>',
        ),
      );
      expect(
        content,
        contains(
          '<style:font-face style:name="Aptos" svg:font-family="&apos;Aptos&apos;"/>',
        ),
      );
      expect(
        RegExp(
          r'<style:default-style style:family="paragraph">.*?style:font-name="Aptos Light"',
          dotAll: true,
        ).hasMatch(content),
        isTrue,
      );
      expect(
        RegExp(
          r'style:name="Heading_20_1".*?style:font-name="Aptos"',
          dotAll: true,
        ).hasMatch(content),
        isTrue,
      );
    });
  });
}
