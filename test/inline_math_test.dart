import 'package:material_ui/material_ui.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/inline_markdown.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';

/// Inline-`$…$`-wiskunde in een tekstregel (bullets/richText/free-markdown).
///
/// De parser is bewust widget-vrij; hij markeert alleen een math-run. De
/// widgetlaag tekent die als echte formule. De guard houdt valuta (`$5`) en
/// losse dollartekens tekst — alleen inhoud met een LaTeX-commando telt als
/// wiskunde, zodat bestaande decks met bedragen niet ineens formules tonen.
void main() {
  group('parser', () {
    test('herkent inline-math met een LaTeX-commando als een math-run', () {
      final runs = parseInlineRuns(r'een kat spint rond $f \approx 25$ Hz');
      final math = runs.where((r) => r.math).toList();
      expect(math, hasLength(1));
      expect(math.single.text, r'f \approx 25');
      // De tekst eromheen blijft gewone runs.
      expect(runs.first.math, isFalse);
      expect(runs.last.math, isFalse);
    });

    test('laat valuta met rust', () {
      for (final s in [
        r'dat kost $5',
        r'$5 tot $10 per stuk',
        r'prijs: $1000',
      ]) {
        expect(
          parseInlineRuns(s).any((r) => r.math),
          isFalse,
          reason: 'valuta zou geen wiskunde mogen worden: $s',
        );
      }
    });

    test('een ontsnapte dollar blijft tekst', () {
      final runs = parseInlineRuns(r'prijs \$5 en \$10');
      expect(runs.any((r) => r.math), isFalse);
      expect(runs.map((r) => r.text).join(), r'prijs $5 en $10');
    });

    test('negeert blokwiskunde met dubbele dollar', () {
      expect(parseInlineRuns(r'zie $$x=y$$ hier').any((r) => r.math), isFalse);
    });

    test('een onafgesloten dollar blijft tekst', () {
      expect(
        parseInlineRuns(r'los teken $ en \alpha').any((r) => r.math),
        isFalse,
      );
    });
  });

  testWidgets('de widgetlaag tekent een inline-formule als Math', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: InlineMarkdownText(
              r'spint rond $f \approx 25\ \text{Hz}$, precies goed',
              style: const TextStyle(fontSize: 24, color: Colors.black),
              linkColor: Colors.blue,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    tester.takeException(); // eventuele horizontale overflow is ruis
    expect(find.byType(Math), findsOneWidget);
    // De omringende tekst staat er nog gewoon (in de RichText).
    expect(find.byType(RichText), findsWidgets);
  });

  testWidgets('valuta rendert géén Math-widget', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: InlineMarkdownText(
              r'dat kost $5 en $10',
              style: const TextStyle(fontSize: 24, color: Colors.black),
              linkColor: Colors.blue,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Math), findsNothing);
  });
}
