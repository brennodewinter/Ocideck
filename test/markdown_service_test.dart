import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

void main() {
  test('round-trips image slide with title as image slide', () {
    final service = MarkdownService();
    final markdown = service.generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.image,
          ).copyWith(title: 'Overlay title', imagePath: 'images/photo.png'),
        ],
      ),
    );

    final deck = service.parseDeck(markdown);

    expect(deck, isNotNull);
    expect(deck!.slides.single.type, SlideType.image);
    expect(deck.slides.single.title, 'Overlay title');
    expect(deck.slides.single.imagePath, 'images/photo.png');
  });

  test('round-trips title background overlay setting', () {
    final service = MarkdownService();
    final markdown = service.generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.title).copyWith(
            title: 'Welkom',
            imagePath: 'images/bg.png',
            titleImageOverlay: false,
          ),
        ],
      ),
    );

    expect(markdown, contains('![bg](images/bg.png)'));
    expect(markdown, contains('<!-- ocideck_title_image_overlay: false -->'));
    expect(markdown, isNot(contains('opacity:.45')));

    final deck = service.parseDeck(markdown);

    expect(deck, isNotNull);
    final slide = deck!.slides.single;
    expect(slide.type, SlideType.title);
    expect(slide.imagePath, 'images/bg.png');
    expect(slide.titleImageOverlay, isFalse);
  });

  test('round-trips bulletsImage slide with image and size', () {
    final service = MarkdownService();
    final markdown = service.generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bulletsImage).copyWith(
            title: 'Profiel',
            bullets: ['Eerste punt', '\tGenest punt'],
            imagePath: 'images/portret.png',
            imageCaption: 'Een onderschrift',
            imageSize: 45,
          ),
        ],
      ),
    );

    final deck = service.parseDeck(markdown);

    expect(deck, isNotNull);
    final slide = deck!.slides.single;
    expect(slide.type, SlideType.bulletsImage);
    expect(slide.title, 'Profiel');
    expect(slide.imagePath, 'images/portret.png');
    expect(slide.imageCaption, 'Een onderschrift');
    expect(slide.imageSize, 45);
    expect(slide.bullets, ['Eerste punt', '\tGenest punt']);
  });

  test('parses split text bullets from saved markdown', () {
    final service = MarkdownService();
    final markdown = [
      '---',
      'marp: true',
      'theme: ocideck',
      '---',
      '',
      '<!-- _class: split logo-safe -->',
      '',
      '<!-- _style: --image-width: 40%; --split-text-scale: 1.00; -->',
      '',
      '<div class="split-text" style="font-size: 1.00em">',
      '',
      '# blah blah blah',
      '',
      for (var i = 1; i <= 13; i++)
        '- Controleer op een SPECI: Kijk of er tussentijds een speciaal '
            'weerrapport is uitgegeven vanwege plotseling veranderde '
            'omstandigheden $i.',
      '',
      '</div>',
      '',
      '<div class="split-image">',
      '',
      '![](images/pasted.png)',
      '',
      '</div>',
    ].join('\n');

    final deck = service.parseDeck(markdown);

    expect(deck, isNotNull);
    final slide = deck!.slides.single;
    expect(slide.type, SlideType.bulletsImage);
    expect(slide.title, 'blah blah blah');
    expect(slide.bullets, hasLength(13));
    expect(slide.imagePath, 'images/pasted.png');
  });

  test('keeps a plain image inside free markdown as free markdown', () {
    final service = MarkdownService();
    final deck = service.parseDeck(
      '---\nmarp: true\ntheme: vigilis\n---\n\n'
      '![](images/inline.png)\n\nWat losse tekst.\n',
    );

    expect(deck, isNotNull);
    final slide = deck!.slides.single;
    expect(slide.type, SlideType.freeMarkdown);
    expect(slide.imagePath, isEmpty);
  });

  test('parses unicode bullet markers as bullet slides', () {
    final service = MarkdownService();
    final markdown = [
      '---',
      'marp: true',
      '---',
      '',
      '# Veel punten',
      '',
      for (var i = 1; i <= 13; i++) '• Punt $i',
    ].join('\n');

    final deck = service.parseDeck(markdown);

    expect(deck, isNotNull);
    final slide = deck!.slides.single;
    expect(slide.type, SlideType.bullets);
    expect(slide.bullets, hasLength(13));
  });

  test('parses simple HTML list items as bullet slides', () {
    final service = MarkdownService();
    final markdown = [
      '---',
      'marp: true',
      '---',
      '',
      '# Veel punten',
      '',
      '<ul>',
      for (var i = 1; i <= 13; i++) '<li>Punt $i</li>',
      '</ul>',
    ].join('\n');

    final deck = service.parseDeck(markdown);

    expect(deck, isNotNull);
    final slide = deck!.slides.single;
    expect(slide.type, SlideType.bullets);
    expect(slide.bullets, hasLength(13));
  });

  test('round-trips cockpit slide JSON', () {
    final service = MarkdownService();
    const spec = CockpitSpec(
      meters: [
        CockpitMeterSpec(
          type: CockpitMeterType.speedometer,
          label: 'Overall risk',
          value: 78,
          greenFrom: 0,
          greenTo: 40,
          redFrom: 70,
        ),
        CockpitMeterSpec(
          type: CockpitMeterType.heading,
          label: 'Phase',
          heading: 90,
          markerLabel: 'Build',
        ),
      ],
    );
    final markdown = service.generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.cockpit,
          ).copyWith(title: 'Cockpit overview', customMarkdown: spec.toBlock()),
        ],
      ),
    );

    final deck = service.parseDeck(markdown);

    expect(deck, isNotNull);
    final slide = deck!.slides.single;
    expect(slide.type, SlideType.cockpit);
    expect(slide.title, 'Cockpit overview');
    final back = CockpitSpec.parse(slide.customMarkdown);
    expect(back.meters, hasLength(2));
    expect(back.meters.first.label, 'Overall risk');
    expect(back.meters.last.type, CockpitMeterType.heading);
    expect(back.meters.last.markerLabel, 'Build');
  });

  test('round-trips deck style profile', () {
    final service = MarkdownService();
    final profile = const ThemeProfile(
      name: 'Klant A',
      slideBackgroundColor: '#111827',
      textColor: '#F8FAFC',
      accentColor: '#F59E0B',
      tableTextColor: '#111111',
      tableHeaderTextColor: '#EEEEEE',
      logoPosition: 'top-left',
      logoSize: 120,
      fontFamily: 'Georgia',
      footerText: 'Vertrouwelijk · {page}/{total}',
      footerShowPageNumbers: true,
      footerPosition: 'center',
      closingSlideEnabled: true,
      closingSlideMarkdown: '# Einde\n\nDank voor jullie aandacht.',
    );

    // The style profile only travels inside the markdown when explicitly
    // inlined (transient beamer payloads); a plain save keeps the file clean.
    final markdown = service.generateDeck(
      Deck(
        title: 'Demo',
        themeProfile: profile,
        slides: [Slide.create(SlideType.title).copyWith(title: 'Demo')],
      ),
      inlineStyleProfile: true,
    );

    final deck = service.parseDeck(markdown);

    expect(deck, isNotNull);
    expect(deck!.themeProfile.name, 'Klant A');
    expect(deck.themeProfile.slideBackgroundColor, '#111827');
    expect(deck.themeProfile.tableTextColor, '#111111');
    expect(deck.themeProfile.tableHeaderTextColor, '#EEEEEE');
    expect(deck.themeProfile.logoPosition, 'top-left');
    expect(deck.themeProfile.logoSize, 120);
    expect(deck.themeProfile.fontFamily, 'Georgia');
    expect(deck.themeProfile.footerText, 'Vertrouwelijk · {page}/{total}');
    expect(deck.themeProfile.footerShowPageNumbers, isTrue);
    expect(deck.themeProfile.footerPosition, 'center');
    expect(deck.themeProfile.closingSlideEnabled, isTrue);
    expect(
      deck.themeProfile.closingSlideMarkdown,
      '# Einde\n\nDank voor jullie aandacht.',
    );
  });

  test('a saved deck does not embed the style profile', () {
    final service = MarkdownService();
    final markdown = service.generateDeck(
      Deck(
        title: 'Demo',
        themeProfile: const ThemeProfile(
          name: 'Klant A',
          slideBackgroundColor: '#111827',
        ),
        slides: [Slide.create(SlideType.title).copyWith(title: 'Demo')],
      ),
    );

    // The file is the base content only; styling stays out of it. Parsing it
    // back yields the default profile, not the one that was saved.
    expect(markdown.contains('ocideck_style_profile'), isFalse);
    final deck = service.parseDeck(markdown);
    expect(deck!.themeProfile.name, 'Standaard');
    expect(deck.themeProfile.slideBackgroundColor, isNot('#111827'));
  });

  test('adds logo-safe class when deck profile has logo', () {
    final service = MarkdownService();
    final markdown = service.generateDeck(
      Deck(
        title: 'Demo',
        themeProfile: const ThemeProfile(logoPath: '/tmp/logo.png'),
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Demo', bullets: ['Een lange bullet']),
        ],
      ),
    );

    expect(markdown, contains('<!-- _class: logo-safe -->'));
  });

  test('round-trips video slide with audio attachment', () {
    final service = MarkdownService();
    final markdown = service.generateDeck(
      Deck(
        title: 'Media',
        slides: [
          Slide.create(SlideType.video).copyWith(
            title: 'Film',
            videoPath: 'media/movie.mp4',
            videoAutoplay: true,
            audioPath: 'media/narration.mp3',
            audioAutoplay: true,
          ),
        ],
      ),
    );

    final deck = service.parseDeck(markdown);

    expect(deck, isNotNull);
    expect(deck!.slides.single.type, SlideType.video);
    expect(deck.slides.single.videoPath, 'media/movie.mp4');
    expect(deck.slides.single.videoAutoplay, isTrue);
    expect(deck.slides.single.audioPath, 'media/narration.mp3');
    expect(deck.slides.single.audioAutoplay, isTrue);
  });
}
