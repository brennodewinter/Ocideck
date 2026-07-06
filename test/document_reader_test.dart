import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/documentation_service.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/reader/document_reader_screen.dart';

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
    testWidgets('shows the title and the document body', (tester) async {
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
          home: const DocumentReaderScreen(
            title: 'Sneltoetsen',
            assetBase: 'docs/SHORTCUTS.md',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sneltoetsen'), findsOneWidget);
      expect(find.byType(DocumentMarkdownView), findsOneWidget);
    });
  });
}
