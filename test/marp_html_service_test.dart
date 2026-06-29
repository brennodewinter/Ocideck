import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/markdown_service.dart';

/// Reads the vendored libraries straight from the repo (tests run at the root).
Future<String> _diskLoader(String asset) => File(asset).readAsString();
Future<Uint8List> _diskBytes(String asset) => File(asset).readAsBytes();

void main() {
  group('marpSlides', () {
    test('drops the YAML front-matter and splits on --- separators', () {
      const md = '''
---
marp: true
theme: ocideck
---

# Slide one

---

## Slide two
''';
      final slides = MarpHtmlService.marpSlides(md);
      expect(slides, hasLength(2));
      expect(slides[0], contains('# Slide one'));
      expect(slides[0], isNot(contains('marp: true')));
      expect(slides[1], contains('## Slide two'));
    });

    test('a deck without front-matter keeps every slide', () {
      final slides = MarpHtmlService.marpSlides(
        '# A\n\n---\n\n# B\n\n---\n\n# C',
      );
      expect(slides, hasLength(3));
    });
  });

  test('build() inlines the libraries and the slide content', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    const md = '''
---
marp: true
---

# Titel

\$\$E=mc^2\$\$

```dart
void main() {}
```
''';
    final html = await service.build(md);

    expect(html, startsWith('<!doctype html>'));
    // Slide payload is embedded for the in-browser renderer.
    expect(html, contains('# Titel'));
    expect(html, contains(r'E=mc^2'));
    // Each engine is inlined (offline): marked, highlight.js, MathJax, mermaid.
    expect(html, contains('marked'));
    expect(html, contains('hljs'));
    expect(html, contains('MathJax'));
    expect(html, contains('mermaid'));
    // Everything is inlined: there must be no external <script src=...> tags.
    expect(html, isNot(contains('<script src')));

    // A nonce-based CSP backs DOMPurify: injected inline scripts can't run.
    expect(html, contains('http-equiv="Content-Security-Policy"'));
    expect(html, contains("script-src 'nonce-"));
    expect(html, contains("object-src 'none'"));
    // Every executable <script> we emit carries the nonce (the per-slide
    // markdown holders use `<script type="text/markdown">`), so no bare
    // `<script>` opening tag should remain.
    expect(html, isNot(contains('<script>')));

    // Mermaid runs strict and its injected SVG is sanitised post-render.
    expect(html, contains("securityLevel:'strict'"));
    expect(html, contains('sanitizeMermaid'));
  });

  test(
    'build() stamps classification metadata and banner in the head',
    () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      const md = '# Slide\n';
      final html = await service.build(
        md,
        metadata: const ExportDocumentMetadata(
          title: 'Rapport',
          author: 'Bob',
          tlp: TlpLevel.amber,
        ),
        fallbackTitle: 'deck',
      );

      expect(html, contains('<title>Rapport</title>'));
      expect(html, contains('name="classification" content="TLP:AMBER"'));
      expect(html, contains('name="tlp" content="amber"'));
      expect(html, contains('name="author" content="Bob"'));
      expect(html, contains('class="tlp-export-banner">TLP:AMBER</div>'));
    },
  );

  test('build() neutralises a closing-script breakout in content', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    final html = await service.build('# X\n\nfoo </script> bar');
    // The literal breakout must be escaped so it cannot terminate the payload.
    expect(html, isNot(contains('foo </script> bar')));
    expect(html, contains(r'<\/script'));
  });

  test('build() neutralises a mixed-case closing-script breakout', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    final html = await service.build('# X\n\nfoo </ScRiPt> bar');
    // Case tricks must not slip past the guard.
    expect(html, isNot(contains('</ScRiPt>')));
    expect(html, contains(r'<\/ScRiPt'));
  });

  test(
    'build() bundles DOMPurify and sanitises the rendered markdown',
    () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build('# X');
      // The sanitiser is inlined and actually used before content hits the DOM.
      expect(html, contains('DOMPurify'));
      expect(html, contains('DOMPurify.sanitize('));
    },
  );

  test('a theme colours the slides with the profile palette', () async {
    final service = MarpHtmlService(
      loadAsset: _diskLoader,
      loadBytes: _diskBytes,
    );
    const theme = ThemeProfile(
      slideBackgroundColor: '#102030',
      textColor: '#EEF1F4',
      accentColor: '#33CC99',
      fontFamily: 'Arial',
    );
    final html = await service.build('# Titel', theme: theme);

    expect(html, contains('background:#102030'));
    expect(html, contains('color:#EEF1F4'));
    expect(html, contains('#33CC99'));
    expect(html, contains("'Arial'"));
    // A system font is not embedded as base64.
    expect(html, isNot(contains('data:font/ttf;base64,')));
  });

  test('code blocks use the themed code colours in the export CSS', () async {
    final service = MarpHtmlService(
      loadAsset: _diskLoader,
      loadBytes: _diskBytes,
    );
    const theme = ThemeProfile(
      codeBackgroundColor: '#000000',
      codeTextColor: '#33FF33',
      codeFontFamily: 'Courier New',
    );
    final html = await service.build(
      '```dart\nvoid main() {}\n```',
      theme: theme,
    );

    expect(html, contains('.slide pre{background:#000000;color:#33FF33'));
    expect(html, contains('.slide pre code{color:#33FF33'));
    // The chosen code font is used (with a monospace fallback chain).
    expect(html, contains("font-family:'Courier New',"));
  });

  test('EB Garamond theme embeds the font for offline rendering', () async {
    final service = MarpHtmlService(
      loadAsset: _diskLoader,
      loadBytes: _diskBytes,
    );
    const theme = ThemeProfile(fontFamily: 'EB Garamond');
    final html = await service.build('# Titel', theme: theme);

    expect(html, contains('@font-face'));
    expect(html, contains('data:font/ttf;base64,'));
    expect(html, contains("'EB Garamond'"));
  });

  test('pie chart SVG renders every series and label', () {
    const slide = '''
```chart
{
  "type": "pie",
  "x": ["Team A", "Team B"],
  "series": [
    {"name": "Gereed", "color": "#10B981", "data": [70, 40]},
    {"name": "Open", "color": "#EF4444", "data": [30, 60]}
  ]
}
```
''';

    final html = MarpHtmlService.renderChartBlocks(slide);

    expect(html, contains('Team A'));
    expect(html, contains('Team B'));
    expect(html, contains('Gereed'));
    expect(html, contains('Open'));
    expect(html, contains('#003399'));
    expect(html, contains('#FFCC00'));
  });

  test('pie chart SVG renders at most two series', () {
    const slide = '''
```chart
{
  "type": "pie",
  "x": ["A", "B"],
  "series": [
    {"name": "Een", "data": [1, 2]},
    {"name": "Twee", "data": [2, 3]},
    {"name": "Drie", "data": [3, 4]}
  ]
}
```
''';

    final html = MarpHtmlService.renderChartBlocks(slide);

    expect(html, contains('Een'));
    expect(html, contains('Twee'));
    expect(html, isNot(contains('Drie')));
  });

  test('cockpit SVG renders meters for portable HTML export', () {
    final block = CockpitSpec(
      meters: const [
        CockpitMeterSpec(label: 'Overall risk', value: 78),
        CockpitMeterSpec(
          type: CockpitMeterType.heading,
          label: 'Current phase',
          value: 187,
          heading: 90,
          markerLabel: 'Build',
        ),
      ],
    ).toBlock();
    final slide = '```cockpit\n$block\n```';

    final html = MarpHtmlService.renderCockpitBlocks(slide);

    expect(html, contains('<svg'));
    expect(html, contains('COCKPIT VIEW'));
    expect(html, contains('Overall risk'));
    expect(html, contains('ACT 187'));
    expect(html, contains('TGT 090'));
    expect(html, contains('Build'));
    expect(html, isNot(contains('```cockpit')));
  });

  test('cockpit SVG uses the active colour scheme', () {
    final block = CockpitSpec(
      meters: const [
        CockpitMeterSpec(
          label: 'Risk',
          value: 30,
          greenFrom: 0,
          greenTo: 40,
          redFrom: 70,
        ),
      ],
    ).toBlock();
    final slide = '```cockpit\n$block\n```';

    const scheme = CockpitColorScheme(
      name: 'Test',
      good: '#0AA0FF',
      warning: '#FF22AA',
      critical: '#00FF7F',
      cold: '#123456',
    );
    final html = MarpHtmlService.renderCockpitBlocks(slide, scheme: scheme);

    // The green zone of the speedometer now uses the scheme colour, not the
    // previously hardcoded green.
    expect(html, contains('#0AA0FF'));
    expect(html, isNot(contains('#22C55E')));
  });

  test('cockpit horizon SVG uses the scheme sky and ground colours', () {
    final block = CockpitSpec(
      meters: const [
        CockpitMeterSpec(type: CockpitMeterType.horizon, pitch: 5, bank: 10),
      ],
    ).toBlock();
    final slide = '```cockpit\n$block\n```';

    const scheme = CockpitColorScheme(
      name: 'Test',
      sky: '#0EA5E9',
      ground: '#7C4A12',
    );
    final html = MarpHtmlService.renderCockpitBlocks(slide, scheme: scheme);

    expect(html, contains('#0EA5E9')); // sky
    expect(html, contains('#7C4A12')); // ground
    expect(html, isNot(contains('#2563EB'))); // not the hardcoded sky
    expect(html, isNot(contains('#92400E'))); // not the hardcoded ground
  });

  test('bar chart SVG draws optional min/max bound lines with labels', () {
    const slide = '''
```chart
{
  "type": "bar",
  "x": ["Q1", "Q2"],
  "series": [{"name": "Omzet", "data": [10, 14]}],
  "minBound": 5,
  "maxBound": 20
}
```
''';

    final html = MarpHtmlService.renderChartBlocks(slide);

    expect(html, contains('stroke-dasharray'));
    expect(html, contains('min 5'));
    expect(html, contains('max 20'));
  });

  test('pie chart SVG never draws bound lines', () {
    const slide = '''
```chart
{
  "type": "pie",
  "x": ["A", "B"],
  "series": [{"name": "Een", "data": [1, 2]}],
  "minBound": 5,
  "maxBound": 20
}
```
''';

    final html = MarpHtmlService.renderChartBlocks(slide);

    expect(html, isNot(contains('stroke-dasharray')));
    expect(html, isNot(contains('min 5')));
  });

  test('radar chart SVG draws a polygon per series with axis labels', () {
    const slide = '''
```chart
{
  "type": "radar",
  "x": ["Snelheid", "Kracht", "Uithouding"],
  "series": [
    {"name": "A", "color": "#2563EB", "data": [3, 4, 5]},
    {"name": "B", "color": "#EF4444", "data": [5, 2, 3]}
  ]
}
```
''';

    final html = MarpHtmlService.renderChartBlocks(slide);

    expect(html, contains('<polygon'));
    expect(html, contains('Snelheid'));
    expect(html, contains('Kracht'));
    expect(html, contains('Uithouding'));
    // Both series are drawn with their colours.
    expect(html, contains('fill="#2563EB"'));
    expect(html, contains('fill="#EF4444"'));
    // The series legend is shown (not a pie legend).
    expect(html, contains('A'));
    expect(html, contains('B'));
  });

  group('cat-paw bullet markers in HTML export', () {
    final service = MarpHtmlService(
      loadAsset: _diskLoader,
      loadBytes: _diskBytes,
    );
    const pawTheme = ThemeProfile(bulletMarker: BulletMarker.paw);

    // Builds export-ready markdown exactly as the app does (forExport pins the
    // effective marker), then renders it to HTML.
    Future<String> exportHtml(List<Slide> slides, ThemeProfile theme) {
      final md = MarkdownService().generateDeck(
        Deck(title: 'D', slides: slides, themeProfile: theme),
        forExport: true,
      );
      return service.build(md, theme: theme);
    }

    test(
      'a paw theme tags bullet slides and emits the SVG marker CSS',
      () async {
        final html = await exportHtml([
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Punten', bullets: const ['Een', 'Twee']),
        ], pawTheme);

        expect(html, contains('<section class="slide paw-bullets">'));
        expect(html, contains('.slide.paw-bullets ul{list-style:none'));
        expect(html, contains('data:image/svg+xml'));
      },
    );

    test('a per-slide paw override beats a dot theme', () async {
      final html = await exportHtml([
        Slide.create(SlideType.bullets).copyWith(
          title: 'Punten',
          bullets: const ['Een'],
          bulletMarkerOverride: BulletMarker.paw,
        ),
      ], const ThemeProfile());

      expect(html, contains('<section class="slide paw-bullets">'));
    });

    test('a per-slide dot override beats a paw theme', () async {
      final html = await exportHtml([
        Slide.create(SlideType.bullets).copyWith(
          title: 'Punten',
          bullets: const ['Een'],
          bulletMarkerOverride: BulletMarker.dot,
        ),
      ], pawTheme);

      expect(html, isNot(contains('class="slide paw-bullets"')));
    });

    test('checklist and numbered slides never get paws', () async {
      final checklist = await exportHtml([
        Slide.create(SlideType.bullets).copyWith(
          title: 'Taken',
          listStyle: ListStyle.checklist,
          bullets: const ['[ ] Een'],
        ),
      ], pawTheme);
      final numbered = await exportHtml([
        Slide.create(SlideType.bullets).copyWith(
          title: 'Stappen',
          listStyle: ListStyle.numbered,
          bullets: const ['Een'],
        ),
      ], pawTheme);

      expect(checklist, isNot(contains('class="slide paw-bullets"')));
      expect(numbered, isNot(contains('class="slide paw-bullets"')));
    });

    test(
      'a free-markdown slide with a "-" list never gets paws (parity)',
      () async {
        final html = await exportHtml([
          Slide.create(
            SlideType.freeMarkdown,
          ).copyWith(customMarkdown: '- Een\n- Twee'),
        ], pawTheme);

        // The app renders this list without paws, so the export must not add them.
        expect(html, isNot(contains('class="slide paw-bullets"')));
      },
    );
  });
}
