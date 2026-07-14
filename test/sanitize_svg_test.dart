import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/sanitize_svg.dart';

void main() {
  test('keeps a simple SVG intact', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10"/></svg>';
    final safe = sanitizeMermaidSvg(svg);
    expect(safe, contains('<svg'));
    expect(safe, contains('<rect'));
  });

  test('removes script elements', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script><rect/></svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe, isNot(contains('<script')));
    expect(safe, contains('<rect'));
  });

  test('removes foreignObject and event handlers', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<foreignObject><body onclick="x()">bad</body></foreignObject>'
        '<rect onclick="evil()"/>'
        '</svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe, isNot(contains('foreignObject')));
    expect(safe, isNot(contains('onclick')));
  });

  test('strips javascript: href values', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<a href="javascript:alert(1)"><text>link</text></a>'
        '</svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe, isNot(contains('javascript:')));
  });

  test('strips javascript: hidden behind an in-scheme control character', () {
    // Browsers ignore ASCII whitespace/control chars inside a URL scheme, so
    // `java<newline>script:` still executes. XML attribute normalisation turns
    // the newline into a space; a naive `startsWith('javascript:')` misses both.
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<a href="java\nscript:alert(1)"><text>x</text></a>'
        '<a xlink:href="java\tscript:alert(2)"><text>y</text></a>'
        '</svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe.toLowerCase(), isNot(contains('script:alert')));
  });

  test('strips javascript: hidden behind a numeric character reference', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<a href="java&#10;script:alert(1)"><text>x</text></a>'
        '</svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe.toLowerCase(), isNot(contains('script:alert')));
  });

  test('strips vbscript: URLs', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<a href="vbscript:MsgBox(1)"><text>x</text></a>'
        '</svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe.toLowerCase(), isNot(contains('vbscript:')));
  });

  test('returns null for non-svg markup', () {
    expect(sanitizeMermaidSvg('<html></html>'), isNull);
    expect(sanitizeMermaidSvg(''), isNull);
  });
}
