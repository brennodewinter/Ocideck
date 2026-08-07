// Tests voor de Beamer-slide-bouwer: bewijst per SlideType dat de uitvoer
// klopt — frames, titels, lijsten, tabellen, code, afbeeldingen, fallback.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/latex/beamer_slide_builder.dart';

void main() {
  group('buildBeamerBody', () {
    test('title-slide wordt center met Large titel', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(
            SlideType.title,
          ).copyWith(title: 'Mijn Presentatie', subtitle: 'Een ondertitel'),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{frame}'));
      expect(out, contains(r'\begin{center}'));
      expect(out, contains(r'\Large'));
      expect(out, contains('Mijn Presentatie'));
      expect(out, contains('Een ondertitel'));
      expect(out, contains(r'\end{frame}'));
    });

    test('section-slide wordt \\section + sectionpage', () {
      final deck = Deck(
        title: 'Test',
        slides: [Slide.create(SlideType.section).copyWith(title: 'Inleiding')],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\section{Inleiding}'));
      expect(out, contains(r'\sectionpage'));
    });

    test('bullets-slide wordt itemize met items', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Belangrijke punten',
            bullets: const ['Eerste punt', 'Tweede punt'],
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\frametitle{Belangrijke punten}'));
      expect(out, contains(r'\begin{itemize}'));
      expect(out, contains(r'\item Eerste punt'));
      expect(out, contains(r'\item Tweede punt'));
      expect(out, contains(r'\end{itemize}'));
    });

    test('numbered bullets-slide wordt enumerate', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Stappen',
            bullets: const ['Stap 1', 'Stap 2'],
            listStyle: ListStyle.numbered,
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{enumerate}'));
      expect(out, contains(r'\end{enumerate}'));
    });

    test('twoBullets-slide wordt columns', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.twoBullets).copyWith(
            title: 'Vergelijking',
            columnTitle1: 'Voor',
            columnTitle2: 'Na',
            bullets: const ['Oud'],
            bullets2: const ['Nieuw'],
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{columns}'));
      expect(out, contains(r'\textbf{Voor}'));
      expect(out, contains(r'\textbf{Na}'));
      expect(out, contains('Oud'));
      expect(out, contains('Nieuw'));
      expect(out, contains(r'\end{columns}'));
    });

    test('image-slide wordt includegraphics met caption', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.image).copyWith(
            title: 'Diagram',
            imagePath: 'diagram.png',
            imageCaption: 'Figuur 1',
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\includegraphics'));
      expect(out, contains('diagram.png'));
      expect(out, contains('Figuur 1'));
    });

    test('quote-slide wordt quote-omgeving met auteur', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.quote).copyWith(
            title: 'Citaat',
            quote: 'Wees jezelf',
            quoteAuthor: 'Confucius',
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{quote}'));
      expect(out, contains('Wees jezelf'));
      expect(out, contains(r'\end{quote}'));
      expect(out, contains('Confucius'));
    });

    test('code-slide wordt lstlisting', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.code).copyWith(
            title: 'Voorbeeld',
            codeLanguage: 'python',
            customMarkdown: '```python\nprint("hello")\n```',
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{lstlisting}[language=python]'));
      expect(out, contains('print("hello")'));
      expect(out, contains(r'\end{lstlisting}'));
    });

    test('table-slide wordt tabular met booktabs', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.table).copyWith(
            title: 'Resultaten',
            tableRows: const [
              ['Naam', 'Waarde'],
              ['Jan', '30'],
            ],
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{tabular}{ll}'));
      expect(out, contains(r'\toprule'));
      expect(out, contains(r'\midrule'));
      expect(out, contains(r'\bottomrule'));
      expect(out, contains('Naam'));
      expect(out, contains('Jan'));
    });

    test('freeMarkdown-slide gaat door kernconverter', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.freeMarkdown).copyWith(
            title: 'Vrij',
            customMarkdown: '# Kopje\n\nTekst met **vet**.',
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\section{Kopje}'));
      expect(out, contains(r'\textbf{vet}'));
    });

    test('skipped slides worden overgeslagen', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Zichtbaar', bullets: const ['A']),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Verborgen', bullets: const ['B'], skipped: true),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains('Zichtbaar'));
      expect(out, isNot(contains('Verborgen')));
    });

    test('fallback voor ongedekte types gebruikt customMarkdown', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.checklist).copyWith(
            title: 'Controlelijst',
            customMarkdown: '# Checklist\n\n- [x] Eerste item',
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      // Fallback: kernconverter over customMarkdown
      expect(out, contains(r'\section{Checklist}'));
      expect(out, contains(r'\item'));
    });

    test('wiskunde in bullets gaat rechtstreeks door', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Formules',
            bullets: const [r'De formule $E = mc^2$ is bekend.'],
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'$E = mc^2$'));
    });

    test('LaTeX-speciale tekens in titel worden geëscaped', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: '50% korting & meer', bullets: const []),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\%'));
      expect(out, contains(r'\&'));
    });
  });
}
