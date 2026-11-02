import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/improvement_y01.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/rich_text_layout.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

List<Slide> _slides() => [
  Slide.create(SlideType.table).copyWith(
    title: 'Zichtbare tabel',
    tableRows: [
      ['Kolom'],
      for (var i = 0; i < 40; i++) ['Rij $i'],
    ],
    notes: 'alleenprivé',
  ),
  Slide.create(SlideType.freeMarkdown).copyWith(
    customMarkdown: List.generate(
      80,
      (i) => 'Zichtbare **inhoud** $i voor meerdere pagina’s.',
    ).join('\n\n'),
    notes: 'ookprivé',
  ),
];

void _check(String markdown, List<Slide> source) {
  expect(markdown, isNot(contains('alleenprivé')));
  expect(markdown, isNot(contains('ookprivé')));
  final shown = MarkdownService().parseDeck(markdown)!.slides;
  expect(shown.map((s) => s.notes), everyElement(isEmpty));
  expect(shown.map((s) => s.title), source.map((s) => s.title));
  expect(shown.first.tableRows, source.first.tableRows);
  expect(shown.last.customMarkdown, source.last.customMarkdown);
  expect(source.first.renderPage, 0);
  final originalPages = richTextPageCountForSlide(
    slide: source.last,
    profile: const ThemeProfile(),
  );
  expect(originalPages, greaterThan(1));
  expect(
    richTextPageCountForSlide(slide: shown.last, profile: const ThemeProfile()),
    originalPages,
  );
  expect(source.map((s) => s.notes), ['alleenprivé', 'ookprivé']);
}

void main() {
  test(
    'initial audience markdown omits notes and preserves source and visible content',
    () {
      final slides = _slides();
      _check(
        buildBeamerMarkdown(
          slides: slides,
          projectPath: null,
          themeProfile: const ThemeProfile(),
        ),
        slides,
      );
    },
  );

  testWidgets(
    'replaceDeck omits notes without changing rendered content or source',
    (tester) async {
      const bridge = MethodChannel('mixin.one/desktop_multi_window/channels');
      Map<String, dynamic>? payload;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
        call,
      ) async {
        if (call.method == 'invokeMethod') {
          final envelope = Map<String, dynamic>.from(call.arguments as Map);
          if (envelope['method'] == 'replaceDeck') {
            payload = Map<String, dynamic>.from(envelope['arguments'] as Map);
          }
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          bridge,
          null,
        ),
      );
      final slides = _slides();
      sendDeckReplaceToAudience(
        AudienceWindowHandle(
          WindowController.fromWindowId('test'),
          closeImpl: (_) async {},
        ),
        slides: slides,
        projectPath: null,
        themeProfile: const ThemeProfile(),
        tlp: TlpLevel.none,
        organization: '',
        reportLanguage: '',
        index: 1,
        improvementY01: ImprovementY01Metric.empty,
        annotations: const {},
      );
      await tester.pump();
      expect(payload, isNotNull);
      expect(payload!['index'], 1);
      _check(payload!['markdown'] as String, slides);
    },
  );
}
