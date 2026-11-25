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
import 'package:ocideck/services/plain_document_table.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/utils/document_front_matter.dart';
import 'package:path/path.dart' as p;

import 'pdf/pdf_text_probe.dart';

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

  Future<ExportBundle> buildBundle(String body, {ThemeProfile style = theme}) =>
      buildDocumentExportBundle(
        body,
        projectPath: null,
        profile: PrivacyExportProfile.full,
        ownIdentity: OwnIdentity.empty,
        regions: defaultPrivacyRegions,
        disabledRules: const {},
        markdownService: MarkdownService(),
        title: 'Proeftitel',
        theme: style,
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

  test('vier kopregels blijven leesbaar in alle exportvormen', () async {
    const lines = [
      'Eerste kopregel',
      'Tweede kopregel',
      'Derde kopregel',
      'Café € ·',
    ];
    final bundle = await buildBundle(
      'Een alinea.\n',
      style: theme.copyWith(
        fontFamily: 'EB Garamond',
        documentHeaderText: lines.join('\r\n'),
      ),
    );

    final md = await exportText(bundle, DocumentExportFormat.md);
    expect(md, contains('header: |-\n  ${lines.join('\n  ')}'));
    final html = await exportText(bundle, DocumentExportFormat.html);
    expect(
      html,
      contains('Eerste kopregel<br>Tweede kopregel<br>Derde kopregel'),
    );
    final tex = await exportText(bundle, DocumentExportFormat.latex);
    expect(tex, contains(r'\strut Eerste kopregel \\ \strut Tweede kopregel'));
    expect(tex, contains('includehead,headheight='));
    expect(tex, contains(r'Café \texteuro{} \textperiodcentered{}'));

    final pdf = await buildDocumentExportBytes(
      bundle,
      DocumentExportFormat.pdf,
      html: MarpHtmlService(loadAsset: _diskLoader),
      onPdfUnsupportedCharacters: (runes) => fail('Ontbrekende tekens: $runes'),
    );
    expect(pdfBaseFonts(pdf), contains('EBGaramond-Regular'));
    expect(pdfBaseFonts(pdf), isNot(contains('Times-Roman')));
    for (final line in lines) {
      expect(pdfVisibleText(pdf), contains(line));
    }
    expect(pdfLineCountsPerPage(pdf).single, greaterThanOrEqualTo(6));

    final odtContent = zipText(
      await buildDocumentExportOdt(bundle),
      'content.xml',
    );
    final headerXml = zipText(
      await buildDocumentExportDocx(bundle),
      'word/header1.xml',
    );
    final epubDoc = zipText(
      await buildDocumentExportEpub(bundle),
      'OEBPS/document.xhtml',
    );
    for (final line in lines.take(3)) {
      expect(
        odtContent,
        contains('<text:p text:style-name="Header">$line</text:p>'),
      );
      expect(headerXml, contains(line));
      expect(epubDoc, contains('<p>$line</p>'));
    }
    expect(headerXml.split('<w:p>').length - 1, lines.length);
  });

  test('blanco tabel behoudt haar vormgeving via de exportbundel', () async {
    const table = '| Naam | Functie |\n| --- | --- |\n| Ada | Voorzitter |';
    final bundle = await buildBundle(
      'Hoogachtend,\n\n$plainDocumentTableMarker\n$table\n',
      style: theme.copyWith(tableHeaderBackgroundColor: '#FF00FF'),
    );

    final md = await exportText(bundle, DocumentExportFormat.md);
    expect(md, contains('$plainDocumentTableMarker\n$table'));
    final html = await exportText(bundle, DocumentExportFormat.html);
    expect(
      html,
      contains('$plainDocumentTableMarker\n$table'.replaceFirst('<!', r'<\!')),
    );
    final tex = await exportText(bundle, DocumentExportFormat.latex);
    expect(tex, contains('Ada & Voorzitter'));
    expect(tex, isNot(contains(r'\cellcolor')));
    expect(tex, isNot(contains(plainDocumentTableMarker)));

    final pdf = await buildDocumentExportBytes(
      bundle,
      DocumentExportFormat.pdf,
      html: MarpHtmlService(loadAsset: _diskLoader),
    );
    expect(pdfVisibleText(pdf), contains('Ada Voorzitter'));
    expect(pdfVisibleText(pdf), isNot(contains('ocideck:plain_table')));
    expect(pdfFillColors(pdf), isNot(contains([1.0, 0.0, 1.0])));

    final odt = zipText(await buildDocumentExportOdt(bundle), 'content.xml');
    final odtTable = odt.split(RegExp(r'<table:table[ >]')).last;
    expect(odtTable, contains('Ada'));
    expect(odtTable, isNot(contains('Table_Header_Cell')));
    final docx = zipText(
      await buildDocumentExportDocx(bundle),
      'word/document.xml',
    );
    expect(docx, contains('<w:top w:val="nil"/>'));
    expect(docx, contains('<w:keepNext/>'));
    expect(docx, contains('<w:cantSplit/>'));
    expect(docx, isNot(contains('<w:shd')));
    final epub = zipText(
      await buildDocumentExportEpub(bundle),
      'OEBPS/document.xhtml',
    );
    expect(epub, contains('<table class="ocideck-plain-table">'));
    for (final output in [odt, docx, epub]) {
      expect(output, isNot(contains('ocideck:plain_table')));
    }
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
