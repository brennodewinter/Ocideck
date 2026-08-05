import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_kind.dart';

void main() {
  test('key en fromKey round-trippen voor elke soort', () {
    for (final kind in MarkdownKind.values) {
      expect(MarkdownKindX.fromKey(kind.key), kind);
    }
  });

  test('onbekende of ontbrekende sleutel valt terug op presentatie', () {
    expect(MarkdownKindX.fromKey(null), MarkdownKind.presentation);
    expect(MarkdownKindX.fromKey(''), MarkdownKind.presentation);
    expect(MarkdownKindX.fromKey('deck'), MarkdownKind.presentation);
  });

  test('sleutel wordt genormaliseerd (spaties, hoofdletters)', () {
    expect(MarkdownKindX.fromKey(' DOCUMENT '), MarkdownKind.document);
  });

  test('isDocument en isPresentation', () {
    expect(MarkdownKind.document.isDocument, isTrue);
    expect(MarkdownKind.document.isPresentation, isFalse);
    expect(MarkdownKind.presentation.isPresentation, isTrue);
    expect(MarkdownKind.presentation.isDocument, isFalse);
  });
}
