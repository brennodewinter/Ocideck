import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/marp_html_service.dart';

/// Regression guard for the HTML export's defence-in-depth: a strict,
/// nonce-based Content-Security-Policy plus neutralisation of any `</script>`
/// an untrusted deck injects. These are the Dart-side guarantees; DOMPurify
/// does the runtime DOM sanitisation when the file is opened.
void main() {
  // Stub the vendored JS bundles so the test is hermetic and fast — the CSP /
  // script-guard logic under test does not depend on their contents.
  final service = MarpHtmlService(
    loadAsset: (asset) async => '/* stub: $asset */',
    loadBytes: (asset) async => Uint8List(0),
  );

  const malicious = '''# Title

Normal text.

</script><script>alert('xss')</script>

<img src=x onerror="alert('xss')">
''';

  test('HTML export ships a strict, nonce-based CSP', () async {
    final html = await service.build(malicious, fallbackTitle: 'Test');

    final cspMatch = RegExp(
      r'<meta http-equiv="Content-Security-Policy" content="([^"]*)"',
    ).firstMatch(html);
    expect(cspMatch, isNotNull, reason: 'the export must carry a CSP');
    final csp = cspMatch!.group(1)!;

    expect(csp, contains("script-src 'nonce-"));
    expect(csp, contains("object-src 'none'"));
    expect(csp, contains("frame-src 'none'"));
    expect(csp, contains("base-uri 'none'"));
    // A surviving <img src="https://…"> or CSS url() must not beacon out.
    expect(csp, contains("connect-src 'none'"));
    expect(csp, contains('img-src'));
    expect(csp, isNot(contains("img-src 'self' data: blob: file: https:")));
    // Every other network-capable resource type is pinned to local sources too,
    // so remote media, a hostile @font-face, or a planted form can't beacon out
    // when the exported file is opened.
    expect(csp, contains("media-src 'self' data: blob: file:"));
    expect(csp, contains("font-src 'self' data:"));
    expect(csp, contains("form-action 'none'"));
    // None of these may quietly widen to a remote origin.
    expect(csp, isNot(contains('https:')));
    expect(csp, isNot(contains("'unsafe-inline'")));
    expect(csp, isNot(contains("'unsafe-eval'")));
    expect(csp, isNot(contains("script-src 'self'")));

    // The executable scripts carry that exact nonce.
    final nonce = RegExp(
      r"script-src 'nonce-([^']+)'",
    ).firstMatch(csp)!.group(1)!;
    expect(html, contains('<script nonce="$nonce">'));
  });

  test(
    'injected </script> cannot break out of the markdown data holder',
    () async {
      final html = await service.build(malicious, fallbackTitle: 'Test');

      // Every closing script tag from deck content is escaped, so the injected
      // payload can never terminate the inert `type="text/markdown"` holder.
      expect(html, isNot(contains("</script><script>alert")));
      expect(html, contains(r'<\/script>'));
    },
  );

  group('script data escaped state', () {
    // `</script` is niet de enige uitgang uit een script-element. Een `<!--`
    // zet de HTML-tokenizer in *script data escaped*, een daaropvolgende
    // `<script` in *double escaped* — en dáár sluit een echte `</script>` het
    // element niet meer. Alles erna, inclusief het renderscript dat de
    // markdown-houders zichtbaar maakt, werd scripttekst: de export opende als
    // een lege witte pagina. Een codedia die kwetsbare paginabron citeert
    // bevat routineus precies deze twee.
    const trigger = '''# Titel

```html
<!-- oude tracker, uitgezet
<script src="t.js"></script>
```
''';

    List<String> holdersOf(String html) => RegExp(
      r'<script type="text/markdown">([\s\S]*?)</script>',
    ).allMatches(html).map((m) => m.group(1)!).toList();

    test('geen ongemaskeerde uitgang in de markdown-lading', () async {
      final html = await service.build(trigger, fallbackTitle: 'Test');
      final holders = holdersOf(html);
      expect(holders, isNotEmpty);
      for (final h in holders) {
        expect(h, isNot(contains('<!--')), reason: 'opent escaped state');
        expect(
          h,
          isNot(matches(RegExp('</script', caseSensitive: false))),
          reason: 'sluit het element voortijdig',
        );
      }
    });

    test('het renderscript overleeft de dia', () async {
      final html = await service.build(trigger, fallbackTitle: 'Test');
      expect(html, contains("querySelectorAll('section.slide')"));
    });

    test('de ontsnapping wordt in de browser teruggedraaid', () async {
      // Zonder terugdraai zou een `<!-- _class: … -->` als zichtbare tekst met
      // backslash in het document belanden — en dat gold al voor `</script`,
      // dat werd ontsnapt maar nooit hersteld.
      final html = await service.build(trigger, fallbackTitle: 'Test');
      expect(html, contains(r"split('<\\/').join('</')"));
      expect(html, contains(r"split('<\\!--').join('<!--')"));
    });

    test('echte JavaScript wordt niet met <\\!-- gesloopt', () async {
      // In JavaScript is `<!--` een geldige legacy-regelcommentaar en `<\!--`
      // een syntaxfout; de gebundelde bibliotheken mogen die stap niet krijgen.
      final withComment = MarpHtmlService(
        loadAsset: (asset) async => 'var a = 1; <!-- legacy\nvar b = 2;',
        loadBytes: (asset) async => Uint8List(0),
      );
      final html = await withComment.build('# T', fallbackTitle: 'Test');
      expect(html, contains('<!-- legacy'));
      expect(html, isNot(contains(r'<\!-- legacy')));
    });
  });
}
