import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/sanitize_svg.dart';

void main() {
  test('keeps a simple SVG intact', () {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10"/></svg>';
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

  test('returns null for non-svg markup', () {
    expect(sanitizeMermaidSvg('<html></html>'), isNull);
    expect(sanitizeMermaidSvg(''), isNull);
  });
}
