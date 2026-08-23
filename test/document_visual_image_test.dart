import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/utils/image_embed_syntax.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/markdown_editor/image_embed_builder.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';

/// Een afbeelding in een document liet het schrijfvlak omvallen, en gooide
/// onderweg de alt-tekst weg.
///
/// De standaardweg van `markdown_quill` maakt van `![alt](bron)` een
/// `image`-embed die alleen de bron draagt. Voor dat type stond hier geen
/// bouwer, dus Quill wierp `UnimplementedError: Embeddable type "image" is not
/// supported` tijdens het tekenen van de regel — en dat is geen stukgelopen
/// alinea maar een foutscherm in plaats van het document. En omdat de embed de
/// alt-tekst niet meedroeg, schreef de terugweg `![](bron)`: één bewerking
/// elders in het document was genoeg om overal de toegankelijke omschrijving
/// weg te gooien.
void main() {
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

  testWidgets('het schrijfvlak tekent een afbeelding zonder om te vallen', (
    tester,
  ) async {
    await pumpVisual(
      tester,
      'Tekst vooraf.\n\n![Een alt-tekst](assets/foo.png)\n\nErna.\n',
    );
    expect(tester.takeException(), isNull);
    // Het merkteken staat op zijn plek, met de alt-tekst erin: je ziet dát er
    // een afbeelding staat en welke.
    expect(find.text('Een alt-tekst'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('zonder alt-tekst toont het merkteken de bestandsnaam', (
    tester,
  ) async {
    await pumpVisual(tester, '![](assets/beelden/plaatje.png)\n');
    expect(tester.takeException(), isNull);
    expect(find.text('plaatje.png'), findsOneWidget);
  });

  group('de heen-en-terugweg', () {
    String roundTrip(String markdown) =>
        MarkdownQuillCodec.markdownFromDocument(
          MarkdownQuillCodec.documentFromMarkdown(markdown),
        );

    test('houdt de alt-tekst vast', () {
      expect(
        roundTrip('Vooraf.\n\n![Een alt-tekst](assets/foo.png)\n\nErna.\n'),
        contains('![Een alt-tekst](assets/foo.png)'),
      );
    });

    test('houdt een titel en een pad met spaties vast', () {
      expect(
        roundTrip('![Alt](map met spaties/foo.png "Een titel")\n'),
        contains('![Alt](map met spaties/foo.png "Een titel")'),
      );
    });

    test('twee afbeeldingen op één regel blijven twee afbeeldingen', () {
      expect(
        roundTrip('![Een](a.png)![Twee](b.png)\n'),
        contains('![Een](a.png)![Twee](b.png)'),
      );
    });
  });

  group('het lezen van de opgeslagen markdown', () {
    test('splitst alt-tekst en bron, en laat de titel bij de markdown', () {
      final image = EmbeddableMarkdownImage('![Alt](a.png "Titel")');
      final parsed = EmbeddableMarkdownImage.parse(image);
      expect(parsed.alt, 'Alt');
      expect(parsed.source, 'a.png');
      expect(
        EmbeddableMarkdownImage.markdownOf(image),
        '![Alt](a.png "Titel")',
      );
    });

    test('onleesbare inhoud levert lege velden op, geen uitzondering', () {
      final parsed = EmbeddableMarkdownImage.parse(
        EmbeddableMarkdownImage('geen afbeelding'),
      );
      expect(parsed.alt, isEmpty);
      expect(parsed.source, isEmpty);
    });
  });

  testWidgets('een onbekend embed-type valt terug in plaats van om te vallen', (
    tester,
  ) async {
    // Het vangnet, los getoetst: wat hier langskomt is per definitie een gat in
    // de registratie, en zo'n gat hoort een rafeltje te zijn.
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    controller.document.insert(0, BlockEmbed('x-nog-nooit-vertoond', 'inhoud'));
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

    expect(tester.takeException(), isNull);
    expect(find.text('inhoud'), findsOneWidget);
  });

  test('de vangnet-sleutel botst niet met een echte bouwer', () {
    const echte = [
      EmbeddableMarkdownImage.imageType,
      'x-embed-table',
      'x-embed-toc',
      'x-embed-footnote-ref',
      'x-embed-footnote-def',
      'x-embed-document-timeline',
    ];
    expect(echte, isNot(contains(const FallbackEmbedBuilder().key)));
  });
}
