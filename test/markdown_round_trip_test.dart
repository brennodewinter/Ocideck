import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/timeline.dart';
import 'package:ocideck/services/markdown_service.dart';

/// Serialize a single slide to markdown and parse it straight back.
Slide _roundTrip(Slide slide) {
  final service = MarkdownService();
  final markdown = service.generateDeck(Deck(title: 'Demo', slides: [slide]));
  final deck = service.parseDeck(markdown);
  expect(deck, isNotNull, reason: 'parseDeck returned null for:\n$markdown');
  expect(
    deck!.slides,
    hasLength(1),
    reason: 'Expected exactly one slide from:\n$markdown',
  );
  return deck.slides.single;
}

void main() {
  group('markdown round-trip per slide type', () {
    test('title slide keeps title, subtitle, image and size', () {
      final out = _roundTrip(
        Slide.create(SlideType.title).copyWith(
          title: 'Welkom',
          subtitle: 'Een ondertitel',
          imagePath: 'images/cover.png',
          imageSize: 80,
          imageCaption: 'Bron: archief',
        ),
      );
      expect(out.type, SlideType.title);
      expect(out.title, 'Welkom');
      expect(out.subtitle, 'Een ondertitel');
      expect(out.imagePath, 'images/cover.png');
      expect(out.imageSize, 80);
      expect(out.imageCaption, 'Bron: archief');
    });

    test('caption round-trips a pipe and a literal sentinel char', () {
      // The pipe uses the private-use sentinel internally; a user-typed
      // sentinel (U+E000) must not be mistaken for an encoded pipe on parse.
      const tricky = 'a | b \u{E000} c';
      final out = _roundTrip(
        Slide.create(SlideType.title).copyWith(
          title: 'T',
          imagePath: 'images/cover.png',
          imageCaption: tricky,
        ),
      );
      expect(out.imageCaption, tricky);
    });

    test('title slide round-trips a per-slide text colour override', () {
      final out = _roundTrip(
        Slide.create(SlideType.title).copyWith(
          title: 'Welkom',
          imagePath: 'images/cover.png',
          titleTextColorOverride: '#FFFFFF',
        ),
      );
      expect(out.titleTextColorOverride, '#FFFFFF');
    });

    test('title slide without override keeps it empty', () {
      final out = _roundTrip(
        Slide.create(
          SlideType.title,
        ).copyWith(title: 'Welkom', imagePath: 'images/cover.png'),
      );
      expect(out.titleTextColorOverride, '');
    });

    test('section slide keeps title and subtitle', () {
      final out = _roundTrip(
        Slide.create(
          SlideType.section,
        ).copyWith(title: 'Hoofdstuk 1', subtitle: 'De inleiding'),
      );
      expect(out.type, SlideType.section);
      expect(out.title, 'Hoofdstuk 1');
      expect(out.subtitle, 'De inleiding');
    });

    test('bullets slide keeps title and nested bullets', () {
      final out = _roundTrip(
        Slide.create(SlideType.bullets).copyWith(
          title: 'Agenda',
          bullets: [
            'Punt een',
            '\tSubpunt',
            '\t\tDiep subpunt',
            '\t\t\tNog dieper',
            '\t\t\t\tExtra dieper',
            'Punt twee',
          ],
        ),
      );
      expect(out.type, SlideType.bullets);
      expect(out.title, 'Agenda');
      expect(out.bullets, [
        'Punt een',
        '\tSubpunt',
        '\t\tDiep subpunt',
        '\t\t\tNog dieper',
        '\t\t\t\tExtra dieper',
        'Punt twee',
      ]);
    });

    test('bullets slide keeps an optional subheading', () {
      final out = _roundTrip(
        Slide.create(SlideType.bullets).copyWith(
          title: 'Agenda',
          subtitle: 'Vandaag',
          bullets: ['Punt een', 'Punt twee'],
        ),
      );
      expect(out.type, SlideType.bullets);
      expect(out.title, 'Agenda');
      expect(out.subtitle, 'Vandaag');
      expect(out.bullets, ['Punt een', 'Punt twee']);
    });

    test('numbered list style round-trips', () {
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          slides: [
            Slide.create(SlideType.bullets).copyWith(
              title: 'Stappen',
              bullets: ['Eerst', '\tDetail', 'Daarna'],
              listStyle: ListStyle.numbered,
            ),
          ],
        ),
      );
      final out = service.parseDeck(markdown)!.slides.single;
      expect(out.listStyle, ListStyle.numbered);
      expect(out.bullets, ['Eerst', '\tDetail', 'Daarna']);
      expect(markdown, contains('1. Eerst'));
      expect(markdown, contains('2. Daarna'));
    });

    test('continue-numbering round-trips (default stays clean)', () {
      final service = MarkdownService();
      Slide roundTrip(bool cont) => service
          .parseDeck(
            service.generateDeck(
              Deck(
                title: 'Demo',
                slides: [
                  Slide.create(SlideType.bullets).copyWith(
                    bullets: ['a'],
                    listStyle: ListStyle.numbered,
                    continueNumbering: cont,
                  ),
                ],
              ),
            ),
          )!
          .slides
          .single;
      // Off is the default and leaves no marker; on round-trips.
      expect(roundTrip(false).continueNumbering, isFalse);
      expect(roundTrip(true).continueNumbering, isTrue);
    });

    test('continue-split round-trips on bullets and two-column slides', () {
      // Default off leaves no marker; the split continuation flag survives a
      // save/open on both a plain bullets slide and a two-column slide.
      expect(
        _roundTrip(
          Slide.create(SlideType.bullets).copyWith(bullets: ['a', 'b']),
        ).continuesSplit,
        isFalse,
      );
      expect(
        _roundTrip(
          Slide.create(
            SlideType.bullets,
          ).copyWith(bullets: ['a', 'b'], continuesSplit: true),
        ).continuesSplit,
        isTrue,
      );
      expect(
        _roundTrip(
          Slide.create(
            SlideType.twoBullets,
          ).copyWith(bullets: ['a'], bullets2: ['b'], continuesSplit: true),
        ).continuesSplit,
        isTrue,
      );
      // Een gesplitste bulletsImage-vervolgpagina behoudt zowel de afbeelding als
      // de split-vlag, zodat de gedeelde-schaal-run een save/open overleeft.
      final splitImage = _roundTrip(
        Slide.create(SlideType.bulletsImage).copyWith(
          bullets: ['a', 'b'],
          imagePath: 'images/foto.png',
          continuesSplit: true,
        ),
      );
      expect(splitImage.type, SlideType.bulletsImage);
      expect(splitImage.imagePath, 'images/foto.png');
      expect(splitImage.continuesSplit, isTrue);
    });

    test('checklist style and checked items round-trip', () {
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          slides: [
            Slide.create(SlideType.bullets).copyWith(
              title: 'Taken',
              bullets: ['[x] Gedaan', '[ ] Nog doen', '\t[x] Subtaak'],
              listStyle: ListStyle.checklist,
              showChecklistProgress: true,
            ),
          ],
        ),
      );
      final out = service.parseDeck(markdown)!.slides.single;
      expect(out.listStyle, ListStyle.checklist);
      expect(out.showChecklistProgress, isTrue);
      expect(out.bullets, ['[x] Gedaan', '[ ] Nog doen', '\t[x] Subtaak']);
      expect(markdown, contains('- [x] Gedaan'));
      expect(markdown, contains('- [ ] Nog doen'));
      expect(markdown, contains('ocideck_checklist_progress: true'));
    });

    test('richText bullets slide round-trips with custom markdown', () {
      final service = MarkdownService();
      const body = 'Paragraaf één\n\n**Vet** tekst';
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          slides: [
            Slide.create(SlideType.bullets).copyWith(
              title: 'Titel',
              subtitle: 'Sub',
              listStyle: ListStyle.richText,
              customMarkdown: body,
            ),
          ],
        ),
      );
      final out = service.parseDeck(markdown)!;
      expect(out.slides, hasLength(1));
      final slide = out.slides.single;
      expect(slide.type, SlideType.bullets);
      expect(slide.listStyle, ListStyle.richText);
      expect(slide.title, 'Titel');
      expect(slide.subtitle, 'Sub');
      expect(slide.customMarkdown, body);
      expect(markdown, contains('ocideck_list_style: richText'));
    });

    test('richText content with dash lines does not create extra slides', () {
      final service = MarkdownService();
      const body = 'Scheiding\n---\nNog tekst';
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          slides: [
            Slide.create(SlideType.bullets).copyWith(
              title: 'Dash test',
              listStyle: ListStyle.richText,
              customMarkdown: body,
            ),
            Slide.create(
              SlideType.bullets,
            ).copyWith(title: 'Tweede slide', bullets: ['Punt']),
          ],
        ),
      );
      final out = service.parseDeck(markdown)!;
      expect(out.slides, hasLength(2));
      expect(out.slides.first.listStyle, ListStyle.richText);
      expect(out.slides.first.customMarkdown, body);
      expect(out.slides.last.title, 'Tweede slide');
    });

    test('twoBullets slide keeps both bullet columns', () {
      final out = _roundTrip(
        Slide.create(SlideType.twoBullets).copyWith(
          title: 'Vergelijking',
          bullets: ['Links punt', '\tLinks subpunt'],
          bullets2: ['Rechts punt', '\t\tRechts diep'],
        ),
      );
      expect(out.type, SlideType.twoBullets);
      expect(out.title, 'Vergelijking');
      expect(out.bullets, ['Links punt', '\tLinks subpunt']);
      expect(out.bullets2, ['Rechts punt', '\t\tRechts diep']);
    });

    test('twoBullets slide keeps its subtitle', () {
      final out = _roundTrip(
        Slide.create(SlideType.twoBullets).copyWith(
          title: 'Vergelijking',
          subtitle: 'Een ondertitel',
          bullets: ['Links'],
          bullets2: ['Rechts'],
        ),
      );
      expect(out.type, SlideType.twoBullets);
      expect(out.subtitle, 'Een ondertitel');
    });

    test('twoBullets slide keeps optional column headings', () {
      final out = _roundTrip(
        Slide.create(SlideType.twoBullets).copyWith(
          title: 'Vergelijking',
          columnTitle1: 'Voordelen',
          columnTitle2: 'Nadelen',
          bullets: ['Snel'],
          bullets2: ['Duur'],
        ),
      );
      expect(out.type, SlideType.twoBullets);
      expect(out.columnTitle1, 'Voordelen');
      expect(out.columnTitle2, 'Nadelen');
      expect(out.bullets, ['Snel']);
      expect(out.bullets2, ['Duur']);
    });

    test('twoBullets without headings stays empty (no spurious comments)', () {
      final service = MarkdownService();
      final md = service.generateDeck(
        Deck(
          title: 'Demo',
          slides: [
            Slide.create(
              SlideType.twoBullets,
            ).copyWith(bullets: ['A'], bullets2: ['B']),
          ],
        ),
      );
      expect(md, isNot(contains('ocideck_two_bullets_left_title')));
      final out = service.parseDeck(md)!.slides.single;
      expect(out.columnTitle1, '');
      expect(out.columnTitle2, '');
    });

    test('two-column checklist export respects disabled strike-through', () {
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          themeProfile: const ThemeProfile(checklistStrikeThrough: false),
          slides: [
            Slide.create(SlideType.twoBullets).copyWith(
              bullets: ['[x] Klaar'],
              bullets2: ['[ ] Open'],
              listStyle: ListStyle.checklist,
            ),
          ],
        ),
      );
      expect(markdown, isNot(contains('text-decoration:line-through')));
    });

    test('bulletsImage slide keeps bullets, image, size and caption', () {
      final out = _roundTrip(
        Slide.create(SlideType.bulletsImage).copyWith(
          title: 'Profiel',
          bullets: ['Eerste punt', '\tGenest punt'],
          imagePath: 'images/portret.png',
          imageSize: 45,
          imageCaption: 'Een onderschrift',
        ),
      );
      expect(out.type, SlideType.bulletsImage);
      expect(out.title, 'Profiel');
      expect(out.bullets, ['Eerste punt', '\tGenest punt']);
      expect(out.imagePath, 'images/portret.png');
      expect(out.imageSize, 45);
      expect(out.imageCaption, 'Een onderschrift');
    });

    test('bulletsImage richText slide round-trips with custom markdown', () {
      const body = 'Dit is **vet** tekst\n\n- Een lijst in markdown';
      final out = _roundTrip(
        Slide.create(SlideType.bulletsImage).copyWith(
          title: 'Profiel',
          listStyle: ListStyle.richText,
          customMarkdown: body,
          imagePath: 'images/portret.png',
          imageSize: 45,
        ),
      );
      expect(out.type, SlideType.bulletsImage);
      expect(out.listStyle, ListStyle.richText);
      expect(out.customMarkdown, body);
      expect(out.title, 'Profiel');
      expect(out.imagePath, 'images/portret.png');
      expect(out.imageSize, 45);

      final markdown = MarkdownService().generateDeck(
        Deck(title: 'Demo', slides: [out]),
      );
      expect(markdown, contains('ocideck_list_style: richText'));
      expect(markdown, contains('images/portret.png'));
      expect(markdown, contains('Dit is **vet** tekst'));
    });

    test('twoImages slide keeps both images, split and captions', () {
      final out = _roundTrip(
        Slide.create(SlideType.twoImages).copyWith(
          title: 'Voor en na',
          imagePath: 'images/a.png',
          imagePath2: 'images/b.png',
          imageSize: 60,
          imageCaption: 'Links',
          imageCaption2: 'Rechts',
        ),
      );
      expect(out.type, SlideType.twoImages);
      expect(out.title, 'Voor en na');
      expect(out.imagePath, 'images/a.png');
      expect(out.imagePath2, 'images/b.png');
      expect(out.imageSize, 60);
      expect(out.imageCaption, 'Links');
      expect(out.imageCaption2, 'Rechts');
    });

    test('image slide keeps title, image and size', () {
      final out = _roundTrip(
        Slide.create(SlideType.image).copyWith(
          title: 'Overzicht',
          imagePath: 'images/big.png',
          imageSize: 70,
          imageCaption: 'Foto',
        ),
      );
      expect(out.type, SlideType.image);
      expect(out.title, 'Overzicht');
      expect(out.imagePath, 'images/big.png');
      expect(out.imageSize, 70);
      expect(out.imageCaption, 'Foto');
    });

    test('YouTube embed keeps its source and trim window', () {
      final out = _roundTrip(
        Slide.create(SlideType.video).copyWith(
          title: 'Embed',
          videoPath: 'https://www.youtube.com/watch?v=abc12345678',
          videoStartMs: 1500,
          videoEndMs: 30000,
        ),
      );
      expect(out.type, SlideType.video);
      expect(out.videoPath, 'https://www.youtube.com/watch?v=abc12345678');
      expect(out.videoStartMs, 1500);
      expect(out.videoEndMs, 30000);
    });

    test('video slide keeps video and audio with autoplay flags', () {
      final out = _roundTrip(
        Slide.create(SlideType.video).copyWith(
          title: 'Film',
          videoPath: 'media/movie.mp4',
          videoAutoplay: true,
          audioPath: 'media/narration.mp3',
          audioAutoplay: true,
        ),
      );
      expect(out.type, SlideType.video);
      expect(out.title, 'Film');
      expect(out.videoPath, 'media/movie.mp4');
      expect(out.videoAutoplay, isTrue);
      expect(out.audioPath, 'media/narration.mp3');
      expect(out.audioAutoplay, isTrue);
    });

    test('quote slide keeps quote, author and background image', () {
      final out = _roundTrip(
        Slide.create(SlideType.quote).copyWith(
          quote: 'Kennis is macht',
          quoteAuthor: 'Francis Bacon',
          imagePath: 'images/bg.png',
        ),
      );
      expect(out.type, SlideType.quote);
      expect(out.quote, 'Kennis is macht');
      expect(out.quoteAuthor, 'Francis Bacon');
      expect(out.imagePath, 'images/bg.png');
    });

    test('table slide keeps title, header and rows', () {
      final out = _roundTrip(
        Slide.create(SlideType.table).copyWith(
          title: 'Vergelijking',
          tableRows: [
            ['Functie', 'Gratis', 'Pro'],
            ['Export', 'Nee', 'Ja'],
            ['Support', 'Email', '24/7'],
          ],
        ),
      );
      expect(out.type, SlideType.table);
      expect(out.title, 'Vergelijking');
      expect(out.tableRows, [
        ['Functie', 'Gratis', 'Pro'],
        ['Export', 'Nee', 'Ja'],
        ['Support', 'Email', '24/7'],
      ]);
    });

    test('table editable-during-presentation flag round-trips', () {
      final editable = _roundTrip(
        Slide.create(SlideType.table).copyWith(
          title: 'Bewerkbaar',
          tableEditable: true,
          tableRows: const [
            ['Kolom', 'Waarde'],
            ['Omzet', '100'],
          ],
        ),
      );
      expect(editable.type, SlideType.table);
      expect(editable.tableEditable, isTrue);

      // Standaard (alleen-lezen) blijft alleen-lezen en zonder de flag is dat
      // ook het gedrag voor oudere presentaties zonder het token.
      final readOnly = _roundTrip(
        Slide.create(SlideType.table).copyWith(
          title: 'Alleen lezen',
          tableRows: const [
            ['Kolom', 'Waarde'],
          ],
        ),
      );
      expect(readOnly.tableEditable, isFalse);
    });

    test('table slide escapes pipes and newlines in cells', () {
      final out = _roundTrip(
        Slide.create(SlideType.table).copyWith(
          title: 'Speciale tekens',
          tableRows: [
            ['Kolom A', 'Kolom B'],
            ['waarde | met pipe', 'regel een\nregel twee'],
          ],
        ),
      );
      expect(out.type, SlideType.table);
      expect(out.tableRows, [
        ['Kolom A', 'Kolom B'],
        ['waarde | met pipe', 'regel een\nregel twee'],
      ]);
    });

    test('a new table slide starts with empty cells (nothing to delete)', () {
      final slide = Slide.create(SlideType.table);
      expect(
        slide.tableRows.every((row) => row.every((c) => c.isEmpty)),
        isTrue,
      );
    });

    test('table slide stays a table even with empty headers', () {
      final out = _roundTrip(
        Slide.create(SlideType.table).copyWith(
          tableRows: const [
            ['', ''],
            ['waarde', ''],
          ],
        ),
      );
      expect(out.type, SlideType.table);
      expect(out.tableRows.first, ['', '']);
      expect(out.tableRows[1].first, 'waarde');
    });

    test('free markdown slide keeps its raw content', () {
      final out = _roundTrip(
        Slide.create(SlideType.freeMarkdown).copyWith(
          customMarkdown: 'Vrije tekst met **opmaak**.\n\nTweede alinea.',
        ),
      );
      expect(out.type, SlideType.freeMarkdown);
      expect(
        out.customMarkdown.trim(),
        'Vrije tekst met **opmaak**.\n\nTweede alinea.',
      );
    });

    test('code slide keeps title, language and code body', () {
      const code = 'void main() {\n  print("Hallo");\n}';
      final out = _roundTrip(
        Slide.create(SlideType.code).copyWith(
          title: 'Voorbeeld',
          codeLanguage: 'dart',
          customMarkdown: code,
        ),
      );
      expect(out.type, SlideType.code);
      expect(out.title, 'Voorbeeld');
      expect(out.codeLanguage, 'dart');
      expect(out.customMarkdown, code);
    });

    test('chart slide keeps its inline spec', () {
      const block =
          '{\n  "type": "bar",\n  "title": "Omzet",\n  "x": ["Q1","Q2"],\n'
          '  "series": [\n    {"name":"2025","data":[10,14]}\n  ]\n}';
      final out = _roundTrip(
        Slide.create(SlideType.chart).copyWith(customMarkdown: block),
      );
      expect(out.type, SlideType.chart);
      final spec = ChartSpec.parse(out.customMarkdown);
      expect(spec.type, ChartType.bar);
      expect(spec.x, ['Q1', 'Q2']);
      expect(spec.series.single.data, [10, 14]);
    });

    test('chart slide with a source keeps only the reference in markdown', () {
      const block =
          '{"type":"line","source":"data/omzet.csv",'
          '"x":["Q1"],"series":[{"name":"2025","data":[10]}]}';
      final service = MarkdownService();
      final md = service.generateDeck(
        Deck(
          title: 'Demo',
          slides: [
            Slide.create(SlideType.chart).copyWith(customMarkdown: block),
          ],
        ),
      );
      // The stored markdown references the CSV but does not inline the data.
      expect(md.contains('data/omzet.csv'), isTrue);
      final out = service.parseDeck(md)!.slides.single;
      final spec = ChartSpec.parse(out.customMarkdown);
      expect(spec.source, 'data/omzet.csv');
      expect(spec.hasInlineData, isFalse);
    });

    test('code slide without a language stays plain code', () {
      const code = 'GET /api/v1/status HTTP/1.1\nHost: example.org';
      final out = _roundTrip(
        Slide.create(SlideType.code).copyWith(customMarkdown: code),
      );
      expect(out.type, SlideType.code);
      expect(out.codeLanguage, '');
      expect(out.customMarkdown, code);
    });

    test('question slide keeps spec, image and settings', () {
      final spec = const QuestionSpec(
        prompt: 'Wat is de hoofdstad van Nederland?',
        answers: [
          QuestionAnswer(text: 'Amsterdam', correct: true),
          QuestionAnswer(text: 'Rotterdam'),
          QuestionAnswer(text: 'Den Haag'),
          QuestionAnswer(text: 'Utrecht'),
          QuestionAnswer(text: 'Eindhoven'),
        ],
        optionCount: 3,
        timeLimitSeconds: 20,
        onWrong: QuestionOnWrong.lockAndContinue,
      );
      final out = _roundTrip(
        Slide.create(SlideType.question).copyWith(
          title: 'Aardrijkskunde',
          customMarkdown: spec.toBlock(),
          imagePath: 'images/nl.png',
          imageCaption: 'Bron: atlas',
          imageSize: 45,
        ),
      );
      expect(out.type, SlideType.question);
      expect(out.title, 'Aardrijkskunde');
      expect(out.imagePath, 'images/nl.png');
      expect(out.imageCaption, 'Bron: atlas');
      expect(out.imageSize, 45);
      final parsed = QuestionSpec.parse(out.customMarkdown);
      expect(parsed.prompt, 'Wat is de hoofdstad van Nederland?');
      expect(parsed.answers, hasLength(5));
      expect(parsed.correctAnswers.map((a) => a.text), ['Amsterdam']);
      expect(parsed.wrongAnswers, hasLength(4));
      expect(parsed.optionCount, 3);
      expect(parsed.timeLimitSeconds, 20);
      expect(parsed.onWrong, QuestionOnWrong.lockAndContinue);
    });

    test('true/false question keeps kind and statement value', () {
      final spec = const QuestionSpec(
        kind: QuestionKind.trueFalse,
        prompt: 'De maan is gemaakt van kaas.',
        statementIsTrue: false,
      );
      final out = _roundTrip(
        Slide.create(
          SlideType.question,
        ).copyWith(customMarkdown: spec.toBlock()),
      );
      expect(out.type, SlideType.question);
      final parsed = QuestionSpec.parse(out.customMarkdown);
      expect(parsed.kind, QuestionKind.trueFalse);
      expect(parsed.prompt, 'De maan is gemaakt van kaas.');
      expect(parsed.statementIsTrue, isFalse);
      expect(parsed.isPresentable, isTrue);
    });

    test('multiple-correct question keeps kind and all answers', () {
      final spec = const QuestionSpec(
        kind: QuestionKind.multipleCorrect,
        prompt: 'Welke zijn priemgetallen?',
        answers: [
          QuestionAnswer(text: '2', correct: true),
          QuestionAnswer(text: '3', correct: true),
          QuestionAnswer(text: '4'),
          QuestionAnswer(text: '5', correct: true),
          QuestionAnswer(text: '6'),
        ],
        optionCount: 4,
      );
      final out = _roundTrip(
        Slide.create(
          SlideType.question,
        ).copyWith(customMarkdown: spec.toBlock()),
      );
      final parsed = QuestionSpec.parse(out.customMarkdown);
      expect(parsed.kind, QuestionKind.multipleCorrect);
      expect(parsed.correctAnswers.map((a) => a.text), ['2', '3', '5']);
      expect(parsed.wrongAnswers, hasLength(2));
      expect(parsed.isPresentable, isTrue);
    });
  });

  group('markdown round-trip cross-cutting fields', () {
    test('keeps speaker notes and advance duration', () {
      final out = _roundTrip(
        Slide.create(SlideType.bullets).copyWith(
          title: 'Met notities',
          bullets: ['Een punt'],
          notes: 'Vergeet de demo niet te tonen.',
          advanceDuration: 2.5,
        ),
      );
      expect(out.notes, 'Vergeet de demo niet te tonen.');
      expect(out.advanceDuration, 2.5);
    });

    test('keeps the skipped flag and does not leak it into notes', () {
      final skipped = _roundTrip(
        Slide.create(SlideType.bullets).copyWith(
          title: 'Backup-slide',
          bullets: ['Alleen indien nodig'],
          notes: 'Reserve',
          skipped: true,
        ),
      );
      expect(skipped.skipped, isTrue);
      expect(skipped.notes, 'Reserve'); // <!-- skip --> mag geen notitie worden

      final normal = _roundTrip(
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Gewoon', bullets: ['Punt']),
      );
      expect(normal.skipped, isFalse);
    });

    test('keeps the per-slide TLP classification', () {
      final out = _roundTrip(
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Gevoelig', bullets: ['Geheim'], tlp: TlpLevel.amber),
      );
      expect(out.tlp, TlpLevel.amber);

      final none = _roundTrip(
        Slide.create(SlideType.bullets).copyWith(bullets: ['Open']),
      );
      expect(none.tlp, TlpLevel.none);
    });

    test('keeps the per-slide TLP on a code slide', () {
      final out = _roundTrip(
        Slide.create(SlideType.code).copyWith(
          customMarkdown: 'secret_key = 42',
          codeLanguage: 'python',
          tlp: TlpLevel.red,
        ),
      );
      expect(out.type, SlideType.code);
      expect(out.tlp, TlpLevel.red);
    });

    test('keeps general presentation metadata in the front matter', () {
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          author: 'Jan Jansen',
          organization: 'Vigilis',
          version: '1.2',
          date: '2026-05-30',
          description: 'Een korte: omschrijving met dubbele punt',
          keywords: 'kwartaal, cijfers, 2026',
          tlp: TlpLevel.amberStrict,
          slides: [Slide.create(SlideType.title).copyWith(title: 'Een')],
        ),
      );
      final deck = service.parseDeck(markdown);
      expect(deck, isNotNull);
      expect(deck!.title, 'Demo');
      expect(deck.author, 'Jan Jansen');
      expect(deck.organization, 'Vigilis');
      expect(deck.version, '1.2');
      expect(deck.date, '2026-05-30');
      expect(deck.description, 'Een korte: omschrijving met dubbele punt');
      expect(deck.keywords, 'kwartaal, cijfers, 2026');
      expect(deck.tlp, TlpLevel.amberStrict);
    });

    test('TLP none is omitted from the front matter and round-trips', () {
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          slides: [Slide.create(SlideType.title).copyWith(title: 'Een')],
        ),
      );
      expect(markdown.contains('tlp:'), isFalse);
      expect(service.parseDeck(markdown)!.tlp, TlpLevel.none);
    });

    test('per-slide logo visibility round-trips when a logo is configured', () {
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          themeProfile: const ThemeProfile(logoPath: '/tmp/logo.png'),
          slides: [
            Slide.create(
              SlideType.bullets,
            ).copyWith(title: 'Met logo', bullets: ['a']),
            Slide.create(
              SlideType.bullets,
            ).copyWith(title: 'Zonder logo', bullets: ['b'], showLogo: false),
          ],
        ),
      );
      final deck = service.parseDeck(markdown);
      expect(deck, isNotNull);
      expect(deck!.slides[0].showLogo, isTrue);
      expect(deck.slides[1].showLogo, isFalse);
    });

    test('per-slide footer visibility round-trips', () {
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          themeProfile: const ThemeProfile(
            footerText: 'Vertrouwelijk',
            footerPosition: 'center',
          ),
          slides: [
            Slide.create(
              SlideType.bullets,
            ).copyWith(title: 'Met footer', bullets: ['a']),
            Slide.create(SlideType.bullets).copyWith(
              title: 'Zonder footer',
              bullets: ['b'],
              showFooter: false,
            ),
          ],
        ),
      );
      final deck = service.parseDeck(markdown);
      expect(deck, isNotNull);
      expect(deck!.slides[0].showFooter, isTrue);
      expect(deck.slides[1].showFooter, isFalse);
    });

    test('slides default to showing the logo', () {
      final out = _roundTrip(
        Slide.create(SlideType.bullets).copyWith(title: 'x', bullets: ['y']),
      );
      expect(out.showLogo, isTrue);
    });

    test('slides default to showing the footer', () {
      final out = _roundTrip(
        Slide.create(SlideType.bullets).copyWith(title: 'x', bullets: ['y']),
      );
      expect(out.showFooter, isTrue);
    });

    test('preserves slide order and count for a multi-slide deck', () {
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          slides: [
            Slide.create(SlideType.title).copyWith(title: 'Een'),
            Slide.create(
              SlideType.bullets,
            ).copyWith(title: 'Twee', bullets: ['x']),
            Slide.create(SlideType.bulletsImage).copyWith(
              title: 'Drie',
              bullets: ['y'],
              imagePath: 'images/c.png',
            ),
            Slide.create(SlideType.image).copyWith(imagePath: 'images/d.png'),
          ],
        ),
      );
      final deck = service.parseDeck(markdown);
      expect(deck, isNotNull);
      expect(deck!.slides.map((s) => s.type).toList(), [
        SlideType.title,
        SlideType.bullets,
        SlideType.bulletsImage,
        SlideType.image,
      ]);
      expect(deck.slides[2].imagePath, 'images/c.png');
      expect(deck.slides[3].imagePath, 'images/d.png');
    });
  });

  group('markdown round-trip edge cases', () {
    const tricky = 'Quote " back\\slash pipe | angle <b> & amp 🎉 日本語 العربية';

    test('title and subtitle keep special characters and unicode', () {
      final out = _roundTrip(
        Slide.create(SlideType.title).copyWith(title: tricky, subtitle: tricky),
      );
      expect(out.title, tricky);
      expect(out.subtitle, tricky);
    });

    test('bullets keep pipes, angle brackets and unicode', () {
      final out = _roundTrip(
        Slide.create(SlideType.bullets).copyWith(
          title: 'Tekens',
          bullets: ['a | b', 'x <y> z', 'quote " and \\ slash', '✓ café 漢字'],
        ),
      );
      expect(out.bullets, [
        'a | b',
        'x <y> z',
        'quote " and \\ slash',
        '✓ café 漢字',
      ]);
    });

    test('quote slide keeps special characters', () {
      final out = _roundTrip(
        Slide.create(
          SlideType.quote,
        ).copyWith(quote: tricky, quoteAuthor: 'A. "Nony" Mous'),
      );
      expect(out.quote, tricky);
      expect(out.quoteAuthor, 'A. "Nony" Mous');
    });

    test('table cells keep pipes and special characters', () {
      final out = _roundTrip(
        Slide.create(SlideType.table).copyWith(
          title: 'Tabel',
          tableRows: [
            ['Kolom A', 'Kolom B'],
            ['a | b', 'x <y> & z'],
          ],
        ),
      );
      expect(out.tableRows, [
        ['Kolom A', 'Kolom B'],
        ['a | b', 'x <y> & z'],
      ]);
    });

    test('a bullets slide with a title but no bullets keeps its type', () {
      final out = _roundTrip(
        Slide.create(SlideType.bullets).copyWith(title: 'Leeg'),
      );
      expect(out.type, SlideType.bullets);
      expect(out.title, 'Leeg');
      expect(out.bullets, isEmpty);
    });

    test('free-markdown keeps inline and block math verbatim', () {
      const body =
          'Inline \$E = mc^2\$ and a block:\n\n\$\$\n\\int_0^1 x\\,dx\n\$\$';
      final out = _roundTrip(
        Slide.create(SlideType.freeMarkdown).copyWith(customMarkdown: body),
      );
      expect(out.customMarkdown.contains('E = mc^2'), isTrue);
      expect(out.customMarkdown.contains('\\int_0^1 x'), isTrue);
    });

    test('deck-level presentation target seconds round-trips', () {
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          presentationTargetSeconds: 1500,
          slides: [Slide.create(SlideType.title).copyWith(title: 'Een')],
        ),
      );
      final deck = service.parseDeck(markdown);
      expect(deck, isNotNull);
      expect(deck!.presentationTargetSeconds, 1500);
    });

    test(
      'deck-level show-rehearsal-summary round-trips (default stays clean)',
      () {
        final service = MarkdownService();
        Deck? roundTrip(bool show) => service.parseDeck(
          service.generateDeck(
            Deck(
              title: 'Demo',
              showRehearsalSummary: show,
              slides: [Slide.create(SlideType.title).copyWith(title: 'Een')],
            ),
          ),
        );
        // Default (true) is not written to the front matter, but still parses true.
        final onMarkdown = service.generateDeck(
          Deck(title: 'Demo', slides: [Slide.create(SlideType.title)]),
        );
        expect(onMarkdown.contains('ocideck_show_rehearsal_summary'), isFalse);
        expect(roundTrip(true)!.showRehearsalSummary, isTrue);
        // Opt-out is persisted and round-trips.
        expect(roundTrip(false)!.showRehearsalSummary, isFalse);
      },
    );

    test('timeline slide keeps title, events, layout and animation', () {
      final out = _roundTrip(
        Slide.create(SlideType.timeline).copyWith(
          title: 'Van idee tot beursgang',
          bullets: [
            '2019 :: Oprichting :: Drie mensen, één zolderkamer.',
            '2021 :: Lancering :: 1.000 gebruikers in zes weken.',
            'Nu :: Vandaag',
          ],
          timelineLayout: TimelineLayout.vertical,
          timelineReveal: TimelineReveal.steps,
          timelineAnimationMs: 2600,
        ),
      );
      expect(out.type, SlideType.timeline);
      expect(out.title, 'Van idee tot beursgang');
      expect(out.timelineLayout, TimelineLayout.vertical);
      expect(out.timelineReveal, TimelineReveal.steps);
      expect(out.timelineAnimationMs, 2600);
      final events = parseTimelineEvents(out.bullets);
      expect(events, hasLength(3));
      expect(events[0].marker, '2019');
      expect(events[0].title, 'Oprichting');
      expect(events[0].description, 'Drie mensen, één zolderkamer.');
      expect(events[2].marker, 'Nu');
      expect(events[2].title, 'Vandaag');
      expect(events[2].description, isEmpty);
      // cssClass must stay clean: the timeline option tokens are absorbed into
      // the typed fields, not left dangling in the class string.
      expect(out.cssClass, isEmpty);
    });

    test('timeline slide defaults to auto layout and on-enter animation', () {
      final out = _roundTrip(
        Slide.create(SlideType.timeline).copyWith(title: 'Reis'),
      );
      expect(out.type, SlideType.timeline);
      expect(out.timelineLayout, TimelineLayout.auto);
      expect(out.timelineReveal, TimelineReveal.onEnter);
      // No explicit duration: the slide inherits the theme's, so it round-trips
      // as null (no ocideck_timeline_duration comment is written).
      expect(out.timelineAnimationMs, isNull);
      // No current point marked either: no ocideck_timeline_current comment.
      expect(out.timelineCurrentIndex, isNull);
    });

    test('timeline slide keeps the current-point highlight', () {
      final slide = Slide.create(SlideType.timeline).copyWith(
        title: 'Projectfasen',
        bullets: [
          '2024 :: Start :: Kickoff met het team.',
          '2025 :: Bouw :: Realisatie in sprints.',
          '2026 :: Livegang',
        ],
        timelineCurrentIndex: 1,
      );
      // The comment stores the human-friendly 1-based event number.
      final markdown = MarkdownService().generateDeck(
        Deck(title: 'Demo', slides: [slide]),
      );
      expect(markdown, contains('<!-- ocideck_timeline_current: 2 -->'));
      final out = _roundTrip(slide);
      expect(out.timelineCurrentIndex, 1);
      // An out-of-range hand-edited number is ignored (fail-safe: no highlight).
      final hacked = MarkdownService().parseDeck(
        markdown.replaceFirst(
          'ocideck_timeline_current: 2',
          'ocideck_timeline_current: 99',
        ),
      );
      expect(hacked!.slides.single.timelineCurrentIndex, isNull);
    });
  });

  group('round-trip edge cases (silent data-loss regressions)', () {
    test('C1: split-image captions survive a literal " | " in the text', () {
      final out = _roundTrip(
        Slide.create(SlideType.twoImages).copyWith(
          imagePath: 'images/a.png',
          imagePath2: 'images/b.png',
          imageCaption: 'links a | b', // contains the join delimiter
          imageCaption2: 'rechts | c',
        ),
      );
      expect(out.imageCaption, 'links a | b');
      expect(out.imageCaption2, 'rechts | c');
    });

    test('C2: video trim keeps sub-second (millisecond) precision', () {
      final out = _roundTrip(
        Slide.create(SlideType.video).copyWith(
          videoPath: 'media/movie.mp4',
          videoStartMs: 1500,
          videoEndMs: 8200,
        ),
      );
      // Previously start floor()'d to 1s and end ceil()'d to 9s, widening the
      // segment on every save.
      expect(out.videoStartMs, 1500);
      expect(out.videoEndMs, 8200);
    });

    test('C3: speaker notes keep an embedded "-->"', () {
      final out = _roundTrip(
        Slide.create(SlideType.section).copyWith(
          title: 'Deel',
          notes: 'zie a --> b, en c --> d aan het einde',
        ),
      );
      expect(out.notes, 'zie a --> b, en c --> d aan het einde');
    });

    test('C4: table cell separates a literal "<br>" from a real newline', () {
      final out = _roundTrip(
        Slide.create(SlideType.table).copyWith(
          tableRows: const [
            ['Kop'],
            ['gebruik de <br> tag'], // literal text, not a line break
            ['regel1\nregel2'], // an actual newline
          ],
        ),
      );
      expect(out.tableRows[1][0], 'gebruik de <br> tag');
      expect(out.tableRows[2][0], 'regel1\nregel2');
    });

    test(
      'C5: literal escape sequence in notes is the one accepted collision',
      () {
        // Documented in markdown_service_helpers.dart: notes escape `-->` as
        // `--\>` inside the HTML comment. A note that already contains the literal
        // escape `--\>` therefore round-trips back as `-->`. This is a known,
        // negligible, accepted collision (private escape sequence in speaker
        // notes); this test locks the behaviour so any change is intentional.
        final out = _roundTrip(
          Slide.create(
            SlideType.section,
          ).copyWith(title: 'Deel', notes: r'literal escape --\> here'),
        );
        expect(out.notes, 'literal escape --> here');
      },
    );
  });

  // Coverage for the richText-slide parser branch (the `make mutate` survivors,
  // which were latent bugs): a rich-text body is markdown, so an embedded table
  // / <video> / <audio> must stay in the body — extracting them lost the content
  // (the table outright; media on the next save). Only a bulletsImage (split)
  // slide lifts its image and caption into typed fields.
  group('richText slide keeps embedded markdown in the body', () {
    Slide richTextBullets(String body) =>
        Slide.create(SlideType.bullets).copyWith(
          title: 'Rijk',
          listStyle: ListStyle.richText,
          customMarkdown: body,
        );

    test('keeps an embedded markdown table in the body', () {
      const body = 'Inleiding\n\n| A | B |\n| --- | --- |\n| 1 | 2 |';
      final out = _roundTrip(richTextBullets(body));
      expect(out.type, SlideType.bullets);
      expect(out.listStyle, ListStyle.richText);
      expect(out.customMarkdown, contains('| A | B |'));
      expect(out.customMarkdown, contains('| 1 | 2 |'));
      expect(out.tableRows, isEmpty);
    });

    test('keeps an embedded <video> in the body', () {
      final out = _roundTrip(
        richTextBullets('Kijk:\n\n<video src="clip.mp4"></video>'),
      );
      expect(out.customMarkdown, contains('<video src="clip.mp4">'));
      expect(out.videoPath, isEmpty);
    });

    test('round-trips an audio attachment (written for every slide type)', () {
      // The audio attachment is offered on every non-video slide and serialised
      // by the common <audio> block after the type switch, so a richText slide
      // must read it back into audioPath (not leave it in the body).
      final out = _roundTrip(
        Slide.create(SlideType.bullets).copyWith(
          title: 'Rijk',
          listStyle: ListStyle.richText,
          customMarkdown: 'Wat tekst',
          audioPath: 'media/narration.mp3',
          audioAutoplay: true,
        ),
      );
      expect(out.audioPath, 'media/narration.mp3');
      expect(out.audioAutoplay, isTrue);
      expect(out.customMarkdown, contains('Wat tekst'));
    });

    test('lifts the image and caption of a richText bulletsImage slide', () {
      final out = _roundTrip(
        Slide.create(SlideType.bulletsImage).copyWith(
          title: 'Rijk met beeld',
          listStyle: ListStyle.richText,
          imagePath: 'images/foto.png',
          imageCaption: 'Bron: archief',
          customMarkdown: 'Wat begeleidende tekst',
        ),
      );
      expect(out.type, SlideType.bulletsImage);
      expect(out.listStyle, ListStyle.richText);
      expect(out.imagePath, 'images/foto.png');
      expect(out.imageCaption, 'Bron: archief');
      expect(out.customMarkdown, contains('Wat begeleidende tekst'));
    });
  });

  // An <audio> attachment is offered on every non-video slide and serialised by
  // a common block AFTER the type switch, so each specialised parser (code,
  // chart, cockpit, question — the fenced-block parsers) must read it back. The
  // `make mutate` run flagged those `<audio>` branches as untested; these pin
  // them, so an audio attachment can't silently vanish on a save/load.
  group('audio attachment round-trips on the fenced-block slide types', () {
    Slide withAudio(Slide s) =>
        s.copyWith(audioPath: 'media/clip.mp3', audioAutoplay: true);
    void expectAudio(Slide out) {
      expect(out.audioPath, 'media/clip.mp3');
      expect(out.audioAutoplay, isTrue);
    }

    test('code slide', () {
      final out = _roundTrip(
        withAudio(
          Slide.create(SlideType.code).copyWith(
            title: 'Code',
            codeLanguage: 'dart',
            customMarkdown: 'void main() {}',
          ),
        ),
      );
      expect(out.type, SlideType.code);
      expectAudio(out);
    });

    test('chart slide', () {
      const block =
          '{"type":"bar","x":["Q1"],"series":[{"name":"a","data":[1]}]}';
      final out = _roundTrip(
        withAudio(
          Slide.create(SlideType.chart).copyWith(customMarkdown: block),
        ),
      );
      expect(out.type, SlideType.chart);
      expectAudio(out);
    });

    test('cockpit slide', () {
      final out = _roundTrip(
        withAudio(
          Slide.create(SlideType.cockpit).copyWith(
            title: 'Cockpit',
            customMarkdown: CockpitSpec.pentestPreset().toBlock(),
          ),
        ),
      );
      expect(out.type, SlideType.cockpit);
      expectAudio(out);
    });

    test('question slide', () {
      const spec = QuestionSpec(
        prompt: 'Vraag?',
        answers: [
          QuestionAnswer(text: 'A', correct: true),
          QuestionAnswer(text: 'B'),
          QuestionAnswer(text: 'C'),
        ],
        optionCount: 2,
      );
      final out = _roundTrip(
        withAudio(
          Slide.create(
            SlideType.question,
          ).copyWith(title: 'Quiz', customMarkdown: spec.toBlock()),
        ),
      );
      expect(out.type, SlideType.question);
      expectAudio(out);
    });
  });
}
