import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/document_deck_bridge.dart';
import 'package:ocideck/services/document_footnote_setup.dart';
import 'package:ocideck/services/footnotes_html.dart';
import 'package:ocideck/services/latex/markdown_to_latex.dart';

/// De twee exportwegen van een voetnoot. LaTeX kan wat papier kan — de noot
/// onderaan het blad; HTML kent geen bladzijden en zet ze achteraan, met een
/// sprong heen en terug.
void main() {
  const md = '''
# Rapport

Een zin met een noot [^1] erin.

[^1]: De **noot** zelf.
''';

  group('LaTeX', () {
    test('onderaan de bladzijde wordt het een echte \\footnote', () {
      final tex = markdownToLatex(md);
      expect(tex, contains(r'\footnote{De \textbf{noot} zelf.}'));
      // De definitieregel is geen alinea meer.
      expect(tex, isNot(contains(r'[\^{}1]:')));
    });

    test('achterin wordt het een merkteken plus een lijst', () {
      final tex = markdownToLatex(
        md,
        footnotePlacement: FootnotePlacement.document,
        endnotesTitle: 'Noten',
      );
      expect(tex, contains(r'\textsuperscript{1}'));
      expect(tex, contains(r'\section*{Noten}'));
      expect(tex, contains(r'\begin{enumerate}'));
      expect(tex, isNot(contains(r'\footnote{')));
    });

    test('zonder voetnoten verandert de uitvoer niet', () {
      const plain = '# Kop\n\nGewone tekst.\n';
      expect(markdownToLatex(plain), markdownToLatex(plain));
      expect(markdownToLatex(plain), isNot(contains('footnote')));
    });
  });

  group('HTML', () {
    test('de verwijzing wordt een sup met een sprong naar de noot', () {
      final html = documentWithHtmlFootnotes(md, title: 'Noten');
      expect(html, contains('<sup class="ocideck-fnref" id="fnref-1">'));
      expect(html, contains('href="#fn-1"'));
      expect(html, contains('<li id="fn-1">'));
      // En terug: een noot achteraan is alleen bruikbaar met een weg terug.
      expect(html, contains('href="#fnref-1"'));
      // De opmaak binnen de noot blijft opmaak.
      expect(html, contains('<strong>noot</strong>'));
      expect(html, isNot(contains('[^1]:')));
    });

    test('zonder voetnoten blijft de tekst zoals hij was', () {
      const plain = '# Kop\n\nGewone tekst met [^abc] zonder definitie.\n';
      expect(documentWithHtmlFootnotes(plain, title: 'Noten'), plain);
    });
  });

  test('de projectie naar een deck en terug houdt de noten heel', () {
    // De export loopt via een getypeerd Deck (de privacygrens); een voetnoot
    // moet die reis overleven, anders staat hij niet in de uitvoer.
    final deck = DocumentDeckBridge.documentToDeck(md, title: 'Rapport');
    final back = DocumentDeckBridge.deckToDocumentMarkdown(deck);
    expect(back, contains('[^1]'));
    expect(back, contains('[^1]: De **noot** zelf.'));
  });
}
