import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/marp_html_service.dart';

void main() {
  test('exports the example deck for the browser accessibility check', () async {
    final deck = Deck(
      title: 'Workshop handout',
      language: 'en',
      slides: [
        Slide.create(SlideType.table).copyWith(
          title: 'Stock',
          tableRows: [
            ['Item', 'Count'],
            ['Pencils', '8'],
          ],
        ),
        Slide.create(SlideType.chart).copyWith(
          title: 'Workshop sales',
          customMarkdown: const ChartSpec(
            title: 'Workshop sales',
            x: ['January', 'February'],
            series: [
              ChartSeries(name: 'Sales', data: [120, 138]),
            ],
          ).toBlock(),
        ),
        Slide.create(SlideType.freeMarkdown).copyWith(
          customMarkdown: r'''
## Method

[Start the workshop](#method)

```mermaid
flowchart LR
  accTitle: Workshop flow
  Collect --> Review
```

[Review the method](#method)
''',
        ),
        Slide.create(SlideType.bulletsImage).copyWith(
          title: 'Parts',
          anchor: 'parts',
          imagePath: 'fixture.png',
          imageAltText: 'Grey workshop control panel',
          bullets: ['Switch (A)'],
          callouts: const [
            ImageCallout(
              reference: 'A',
              description: 'Power switch',
              targets: [CalloutPoint(0.4, 0.3)],
            ),
          ],
        ),
        Slide.create(SlideType.bullets).copyWith(
          title: 'Next steps',
          bullets: ['Collect feedback', 'Update the plan'],
          calloutReveal: BulletRevealMode.steps,
        ),
      ],
    );
    final markdown = MarkdownService().generateDeck(deck, forExport: true);
    final html =
        await MarpHtmlService(
          loadAsset: (asset) => File(asset).readAsString(),
        ).build(
          markdown,
          fallbackTitle: deck.title,
          htmlLang: deck.language,
          theme: deck.themeProfile,
          embedImage: (_) async =>
              'data:image/png;base64,'
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBAAjRN8sAAAAASUVORK5CYII=',
        );
    final target = File('build/html-a11y/fixture.html');
    await target.parent.create(recursive: true);
    await target.writeAsString(html);
  });
}
