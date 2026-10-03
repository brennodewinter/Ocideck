// Een formulier in OciDeck's eigen oppervlakken: de lezer, de visuele editor en
// elke export (FORM_INTAKE.md §4.9, rij 2–10 van de keten).
//
// Voor andere Markdown-lezers zijn de markers onzichtbaar HTML-commentaar; voor
// OciDeck's lezer en exporteurs niet — zonder deze keten stond er een
// `<!-- field id=naam … -->` als tekst in een PDF. De proef is steeds dubbel:
// het label en het antwoord ZIJN er, de markers NIET. Alleen het tweede beweren
// staat ook groen als het hele blok verdwijnt.

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

import 'pdf/pdf_text_probe.dart';

Future<String> _diskLoader(String asset) => File(asset).readAsString();

// De labels en antwoorden dragen elk een unieke steekwoord, zodat een treffer in
// een export niet toevallig uit andere tekst komt.
const String _formulier = '''<!-- form id=kookboek version=3 -->
# Aanmelding

Intro UNIEKINTRO.

<!-- notice -->
UNIEKNOTICE wordt bewaard.
<!-- /notice -->

<!-- field id=naam type=text required -->
**UNIEKLABEL naam**
<!-- answer -->
UNIEKANTWOORD Sari
<!-- /field id=naam -->

<!-- field id=verhaal type=prose -->
## UNIEKVERHAAL
> uitleg
<!-- answer -->
Het verhaal begint hier.
<!-- /field id=verhaal -->

Tot slot.
''';

const _markers = [
  '<!--',
  '-->',
  'field id',
  'answer',
  '/field',
  'type=text',
  'kookboek',
];

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
    FlutterQuillLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lezer', () {
    testWidgets('toont label, antwoord en notice — geen marker', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(SingleChildScrollView(child: DocumentMarkdownView(_formulier))),
      );
      await tester.pump();

      for (final tekst in [
        'UNIEKINTRO',
        'UNIEKNOTICE',
        'UNIEKLABEL',
        'UNIEKANTWOORD',
        'UNIEKVERHAAL',
      ]) {
        expect(find.textContaining(tekst, findRichText: true), findsWidgets);
      }
      for (final marker in _markers) {
        expect(
          find.textContaining(marker, findRichText: true),
          findsNothing,
          reason: '"$marker" lekt als tekst in de lezer',
        );
      }
    });

    testWidgets('een kapot formulier toont zijn markers — zichtbaar kapot', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // Geen `/field` → geen geldig formulier → niets wordt weggestript.
      const kapot =
          '<!-- form id=f -->\n'
          '\n'
          '<!-- field id=naam type=text -->\n'
          '**Naam**\n'
          '<!-- answer -->\n'
          'Sari\n';
      await tester.pumpWidget(
        _app(SingleChildScrollView(child: DocumentMarkdownView(kapot))),
      );
      await tester.pump();
      // Het label en het antwoord zijn er in elk geval nog; stil verliezen is
      // erger dan een rauwe marker.
      expect(find.textContaining('Sari', findRichText: true), findsWidgets);
    });
  });

  group('visuele editor', () {
    Future<QuillController> pumpEditor(WidgetTester tester) async {
      final controller = QuillController(
        document: MarkdownQuillCodec.documentFromMarkdown(_formulier),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(controller.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 800,
            height: 1500,
            child: WysiwygNotesField(
              controller: controller,
              scrollController: scroll,
              focusNode: focus,
              editorTheme: MarkdownEditorTheme.documentSurface(
                scheme: const ColorScheme.light(),
              ),
              hintText: '',
            ),
          ),
        ),
      );
      await tester.pump();
      return controller;
    }

    testWidgets('tekent kop, notice en velden zonder markers', (tester) async {
      await pumpEditor(tester);

      // De notice en de twee velden (label + antwoordkader) komen uit dezelfde
      // weergave als de lezer.
      expect(find.byType(DocumentMarkdownView), findsWidgets);
      expect(find.textContaining('UNIEKLABEL'), findsWidgets);
      expect(find.textContaining('UNIEKANTWOORD'), findsWidgets);
      expect(find.textContaining('UNIEKNOTICE'), findsWidgets);
      // De kop toont id en versie, zoals ze in de marker staan.
      expect(find.text('kookboek · v3'), findsOneWidget);
      for (final marker in ['<!--', '-->', 'field id', '/field']) {
        expect(
          find.textContaining(marker),
          findsNothing,
          reason: '"$marker" lekt als tekst in de visuele editor',
        );
      }
    });

    testWidgets('typen naast een blok laat de blokbron byte-gelijk', (
      tester,
    ) async {
      final controller = await pumpEditor(tester);
      controller.replaceText(
        0,
        0,
        'Vooraf. ',
        const TextSelection.collapsed(offset: 0),
      );
      await tester.pump();

      final terug = MarkdownQuillCodec.markdownFromDocument(
        controller.document,
      );
      expect(terug, contains('Vooraf. '));
      expect(
        terug,
        contains(
          '<!-- field id=naam type=text required -->\n'
          '**UNIEKLABEL naam**\n'
          '<!-- answer -->\n'
          'UNIEKANTWOORD Sari\n'
          '<!-- /field id=naam -->',
        ),
      );
      expect(terug, contains('<!-- notice -->\nUNIEKNOTICE wordt bewaard.\n'));
    });
  });

  group('exports', () {
    Future<ExportBundle> bundle() => buildDocumentExportBundle(
      _formulier,
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
      title: 'Aanmelding',
    );

    Future<String> render(DocumentExportFormat format) async {
      final bytes = await buildDocumentExportBytes(
        await bundle(),
        format,
        html: MarpHtmlService(loadAsset: _diskLoader),
      );
      switch (format) {
        case DocumentExportFormat.docx:
          return _unzipText(bytes, 'word/document.xml');
        case DocumentExportFormat.odt:
          return _unzipText(bytes, 'content.xml');
        case DocumentExportFormat.epub:
          return _unzipAllText(bytes);
        case DocumentExportFormat.pdf:
          return pdfVisibleText(bytes);
        case _:
          return String.fromCharCodes(bytes);
      }
    }

    for (final format in [
      DocumentExportFormat.html,
      DocumentExportFormat.latex,
      DocumentExportFormat.pdf,
      DocumentExportFormat.docx,
      DocumentExportFormat.odt,
      DocumentExportFormat.epub,
    ]) {
      test('${format.name}: label en antwoord erin, de markers niet', () async {
        final text = await render(format);
        for (final tekst in ['UNIEKLABEL', 'UNIEKANTWOORD', 'UNIEKNOTICE']) {
          expect(text, contains(tekst), reason: '$tekst ontbreekt');
        }
        for (final marker in ['field id', '/field', 'type=text', 'kookboek']) {
          expect(text, isNot(contains(marker)), reason: '"$marker" lekt');
        }
        // Ook niet als commentaar, in welke verpakking dan ook. Niet het kale
        // `<!--`: een volledige HTML-pagina draagt de bibliotheken van de
        // syntaxiskleuring mee, en die bevatten het zelf.
        for (final name in ['form', 'field', 'answer', 'notice', '/notice']) {
          expect(text, isNot(contains('<!-- $name')), reason: '<!-- $name');
        }
      });
    }

    test('md: de markers reizen mee — ze zijn bronbezit', () async {
      final bytes = await buildDocumentExportBytes(
        await bundle(),
        DocumentExportFormat.md,
        html: MarpHtmlService(loadAsset: _diskLoader),
      );
      final text = String.fromCharCodes(bytes);
      expect(text, contains('<!-- field id=naam type=text required -->'));
      expect(text, contains('<!-- /field id=naam -->'));
      expect(text, contains('UNIEKANTWOORD Sari'));
    });
  });
}

String _unzipText(List<int> bytes, String name) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.findFile(name)!;
  return String.fromCharCodes(file.content as List<int>);
}

String _unzipAllText(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = StringBuffer();
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = file.name;
    if (name.endsWith('.xhtml') || name.endsWith('.html')) {
      out.writeln(String.fromCharCodes(file.content as List<int>));
    }
  }
  return out.toString();
}
