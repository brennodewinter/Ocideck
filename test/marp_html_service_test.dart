import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/l10n/app_localizations.dart';

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
    // MIAUW tables fill the slide width in the export (feedback #2), matching
    // the project export path.
    expect(html, contains('.slide table{border-collapse:collapse;width:100%}'));
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
    // …en zonder HTML-labels, want die reizen in een <foreignObject> dat de
    // sanitisatie eruit haalt: het diagram houdt dan lege vakjes over.
    expect(html, contains('htmlLabels:false'));
    expect(html, contains('flowchart:{htmlLabels:false}'));
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

  test('build() shows and stamps the unreviewed-AI marking', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    final html = await service.build(
      '# Slide\n',
      metadata: const ExportDocumentMetadata(
        title: 'Rapport',
        unreviewedAiSlideCount: 2,
      ),
      fallbackTitle: 'deck',
    );

    // Machineleesbaar (art. 50 lid 2) …
    expect(html, contains('name="ai-generated" content="$kAiDraftKeyword"'));
    expect(html, contains('name="ai-generated-slides" content="2"'));
    // … én leesbaar voor wie het document opent. Metadata alleen is onzichtbaar
    // voor de lezer, en die is degene die het moet weten.
    expect(html, contains('class="ai-export-banner"'));
    expect(html, contains('AI-tekst'));
    // Zonder TLP-balk staat hij bovenaan; is die er wel, dan eronder.
    expect(html, contains('style="top:0"'));
  });

  test('build() stacks the AI banner under the TLP banner', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    final html = await service.build(
      '# Slide\n',
      metadata: const ExportDocumentMetadata(
        tlp: TlpLevel.red,
        unreviewedAiSlideCount: 1,
      ),
      fallbackTitle: 'deck',
    );
    expect(html, contains('class="tlp-export-banner">TLP:RED</div>'));
    expect(html, contains('class="ai-export-banner" style="top:2.4em"'));
  });

  test('build() says nothing about AI once the text is reviewed', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    final html = await service.build(
      '# Slide\n',
      metadata: const ExportDocumentMetadata(title: 'Rapport'),
      fallbackTitle: 'deck',
    );
    // De CSS-regel staat er altijd; het gáát om de div die hem gebruikt.
    expect(html, isNot(contains('<div class="ai-export-banner"')));
    expect(html, isNot(contains('name="ai-generated"')));
    expect(html, isNot(contains(kAiDraftKeyword)));
  });

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

  group('een kapot mermaid-diagram', () {
    test('krijgt een leesbare melding in het document zelf', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build('# X\n\n```mermaid\ngraph TD\n```');

      // De ontvanger heeft geen console: de melding moet in het document staan,
      // in zijn taal, met de brontekst van het diagram erbij.
      expect(html, contains('Dit diagram kon niet worden getekend'));
      expect(html, contains('Brontekst van het diagram'));
      expect(html, contains('mermaid-error'));
      expect(html, contains('.slide .mermaid-error{'));
      // Elk diagram wordt eerst apart gecontroleerd, zodat mermaid zijn eigen
      // Engelse foutplaatje niet tekent.
      expect(html, contains('mermaid.parse('));
    });

    test('laat de sanitisatie van de andere diagrammen niet vallen', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build('# X');

      // De stille `.catch(function(e){})` op mermaid.run() sloeg
      // sanitizeMermaid over voor het HELE document zodra één diagram omviel.
      expect(html, isNot(contains('.catch(function(e){})')));
      expect(html, contains('.then(sanitizeMermaid)'));
    });
  });

  test('a themed export keeps the structural stylesheet', () async {
    // De opmaak van de tijdlijn, de ondertekening, het redactievlak en de
    // classificatiebanner hoort niet bij het thema. Toen de themed CSS het
    // basisblok verving in plaats van aanvulde, verloor élke export uit de app
    // (die geeft altijd een thema mee) die vier — de banner met de TLP-marking
    // voorop.
    final service = MarpHtmlService(
      loadAsset: _diskLoader,
      loadBytes: _diskBytes,
    );
    const theme = ThemeProfile(accentColor: '#33CC99');
    final html = await service.build('# Titel', theme: theme);

    expect(html, contains('.slide ol.timeline'));
    expect(html, contains('.slide .signoff'));
    expect(html, contains('.slide .media-redacted'));
    expect(html, contains('.tlp-export-banner{'));
    expect(html, contains('@media print'));
    // En het thema kleurt de tijdlijn mee via de enige haak die het heeft.
    expect(html, contains('--ocideck-accent:#33CC99'));
  });

  group('per-slide title colour override', () {
    test('a title override becomes a scoped variable the h1 reads', () async {
      final service = MarpHtmlService(
        loadAsset: _diskLoader,
        loadBytes: _diskBytes,
      );
      const theme = ThemeProfile(textColor: '#EEF1F4');
      final html = await service.build(
        '# Titel\n<!-- ocideck_title_text_color: #111827 -->',
        theme: theme,
      );

      // The section carries the override as a custom property...
      expect(html, contains('style="--ocideck-title-color:#111827"'));
      // ...and the h1 rule reads it, falling back to the theme text colour.
      expect(html, contains('color:var(--ocideck-title-color,#EEF1F4)'));
    });

    test('a slide without an override gets no title-colour style', () async {
      final service = MarpHtmlService(
        loadAsset: _diskLoader,
        loadBytes: _diskBytes,
      );
      final html = await service.build('# Titel', theme: const ThemeProfile());

      // The `:` only appears in the inline style, not the var() reference.
      expect(html, isNot(contains('--ocideck-title-color:')));
    });

    test(
      'a non-hex override value is rejected, so no style is injected',
      () async {
        final service = MarpHtmlService(
          loadAsset: _diskLoader,
          loadBytes: _diskBytes,
        );
        final html = await service.build(
          '# Titel\n<!-- ocideck_title_text_color: red;} body{display:none -->',
          theme: const ThemeProfile(),
        );

        // The value never reaches an active `style` attribute — the raw comment
        // text survives only inside the inert `<script type="text/markdown">`
        // payload, never as a `--ocideck-title-color:` declaration on the section.
        expect(html, isNot(contains('--ocideck-title-color:')));
      },
    );
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

  test('a donut hole matches the app render fraction (kDonutHoleFraction)', () {
    // The export drew a thinner ring (0.6 hole) than the app (0.38); both now
    // read the one shared constant so the same donut looks the same everywhere.
    const slide = '''
```chart
{
  "type": "donut",
  "x": ["A", "B", "C"],
  "series": [{"name": "Aandeel", "data": [50, 30, 20]}]
}
```
''';

    final html = MarpHtmlService.renderChartBlocks(slide);

    // Slices arc out to the outer radius (`A r,r …`, all the same). The hole is a
    // background circle; it is by far the largest circle (the legend swatches are
    // r=5), so take the max radius rather than depend on element order.
    final outer = double.parse(
      RegExp(r'A([\d.]+),').firstMatch(html)!.group(1)!,
    );
    final hole = RegExp(r'<circle[^>]*\br="([\d.]+)"')
        .allMatches(html)
        .map((m) => double.parse(m.group(1)!))
        .reduce((a, b) => a > b ? a : b);
    expect(hole / outer, closeTo(kDonutHoleFraction, 1e-6));
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
    // Geen hardgecodeerde Engelse header meer: die stond niet in de app-render
    // en is uit de export gehaald (#COCKPIT-export volgt nu het dia-thema).
    expect(html, isNot(contains('COCKPIT VIEW')));
    expect(html, contains('Overall risk'));
    expect(html, contains('ACT 187'));
    expect(html, contains('TGT 090'));
    expect(html, contains('Build'));
    expect(html, isNot(contains('```cockpit')));
    expect(html, contains('class="cockpit-svg authentic"'));
  });

  test('cockpit heading readouts stay inside the card in export (#1110)', () {
    // Een lange gelokaliseerde markerregel liep in de export ongeclipt over het
    // buurinstrument (center-anchored, geen breedtegrens). Nu rechts uitgelijnd
    // en afgekapt met een ellipsis binnen de vrije kolom. Getoetst in de
    // 3-koloms rasterindeling (zes meters) waar de kaart smal is — precies de
    // situatie uit het issue, waar één brede kaart de afkapping zou verbergen.
    const longMarker = 'Kursabweichungen im Steigflug über dem Fjord';
    final block = CockpitSpec(
      meters: const [
        CockpitMeterSpec(label: 'Capacity', value: 78),
        CockpitMeterSpec(
          type: CockpitMeterType.heading,
          label: 'Findings trend',
          value: 187,
          heading: 90,
          markerLabel: longMarker,
        ),
        CockpitMeterSpec(label: 'Signal', value: 92),
        CockpitMeterSpec(label: 'Quality', value: 64),
        CockpitMeterSpec(label: 'Coverage', value: 41),
        CockpitMeterSpec(label: 'Backlog', value: 12),
      ],
    ).toBlock();
    final slide = '```cockpit\n$block\n```';

    final html = MarpHtmlService.renderCockpitBlocks(slide);

    // De volledige lange marker staat er niet meer in; hij is gewikkeld en
    // afgekapt binnen het uitleesvenster naast de roos, in een clip van dat
    // venster als laatste vangnet.
    expect(html, isNot(contains(longMarker)));
    expect(html, contains('…'));
    expect(html, contains('clip-path="url(#cockpit-readout-1-'));
    // De korte readouts blijven voluit leesbaar.
    expect(html, contains('ACT 187°'));
    expect(html, contains('TGT 090°'));
  });

  test('cockpit SVG keeps the classic visual style available', () {
    final block = const CockpitSpec(
      meters: [CockpitMeterSpec(label: 'Classic meter')],
    ).toBlock();
    final html = MarpHtmlService.renderCockpitBlocks(
      '```cockpit\n$block\n```',
      scheme: const CockpitColorScheme(
        name: 'Classic',
        visualStyle: CockpitVisualStyle.classic,
      ),
    );

    expect(html, contains('class="cockpit-svg classic"'));
    expect(html, contains('Classic meter'));
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

  group('bulletsImage split layout in HTML export', () {
    final service = MarpHtmlService(
      loadAsset: _diskLoader,
      loadBytes: _diskBytes,
    );

    Future<String> exportHtml(List<Slide> slides) {
      final md = MarkdownService().generateDeck(
        Deck(title: 'D', slides: slides),
        forExport: true,
      );
      return service.build(md);
    }

    test('section carries the split class', () async {
      final html = await exportHtml([
        Slide.create(SlideType.bulletsImage).copyWith(
          title: 'Punten',
          bullets: const ['Een', 'Twee'],
          imagePath: 'foto.png',
        ),
      ]);
      expect(html, contains('<section class="slide split"'));
    });

    test('split CSS rules are present in the export stylesheet', () async {
      final html = await exportHtml([
        Slide.create(SlideType.bulletsImage).copyWith(
          title: 'Punten',
          bullets: const ['Een'],
          imagePath: 'foto.png',
        ),
      ]);
      expect(html, contains('section.split{'));
      expect(html, contains('grid-template-columns'));
      expect(html, contains('section.split .split-image{'));
    });

    test('--image-width from _style lands on the section', () async {
      final html = await exportHtml([
        Slide.create(SlideType.bulletsImage).copyWith(
          title: 'Punten',
          bullets: const ['Een'],
          imagePath: 'foto.png',
          imageSize: 55,
        ),
      ]);
      expect(html, contains('--image-width:55%'));
    });

    test('a non-split slide does not get the split class', () async {
      final html = await exportHtml([
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Punten', bullets: const ['Een']),
      ]);
      expect(html, isNot(contains('class="slide split')));
    });
  });

  test(
    'een tijdlijndia wordt een tijdlijn, geen opsomming met dubbele punten',
    () {
      // De dubbele dubbele punt is de interne scheiding tussen datum, kop en
      // toelichting. Die stond letterlijk in het opgeleverde document.
      const slide =
          '<!-- _class: timeline -->\n\n# Verloop\n\n'
          '- 2024-01 :: Start :: kickoff met de klant\n'
          '- 2024-06 :: Rapport\n';
      final html = MarpHtmlService.renderTimelineBlocks(slide);

      expect(html, isNot(contains('::')));
      expect(html, contains('<ol class="timeline">'));
      expect(html, contains('2024-01'));
      expect(html, contains('kickoff met de klant'));
      expect(html, contains('# Verloop'), reason: 'de kop blijft markdown');
    },
  );

  test('een gewone opsomming blijft een gewone opsomming', () {
    const slide = '# Punten\n\n- eerste\n- tweede\n';
    expect(MarpHtmlService.renderTimelineBlocks(slide), slide);
  });

  test('de akkoordpagina draagt de verklaring, niet alleen een kop', () {
    // De ondertekening staat op dekniveau; de dia bewaart alleen een kop. De
    // export liet daardoor precies de pagina leeg waar de verklaring hoort.
    const deck =
        '---\nmarp: true\n'
        'ocideck_sig_name: "J. Tester"\n'
        'ocideck_sig_role: "Pentester"\n'
        'ocideck_sig_statement: "Naar waarheid opgesteld."\n'
        'ocideck_sig_typed: "J. Tester"\n'
        'ocideck_seal_at: "2026-07-20 10:00"\n'
        '---\n\n<!-- _class: sign-off -->\n\n# Akkoord\n';
    final fields = MarpHtmlService.signatureFields(deck);
    final html = MarpHtmlService.renderSignOffBlock(
      MarpHtmlService.marpSlides(deck).first,
      fields,
      sealedAt: fields['ocideck_seal_at'] ?? '',
    );

    expect(html, contains('Naar waarheid opgesteld.'));
    expect(html, contains('J. Tester'));
    expect(html, contains('Pentester'));
    expect(html, contains('2026-07-20 10:00'));
    expect(html, contains('# Akkoord'), reason: 'de kop blijft staan');
  });

  test('een onondertekende akkoordpagina zegt dat met zoveel woorden', () {
    const slide = '<!-- _class: sign-off -->\n\n# Akkoord\n';
    final html = MarpHtmlService.renderSignOffBlock(slide, const {});
    expect(html, contains('Nog niet ondertekend'));
    expect(html, contains('Nog niet verzegeld'));
  });

  test('andere dia\'s krijgen geen ondertekeningsblok', () {
    const slide = '# Gewoon\n\n- punt\n';
    expect(
      MarpHtmlService.renderSignOffBlock(slide, const {
        'ocideck_sig_name': 'J. Tester',
      }),
      slide,
    );
  });

  test('een geredigeerde media-slide toont een zwart vlak in de export', () {
    // De privacyprojectie zet mediaRedacted en leegt het beeldpad; de
    // serialisatie voor de export schrijft dan een marker, en de HTML-render
    // maakt daar een zichtbaar zwart vlak van — anders verdween het beeld
    // spoorloos terwijl de tekst wél zwarte blokken toonde.
    final slide = Slide.create(SlideType.bulletsImage).copyWith(
      title: 'Bewijs',
      bullets: const ['een waarneming'],
      imagePath: 'images/foto.png',
      mediaRedacted: true,
    );
    final md = MarkdownService().generateSlide(slide, forExport: true);
    expect(md, contains('ocideck_media_redacted'));

    final html = MarpHtmlService.renderMediaRedacted(md);
    expect(html, isNot(contains('ocideck_media_redacted')));
    expect(html, contains('class="media-redacted"'));
    expect(html, contains('Media verwijderd'));
  });

  test('zonder redactie komt er geen media-vlak en geen marker', () {
    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(title: 'Bewijs', imagePath: 'images/foto.png');
    final md = MarkdownService().generateSlide(slide, forExport: true);
    expect(md, isNot(contains('ocideck_media_redacted')));
    expect(MarpHtmlService.renderMediaRedacted(md), md);
  });

  test('de marker landt nooit in een bewaard bestand (forExport: false)', () {
    final slide = Slide.create(
      SlideType.bulletsImage,
    ).copyWith(title: 'Bewijs', mediaRedacted: true);
    // mediaRedacted bestaat alleen in de projectie, maar de poort staat óók op
    // forExport: een bewaarpad mag de marker nooit schrijven.
    expect(
      MarkdownService().generateSlide(slide),
      isNot(contains('ocideck_media_redacted')),
    );
  });

  group('rapportagedia\'s in de HTML-export', _reportingTests);
  group('afbeeldingen insluiten', _imageEmbedTests);
  group('video in de HTML-export', _videoTests);
}

// ── Rapportagedia's ────────────────────────────────────────────────────────
//
// Zes slidetypes bewaren hun inhoud als een Markdown-tabel en vielen in de
// export terug op precies dat. Deze tests bewaken dat elk van de zes zijn eigen
// weergave krijgt, en dat de afgeleide getallen — de teller boven een
// dekkingsbalk, de verandering op een scorecard — meekomen. Die zijn de reden
// dat een tabel niet volstaat: ze staan nergens in de rijen.

/// Bouwt de dia via de échte serialiser, zodat de test breekt zodra de
/// opslagvorm verandert in plaats van een handgeschreven tabel te bevestigen.
String _reportingSlideMarkdown(Slide slide) =>
    MarkdownService().generateSlide(slide, forExport: true);

void _reportingTests() {
  test('een scorecard wordt een reeks kaarten met de verandering', () {
    final slide = Slide.create(SlideType.scorecard).copyWith(
      title: 'Kerncijfers',
      tableRows: const [
        ['Label', 'Value', 'Previous', 'Unit', 'Polarity'],
        ['Open bevindingen', '12', '19', '', 'lower-better'],
        ['Dekking', '87', '74', '%', 'higher-better'],
      ],
    );
    final html = MarpHtmlService.renderReportingSlide(
      _reportingSlideMarkdown(slide),
    );

    expect(html, contains('rep-scorecard'));
    expect(html, contains('Open bevindingen'));
    // De verandering is afgeleid en staat nergens in de tabel: minder open
    // bevindingen is goed nieuws (lower-better), meer dekking ook.
    expect(html, contains('-7'));
    expect(html, contains('+13'));
    expect(html, contains(RegExp('color:#15803D')));
    // En de kale tabel is weg: dat was de hele klacht.
    expect(html, isNot(contains('| Open bevindingen |')));
  });

  test('een aanvalsoppervlak krijgt balken op één gedeelde schaal', () {
    final slide = Slide.create(SlideType.assets).copyWith(
      title: 'Aanvalsoppervlak',
      tableRows: const [
        ['Group', 'Total', 'AtRisk', 'New', 'Unowned'],
        ['Web', '200', '50', '3', '1'],
        ['Mail', '50', '0', '0', '0'],
      ],
    );
    final html = MarpHtmlService.renderReportingSlide(
      _reportingSlideMarkdown(slide),
    );

    expect(html, contains('rep-assets'));
    // Mail is een kwart van Web, niet even breed: de schaal is gedeeld.
    expect(html, contains('width:100.0%'));
    expect(html, contains('width:25.0%'));
    // Het totaal is afgeleid, niet ingetypt.
    expect(html, contains('>250<'));
  });

  test('een ontdekking zonder bekende blootstelling krijgt geen balk', () {
    final slide = Slide.create(SlideType.discoveries).copyWith(
      title: 'Ontdekkingen',
      tableRows: const [
        ['Discovery', 'Kind', 'DaysUnnoticed', 'Owner'],
        ['oud.klant.nl', 'Web', '420', ''],
        ['vpn.klant.nl', 'Infra', '', 'Team Netwerk'],
      ],
    );
    final html = MarpHtmlService.renderReportingSlide(
      _reportingSlideMarkdown(slide),
    );

    expect(html, contains('rep-discoveries'));
    // 420 dagen leest als 14 maanden, en dat is de kop van de dia.
    expect(html, contains('14 maanden'));
    expect(html, contains('langst onopgemerkt bereikbaar'));
    // "onbekend" is geen nul: een lege baan zou "meteen gevonden" beweren.
    expect(html, contains('onbekend'));
    expect('class="rep-bar"'.allMatches(html).length, 1);
    expect(html, contains('geen eigenaar'));
  });

  test('een checklist krijgt haar voortgang en gekleurde statuspillen', () {
    final slide = Slide.create(SlideType.checklist).copyWith(
      title: 'Checklist — OWASP WSTG',
      checklistScope: 'portaal.klant.nl',
      tableRows: const [
        ['ID', 'Test', 'Status', 'Finding', 'Note'],
        ['WSTG-INFO-01', 'Zoekmachines', 'Tested', '—', ''],
        ['WSTG-CONF-02', 'Beheerinterfaces', 'Anomaly', 'BEV-03', ''],
        ['WSTG-SESS-01', 'Sessiebeheer', '', '—', ''],
      ],
    );
    final html = MarpHtmlService.renderReportingSlide(
      _reportingSlideMarkdown(slide),
    );

    expect(html, contains('rep-checklist'));
    // 2 van de 3 getoetst — afgeleid, nergens opgeslagen.
    expect(html, contains('2/3 getoetst'));
    expect(html, contains('Scope-object'));
    expect(html, contains('portaal.klant.nl'));
    expect(html, contains('Afwijking'));
    // Een afwijking is rood, niet zomaar een woord in een kolom.
    expect(html, contains('color:#B91C1C'));
    expect(html, contains('BEV-03'));
  });

  test('een scope-matrix krijgt haar dekkingsteller en standaard', () {
    final slide = Slide.create(SlideType.scopeMatrix).copyWith(
      title: 'Scope-matrix',
      tableRows: const [
        ['Object', 'Type', 'Standard', 'Status', 'Note', 'C', 'I', 'A'],
        ['portaal.klant.nl', 'Web', 'WSTG', 'Tested', '', '', '', ''],
        ['app iOS', 'Mobile', 'MASTG', 'Unreachable', '', '', '', ''],
      ],
    );
    final html = MarpHtmlService.renderReportingSlide(
      _reportingSlideMarkdown(slide),
    );

    expect(html, contains('rep-scope'));
    // Onbereikbaar telt níét als getoetst — dat is de hele reden dat de teller
    // afgeleid is en niet opgeteld uit de rijen.
    expect(html, contains('1/2 gedekt'));
    expect(html, contains('MASTG'));
    expect(html, contains('Onbereikbaar'));
  });

  test('een bevindingenoverzicht wordt een staafje per ernstband', () {
    final slide = Slide.create(SlideType.findingsSummary).copyWith(
      title: 'Bevindingenoverzicht',
      tableRows: const [
        ['Severity', 'Count'],
        ['Critical', '2'],
        ['High', '4'],
        ['Medium', '8'],
        ['Low', '0'],
        ['None', '0'],
        ['Resolved', '5'],
      ],
    );
    final html = MarpHtmlService.renderReportingSlide(
      _reportingSlideMarkdown(slide),
    );

    expect(html, contains('rep-findings'));
    // 2 + 4 + 8 — afgeleid, en de hertest staat er los naast.
    expect(html, contains('Totaal: 14'));
    expect(html, contains('Opgelost na hertest: 5'));
    // De hoogste band vult de staaf; de rest schaalt eraan mee.
    expect(html, contains('height:100.0%'));
    expect(html, contains('height:25.0%'));
    expect(html, contains('Kritiek'));
    expect(html, contains('Informatief'));
  });

  test('een gewone dia komt onveranderd terug', () {
    const md = '# Gewone dia\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n';
    expect(MarpHtmlService.renderReportingSlide(md), md);
  });

  test('een opsomming met aankruisvakjes is geen checklist-dia', () {
    // De aankruislijst is een LIJSTSTIJL op een bullets-dia; het MIAUW-type
    // `checklist` is iets anders. Zou de export op het woord "checklist" gaan,
    // dan verdween hier de opsomming.
    final slide = Slide.create(SlideType.bullets).copyWith(
      title: 'Voorbereiding',
      listStyle: ListStyle.checklist,
      bullets: const ['[x] Scope afgestemd', '[ ] Testaccounts ontvangen'],
    );
    final md = _reportingSlideMarkdown(slide);
    expect(MarpHtmlService.renderReportingSlide(md), md);
  });

  test('een tabeldia blijft een tabel', () {
    final slide = Slide.create(SlideType.table).copyWith(
      title: 'Planning',
      tableRows: const [
        ['Fase', 'Datum'],
        ['Start', '2026-01'],
      ],
    );
    final md = _reportingSlideMarkdown(slide);
    expect(MarpHtmlService.renderReportingSlide(md), md);
  });

  test('de opmaak van de rapportagedia\'s zit in de export', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    final html = await service.build('# X');
    // Thema-onafhankelijk, dus altijd meegestuurd — dezelfde les als bij de
    // tijdlijn, die zijn opmaak verloor zodra er een thema meeging.
    expect(html, contains('.slide .rep-title'));
    expect(html, contains('.slide .sc-card'));
    expect(html, contains('.slide .fs-bar'));
  });
}

// ── Afbeeldingen insluiten ─────────────────────────────────────────────────
//
// "Self-contained" was niet waar voor een deck met beeld: de export droeg de
// paden van de auteur, en de ontvanger kreeg kapotte pictogrammen.

void _imageEmbedTests() {
  test('elke afbeelding gaat één keer mee, ook op tien dia\'s', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    const md =
        '# A\n\n![bg](images/achtergrond.png)\n\n---\n\n'
        '# B\n\n![bg](images/achtergrond.png)\n\n'
        '![Bewijs](images/bewijs.jpg)\n';
    final resolved = <String>[];
    final html = await service.build(
      md,
      embedImage: (source) async {
        resolved.add(source);
        return 'data:image/jpeg;base64,AAA${resolved.length}';
      },
    );

    // Geen enkel bronpad blijft over: dat is wat "self-contained" betekent.
    expect(html, isNot(contains('images/achtergrond.png')));
    expect(html, isNot(contains('images/bewijs.jpg')));
    // Twee bronnen, twee keer gelezen en twee keer ingesloten — niet drie. Een
    // achtergrond op veertig dia\'s mag het bestand niet veertig keer zo groot
    // maken, en hem veertig keer van schijf lezen is even zinloos.
    expect(resolved, hasLength(2));
    expect(html, contains('#ocideck-img-0'));
    expect(html, contains('#ocideck-img-1'));
    expect(html, isNot(contains('#ocideck-img-2')));
    expect('data:image/jpeg;base64,AAA'.allMatches(html).length, 2);
    // De alt-tekst blijft staan; die is het toegankelijkheidsanker.
    expect(html, contains('![Bewijs]'));
  });

  test('een afbeelding die niet mee kan, wordt een zichtbare melding', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    final html = await service.build(
      '# A\n\n![Foto](images/weg.png)\n',
      embedImage: (source) async => null,
    );

    // Zichtbaar, want een stille lege plek ziet de ontvanger over het hoofd.
    expect(html, contains('image-missing'));
    expect(html, contains('Afbeelding niet ingesloten'));
    // En het pad van de auteur blijft eruit: dat is zijn mappenstructuur, niet
    // iets wat de ontvanger hoeft te kennen.
    expect(html, isNot(contains('images/weg.png')));
    expect(html, contains('.slide .image-missing{'));
  });

  test('zonder insluiter blijft de markdown zoals hij was', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    final html = await service.build('# A\n\n![Foto](images/foto.png)\n');

    expect(html, contains('images/foto.png'));
    expect(html, contains('var OCIDECK_IMG=[]'));
  });

  test(
    'een bron die al een data:image-URI is wordt eenmaal ingesloten',
    () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      var calls = 0;
      final html = await service.build(
        '# A\n\n![Al ingesloten](data:image/gif;base64,R0lGOD)\n',
        embedImage: (source) async {
          calls++;
          return 'data:image/png;base64,ZZZ';
        },
      );

      expect(calls, 0);
      expect(
        RegExp('data:image/gif;base64,R0lGOD').allMatches(html),
        hasLength(1),
      );
      expect(html, contains('![Al ingesloten](#ocideck-img-0)'));
    },
  );

  test(
    'gelijke data:image-URI telt eenmaal, ook voor verschillende bronnen',
    () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      const uri = 'data:image/png;base64,AAAA';
      final html = await service.build(
        '# A\n\n![een]($uri)\n\n![twee](images/twee.png)\n',
        embedImage: (source) async => uri,
        maxEmbedBytes: uri.length,
      );

      expect(RegExp(uri).allMatches(html), hasLength(1));
      expect(html, contains('![een](#ocideck-img-0)'));
      expect(html, contains('![twee](#ocideck-img-0)'));
    },
  );

  test('een inline data:image-URI valt vroeg onder het cumulatieve budget', () {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    const uri = 'data:image/png;base64,AAAA';

    expect(
      () => service.build('# A\n\n![een]($uri)', maxEmbedBytes: uri.length - 1),
      throwsA(isA<HtmlEmbedBudgetExceeded>()),
    );
  });

  test('de plaatshouder wordt alleen door onze eigen lijst ingevuld', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    final html = await service.build(
      '# A\n\n![X](images/x.png)\n',
      embedImage: (source) async => 'data:image/png;base64,ZZZ',
    );

    // De index komt uit het document en is dus onbetrouwbaar: het renderscript
    // zet alleen een waarde die echt een data:image/-URI uit OCIDECK_IMG is.
    expect(html, contains("uri.indexOf('data:image/')===0"));
    expect(html, contains('OCIDECK_IMG'));
  });

  test('het cumulatieve insluitbudget valt op de grens en één byte '
      'erover (#1045)', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    const md =
        '# A\n\n![one](images/a.png)\n\n---\n\n# B\n\n![two](images/b.png)\n';
    const uriA = 'data:image/png;base64,AAAA';
    const uriB = 'data:image/png;base64,BBBB';
    Future<String?> resolve(String s) async =>
        s.endsWith('a.png') ? uriA : uriB;
    final total = uriA.length + uriB.length; // twee unieke beelden

    // Precies op de grens: het hele document wordt gebouwd.
    final ok = await service.build(
      md,
      embedImage: resolve,
      maxEmbedBytes: total,
    );
    expect(ok, contains('OCIDECK_IMG'));

    // Eén byte minder: de export weigert vóór geheugenuitputting.
    expect(
      () => service.build(md, embedImage: resolve, maxEmbedBytes: total - 1),
      throwsA(isA<HtmlEmbedBudgetExceeded>()),
    );
  });

  test(
    'een hergebruikt beeld telt één keer tegen het budget (#1045)',
    () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      // Dezelfde bron op twee dia's.
      const md =
          '# A\n\n![bg](images/zelfde.png)\n\n---\n\n'
          '# B\n\n![bg](images/zelfde.png)\n';
      const uri = 'data:image/png;base64,AAAA';
      var calls = 0;
      Future<String?> resolve(String s) async {
        calls++;
        return uri;
      }

      // Een budget voor één beeld volstaat: dedup telt de bron één keer, dus de
      // grens ziet niet twee kopieën.
      final html = await service.build(
        md,
        embedImage: resolve,
        maxEmbedBytes: uri.length,
      );
      expect(calls, 1);
      expect(html, contains('OCIDECK_IMG'));
    },
  );
}

// ── Video ──────────────────────────────────────────────────────────────────

void _videoTests() {
  test('een lokale video wordt een zichtbare melding', () {
    final slide = Slide.create(
      SlideType.video,
    ).copyWith(title: 'Demo', videoPath: 'media/demo.mp4');
    final md = MarkdownService().generateSlide(slide, forExport: true);
    expect(md, contains('<video'), reason: 'de opslagvorm is een speler');

    final html = MarpHtmlService.renderVideoNotice(md);
    // Een speler die naar een bestand wijst dat de ontvanger niet heeft, blijft
    // zwart en zegt niets. De melding zegt tenminste dát er iets ontbreekt.
    expect(html, isNot(contains('<video')));
    expect(html, contains('Video niet ingesloten'));
    expect(html, contains('media-absent'));
  });

  test('een YouTube-insluiting wordt dezelfde melding', () {
    final slide = Slide.create(
      SlideType.video,
    ).copyWith(videoPath: 'https://www.youtube.com/watch?v=aaaaaaaaaaa');
    final md = MarkdownService().generateSlide(slide, forExport: true);
    expect(md, contains('ocideck-embed'));

    final html = MarpHtmlService.renderVideoNotice(md);
    // De CSP van de export zet frame-src 'none', dus de speler kan hier niet
    // werken — een leeg vak zonder uitleg was het gevolg.
    expect(html, isNot(contains('<iframe')));
    expect(html, contains('Video niet ingesloten'));
    // De letterlijke URL die de serialiser eronder schrijft blijft staan, dus
    // de bron zelf is nog te bereiken.
    expect(html, contains('youtube.com/watch'));
  });

  test('een dia zonder video blijft ongemoeid', () {
    const md = '# Gewone dia\n\nTekst.\n';
    expect(MarpHtmlService.renderVideoNotice(md), md);
  });

  test('cockpit-export volgt het dia-thema (licht vs donker)', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    const deck =
        '# Cockpit\n\n'
        '```cockpit\n'
        '{"meters":[{"type":"speedometer","label":"Cap","value":78},'
        '{"type":"heading","label":"Koers","value":187,"heading":90}]}\n'
        '```\n';
    final light = await service.build(
      deck,
      theme: const ThemeProfile(slideBackgroundColor: '#FFFFFF'),
      fallbackTitle: 'deck',
    );
    final dark = await service.build(
      deck,
      theme: const ThemeProfile(slideBackgroundColor: '#0F172A'),
      fallbackTitle: 'deck',
    );

    // Beide renderen een cockpit-SVG.
    expect(light, contains('class="cockpit-svg'));
    expect(dark, contains('class="cockpit-svg'));

    // Lichte dia → licht instrumentpaneel; donkere dia → het zwarte. De
    // export volgt zo hetzelfde dia-thema als de app-render.
    expect(light, contains('#CED2D6'));
    expect(light, isNot(contains('#202223')));
    expect(dark, contains('#202223'));
    expect(dark, isNot(contains('#CED2D6')));

    // De hardgecodeerde Engelse header hoort nergens meer te staan.
    expect(light, isNot(contains('COCKPIT VIEW')));
    expect(dark, isNot(contains('COCKPIT VIEW')));
  });

  // WCAG 2.1 SC 3.1.1: de HTML-export moet <html lang="…"> op de taal van de
  // inhoud zetten. De chrome-strings volgen AppLocalizations.languageCode (een
  // bibliotheek-brede static); ExportService zet die tijdelijk op de
  // exporttaal — hier stellen we haar zelf in om de builder los te toetsen. #1249
  group('HTML-export taal (WCAG 3.1.1, #1249)', () {
    test('<html lang> volgt htmlLang, niet het Nederlands', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build('# Titel\n', htmlLang: 'fi');

      expect(html, contains('<html lang="fi">'));
      expect(html, isNot(contains('<html lang="nl">')));
    });

    test('build() zonder taal valt terug op <html lang="nl">', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build('# Titel\n');

      expect(html, contains('<html lang="nl">'));
    });

    test('chrome-strings volgen de actieve taalcode', () async {
      AppLocalizations.setActiveLanguageCode('en');
      addTearDown(() => AppLocalizations.setActiveLanguageCode('nl'));
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build('# Titel\n');

      // De licentie-samenvatting en de mermaid-labels zijn chrome: ze horen
      // in de actieve taal te staan, niet in het Nederlands.
      expect(html, contains('Third-party licences'));
      expect(html, contains('This diagram could not be drawn'));
      expect(html, isNot(contains('Licenties van derden')));
    });
  });

  // WCAG 2.1 SC 1.3.1 (Info en relaties) en 2.4.1 (Blokken omzeilen): de
  // HTML-export is de aanbevolen route voor wie leest in plaats van kijkt, dus
  // het document heeft landmarks en een titel nodig — anders is het voor een
  // schermlezer één platte rij dia's zonder ingang. #1250
  group('HTML-export documentstructuur (WCAG 1.3.1/2.4.1, #1250)', () {
    test(
      'wikkel de dia\'s in <main> met een visueel-verborgen <h1>-titel',
      () async {
        final service = MarpHtmlService(loadAsset: _diskLoader);
        final html = await service.build(
          '# Mijn deck\n',
          metadata: const ExportDocumentMetadata(title: 'Mijn deck'),
          fallbackTitle: 'Voorraad',
        );

        // <main> als landmark rond de secties.
        expect(html, contains('<main>'));
        expect(html, contains('</main>'));
        // De secties staan binnen <main>, ná de h1.
        final mainStart = html.indexOf('<main>');
        final firstSection = html.indexOf('<section class="slide');
        final mainEnd = html.indexOf('</main>');
        expect(mainStart, lessThan(firstSection));
        expect(firstSection, lessThan(mainEnd));

        // Een document-h1 met de decktitel, visueel verborgen.
        expect(html, contains('<h1 class="ocideck-sr-only">Mijn deck</h1>'));
        // De sr-only-regel staat in de structural CSS.
        expect(html, contains('.ocideck-sr-only{'));
      },
    );

    test('valt terug op fallbackTitle wanneer de decktitel leeg is', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(
        '\n\nEerste dia zonder kop\n',
        fallbackTitle: 'Presentatie',
      );

      expect(html, contains('<h1 class="ocideck-sr-only">Presentatie</h1>'));
    });

    test('ontsnapt de titel als tekstinhoud, niet als attribuut', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(
        '# A & B <script>\n',
        fallbackTitle: 'A & B <script>',
      );

      // _htmlText ontsnapt & en <, dus geen ruwe <script> in de h1-inhoud.
      expect(
        html,
        contains('<h1 class="ocideck-sr-only">A &amp; B &lt;script&gt;</h1>'),
      );
    });
  });
}
