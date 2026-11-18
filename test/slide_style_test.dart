// Tests voor de stijlwissel (#2996): markering-parse en round-trip, de
// voorwaartse cascade, de `deck`-reset, fallback op een onbekende naam,
// CSS-scoping, de HTML-export en de pakket-sidecar.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_style.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/marp_html_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/theme_css_scope.dart';
import 'package:path/path.dart' as p;

Slide _bulletSlide({String styleName = ''}) => Slide.create(
  SlideType.bullets,
).copyWith(title: 'Dia', bullets: const ['punt'], styleName: styleName);

void main() {
  final svc = MarkdownService();

  group('markering: parse en round-trip', () {
    test('ocideck_style-commentaar landt op de dia', () {
      const md = '''---
marp: true
---

# Een

---

<!-- ocideck_style: Donker -->

# Twee

---

<!-- ocideck_style: deck -->

# Drie
''';
      final deck = svc.parseDeck(md)!;
      expect(deck.slides, hasLength(3));
      expect(deck.slides[0].styleName, '');
      expect(deck.slides[1].styleName, 'Donker');
      expect(deck.slides[2].styleName, 'deck');
    });

    test('serialiseert de markering terug en parset hem weer', () {
      final deck = Deck(
        title: 't',
        slides: [
          _bulletSlide(),
          _bulletSlide(styleName: 'Donker'),
          _bulletSlide(styleName: 'deck'),
        ],
      );
      final out = svc.generateDeck(deck);
      expect(out, contains('<!-- ocideck_style: Donker -->'));
      expect(out, contains('<!-- ocideck_style: deck -->'));

      final reparsed = svc.parseDeck(out)!;
      expect(reparsed.slides[1].styleName, 'Donker');
      expect(reparsed.slides[2].styleName, 'deck');
    });

    test('een deck zonder wissels schrijft geen markering', () {
      final out = svc.generateDeck(
        Deck(title: 't', slides: [_bulletSlide(), _bulletSlide()]),
      );
      expect(out, isNot(contains('ocideck_style')));
    });
  });

  group('cascade', () {
    final slides = [
      _bulletSlide(),
      _bulletSlide(styleName: 'Donker'),
      _bulletSlide(),
      _bulletSlide(styleName: 'deck'),
      _bulletSlide(),
      _bulletSlide(styleName: 'Licht'),
    ];

    test('de laatste markering geldt vanaf zijn dia tot de volgende', () {
      expect(slideStyleNameAt(slides, 0), isNull);
      expect(slideStyleNameAt(slides, 1), 'Donker');
      expect(slideStyleNameAt(slides, 2), 'Donker');
      expect(slideStyleNameAt(slides, 3), isNull); // deck-reset
      expect(slideStyleNameAt(slides, 4), isNull);
      expect(slideStyleNameAt(slides, 5), 'Licht');
    });

    test('markerIndex wijst naar de dia waar het bereik verankerd is', () {
      expect(slideStyleMarkerIndex(slides, 2), 1);
      expect(slideStyleMarkerIndex(slides, 4), isNull);
    });

    test('usedSlideStyleNames verzamelt de echte profielnamen', () {
      expect(usedSlideStyleNames(slides), {'Donker', 'Licht'});
    });
  });

  group('resolutie', () {
    const base = ThemeProfile(accentColor: '#111111');
    const dark = ThemeProfile(name: 'Donker', accentColor: '#222222');
    final slides = [_bulletSlide(), _bulletSlide(styleName: 'Donker')];

    test('een bekende naam levert zijn profiel', () {
      expect(resolveSlideStyle(base, [dark], slides, 1).accentColor, '#222222');
    });

    test('een onbekende naam valt terug op de deckstijl', () {
      expect(
        resolveSlideStyle(base, const [], slides, 1).accentColor,
        '#111111',
      );
    });

    test('slideProfileAt gebruikt Deck.slideStyles', () {
      final deck = Deck(
        title: 't',
        slides: slides,
        themeProfile: base,
        slideStyles: const {'Donker': dark},
      );
      expect(deck.slideProfileAt(0).accentColor, '#111111');
      expect(deck.slideProfileAt(1).accentColor, '#222222');
      // Naam in de markering, maar niet in de map → deckstijl.
      final orphaned = deck.copyWith(slideStyles: const {});
      expect(orphaned.slideProfileAt(1).accentColor, '#111111');
    });
  });

  group('class-token en CSS-scope', () {
    test('de profielnaam wordt een stabiel token', () {
      expect(slideStyleClassToken('Donker'), 'stijl-donker');
      expect(slideStyleClassToken('Mijn Profiel 2'), 'stijl-mijn-profiel-2');
    });

    test('scoping bindt elke regel aan het bereik-element', () {
      final scoped = scopeThemeCss(
        'section{background:#000}\n'
        'section.title h1{color:#fff}\n'
        'table td{color:#eee}\n'
        ':root{--x:1}\n'
        '@media print{section{color:#000}}',
        root: 'section',
        token: 'stijl-donker',
      );
      expect(scoped, contains('section.stijl-donker {background:#000}'));
      expect(scoped, contains('section.stijl-donker.title h1 {color:#fff}'));
      expect(scoped, contains('section.stijl-donker table td {color:#eee}'));
      expect(scoped, contains('section.stijl-donker {--x:1}'));
      expect(scoped, contains('@media print'));
      // Een naam die op de wortel lijkt maar hem niet is, lift niet mee.
      final other = scopeThemeCss(
        'sectionx{color:red}',
        root: 'section',
        token: 'stijl-donker',
      );
      expect(other, contains('section.stijl-donker sectionx {color:red}'));
    });
  });

  group('HTML-export', () {
    Future<String> diskLoader(String asset) => File(asset).readAsString();

    test(
      'dia\'s in een bereik dragen het token en krijgen gescope CSS',
      () async {
        final service = MarpHtmlService(loadAsset: diskLoader);
        const md = '''---
marp: true
---

# Een

---

<!-- ocideck_style: Donker -->

# Twee

---

# Drie
''';
        const dark = ThemeProfile(
          name: 'Donker',
          slideBackgroundColor: '#101018',
          textColor: '#EEEEEE',
        );
        final html = await service.build(
          md,
          theme: const ThemeProfile(slideBackgroundColor: '#FFFFFF'),
          slideStyles: const {'Donker': dark},
        );
        // Dia 2 én dia 3 zitten in het bereik; dia 1 niet.
        expect(
          RegExp('class="slide stijl-donker"').allMatches(html),
          hasLength(2),
        );
        // De gescope variant overschrijft de basisregels van de deckstijl.
        expect(html, contains('.slide.stijl-donker {'));
        expect(html, contains('#101018'));
      },
    );

    test('een onbekende profielnaam draagt geen token', () async {
      final service = MarpHtmlService(loadAsset: diskLoader);
      const md = '''---
marp: true
---

# Een

---

<!-- ocideck_style: BestaatNiet -->

# Twee
''';
      final html = await service.build(md, slideStyles: const {});
      expect(html, isNot(contains('stijl-bestaatniet')));
    });
  });

  group('pakket', () {
    late Directory tmp;
    late FileService file;

    setUp(() {
      // De thema-CSS komt uit rootBundle; zonder binding is er geen asset-map
      // en slaat het pakket de stylesheet-stap over.
      TestWidgetsFlutterBinding.ensureInitialized();
      tmp = Directory.systemTemp.createTempSync('ocideck_style_pkg');
      file = FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(name: 'Basis'),
        themeProfiles: () => const [
          ThemeProfile(name: 'Basis'),
          ThemeProfile(name: 'Donker', slideBackgroundColor: '#101018'),
        ],
      );
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Deck deck() => Deck(
      title: 't',
      slides: [
        _bulletSlide(),
        _bulletSlide(styleName: 'Donker'),
        _bulletSlide(),
      ],
      slideStyles: const {
        'Donker': ThemeProfile(name: 'Donker', slideBackgroundColor: '#101018'),
      },
    );

    test(
      'het pakket draagt stijltoken, gescope CSS en de styles-sidecar',
      () async {
        final bytes = await file.buildPackageBytes(deck());
        final archive = ZipDecoder().decodeBytes(bytes);
        final names = archive.files.map((f) => f.name).toSet();
        expect(names, contains('ocideck-styles.json'));

        // De markdown schrijft het stijltoken mee in `_class` zodat kale Marp
        // het bereik rendert; de `ocideck_style`-markering blijft voor herimport.
        final mdFile = archive.files.firstWhere((f) => f.name.endsWith('.md'));
        final md = utf8.decode(mdFile.content as List<int>);
        expect(md, contains('stijl-donker'));
        expect(md, contains('<!-- ocideck_style: Donker -->'));

        final cssFile = archive.files.firstWhere(
          (f) => f.name.endsWith('.css'),
          orElse: () => throw StateError('geen thema-css in pakket'),
        );
        final css = utf8.decode(cssFile.content as List<int>);
        expect(css, contains('section.stijl-donker'));
      },
    );

    test('herimport herstelt de markering én de meegedragen stijl', () async {
      final zipPath = p.join(tmp.path, 'deck.ocideck');
      await file.exportPackage(deck(), zipPath);
      final out = Directory(p.join(tmp.path, 'out'))..createSync();
      final mdPath = await file.importPackageBytes(
        File(zipPath).readAsBytesSync(),
        out.path,
      );
      expect(mdPath, isNotNull);
      final imported = await file.openDeck(mdPath!);
      expect(imported, isNotNull);
      expect(imported!.slides[1].styleName, 'Donker');
      expect(imported.slides[2].styleName, isNot('Donker'));
      expect(imported.slideStyles.keys, contains('Donker'));
      // Het meegedragen profiel wint: ook zonder instellingenprofiel staat
      // zijn achtergrondkleur klaar.
      expect(imported.slideProfileAt(1).slideBackgroundColor, '#101018');
    });
  });
}
