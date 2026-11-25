// Kop- en voettekst van het documentstijlprofiel in elke exportvorm (#3166).
//
// Het issue: een ingestelde `documentHeaderText`/`documentFooterText` kwam
// alleen in PDF, HTML en LaTeX terecht; ODT, DOCX, ePub en platte Markdown
// lieten de teksten stil vallen. Deze test legt per formaat vast waar de
// opgeloste tekst moet staan:
//
// - ODT   — een master page met `style:header`/`style:footer`, zodat de band
//           op elke pagina herhaalt.
// - DOCX  — `word/header1.xml`/`word/footer1.xml` met `w:headerReference`/
//           `w:footerReference` in de sectie-eigenschappen.
// - ePub  — eenmaal zichtbaar als `<header>`/`<footer>` in document.xhtml:
//           herflowbaar kent geen betrouwbare herhaalband.
// - .md   — `header:`/`footer:` als blokscalar in de front matter: vreemde
//           front matter die verbatim bewaard blijft en die een bestand met
//           `marp: true` meteen als dia-chrome leest.
//
// PDF, HTML en LaTeX waren al goed en blijven in de matrix als regressie.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/docx/document_docx_export.dart';
import 'package:ocideck/services/epub/document_epub_export.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/odt/document_odt_export.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/utils/document_front_matter.dart';
import 'package:path/path.dart' as p;

Future<String> _diskLoader(String asset) => File(asset).readAsString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ocideck_chrome_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  const theme = ThemeProfile(
    documentHeaderText: 'OCIDECKPROEFKOP {title}',
    documentFooterText: 'OCIDECKPROEFVOET',
    documentHeaderFontSize: 14,
    documentFooterFontSize: 10.5,
  );

  Future<ExportBundle> buildBundle(String body) => buildDocumentExportBundle(
    body,
    projectPath: null,
    profile: PrivacyExportProfile.full,
    ownIdentity: OwnIdentity.empty,
    regions: defaultPrivacyRegions,
    disabledRules: const {},
    markdownService: MarkdownService(),
    title: 'Proeftitel',
    theme: theme,
  );

  Future<String> exportText(
    ExportBundle bundle,
    DocumentExportFormat format,
  ) async {
    final path = p.join(temp.path, 'doc.${format.name}');
    await writeDocumentExport(
      bundle,
      format,
      html: MarpHtmlService(loadAsset: _diskLoader),
      enforcementPolicy: const ClassificationEnforcementPolicy(),
      privacyAcknowledged: true,
      outputPath: path,
    );
    return File(path).readAsString();
  }

  String zipText(Uint8List bytes, String name) {
    final file = ZipDecoder().decodeBytes(bytes).findFile(name);
    expect(file, isNotNull, reason: '$name ontbreekt in het pakket');
    return String.fromCharCodes(file!.content as List<int>);
  }

  test('kop en voet landen in alle zeven exportvormen', () async {
    final bundle = await buildBundle('Een alinea.\n');

    // Platte uitvoer: tekst of XML in het pakket.
    final md = await exportText(bundle, DocumentExportFormat.md);
    expect(md, contains('header: |-\n  OCIDECKPROEFKOP Proeftitel'));
    expect(md, contains('footer: |-\n  OCIDECKPROEFVOET'));

    final html = await exportText(bundle, DocumentExportFormat.html);
    expect(html, contains('OCIDECKPROEFKOP Proeftitel'));
    expect(html, contains('OCIDECKPROEFVOET'));
    expect(html, contains('.document-header-text{font-size:14.0pt}'));
    expect(html, contains('.document-footer-text{font-size:10.5pt}'));

    final tex = await exportText(bundle, DocumentExportFormat.latex);
    expect(tex, contains('OCIDECKPROEFKOP Proeftitel'));
    expect(tex, contains('OCIDECKPROEFVOET'));
    expect(tex, contains(r'\fontsize{14.0bp}'));
    expect(tex, contains(r'\fontsize{10.5bp}'));

    // ODT: native paginastijl met kop- en voetband.
    final odtContent = zipText(
      await buildDocumentExportOdt(bundle),
      'content.xml',
    );
    expect(odtContent, contains('<office:master-styles>'));
    expect(odtContent, contains('fo:font-size="14.0pt"'));
    expect(odtContent, contains('fo:font-size="10.5pt"'));
    expect(odtContent, contains('<style:header>'));
    expect(odtContent, contains('<style:footer>'));
    expect(odtContent, contains('OCIDECKPROEFKOP Proeftitel'));
    expect(odtContent, contains('OCIDECKPROEFVOET'));

    // DOCX: eigen header-/footerparts, verwijzing én relatie.
    final docx = await buildDocumentExportDocx(bundle);
    final documentXml = zipText(docx, 'word/document.xml');
    final docxStyles = zipText(docx, 'word/styles.xml');
    expect(docxStyles, contains('<w:sz w:val="28"/>'));
    expect(docxStyles, contains('<w:sz w:val="21"/>'));
    expect(documentXml, contains('<w:headerReference'));
    expect(documentXml, contains('<w:footerReference'));
    expect(zipText(docx, 'word/header1.xml'), contains('OCIDECKPROEFKOP'));
    expect(zipText(docx, 'word/footer1.xml'), contains('OCIDECKPROEFVOET'));
    expect(
      zipText(docx, 'word/_rels/document.xml.rels'),
      allOf(contains('header1.xml'), contains('footer1.xml')),
    );
    expect(
      zipText(docx, '[Content_Types].xml'),
      allOf(contains('header1.xml'), contains('footer1.xml')),
    );

    // ePub: eenmaal zichtbaar — herflowbaar kent geen herhaalband.
    final epub = await buildDocumentExportEpub(bundle);
    final epubDoc = zipText(epub, 'OEBPS/document.xhtml');
    final epubCss = zipText(epub, 'OEBPS/style.css');
    expect(epubCss, contains('header.doc-chrome { font-size: 14.0pt; }'));
    expect(epubCss, contains('footer.doc-chrome { font-size: 10.5pt; }'));
    expect(epubDoc, contains('<header class="doc-chrome">'));
    expect(epubDoc, contains('OCIDECKPROEFKOP Proeftitel'));
    expect(epubDoc, contains('<footer class="doc-chrome">'));
    expect(epubDoc, contains('OCIDECKPROEFVOET'));

    // PDF is de referentie-implementatie; diens tekstlaag is elders afgedekt.
  });

  test('een meerregelige kop levert meerdere regels per formaat', () async {
    final multiTheme = theme.copyWith(
      documentHeaderText: 'Eerste kopregel\nTweede kopregel',
    );
    final bundle = await buildDocumentExportBundle(
      'Een alinea.\n',
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      title: 'Proeftitel',
      theme: multiTheme,
    );

    final md = await exportText(bundle, DocumentExportFormat.md);
    expect(md, contains('header: |-\n  Eerste kopregel\n  Tweede kopregel'));

    final odtContent = zipText(
      await buildDocumentExportOdt(bundle),
      'content.xml',
    );
    expect(
      RegExp(
        '<text:p text:style-name="Header">[^<]*Eerste kopregel</text:p>\n'
        '<text:p text:style-name="Header">[^<]*Tweede kopregel</text:p>',
      ).hasMatch(odtContent),
      isTrue,
    );

    final headerXml = zipText(
      await buildDocumentExportDocx(bundle),
      'word/header1.xml',
    );
    expect(headerXml.split('<w:p>').length - 1, greaterThanOrEqualTo(2));
    expect(
      headerXml,
      allOf(contains('Eerste kopregel'), contains('Tweede kopregel')),
    );
  });

  test(
    'inline-markdown in de kop overleeft als opmaak in ODT/DOCX/ePub',
    () async {
      final styledTheme = theme.copyWith(
        documentHeaderText: '**Vette** en *schuine* kop',
        documentFooterText: '',
      );
      final bundle = await buildDocumentExportBundle(
        'Een alinea.\n',
        projectPath: null,
        profile: PrivacyExportProfile.full,
        ownIdentity: OwnIdentity.empty,
        regions: defaultPrivacyRegions,
        disabledRules: const {},
        markdownService: MarkdownService(),
        title: 'Proeftitel',
        theme: styledTheme,
      );

      final odtContent = zipText(
        await buildDocumentExportOdt(bundle),
        'content.xml',
      );
      expect(
        odtContent,
        contains('<text:span text:style-name="Strong">Vette</text:span>'),
      );
      expect(
        odtContent,
        contains('<text:span text:style-name="Emphasis">schuine</text:span>'),
      );

      final headerXml = zipText(
        await buildDocumentExportDocx(bundle),
        'word/header1.xml',
      );
      expect(headerXml, contains('<w:b/>'));
      expect(headerXml, contains('<w:i/>'));

      final epubDoc = zipText(
        await buildDocumentExportEpub(bundle),
        'OEBPS/document.xhtml',
      );
      expect(epubDoc, contains('<strong>Vette</strong>'));
      expect(epubDoc, contains('<em>schuine</em>'));
    },
  );

  test('lege kop en voet schrijven nergens een band', () async {
    final bundle = await buildDocumentExportBundle(
      'Een alinea.\n',
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      title: 'Proeftitel',
      theme: const ThemeProfile(),
    );

    final md = await exportText(bundle, DocumentExportFormat.md);
    expect(md, isNot(contains('header:')));
    expect(md, isNot(contains('footer:')));

    final odtContent = zipText(
      await buildDocumentExportOdt(bundle),
      'content.xml',
    );
    expect(odtContent, isNot(contains('<style:header>')));
    expect(odtContent, isNot(contains('<style:footer>')));

    final docxBytes = await buildDocumentExportDocx(bundle);
    final docxArchive = ZipDecoder().decodeBytes(docxBytes);
    expect(docxArchive.findFile('word/header1.xml'), isNull);
    expect(docxArchive.findFile('word/footer1.xml'), isNull);
    final documentXml = zipText(docxBytes, 'word/document.xml');
    expect(documentXml, isNot(contains('headerReference')));
    expect(documentXml, isNot(contains('footerReference')));

    final epubDoc = zipText(
      await buildDocumentExportEpub(bundle),
      'OEBPS/document.xhtml',
    );
    expect(epubDoc, isNot(contains('doc-chrome')));
  });

  test('de geëxporteerde kop is geen vrij documentveld bij herlezen', () async {
    final bundle = await buildBundle('Een alinea.\n');
    final md = await exportText(bundle, DocumentExportFormat.md);

    // `header: |-` is een blokscalar — vreemde front matter die verbatim
    // bewaard blijft en niet als bewerkbaar veld in het venster duikt.
    final fields = documentFields(md);
    expect(fields['header'], isNull);
    expect(fields['footer'], isNull);
    expect(md, contains('---\n'));
    expect(md, contains('header: |-'));
  });
}
