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
      // freeMarkdown is de fallback-route: kernconverter over customMarkdown.
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.freeMarkdown).copyWith(
            title: 'Vrij',
            customMarkdown: '# Checklist\n\n- [x] Eerste item',
          ),
        ],
      );
      final out = buildBeamerBody(deck);
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

  group('buildBeamerBody rijke types', () {
    test('checklist-slide wordt tabular', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.checklist).copyWith(
            title: 'Controlelijst',
            tableRows: const [
              ['ID', 'Test', 'Status'],
              ['1', 'TLS', 'OK'],
            ],
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{tabular}{lll}'));
      expect(out, contains('Controlelijst'));
    });

    test('scorecard-slide wordt tabular', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.scorecard).copyWith(
            title: 'Scorecard',
            tableRows: const [
              ['Label', 'Waarde'],
              ['CPU', '90%'],
            ],
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{tabular}'));
      expect(out, contains('CPU'));
    });

    test('signOff-slide wordt gecentreerde titel', () {
      final deck = Deck(
        title: 'Test',
        slides: [Slide.create(SlideType.signOff).copyWith(title: 'Einde')],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{center}'));
      expect(out, contains('Einde'));
    });

    test('menu-slide wordt itemize met links', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.menu).copyWith(
            title: 'Menu',
            bullets: const [
              '[Inleiding](#inleiding)',
              '[Conclusie](#conclusie)',
            ],
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{itemize}'));
      expect(out, contains('Inleiding'));
      expect(out, contains('Conclusie'));
    });

    test('video-slide wordt hyperlink', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(
            SlideType.video,
          ).copyWith(title: 'Demo', videoPath: 'demo.mp4'),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\href{'));
      expect(out, contains('demo.mp4'));
    });

    test('timeline-slide wordt itemize met marker', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.timeline).copyWith(
            title: 'Tijdlijn',
            bullets: const [
              '2024 :: Start :: Project begon',
              '2025 :: Live :: Productie',
            ],
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{itemize}'));
      expect(out, contains(r'\item[2024]'));
      expect(out, contains(r'\textbf{Start}'));
      expect(out, contains('Project begon'));
    });

    test('canvas-slide gaat door kernconverter', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.canvas).copyWith(
            title: 'Canvas',
            customMarkdown: '## Regio A\n\nTekst hier.',
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\subsection{Regio A}'));
      expect(out, contains('Tekst hier.'));
    });

    test('question-slide gaat door kernconverter', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.question).copyWith(
            title: 'Vraag',
            customMarkdown: '```question\n{"q":"Wat is 2+2?"}\n```',
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains('question'));
      expect(out, contains('Wat is 2+2?'));
    });

    test('finding-slide gaat door kernconverter', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.finding).copyWith(
            title: 'Bevinding',
            customMarkdown: '## Description\n\nEen kwetsbaarheid.\n',
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\subsection{Description}'));
      expect(out, contains('Een kwetsbaarheid'));
    });

    test('chart-slide wordt lstlisting met chart-data', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.chart).copyWith(
            title: 'Grafiek',
            customMarkdown: '```chart\n{"type":"bar"}\n```',
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{lstlisting}'));
      expect(out, contains('"type":"bar"'));
    });

    test('cockpit-slide wordt lstlisting', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.cockpit).copyWith(
            title: 'Dashboard',
            customMarkdown: '```cockpit\n{"meters":[]}\n```',
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{lstlisting}'));
      expect(out, contains('"meters":[]'));
    });

    test('tree-slide wordt geneste itemize', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.tree).copyWith(
            title: 'Boom',
            bullets: const ['Hoofd', '\tSub 1', '\tSub 2'],
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{itemize}'));
      expect(out, contains('Hoofd'));
      expect(out, contains('Sub 1'));
      expect(out, contains('Sub 2'));
    });

    test('gantt-slide wordt tabular', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.gantt).copyWith(
            title: 'Planning',
            tableRows: const [
              ['Taak', 'Start', 'Duur'],
              ['Ontwerp', '1', '5'],
            ],
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{tabular}'));
      expect(out, contains('Ontwerp'));
    });

    test('scopeMatrix-slide wordt tabular', () {
      final deck = Deck(
        title: 'Test',
        slides: [
          Slide.create(SlideType.scopeMatrix).copyWith(
            title: 'Scope',
            tableRows: const [
              ['Object', 'Type', 'Status'],
              ['Server', 'Host', 'OK'],
            ],
          ),
        ],
      );
      final out = buildBeamerBody(deck);
      expect(out, contains(r'\begin{tabular}'));
      expect(out, contains('Server'));
    });
  });
}
