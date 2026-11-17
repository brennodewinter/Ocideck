import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/markdown_outline.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/epub/document_epub_export.dart';
import 'package:ocideck/services/epub/markdown_to_xhtml.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/pdf/document_pdf_links.dart';
import 'package:ocideck/services/table_of_contents.dart';
import 'package:ocideck/utils/heading_anchors.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

const _source = '''
<!-- toc -->

## A - B

Eerste.

## A   B

Tweede.

## **Café** en `code`

Derde.

## 中文

Vierde.

## A - B

Vijfde.

### a-b-1

Zesde.
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'documentindex maakt unieke Unicode-doelen en behoudt oude aliassen',
    () {
      final index = HeadingAnchorIndex(
        markdownHeadings(_source).map((h) => h.text),
      );
      expect(index.entries.map((e) => e.id), [
        'a-b',
        'a-b-1',
        'café-en-code',
        '中文',
        'a-b-2',
        'a-b-1-1',
      ]);
      expect(index.resolve('a---b'), 0);
      expect(index.resolve('caf-en-code'), 2);
      expect(index.resolve('café-en-code'), 2);
      expect(index.resolve('a-b-1'), 1);
      expect(index.resolve('onbekend'), -1);
    },
  );

  test('alle TOC-fragmenten landen op hun eigen blok, ook na URL-encoding', () {
    final toc = generateTocMarkdown(_source, maxDepth: 6);
    final fragments = RegExp(
      r'\]\(#([^)]*)\)',
    ).allMatches(toc).map((m) => m.group(1)!);
    final blocks = fragments
        .map(
          (f) => DocumentMarkdownView.headingBlockIndex(
            _source,
            Uri.decodeComponent(Uri.encodeComponent(f)),
          ),
        )
        .toList();
    expect(blocks.every((i) => i >= 0), isTrue);
    expect(blocks.toSet(), hasLength(6));
    expect(blocks, orderedEquals([...blocks]..sort()));
    expect(DocumentMarkdownView.headingBlockIndex(_source, 'a---b'), blocks[0]);
    expect(
      DocumentMarkdownView.headingBlockIndex(_source, 'a---b', occurrence: 1),
      blocks[1],
    );
  });

  test(
    'broneditor volgt dezelfde kopvolgorde, ook bij setext en tilde-fences',
    () {
      const source = '~~~dart\n## verborgen\n~~~\n\nCafé\n====\n\n## Café\n';
      final outline = buildMarkdownOutline(source);
      expect(outline.map((e) => e.title), ['Café', 'Café']);
      final anchors = HeadingAnchorIndex(outline.map((e) => e.title));
      expect(anchors.entries.map((e) => e.id), ['café', 'café-1']);
      expect(source.substring(outline[0].offset), startsWith('Café\n===='));
    },
  );

  test('dieptefilter verandert de documentbrede suffixen niet', () {
    const source = '### Dubbel\n\n## Dubbel\n';
    expect(generateTocMarkdown(source, maxDepth: 2), contains('(#dubbel-1)'));
    expect(
      DocumentMarkdownView.headingBlockIndex(source, 'dubbel-1'),
      greaterThan(0),
    );
  });

  test('setext en inline-opmaak gebruiken dezelfde doelen als ATX', () {
    const source = 'Café met **code**\n================\n\n## Café met code\n';
    expect(generateTocMarkdown(source), contains('(#café-met-code-1)'));
    expect(DocumentMarkdownView.headingBlockIndex(source, 'café-met-code'), 0);
    expect(
      DocumentMarkdownView.headingBlockIndex(source, 'café-met-code-1'),
      1,
    );
  });

  test('lege titels en suffixvormige titels blijven uniek', () {
    final index = HeadingAnchorIndex(['!!!', '???', 'section-1', '!!!']);
    expect(index.entries.map((e) => e.id), [
      'section',
      'section-1',
      'section-1-1',
      'section-2',
    ]);
  });

  test('canonieke titel wint van een dubbelzinnige historische alias', () {
    final index = HeadingAnchorIndex(['Café', 'Caf']);
    expect(index.resolve('café'), 0);
    expect(index.resolve('caf'), 1);
  });

  test('PDF-doelen gebruiken dezelfde index en compatibiliteitsaliassen', () {
    final titles = markdownHeadings(_source).map((h) => h.text);
    final links = pdfHeadingLinks(titles);
    expect(
      pdfFragmentDestination('#caf%C3%A9-en-code', links),
      'ocideck-kop-2',
    );
    expect(pdfFragmentDestination('#caf-en-code', links), 'ocideck-kop-2');
    expect(pdfFragmentDestination('#a-b-2', links), 'ocideck-kop-4');
    expect(pdfFragmentDestination('#%zz', links), isNull);
  });

  test('XHTML bevat voor elke TOC-link een uniek doel en oude ASCII-alias', () {
    final output = markdownToXhtml(
      replaceTocMarker(_source, generateTocMarkdown(_source)),
    );
    final doc = html.parse(output);
    final ids = doc.querySelectorAll('[id]').map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final link in doc.querySelectorAll('a[href^="#"]')) {
      expect(
        ids,
        contains(Uri.decodeComponent(link.attributes['href']!.substring(1))),
        reason: output,
      );
    }
    expect(doc.getElementById('caf-en-code'), isNotNull);
    expect(doc.getElementById('café-en-code')!.localName, 'h2');
    expect(() => markdownToXhtml('> ## Genest\n\n## Boven\n'), returnsNormally);
  });

  test(
    'EPUB-navigatie en Markdown-links delen doelen; heading-N blijft werken',
    () async {
      final bundle = await buildDocumentExportBundle(
        _source,
        projectPath: null,
        profile: PrivacyExportProfile.full,
        ownIdentity: OwnIdentity.empty,
        regions: defaultPrivacyRegions,
        disabledRules: const {},
        markdownService: MarkdownService(),
      );
      final bytes = await buildDocumentExportEpub(bundle);
      final zip = ZipDecoder().decodeBytes(bytes);
      String read(String path) =>
          utf8.decode(zip.findFile(path)!.content as List<int>);
      final content = html.parse(read('OEBPS/document.xhtml'));
      final nav = html.parse(read('OEBPS/nav.xhtml'));
      final ids = content.querySelectorAll('[id]').map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final link in nav.querySelectorAll('a')) {
        expect(ids, contains(link.attributes['href']!.split('#').last));
      }
      expect(
        ids,
        containsAll([
          'a-b',
          'a-b-1',
          'café-en-code',
          '中文',
          'a-b-2',
          'a-b-1-1',
          'heading-0',
        ]),
      );
    },
  );

  test(
    'HTML-export draagt dezelfde vooraf berekende index en veilige DOM-toekenning',
    () async {
      final output = await MarpHtmlService(
        loadAsset: (p) => File(p).readAsString(),
      ).build(_source, continuous: true);
      final data = RegExp(
        r'var OCIDECK_HEADING_ANCHORS=(.*);',
      ).firstMatch(output)!.group(1)!;
      final entries = jsonDecode(data) as List<dynamic>;
      expect(
        entries.map((dynamic e) => (e as Map<String, dynamic>)['id']),
        containsAll(['a-b', 'a-b-1', 'café-en-code', '中文', 'a-b-2']),
      );
      expect(output, contains('heading.before(anchor)'));
    },
  );
}
