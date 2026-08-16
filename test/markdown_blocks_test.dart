import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/markdown_blocks.dart';

/// De gedeelde ` ```chart `-fence (`markdown_blocks.dart`): één bron voor de
/// editor, de HTML-export en de grafiek-hydratie. (GFM-tabellen worden getoetst
/// bij hun codec, `markdown_table_codec.dart`.)
void main() {
  group('chartFencePattern', () {
    test('vangt een ```chart-blok en levert de kale spec in groep 1', () {
      final m = chartFencePattern.firstMatch('# K\n\n```chart\nSPEC\n```\n');
      expect(m, isNotNull);
      expect(m!.group(1), 'SPEC');
    });

    test('telt meerdere blokken', () {
      const src = '```chart\nA\n```\n\ntekst\n\n```chart\nB\n```\n';
      final specs = chartFencePattern
          .allMatches(src)
          .map((m) => m.group(1))
          .toList();
      expect(specs, ['A', 'B']);
    });

    test('een niet-chart fence matcht niet', () {
      expect(
        chartFencePattern.hasMatch('```mermaid\ngraph TD;\n```\n'),
        isFalse,
      );
    });
  });

  group('markdownImageAlt', () {
    test('laat een gewoon bijschrift staan', () {
      expect(markdownImageAlt('Een kade bij avond'), 'Een kade bij avond');
    });

    test('strippen van blokhaken houdt de afbeeldingsverwijzing heel', () {
      // Zonder strippen sluit de `]` de alt-tekst af en valt de rest van het
      // bijschrift als losse tekst naast de afbeelding.
      final alt = markdownImageAlt('Grafiek [2026] jaarcijfers');
      expect(alt, 'Grafiek 2026 jaarcijfers');
      expect('![$alt](foto.png)', '![Grafiek 2026 jaarcijfers](foto.png)');
    });

    test('een leeg bijschrift blijft leeg', () {
      expect(markdownImageAlt(''), '');
    });
  });
}
