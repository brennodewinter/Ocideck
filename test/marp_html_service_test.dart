import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/marp_html_service.dart';

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
  });

  test('build() neutralises a closing-script breakout in content', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    final html = await service.build('# X\n\nfoo </script> bar');
    // The literal breakout must be escaped so it cannot terminate the payload.
    expect(html, isNot(contains('foo </script> bar')));
    expect(html, contains(r'<\/script'));
  });

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
}
