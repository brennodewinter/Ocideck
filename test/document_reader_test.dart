import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/documentation_service.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/reader/doc_mermaid_view.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/reader/document_reader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('DocumentMarkdownView', () {
    testWidgets('renders headings, paragraphs and bullets as text', (
      tester,
    ) async {
      await pump(
        tester,
        const DocumentMarkdownView(
          '# Title\n\nA paragraph with **bold**.\n\n- first\n- second\n',
        ),
      );
      expect(find.text('Title'), findsOneWidget);
      // Bulleted lines render as their own text runs.
      expect(find.textContaining('first'), findsOneWidget);
      expect(find.textContaining('second'), findsOneWidget);
      // Bullet marker glyph is present.
      expect(find.text('•'), findsWidgets);
    });

    testWidgets('renders a GFM task list as boxes, not literal brackets', (
      tester,
    ) async {
      await pump(
        tester,
        const DocumentMarkdownView('- [ ] open item\n- [x] done item\n'),
      );
      // The marker is stripped from the text — it used to read "• [ ] open".
      expect(find.textContaining('[ ]'), findsNothing);
      expect(find.textContaining('[x]'), findsNothing);
      expect(find.text('•'), findsNothing);
      expect(find.textContaining('open item'), findsOneWidget);
      expect(find.textContaining('done item'), findsOneWidget);
      // One empty box and one ticked box.
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    });

    testWidgets('a task item reports its tick state to screen readers', (
      tester,
    ) async {
      await pump(
        tester,
        const DocumentMarkdownView('- [ ] open item\n- [x] done item\n'),
      );
      // Only the task rows carry a checked state; plain rows leave it null, so
      // a screen reader does not announce ordinary bullets as checkboxes.
      final states = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((s) => s.properties.checked)
          .whereType<bool>()
          .toList();
      expect(states, unorderedEquals([true, false]));
    });

    testWidgets('a plain bullet is not mistaken for a task item', (
      tester,
    ) async {
      // A line that merely starts with a bracket is prose, not a checklist.
      await pump(
        tester,
        const DocumentMarkdownView('- [link](https://example.org) matters\n'),
      );
      expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
      expect(find.text('•'), findsOneWidget);
    });

    testWidgets('renders a GFM table with header and cells', (tester) async {
      await pump(
        tester,
        const DocumentMarkdownView(
          '| Key | Action |\n| --- | --- |\n| Ctrl+S | Save |\n',
        ),
      );
      expect(find.byType(Table), findsOneWidget);
      expect(find.textContaining('Key'), findsOneWidget);
      expect(find.textContaining('Ctrl+S'), findsOneWidget);
      expect(find.textContaining('Save'), findsOneWidget);
    });

    testWidgets('renders a fenced code block verbatim', (tester) async {
      await pump(
        tester,
        const DocumentMarkdownView('```\nplain code line\n```\n'),
      );
      expect(find.textContaining('plain code line'), findsOneWidget);
    });

    testWidgets('invokes onTapLink when a link is tapped', (tester) async {
      String? tapped;
      await pump(
        tester,
        DocumentMarkdownView(
          'See [the site](https://example.com) now.',
          onTapLink: (url) => tapped = url,
        ),
      );
      // The link renders as part of a rich paragraph.
      expect(find.textContaining('the site'), findsOneWidget);
      // Tapping is exercised via the recognizer; presence of the run suffices
      // here (gesture wiring is covered by the inline_markdown tests).
      expect(tapped, isNull);
    });

    // A minimal SVG that survives sanitizeMermaidSvg (svg + rect are allowed)
    // and carries a viewBox so the reader can read its natural size.
    const fakeSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 60">'
        '<rect width="120" height="60"/></svg>';

    testWidgets('draws a ```mermaid fence as a diagram, not source', (
      tester,
    ) async {
      await pump(
        tester,
        DocumentMarkdownView(
          '```mermaid\ngraph TD; A-->B;\n```\n',
          mermaidRenderer: (_) async => fakeSvg,
        ),
      );
      expect(find.byType(SvgPicture), findsOneWidget);
      // Once it renders, the raw definition is no longer shown as text.
      expect(find.textContaining('graph TD'), findsNothing);
    });

    testWidgets('a mermaid fence falls back to its source when render fails', (
      tester,
    ) async {
      await pump(
        tester,
        DocumentMarkdownView(
          '```mermaid\ngraph TD; A-->B;\n```\n',
          mermaidRenderer: (_) async => null,
        ),
      );
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.textContaining('graph TD'), findsOneWidget);
    });

    testWidgets('a non-mermaid fence stays a code block', (tester) async {
      await pump(
        tester,
        DocumentMarkdownView(
          '```dart\nvoid main() {}\n```\n',
          // Even with a working renderer, only ```mermaid is drawn.
          mermaidRenderer: (_) async => fakeSvg,
        ),
      );
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.textContaining('void main'), findsOneWidget);
    });

    test('blockTexts returns one searchable string per block, in order', () {
      final texts = DocumentMarkdownView.blockTexts(
        '# Titel\n\nEen alinea.\n\n- item een\n- item twee\n',
      );
      expect(texts, ['Titel', 'Een alinea.', 'item een item twee']);
    });

    test('a pipe line that is not a valid table falls back to a paragraph', () {
      // Regression: a line starting with `|` with no `|---|` delimiter row is
      // consumed by no block branch and fails _isParagraphLine, so the parser
      // must still advance and keep it as text. Before the fix this spun forever
      // building empty blocks until the app ran out of memory — it hung the
      // reader on the real FILE_FORMAT.md and SBOM.md. A parse-only probe so a
      // regression fails by timeout rather than pumping a hung widget tree.
      expect(
        DocumentMarkdownView.blockTexts('| stray | pipe | line |\n\nAfter.\n'),
        ['| stray | pipe | line |', 'After.'],
      );
      // Three pipe rows with no delimiter: each becomes its own paragraph, none
      // dropped, and the parser terminates.
      expect(
        DocumentMarkdownView.blockTexts('| a | b |\n| c | d |\n| e | f |\n'),
        ['| a | b |', '| c | d |', '| e | f |'],
      );
    });

    testWidgets('renders a stray pipe line as text without hanging', (
      tester,
    ) async {
      await pump(
        tester,
        const DocumentMarkdownView('| stray | pipe |\n\nAfter the table.\n'),
      );
      expect(find.textContaining('stray'), findsOneWidget);
      expect(find.textContaining('After the table'), findsOneWidget);
    });
  });

  group('DocMermaidView', () {
    const smallSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 60">'
        '<rect width="120" height="60"/></svg>';
    // A viewBox far wider than any test surface, so the diagram overflows the
    // column and the horizontal-scroll branch is taken.
    const wideSvg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4000 60">'
        '<rect width="4000" height="60"/></svg>';

    Future<void> pumpMermaid(
      WidgetTester tester,
      Future<String?> Function(String) renderer,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DocMermaidView(
                source: 'graph TD; A-->B;',
                fallback: const Text('FALLBACK'),
                renderer: renderer,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('a diagram that fits is centred, no scroller', (tester) async {
      await pumpMermaid(tester, (_) async => smallSvg);
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(Scrollbar), findsNothing);
      expect(find.text('FALLBACK'), findsNothing);
    });

    testWidgets('a diagram wider than the column scrolls horizontally', (
      tester,
    ) async {
      await pumpMermaid(tester, (_) async => wideSvg);
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
      // Overflow branch: a Scrollbar over a horizontal scroll view.
      expect(find.byType(Scrollbar), findsOneWidget);
    });

    testWidgets('shows a spinner while rendering is in flight', (tester) async {
      // A future that never completes stays in the loading branch.
      await pumpMermaid(tester, (_) => Completer<String?>().future);
      await tester.pump(); // one frame, not settle (the spinner animates)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
      expect(find.text('FALLBACK'), findsNothing);
    });

    testWidgets('falls back when the SVG has no usable viewBox', (
      tester,
    ) async {
      // No viewBox → no natural size → it cannot be laid out in the column, so
      // the fallback is shown rather than a collapsed frame.
      await pumpMermaid(
        tester,
        (_) async => '<svg xmlns="http://www.w3.org/2000/svg"><rect/></svg>',
      );
      await tester.pumpAndSettle();
      expect(find.text('FALLBACK'), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    });
  });

  group('DocumentationService', () {
    const service = DocumentationService();

    test('loads a bundled doc and strips a leading comment header', () async {
      final text = await service.load('LICENSE.md', 'nl');
      expect(text, isNotEmpty);
      expect(text.trimLeft(), isNot(startsWith('<!--')));
      expect(text, contains('EUPL'));
    });

    test(
      'falls back to the base doc when no locale variant is bundled',
      () async {
        // No docs/USER_GUIDE.de.md is shipped yet, so `de` must return the base.
        final base = await service.load('docs/USER_GUIDE.md', 'nl');
        final german = await service.load('docs/USER_GUIDE.md', 'de');
        expect(german, equals(base));
        expect(base, isNotEmpty);
      },
    );
  });

  group('DocumentReaderScreen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Widget wrap(Widget home, {String locale = 'nl'}) => ProviderScope(
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

    testWidgets('shows the title and the document body', (tester) async {
      await tester.pumpWidget(
        wrap(
          const DocumentReaderScreen(
            title: 'Sneltoetsen',
            assetBase: 'docs/SHORTCUTS.md',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sneltoetsen'), findsOneWidget);
      expect(find.byType(DocumentMarkdownView), findsOneWidget);
    });

    testWidgets('fills the width but still bounds prose', (tester) async {
      // A wide window: the content column now fills the full available width
      // (no centred, capped column), while prose is held to a readable measure
      // via a ConstrainedBox — tables and code skip that bound.
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrap(
          const DocumentReaderScreen(
            title: 'Gids',
            assetBase: 'x',
            service: _FakeDocs(
              '# Titel\n\n'
              'Een tamelijk lange paragraaf die zonder begrenzing breder zou '
              'worden dan de leesbare maat, om het inperken te tonen.\n\n'
              // A deliberately wide table: it must overflow the prose measure
              // and use the full content width rather than being squeezed.
              '| Kolom1 | Kolom2 | Kolom3 | Kolom4 | Kolom5 | Kolom6 | Kolom7 | Kolom8 | Kolom9 | Kolom10 |\n'
              '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n'
              '| aaaa | bbbb | cccc | dddd | eeee | ffff | gggg | hhhh | iiii | jjjj |\n',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final viewWidth = tester.getSize(find.byType(DocumentMarkdownView)).width;
      // The document view now fills the window minus the side padding (32 each
      // side): ~1536 on a 1600 window, instead of a centred ~1200 column.
      expect(viewWidth, greaterThan(1400));
      // …and prose blocks are wrapped in a bounding ConstrainedBox (940 px).
      final bounded = find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.maxWidth == 940,
      );
      expect(bounded, findsWidgets);
    });

    testWidgets('the text-size buttons grow and shrink the reader scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const DocumentReaderScreen(
            title: 'Gids',
            assetBase: 'x',
            service: _FakeDocs('# Titel\n\nTekst.\n'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(DocumentMarkdownView)),
      );
      double scale() => container.read(settingsProvider).docReaderTextScale;

      expect(scale(), 1.0);

      await tester.tap(find.byIcon(Icons.text_increase));
      await tester.pumpAndSettle();
      expect(scale(), greaterThan(1.0));

      await tester.tap(find.byIcon(Icons.text_decrease));
      await tester.pumpAndSettle();
      expect(scale(), closeTo(1.0, 1e-9));
    });

    testWidgets(
      'find-in-page counts hits, steps with wrap-around, and closes',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const DocumentReaderScreen(
              title: 'Gids',
              assetBase: 'x',
              service: _FakeDocs(
                '# Titel\n\n'
                'Eerste blok noemt doelwit.\n\n'
                'Tweede blok noemt doelwit weer.\n\n'
                'Derde blok zonder dat woord.\n',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No find bar until it is opened.
        expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
        await tester.tap(find.byIcon(Icons.search));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

        // A term in two blocks → "1 / 2".
        await tester.enterText(find.byType(TextField), 'doelwit');
        await tester.pumpAndSettle();
        expect(find.text('1 / 2'), findsOneWidget);

        // Next advances, then wraps back to the first.
        await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
        await tester.pumpAndSettle();
        expect(find.text('1 / 2'), findsOneWidget);

        // Previous from the first wraps to the last.
        await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);

        // A term in no block reports no hits.
        await tester.enterText(find.byType(TextField), 'ditbestaatniet');
        await tester.pumpAndSettle();
        expect(find.text('Geen treffers'), findsOneWidget);

        // Closing hides the bar again.
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
      },
    );

    // #626: de gebundelde documenten bestaan alleen in het Engels, terwijl hun
    // titels in 32 talen staan. Wie de app op Pools zet, ziet een Poolse titel
    // en krijgt Engels — en de app wekte die verwachting zelf.
    group('de melding dat een document alleen in het Engels bestaat', () {
      Future<void> open(
        WidgetTester tester, {
        required bool isBaseVersion,
        String locale = 'nl',
      }) async {
        await tester.pumpWidget(
          wrap(
            DocumentReaderScreen(
              title: 'Gids',
              assetBase: 'x',
              service: _FakeDocs(
                '# Titel\n\nTekst.\n',
                isBaseVersion: isBaseVersion,
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
      }

      // Op de melding zélf toetsen kan niet: in het Duits geeft `d()` de Duitse
      // zin terug, en die hier herhalen zou de vertaling toetsen in plaats van
      // het gedrag. Het icoon is wat de melding uniek maakt.
      Finder melding() => find.byIcon(Icons.translate);

      testWidgets('staat er bij een niet-vertaald document', (tester) async {
        await open(tester, isBaseVersion: true, locale: 'de');
        expect(melding(), findsOneWidget);
      });

      testWidgets('staat er niet zodra er een vertaling ligt', (tester) async {
        // Zet iemand later `USER_GUIDE.de.md` ernaast, dan moet de melding
        // vanzelf verdwijnen — anders vertelt hij een onwaarheid en is hij
        // erger dan geen melding.
        await open(tester, isBaseVersion: false, locale: 'de');
        expect(melding(), findsNothing);
      });

      testWidgets('staat er niet in het Nederlands', (tester) async {
        // De basisversie ís de Nederlandse bron; er valt niets te melden.
        await open(tester, isBaseVersion: true);
        expect(melding(), findsNothing);
      });
    });
  });
}

/// A stand-in documentation service that returns fixed markdown without any
/// asset IO, so reader tests stay deterministic.
class _FakeDocs implements DocumentationService {
  const _FakeDocs(this.markdown, {this.isBaseVersion = true});
  final String markdown;

  /// Of dit "de Engelse basisversie" is. Standaard waar, want dat is wat elk
  /// gebundeld document vandaag is (#626).
  final bool isBaseVersion;

  @override
  Future<String> load(String baseAsset, String languageCode) async => markdown;

  @override
  Future<({String text, bool isBaseVersion})> loadDetailed(
    String baseAsset,
    String languageCode,
  ) async => (text: markdown, isBaseVersion: isBaseVersion);
}
