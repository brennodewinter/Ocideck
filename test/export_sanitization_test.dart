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
}
