import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/widgets/reader/paged_document_view.dart';

void main() {
  for (final generated in [false, true]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('hoofdstuklink op pagina springt: toc=$generated zoom=$scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(900, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final source =
            '${generated ? '<!-- toc -->' : '[Ga naar slot](#slot)'}'
            '\n\n${List.generate(35, (i) => 'Alinea $i met tekst voor meer pagina’s.').join('\n\n')}'
            '\n\n## Slot\n\nLaatste alinea.';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PagedDocumentView(
                markdown: source,
                pageSize: const PageSizeSpec(series: PaperSeries.a, number: 6),
                margins: const PageMargins.uniform(10),
                scale: scale,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final vertical = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(vertical.position.pixels, 0);
        if (generated) {
          await tester.tap(find.text('Slot').first);
        } else {
          await tester.tap(find.text('Ga naar slot').hitTestable().first);
        }
        await tester.pumpAndSettle();
        expect(vertical.position.pixels, greaterThan(200));
        expect(find.text('Slot').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final width in [380.0, 900.0]) {
    testWidgets('ankers volgen passend schalen, marges en afloop bij $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = _longSource();
      await _pumpPages(
        tester,
        source,
        scale: 0.75,
        margins: const PageMargins(
          topMm: 24,
          bottomMm: 18,
          leftMm: 13,
          rightMm: 9,
          bleedMm: 5,
        ),
      );
      await tester.tap(find.text('Ga naar slot').hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.text('Slot').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('externe links blijven via de bestaande URL-opener lopen', (
    tester,
  ) async {
    final previous = UrlLauncherPlatform.instance;
    final launcher = _RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    await _pumpPages(
      tester,
      _longSource(link: '[Mail](mailto:jan@example.com)'),
    );
    await tester.tap(find.text('Mail').hitTestable().first);
    await tester.pumpAndSettle();
    expect(launcher.launched, ['mailto:jan@example.com']);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      0,
    );
  });

  testWidgets('ongeldige en ontbrekende ankers veranderen de rol niet', (
    tester,
  ) async {
    for (final href in ['#ontbreekt', '#bad%ZZ', '#']) {
      await _pumpPages(tester, _longSource(link: '[Ga naar slot]($href)'));
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final before = scroll.position.pixels;
      await tester.tap(find.text('Ga naar slot').hitTestable().first);
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, before);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('gewijzigde tekst en zoom gebruiken nieuwe paginametingen', (
    tester,
  ) async {
    await _pumpPages(tester, _longSource());
    await tester.tap(find.text('Ga naar slot').hitTestable().first);
    await tester.pumpAndSettle();
    final changed = _longSource(paragraphs: 55);
    await _pumpPages(tester, changed, scale: 1.5);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ga naar slot').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Slot').hitTestable(), findsOneWidget);
    expect(
      tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).markdown,
      changed,
    );
  });

  testWidgets(
    'reveal werkt vóór de eerste meting en kiest de juiste dubbele kop',
    (tester) async {
      final source = _longSource().replaceFirst(
        '[Ga naar slot](#slot)',
        '# Slot',
      );
      await _pumpPages(
        tester,
        source,
        signal: 1,
        offset: source.lastIndexOf('## Slot'),
      );
      expect(find.text('Slot').hitTestable(), findsOneWidget);
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroll.position.pixels, greaterThan(200));
      await _pumpPages(tester, source, signal: 2, offset: 0);
      expect(scroll.position.pixels, lessThan(20));
      expect(find.text('Slot').hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'Overzicht in Pagina’s springt zonder bronwijziging of undo-stap',
    (tester) async {
      final (notifier, source) = await _pumpEditor(tester);
      await tester.tap(find.text("Pagina's"));
      await tester.pumpAndSettle();
      final pages = find.byType(PagedDocumentView);
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: pages, matching: find.byType(Scrollable)).first,
      );
      final railTarget = find.descendant(
        of: find.byKey(const Key('document-outline-rail')),
        matching: find.text('Slot'),
      );
      await tester.tap(railTarget);
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(200));
      expect(
        find.descendant(of: pages, matching: find.text('Slot')).hitTestable(),
        findsOneWidget,
      );
      expect(notifier.state.document!.body, source);
      expect(notifier.state.isDirty, isFalse);
      expect(notifier.state.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('gegenereerde TOC in Visueel zet de caret op de kop', (
    tester,
  ) async {
    final (notifier, source) = await _pumpEditor(tester);
    final field = find.byType(WysiwygNotesField);
    await tester.tap(
      find.descendant(of: field, matching: find.text('Slot')).first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final controller = tester.widget<WysiwygNotesField>(field).controller;
    expect(
      controller.selection.baseOffset,
      controller.document.toPlainText().indexOf('Slot', 30),
    );
    expect(notifier.state.document!.body, source);
    expect(notifier.state.canUndo, isFalse);
    expect(notifier.state.isDirty, isFalse);
  });
}

String _longSource({
  String link = '[Ga naar slot](#slot)',
  int paragraphs = 35,
}) =>
    '$link\n\n${List.generate(paragraphs, (i) => 'Alinea $i met tekst voor meer pagina’s.').join('\n\n')}\n\n## Slot\n\nLaatste alinea.';

Future<void> _pumpPages(
  WidgetTester tester,
  String source, {
  double scale = 1,
  PageMargins margins = const PageMargins.uniform(10),
  int signal = 0,
  int? offset,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PagedDocumentView(
          markdown: source,
          pageSize: const PageSizeSpec(series: PaperSeries.a, number: 6),
          margins: margins,
          scale: scale,
          revealSignal: signal,
          revealMarkdownOffset: offset,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<(DocumentNotifier, String)> _pumpEditor(WidgetTester tester) async {
  AppLocalizations.setActiveLanguageCode('nl');
  SharedPreferences.setMockInitialValues({});
  await tester.binding.setSurfaceSize(const Size(1400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final source = _longSource(link: '<!-- toc -->\n\n# Start');
  final notifier = DocumentNotifier()
    ..loadDocument(MarkdownDocument.parse(source));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [documentProvider.overrideWith((_) => notifier)],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DocumentEditorScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (notifier, source);
}

class _RecordingLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final launched = <String>[];
  @override
  get linkDelegate => null;
  @override
  Future<bool> canLaunch(String url) async => true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}
