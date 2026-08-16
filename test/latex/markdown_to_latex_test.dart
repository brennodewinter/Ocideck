// Self-check voor de Markdown→LaTeX-kernconverter. Bewijst per constructie dat
// de uitvoer klopt: koppen, lijsten, tabellen, code, wiskunde-pass-through,
// inline-opmaak, links, en LaTeX-escaping.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart' show TableBorderStyle;
import 'package:ocideck/services/latex/markdown_to_latex.dart';

void main() {
  group('markdownToLatex', () {
    test('koppen worden \\section / \\subsection', () {
      final out = markdownToLatex('# Titel\n\n## Sub');
      expect(out, contains(r'\section{Titel}'));
      expect(out, contains(r'\subsection{Sub}'));
    });

    test('ongeordende lijst wordt itemize', () {
      final out = markdownToLatex('- Appel\n- Peer');
      expect(out, contains(r'\begin{itemize}'));
      expect(out, contains(r'\item Appel'));
      expect(out, contains(r'\item Peer'));
      expect(out, contains(r'\end{itemize}'));
    });

    test('geordende lijst wordt enumerate', () {
      final out = markdownToLatex('1. Eerst\n2. Daarna');
      expect(out, contains(r'\begin{enumerate}'));
      expect(out, contains(r'\item Eerst'));
      expect(out, contains(r'\end{enumerate}'));
    });

    test('GFM-tabel wordt tabular met booktabs', () {
      final out = markdownToLatex(
        '| Naam | Leeftijd |\n| --- | --- |\n| Jan | 30 |\n| Piet | 25 |\n',
      );
      expect(out, contains(r'\begin{tabular}{ll}'));
      expect(out, contains(r'\toprule'));
      expect(out, contains(r'\textbf{Naam}'));
      expect(out, contains(r'\textbf{Leeftijd}'));
      expect(out, contains(r'\midrule'));
      expect(out, contains(r'\bottomrule'));
      expect(out, contains('Jan'));
      expect(out, contains('30'));
    });

    test('een rij houdt precies zoveel cellen als de kolomspec', () {
      // De rij eindigde op ' & ' (elke cel schrijft die scheiding áchter zich)
      // en het opruimpatroon ankerde op een `&` als láátste teken. Resultaat:
      // `Naam & Leeftijd &  \\` — één cel te veel voor `{ll}`, wat LaTeX niet
      // scheef rendert maar weigert ("Extra alignment tab"). De test hierboven
      // stond al die tijd groen, want `contains` ziet het verschil niet.
      final out = markdownToLatex(
        '| Naam | Leeftijd |\n| --- | --- |\n| Jan | 30 |\n',
      );
      expect(out, contains('\\textbf{Naam} & \\textbf{Leeftijd} \\\\'));
      expect(out, contains('Jan & 30 \\\\'));
      expect(out, isNot(contains('& \\\\')));
      for (final line in out.split('\n').where((l) => l.contains('&'))) {
        expect(
          '&'.allMatches(line).length,
          1,
          reason: 'rij "$line" hoort één scheiding te dragen bij twee kolommen',
        );
      }
    });

    test(
      'de midrule staat onder de koprij, niet onder de eerste gegevensrij',
      () {
        final out = markdownToLatex(
          '| Naam | Leeftijd |\n| --- | --- |\n| Jan | 30 |\n| Piet | 25 |\n',
        );
        final lines = out.split('\n');
        expect(
          lines.indexWhere((l) => l.contains(r'\midrule')),
          lines.indexWhere((l) => l.contains(r'\textbf{Naam}')) + 1,
          reason:
              'de scheiding hing aan "de rij ná de eerste" en stond dus onder Jan',
        );
      },
    );

    test('boxed: verticale randen én een lijn onder elke rij', () {
      final out = markdownToLatex(
        '| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n',
        tableBorderStyle: TableBorderStyle.boxed,
      );
      expect(out, contains(r'\begin{tabular}{|l|l|}'));
      // Boven de kop, onder de kop, en onder elk van de twee gegevensrijen.
      expect(RegExp(r'\\hline').allMatches(out).length, 4);
      expect(out, isNot(contains('\\hline\n\\hline')));
      expect(out, isNot(contains(r'\toprule')));
    });

    test('none: een tabel zonder een enkele lijn', () {
      final out = markdownToLatex(
        '| A | B |\n| --- | --- |\n| 1 | 2 |\n',
        tableBorderStyle: TableBorderStyle.none,
      );
      expect(out, contains(r'\begin{tabular}{ll}'));
      for (final rule in [
        r'\hline',
        r'\toprule',
        r'\midrule',
        r'\bottomrule',
      ]) {
        expect(out, isNot(contains(rule)));
      }
    });

    test('een `<!-- toc -->` wordt \\tableofcontents', () {
      final out = markdownToLatex('<!-- toc -->\n\n# Een\n\n## Twee\n');
      expect(out, contains(r'\tableofcontents'));
      expect(out, isNot(contains('<!-- toc -->')));
      // Niet als tekst: de escaper maakte er `\textbackslash{}tableofcontents`
      // van, en de lezer kreeg dat woord op papier in plaats van een
      // inhoudsopgave.
      expect(out, isNot(contains(r'\textbackslash{}tableofcontents')));
      expect(out, isNot(contains('OCIDECK')));
    });

    test('fenced code block wordt lstlisting', () {
      final out = markdownToLatex('```dart\nvoid main() {}\n```\n');
      expect(out, contains(r'\begin{lstlisting}[language=dart]'));
      expect(out, contains('void main() {}'));
      expect(out, contains(r'\end{lstlisting}'));
    });

    test('inline code wordt texttt', () {
      final out = markdownToLatex('Gebruik `print()` hiervoor.');
      expect(out, contains(r'\texttt{print()}'));
    });

    test('wiskunde pass-through: dollar-syntax blijft ongewijzigd', () {
      final out = markdownToLatex('De formule \$E = mc^2\$ is bekend.');
      expect(out, contains(r'$E = mc^2$'));
    });

    test('display-math pass-through: \$\$...\$\$ blijft ongewijzigd', () {
      final out = markdownToLatex(r'$$\int_0^1 x\,dx = \frac{1}{2}$$');
      expect(out, contains(r'$$\int_0^1 x\,dx = \frac{1}{2}$$'));
    });

    test('vet en cursief', () {
      final out = markdownToLatex('**vet** en *cursief*');
      expect(out, contains(r'\textbf{vet}'));
      expect(out, contains(r'\textit{cursief}'));
    });

    test('doorhaling (~~)', () {
      final out = markdownToLatex('~~oud~~');
      expect(out, contains(r'\sout{oud}'));
    });

    test('link wordt href', () {
      final out = markdownToLatex('[OciDeck](https://ocideck.nl)');
      expect(out, contains(r'\href{https://ocideck.nl}{OciDeck}'));
    });

    test('afbeelding wordt includegraphics', () {
      final out = markdownToLatex('![Alt tekst](foto.png)');
      expect(out, contains(r'\includegraphics[width=0.8\textwidth]{foto.png}'));
      expect(out, contains('Alt tekst'));
    });

    test('LaTeX-speciale tekens worden geëscaped', () {
      final out = markdownToLatex('50% korting & meer!');
      expect(out, contains(r'\%'));
      expect(out, contains(r'\&'));
    });

    test('underscore wordt geëscaped', () {
      final out = markdownToLatex('een_variabele_naam');
      expect(out, contains(r'\_'));
    });

    test('blockquote wordt quote-omgeving', () {
      final out = markdownToLatex('> Een citaat\n');
      expect(out, contains(r'\begin{quote}'));
      expect(out, contains(r'\end{quote}'));
      expect(out, contains('Een citaat'));
    });

    test(
      'chapterPageBreak: elk hoofdstuk op een nieuwe pagina, behalve het eerste',
      () {
        const doc = '# Een\n\ntekst\n\n# Twee\n\nmeer\n\n# Drie\n';
        // Drie H1's → twee `\newpage` (het eerste hoofdstuk krijgt er geen, anders
        // een leeg openingsblad).
        final on = markdownToLatex(doc, chapterPageBreak: true);
        expect(r'\newpage'.allMatches(on), hasLength(2));
        // Uit (standaard): geen enkele pagina-breuk bij een hoofdstuk.
        expect(markdownToLatex(doc), isNot(contains(r'\newpage')));
      },
    );

    test('een thematische breuk (---) wordt een pagina-einde (\\newpage)', () {
      // In een document is `---` een pagina-einde, niet een zichtbare lijn
      // (DOCUMENT_MODE.md). Elke thematische-breuk-vorm parseert naar `hr`.
      expect(markdownToLatex('a\n\n---\n\nb'), contains(r'\newpage'));
      expect(markdownToLatex('a\n\n- - -\n\nb'), contains(r'\newpage'));
      expect(markdownToLatex('---\n'), isNot(contains(r'\rule{\textwidth}')));
    });

    test('task-list item krijgt checkbox-marker', () {
      final out = markdownToLatex('- [x] Klaar\n- [ ] Nog doen\n');
      expect(out, contains(r'\item[$\square$]'));
    });
  });

  group('markdownInlineToLatex', () {
    test('inline-fragment zonder blok-elementen', () {
      final out = markdownInlineToLatex('**vet** tekst');
      expect(out, contains(r'\textbf{vet}'));
      expect(out, contains('tekst'));
    });
  });
}
