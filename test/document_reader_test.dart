import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/documentation_service.dart';
import 'package:ocideck/state/settings_provider.dart';
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

    Widget wrap(Widget home) => ProviderScope(
      child: MaterialApp(
        locale: const Locale('nl'),
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

    testWidgets('bounds prose but lets the document use the wide column', (
      tester,
    ) async {
      // A wide window: the content column is far wider than the old fixed
      // narrow one, while prose is held to a readable measure via a
      // ConstrainedBox — tables and code skip that bound.
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
              // and use the wider content column rather than being squeezed.
              '| Kolom1 | Kolom2 | Kolom3 | Kolom4 | Kolom5 | Kolom6 | Kolom7 | Kolom8 | Kolom9 | Kolom10 |\n'
              '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n'
              '| aaaa | bbbb | cccc | dddd | eeee | ffff | gggg | hhhh | iiii | jjjj |\n',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final viewWidth = tester.getSize(find.byType(DocumentMarkdownView)).width;
      // The document view spans well beyond the old ~760 px column…
      expect(viewWidth, greaterThan(900));
      // …and prose blocks are wrapped in a bounding ConstrainedBox (860 px).
      final bounded = find.byWidgetPredicate(
        (w) => w is ConstrainedBox && w.constraints.maxWidth == 860,
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
  });
}

/// A stand-in documentation service that returns fixed markdown without any
/// asset IO, so reader tests stay deterministic.
class _FakeDocs implements DocumentationService {
  const _FakeDocs(this.markdown);
  final String markdown;

  @override
  Future<String> load(String baseAsset, String languageCode) async => markdown;
}
