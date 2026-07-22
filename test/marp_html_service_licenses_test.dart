import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/bundled_licenses.dart';
import 'package:ocideck/services/marp_html_service.dart';

Future<String> _diskLoader(String asset) => File(asset).readAsString();
Future<Uint8List> _diskBytes(String asset) => File(asset).readAsBytes();

/// An HTML export makes the **user** the distributing party: they mail a single
/// file that carries five third-party JavaScript bundles and, with the bundled
/// deck font, an embedded typeface. They can only meet MIT/BSD/Apache/OFL if the
/// notices are in the file — and they were not.
///
/// marked, highlight.js and DOMPurify happen to keep a banner in their minified
/// build; MathJax and Mermaid do not, so 5.4 MB of the export identified itself
/// as nothing at all. And the base64 `@font-face` shipped EB Garamond with no
/// OFL notice anywhere, which OFL-1.1 §2 does not permit.
void main() {
  const md = '# Titel\n\nTekst.\n';

  Future<String> buildExport({ThemeProfile? theme}) => MarpHtmlService(
    loadAsset: _diskLoader,
    loadBytes: _diskBytes,
  ).build(md, theme: theme);

  test('every inlined bundle carries a licence banner', () async {
    final html = await buildExport();
    final manifest =
        jsonDecode(File('assets/web_export/MANIFEST.json').readAsStringSync())
            as Map<String, dynamic>;
    for (final b
        in (manifest['bundles'] as List).cast<Map<String, dynamic>>()) {
      final npm = b['npm'] as String?;
      if (npm == null) continue;
      final entry = BundledLicenses.forNpm(npm)!;
      expect(
        html,
        contains('@license ${entry.component} ${b['version']}'),
        reason:
            'No licence banner for $npm in the export. Without it a recipient '
            'cannot tell what they were handed, or under which terms.',
      );
    }
  });

  test('the banner names the licence and where the full text is', () async {
    final html = await buildExport();
    // MathJax and Mermaid are the two that ship without an upstream banner —
    // the exact gap this guards.
    //
    // The version comes from the manifest, not from a literal here. It used to
    // be hard-coded, and the mermaid 10.9.6 -> 11.16.0 upgrade broke this test
    // for a reason that had nothing to do with what it guards: whether a
    // synthesised banner names the licence and points at the source.
    final manifest =
        jsonDecode(File('assets/web_export/MANIFEST.json').readAsStringSync())
            as Map<String, dynamic>;
    String versionOf(String npm) =>
        (manifest['bundles'] as List).cast<Map<String, dynamic>>().firstWhere(
              (b) => b['npm'] == npm,
            )['version']
            as String;

    expect(
      html,
      contains('@license MathJax ${versionOf('mathjax')} — Apache-2.0'),
    );
    expect(html, contains('@license Mermaid ${versionOf('mermaid')} — MIT'));
    expect(html, contains('github.com/mathjax/MathJax'));
    expect(html, contains('github.com/mermaid-js/mermaid'));
  });

  test('the export carries the full licence text of every bundle', () async {
    final html = await buildExport();
    expect(html, contains('Licenties van derden'));
    // A distinctive line from each licence family, so a pointer-only notice
    // (which is what a banner is) cannot satisfy this test.
    expect(html, contains('Permission is hereby granted')); // MIT
    expect(html, contains('Redistribution and use')); // BSD-3-Clause
    expect(html, contains('Apache License')); // Apache-2.0
  });

  test('the OFL notice appears exactly when the font is embedded', () async {
    const garamond = ThemeProfile(fontFamily: 'EB Garamond');
    const system = ThemeProfile(fontFamily: 'Helvetica');

    final withFont = await buildExport(theme: garamond);
    expect(withFont, contains('data:font/ttf;base64,'));
    expect(
      withFont,
      contains('SIL OPEN FONT LICENSE'),
      reason:
          'The export embeds EB Garamond as base64. OFL-1.1 §2 only permits '
          'that together with the copyright notice and the licence.',
    );

    final withoutFont = await buildExport(theme: system);
    expect(withoutFont, isNot(contains('data:font/ttf;base64,')));
    expect(
      withoutFont,
      isNot(contains('SIL OPEN FONT LICENSE')),
      reason: 'No font is embedded, so claiming an OFL notice would be noise.',
    );
  });

  test('the notice block does not disturb the deck', () async {
    final html = await buildExport();
    // Collapsed by default and hidden in print: the notice lives in the file,
    // not on a printed slide.
    expect(html, contains('<details class="ocideck-licenses">'));
    expect(html, isNot(contains('<details class="ocideck-licenses" open')));
    expect(html, contains('@media print{.ocideck-licenses{display:none}}'));
    // It sits after the render script, which only ever touches section.slide.
    expect(
      html.indexOf('ocideck-licenses'),
      greaterThan(html.indexOf('section.slide')),
    );
  });

  test('licence text is HTML-escaped, never injected raw', () async {
    final html = await buildExport();
    // The OFL text contains "<http://…>" style angle brackets; if any survived
    // unescaped the browser would try to parse them as tags.
    final block = html.substring(html.indexOf('ocideck-licenses'));
    expect(block.contains('<pre>'), isTrue);
    final texts = RegExp(
      r'<pre>([\s\S]*?)</pre>',
    ).allMatches(block).map((m) => m.group(1)!);
    expect(texts, isNotEmpty);
    for (final t in texts) {
      expect(t.contains('<'), isFalse, reason: 'Unescaped "<" in a notice.');
      expect(t.contains('>'), isFalse, reason: 'Unescaped ">" in a notice.');
    }
  });
}
