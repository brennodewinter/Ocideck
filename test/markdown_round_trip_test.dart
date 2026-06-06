import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
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

    test('code slide without a language stays plain code', () {
      const code = 'GET /api/v1/status HTTP/1.1\nHost: example.org';
      final out = _roundTrip(
        Slide.create(SlideType.code).copyWith(customMarkdown: code),
      );
      expect(out.type, SlideType.code);
      expect(out.codeLanguage, '');
      expect(out.customMarkdown, code);
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
      expect(deck!.author, 'Jan Jansen');
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
      expect(deck!.themeProfile.footerPosition, 'center');
      expect(deck.slides[0].showFooter, isTrue);
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
}
