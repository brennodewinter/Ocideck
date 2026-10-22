import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';

const _doc =
    '<!-- transcript version=1 audio="media/opname-1.wav" -->\n'
    '# Transcript — gesprek\n'
    '\n'
    'Bron: [opname-1.wav](media/opname-1.wav)\n'
    'Opgenomen: 2026-10-22 14:03 · Bron: microfoon\n'
    '\n'
    '---\n'
    '\n'
    'Eerste alinea.\n';

void main() {
  group('visuele round-trip (MarkdownQuillCodec)', () {
    test('de marker reist als embed en komt byte-getrouw terug', () {
      final document = MarkdownQuillCodec.documentFromMarkdown(_doc);
      final back = MarkdownQuillCodec.markdownFromDocument(document);
      // De markerregel komt verbatim terug — embed, geen bronfragment.
      expect(
        back,
        contains('<!-- transcript version=1 audio="media/opname-1.wav" -->'),
      );
    });

    test('een bijna-marker reist als bronfragment en blijft verbatim', () {
      const almost = '# Kop\n\n<!-- transcript -->\n\nTekst.\n';
      final document = MarkdownQuillCodec.documentFromMarkdown(almost);
      final back = MarkdownQuillCodec.markdownFromDocument(document);
      expect(back, contains('<!-- transcript -->'));
    });

    test('een volledig transcriptdocument overleeft de heen- en terugweg', () {
      final document = MarkdownQuillCodec.documentFromMarkdown(_doc);
      final back = MarkdownQuillCodec.markdownFromDocument(document);
      // Inhoudelijke regels overleven: kop, link, provenance, body.
      expect(back, contains('# Transcript — gesprek'));
      expect(back, contains('(media/opname-1.wav)'));
      expect(back, contains('Eerste alinea.'));
    });
  });

  group('de chip in het schrijfvlak (TranscriptEmbedBuilder)', () {
    setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

    Future<void> pumpVisual(WidgetTester tester, String markdown) async {
      final controller = QuillController(
        document: MarkdownQuillCodec.documentFromMarkdown(markdown),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(controller.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
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
        ),
      );
      await tester.pump();
    }

    testWidgets('tekent de marker als aanduiding met de audionaam', (
      tester,
    ) async {
      await pumpVisual(tester, _doc);
      expect(tester.takeException(), isNull);
      expect(find.text('Transcript · opname-1.wav'), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
    });

    testWidgets('zonder audio-attribuut toont hij alleen het label', (
      tester,
    ) async {
      await pumpVisual(
        tester,
        '<!-- transcript version=1 -->\n# Transcript — gesprek\n',
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Transcript'), findsOneWidget);
    });
  });
}
