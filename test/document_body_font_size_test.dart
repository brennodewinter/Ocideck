import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/docx/document_docx_export.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/odt/document_odt_export.dart';
import 'package:ocideck/services/pdf/document_pdf_style.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';

/// De basislettergrootte van een documentstijl. Een blad heeft een vaste
/// lettermaat (een dia schaalt naar haar kader), en die was nergens te zetten.
///
/// Wat hier bewaakt wordt is niet dat het veld bestaat maar dat het overal
/// aankomt: in het model, in de gerenderde tekst, in de kopmaten, in de
/// drempel waarmee de paginaverdeling rekent, en in de HTML-export. Eén van die
/// vijf overslaan levert een document op dat op het scherm anders staat dan op
/// papier — en dat zie je niet aan de code.
const _md = '''
---
marp: true
theme: ocideck
---

# Kop

Een alinea.
''';

void main() {
  group('model', () {
    test('standaard is de maat waarin de lezer altijd al stond', () {
      const profile = ThemeProfile(name: 'Test');
      expect(profile.documentBodyFontSize, kDocumentDefaultBodyFontSize);
      expect(profile.documentFontScale, 1.0);
    });

    test('een gezette maat overleeft toJson → fromJson', () {
      const profile = ThemeProfile(name: 'Groot', documentBodyFontSize: 20.0);
      final round = ThemeProfile.fromJson(profile.toJson());
      expect(round.documentBodyFontSize, 20.0);
      expect(
        round.documentFontScale,
        closeTo(20.0 / kDocumentDefaultBodyFontSize, 0.0001),
      );
    });

    test('een maat buiten het bereik wordt bij het lezen ingeklemd', () {
      final tiny = ThemeProfile.fromJson({
        'name': 'Onleesbaar',
        'documentBodyFontSize': 2,
      });
      final huge = ThemeProfile.fromJson({
        'name': 'Reuze',
        'documentBodyFontSize': 400,
      });
      expect(tiny.documentBodyFontSize, kDocumentMinBodyFontSize);
      expect(huge.documentBodyFontSize, kDocumentMaxBodyFontSize);
    });

    test('een profiel zonder het veld leest als de standaardmaat', () {
      final legacy = ThemeProfile.fromJson({'name': 'Oud'});
      expect(legacy.documentBodyFontSize, kDocumentDefaultBodyFontSize);
    });

    // 11 is een puntmaat (de PDF zet hem zo), geen CSS-pixel. Zonder de
    // omzetting 96/72 is dezelfde 11 op het scherm een derde kleiner dan op
    // papier — precies #1947.
    test('de schermmaat is de puntmaat in CSS-pixels', () {
      expect(kCssPxPerPoint, closeTo(96 / 72, 0.0001));
      expect(
        documentBodyFontSizeToCssPx(kDocumentDefaultBodyFontSize),
        closeTo(kDocumentDefaultBodyFontSize * kCssPxPerPoint, 0.0001),
      );
      const profile = ThemeProfile(name: 'Standaard');
      expect(profile.documentBodyFontSizeCssPx, closeTo(14 + 2 / 3, 0.0001));
    });

    test('de PDF houdt de opgeslagen maat in punten', () {
      const profile = ThemeProfile(name: 'Standaard');
      expect(DocumentPdfStyle.fromTheme(profile).bodyFontSize, 11);
      const large = ThemeProfile(name: 'Groot', documentBodyFontSize: 18);
      expect(DocumentPdfStyle.fromTheme(large).bodyFontSize, 18);
    });
  });

  group('weergave', () {
    // De koppen verhouden zich tot de bodytekst. Hielden ze hun vaste maten,
    // dan haalt een grotere bodytekst zijn eigen kop in.
    test('kopmaten schalen mee met de bodytekst', () {
      final normal = documentHeadingSize(1);
      final large = documentHeadingSize(
        1,
        bodyFontSize: kDocumentDefaultBodyFontSize * 2,
      );
      expect(large, closeTo(normal * 2, 0.001));
      expect(
        documentHeadingSize(3, bodyFontSize: kDocumentDefaultBodyFontSize * 2),
        closeTo(documentHeadingSize(3) * 2, 0.001),
      );
    });

    // De drempel "hoeveel tekst moet er onder een kop passen" is twee regels
    // bodytekst. Met de standaardmaat gerekend ligt hij bij een grotere letter
    // een regel te laag, en valt het pagina-einde op de verkeerde plek.
    test('de kop-blijft-bij-tekst drempel schaalt mee', () {
      final normal = documentKeepWithNextHeight(TextScaler.noScaling);
      final large = documentKeepWithNextHeight(
        TextScaler.noScaling,
        bodyFontSize: kDocumentDefaultBodyFontSize * 2,
      );
      expect(large, closeTo(normal * 2, 0.001));
    });

    testWidgets('de gerenderde bodytekst staat in de gekozen maat', (
      tester,
    ) async {
      const profile = ThemeProfile(name: 'Groot', documentBodyFontSize: 22.0);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DocumentMarkdownView(
              'Een gewone alinea.',
              maxTextWidth: null,
              themeProfile: profile,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Op de widget en niet op de RenderParagraph: de inline-renderer zet de
      // maat op de losse spans, dus de wortelspan draagt hem niet.
      final body = tester.widget<InlineMarkdownText>(
        find.byType(InlineMarkdownText).first,
      );
      expect(body.style.fontSize, closeTo(22.0 * kCssPxPerPoint, 0.001));
    });
  });

  group('export', () {
    Future<String> documentHtml(ThemeProfile theme) => MarpHtmlService(
      loadAsset: (asset) => File(asset).readAsString(),
    ).build(_md, continuous: true, theme: theme);

    test('de documentexport draagt de gekozen maat in CSS-pixels', () async {
      const profile = ThemeProfile(name: 'Groot', documentBodyFontSize: 21.5);
      expect(
        await documentHtml(profile),
        contains(
          'font-size:${documentBodyFontSizeToCssPx(21.5).toStringAsFixed(1)}px',
        ),
      );
    });

    test('de standaardmaat komt ook in de CSS terecht, als CSS-pixels', () async {
      const profile = ThemeProfile(name: 'Standaard');
      expect(
        await documentHtml(profile),
        contains(
          'font-size:${documentBodyFontSizeToCssPx(kDocumentDefaultBodyFontSize).toStringAsFixed(1)}px',
        ),
      );
    });
  });

  // De twee office-exports lieten de maat tot #2649 liggen: Word kreeg altijd
  // 11 pt, LibreOffice een percentage van zijn eigen 12-pt-default.
  group('office-export (#2649)', () {
    Future<ExportBundle> bundle({double? bodySize}) =>
        buildDocumentExportBundle(
          '# Titel\n\nEen alinea met wat tekst.\n',
          projectPath: null,
          profile: PrivacyExportProfile.full,
          ownIdentity: OwnIdentity.empty,
          regions: defaultPrivacyRegions,
          disabledRules: const {},
          markdownService: MarkdownService(),
          title: 'Rapport',
          theme: bodySize == null
              ? null
              : ThemeProfile(documentBodyFontSize: bodySize),
        );

    String entry(Uint8List bytes, String name) {
      final archive = ZipDecoder().decodeBytes(bytes);
      final file = archive.find(name);
      expect(file, isNotNull, reason: '$name ontbreekt in de export');
      return String.fromCharCodes(file!.readBytes()!);
    }

    test('DOCX: docDefaults draagt de bodymaat in halve punten', () async {
      final styles16 = entry(
        await buildDocumentExportDocx(await bundle(bodySize: 16)),
        'word/styles.xml',
      );
      expect(styles16, contains('<w:sz w:val="32"/></w:rPr></w:rPrDefault>'));

      final stylesDefault = entry(
        await buildDocumentExportDocx(await bundle()),
        'word/styles.xml',
      );
      // De standaard 11 pt blijft 22 halve punten — byte-gelijk aan vóór.
      expect(
        stylesDefault,
        contains('<w:sz w:val="22"/></w:rPr></w:rPrDefault>'),
      );
    });

    test('DOCX: kopmaten schalen mee met de body', () async {
      final styles = entry(
        await buildDocumentExportDocx(await bundle(bodySize: 22)),
        'word/styles.xml',
      );
      // h1 was 16 pt bij een 11-pt-body; bij 22 pt body is dat 32 pt = 64
      // halve punten.
      expect(styles, contains('<w:sz w:val="64"/></w:rPr>'));
    });

    test('ODT: de default-stijl draagt de bodymaat in punten', () async {
      final content16 = entry(
        await buildDocumentExportOdt(await bundle(bodySize: 16)),
        'content.xml',
      );
      expect(content16, contains('fo:font-size="16pt"'));

      final contentDefault = entry(
        await buildDocumentExportOdt(await bundle()),
        'content.xml',
      );
      expect(contentDefault, contains('fo:font-size="11pt"'));
      // Koppen blijven percentages — relatief aan de body.
      expect(contentDefault, contains('fo:font-size="170%"'));
    });
  });
}
