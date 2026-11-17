// Profielproef op native platforms en web, vóór/na met hetzelfde harnas.
// De timings meten tik → juiste zichtbare caret; de bron blijft ongewijzigd.
import 'support/profile_memory_io.dart'
    if (dart.library.js_interop) 'support/profile_memory_web.dart';

import 'package:flutter/foundation.dart' show kProfileMode;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/widgets/reader/paged_document_view.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/document_navigation_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('herhaalde hoofdstuksprongen in een lang document', (
    tester,
  ) async {
    expect(kProfileMode, isTrue, reason: 'Draai deze proef met --profile.');
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    // Diagramprojectie heeft een eigen regressieproef. De profielmeting houdt
    // rendererinitialisatie buiten de cursor-/scrollmeting.
    final source = documentNavigationFixture(diagrams: false);
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
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final times = <int>[];
    await profileWatchPerformance(binding, () async {
      // De eerste twee sprongen warmen de kaart en het scrollpad op.
      for (var attempt = 0; attempt < 18; attempt++) {
        final title = attempt.isEven ? 'Hoofdstuk 35' : 'Hoofdstuk 01';
        final rail = find.byKey(const Key('document-outline-rail'));
        final target = find.descendant(of: rail, matching: find.text(title));
        final scrollable = find
            .descendant(of: rail, matching: find.byType(Scrollable))
            .first;
        await tester.scrollUntilVisible(
          target,
          attempt.isEven ? 300 : -300,
          scrollable: scrollable,
          maxScrolls: 30,
        );
        // ensureVisible wijzigt de scrollpositie vóór de volgende layout.
        // Meet pas als de rail zijn doel ook werkelijk op die plek tekent.
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        final clock = Stopwatch()..start();
        await tester.tap(target);
        var visible = false;
        while (clock.elapsed < const Duration(seconds: 10)) {
          await tester.pump(const Duration(milliseconds: 16));
          final field = tester.widget<WysiwygNotesField>(
            find.byType(WysiwygNotesField),
          );
          final offset = field.controller.document.toPlainText().indexOf(title);
          final selection = field.controller.selection;
          if (selection.baseOffset != offset) continue;
          final raw = tester.state<QuillRawEditorState>(
            find.byType(QuillRawEditor),
          );
          final point = raw.renderEditor
              .getEndpointsForSelection(selection)
              .first
              .point;
          final global = raw.renderEditor.localToGlobal(point);
          final viewport = tester.getRect(find.byType(QuillEditor));
          visible = viewport.contains(global);
          if (visible) break;
        }
        clock.stop();
        expect(visible, isTrue, reason: '$title moet zichtbaar zijn.');
        if (attempt >= 2) times.add(clock.elapsedMicroseconds);
      }
    }, reportKey: 'chapter_navigation_frames');
    expect(notifier.state.document!.body, source);
    expect(notifier.state.isDirty, isFalse);
    expect(notifier.state.canUndo, isFalse);
    times.sort();
    binding.reportData!['chapter_navigation_latency'] = {
      'platform': profilePlatform,
      'profile': kProfileMode,
      'source_bytes': source.length,
      'samples_us': times,
      'median_us': times[times.length ~/ 2],
      'p95_us': times[((times.length - 1) * .95).ceil()],
    };
  });
  testWidgets(
    'paginering bij 10, 40 en 100 vellen',
    (tester) => _profilePagination(binding, tester),
  );
}

/// Dezelfde harness draait vóór/na op native platforms. De baseline mag nog
/// veel bomen monteren: de vergelijking registreert dat, de regressietest
/// handhaaft de vaste bovengrens op de gewijzigde implementatie.
Future<void> _profilePagination(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
) async {
  expect(kProfileMode, isTrue);
  AppLocalizations.setActiveLanguageCode('nl');
  final results = <Map<String, Object>>[];
  for (final pages in [10, 40, 100]) {
    final source = documentPaginationFixture(pages);
    final samples = <int>[];
    final beforeMemory = profileMemory('before');
    var loadUs = 0;
    var mountedMax = 0;
    await profileWatchPerformance(binding, () async {
      final load = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PagedDocumentView(
              key: ValueKey('profile-$pages'),
              markdown: source,
              pageSize: PageSizeSpec.a4,
              margins: const PageMargins(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      load.stop();
      loadUs = load.elapsedMicroseconds;
      for (var attempt = 0; attempt < 10; attempt++) {
        final last = attempt.isEven;
        final body = tester
            .widgetList<DocumentMarkdownView>(find.byType(DocumentMarkdownView))
            .firstWhere((w) => w.onTapLink != null);
        final clock = Stopwatch()..start();
        body.onTapLink!('#hoofdstuk-${last ? pages - 1 : 0}');
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        clock.stop();
        final trees = find
            .byType(DocumentMarkdownView, skipOffstage: false)
            .evaluate()
            .length;
        if (trees > mountedMax) mountedMax = trees;
        final number = last ? pages : 1;
        final sheet = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Pagina $number van $pages',
        );
        expect(sheet, findsOneWidget);
        final paper = tester.getRect(sheet);
        final viewport = tester.getRect(find.byType(PagedDocumentView));
        expect(paper.overlaps(viewport), isTrue);
        if (attempt >= 2) samples.add(clock.elapsedMicroseconds);
      }
    }, reportKey: 'pagination_${pages}_frames');
    samples.sort();
    results.add({
      'platform': profilePlatform,
      'profile': kProfileMode,
      'pages': pages,
      'source_bytes': source.length,
      'load_us': loadUs,
      'mounted_document_trees_max': mountedMax,
      ...beforeMemory,
      ...profileMemory('after'),
      'jump_samples_us': samples,
      'jump_median_us': samples[samples.length ~/ 2],
      'jump_p95_us': samples[((samples.length - 1) * .95).ceil()],
    });
  }
  binding.reportData!['pagination_scaling'] = results;
}
