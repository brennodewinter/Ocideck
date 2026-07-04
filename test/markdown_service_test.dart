import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

void main() {
  test('unknown underscore comment-directives do not become notes', () {
    // Marp-directives als `_paginate` zijn geen sprekersnotities; alleen
    // niet-directive-commentaren horen in notes te belanden.
    const md =
        '---\nmarp: true\n---\n\n# Titel\n\n- punt\n\n'
        '<!-- _paginate: false -->\n<!-- Echte notitie -->\n';
    final deck = MarkdownService().parseDeck(md)!;
    expect(deck.slides.single.notes, 'Echte notitie');
  });

  test('a body already ending in a newline gets no extra blank line', () {
    final service = MarkdownService();
    String gen(Slide s) => service.generateDeck(Deck(title: 'D', slides: [s]));

    final code = gen(
      Slide.create(
        SlideType.code,
      ).copyWith(customMarkdown: 'regel1\n', codeLanguage: 'dart'),
    );
    expect(code, contains('regel1\n```'));
    expect(code, isNot(contains('regel1\n\n```')));

    final free = gen(
      Slide.create(SlideType.freeMarkdown).copyWith(customMarkdown: 'alinea\n'),
    );
    expect(free, isNot(contains('alinea\n\n\n')));

    final rich = gen(
      Slide.create(
        SlideType.bullets,
      ).copyWith(listStyle: ListStyle.richText, customMarkdown: 'tekst\n'),
    );
    expect(rich, isNot(contains('tekst\n\n\n')));
  });

  test('advance directive clamps Infinity/NaN/overflow to 0', () {
    for (final v in ['Infinity', '-Infinity', 'NaN', '1e400']) {
      final md = '---\nmarp: true\n---\n\n# Slide\n\n<!-- advance: $v -->\n';
      final deck = MarkdownService().parseDeck(md)!;
      expect(
        deck.slides.single.advanceDuration,
        0,
        reason: 'advance: $v must not become a non-finite duration',
      );
    }
  });

  test('advance directive clamps huge finite values to 86400s', () {
    const md = '---\nmarp: true\n---\n\n# Slide\n\n<!-- advance: 999999 -->\n';
    final deck = MarkdownService().parseDeck(md)!;
    expect(deck.slides.single.advanceDuration, 86400);
  });

  test('a huge background image size is clamped at parse (<=400%)', () {
    const md =
        '---\nmarp: true\n---\n\n# Titel\n\n![bg 900000%](images/x.png)\n';
    final deck = MarkdownService().parseDeck(md)!;
    expect(deck.slides.single.imageSize, lessThanOrEqualTo(400));
    expect(deck.slides.single.imageSize, greaterThan(0));
  });

  test('frontmatter tolerates indentation and missing spaces', () {
    const md =
        '---\n'
        '  title:   Mijn Talk\n' // leading indent + extra spaces
        'theme:ocideck\n' // no space after the colon
        'ocideck_target_seconds: 600\n'
        'date: 2026-06-23T09:30:00\n' // value contains colons
        '---\n'
        '# Eerste\n';
    final deck = MarkdownService().parseDeck(md)!;
    expect(deck.title, 'Mijn Talk');
    expect(deck.theme, 'ocideck');
    expect(deck.presentationTargetSeconds, 600);
    expect(deck.date, '2026-06-23T09:30:00');
  });

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

  test('round-trips a caption containing a slash', () {
    // HtmlEscape (unknown-mode) escapet ook `/` naar `&#47;`; de decoder moet
    // die terugvertalen (regressie: eigen unescape-tabel miste &#47;).
    final service = MarkdownService();
    final markdown = service.generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.image).copyWith(
            imagePath: 'images/foto.png',
            imageCaption: 'Bron: NOS/ANP & "archief"',
          ),
        ],
      ),
    );

    final deck = service.parseDeck(markdown);

    expect(deck, isNotNull);
    expect(deck!.slides.single.imageCaption, 'Bron: NOS/ANP & "archief"');
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

  test('round-trips a per-slide cat-paw bullet-marker override', () {
    final service = MarkdownService();
    final markdown = service.generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.bullets).copyWith(
            title: 'Punten',
            bullets: const ['Een', 'Twee'],
            bulletMarkerOverride: BulletMarker.paw,
          ),
        ],
      ),
    );

    expect(markdown, contains('<!-- ocideck_bullet_marker: paw -->'));

    final slide = service.parseDeck(markdown)!.slides.single;
    expect(slide.type, SlideType.bullets);
    expect(slide.bulletMarkerOverride, BulletMarker.paw);
  });

  test('writes no marker comment when the slide inherits the theme', () {
    final service = MarkdownService();
    final markdown = service.generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Punten', bullets: const ['Een']),
        ],
      ),
    );

    expect(markdown, isNot(contains('ocideck_bullet_marker')));
    expect(
      service.parseDeck(markdown)!.slides.single.bulletMarkerOverride,
      isNull,
    );
  });

  test('forExport pins the effective paw marker on bullet slides only', () {
    const theme = ThemeProfile(bulletMarker: BulletMarker.paw);
    final deck = Deck(
      title: 'Demo',
      themeProfile: theme,
      slides: [
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Punten', bullets: const ['x']),
        Slide.create(SlideType.freeMarkdown).copyWith(customMarkdown: '- y'),
      ],
    );

    // Export pins the bullet slide's paw, but never the free-markdown list.
    final exported = MarkdownService().generateDeck(deck, forExport: true);
    expect('ocideck_bullet_marker: paw'.allMatches(exported).length, 1);

    // A normal save leaves the inherited default implicit (no comment), so the
    // override semantics — and the file — stay clean.
    final saved = MarkdownService().generateDeck(deck);
    expect(saved, isNot(contains('ocideck_bullet_marker')));
  });

  test('theme profile round-trips the default bullet marker through JSON', () {
    const profile = ThemeProfile(bulletMarker: BulletMarker.paw);
    final restored = ThemeProfile.fromJson(profile.toJson());
    expect(restored.bulletMarker, BulletMarker.paw);
    // Older files without the key fall back to a dot.
    final legacy = ThemeProfile.fromJson(
      profile.toJson()..remove('bulletMarker'),
    );
    expect(legacy.bulletMarker, BulletMarker.dot);
  });
}
