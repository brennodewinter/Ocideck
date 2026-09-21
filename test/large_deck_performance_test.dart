import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:path/path.dart' as p;

import 'support/fastest_of.dart';

/// Prestatie- en schaalbaarheidstests voor grote presentaties.
///
/// De rest van de suite dekt gedrag functioneel af, maar duwde nooit een deck
/// van >100 slides door de serialise/parse-pijplijn. Deze tests bewaken twee
/// dingen die pas op schaal zichtbaar worden:
///
///  1. **Verliesvrijheid op schaal** — een deck van 150 slides moet volledig
///     round-trippen. Stil inhoudsverlies bij grote decks valt hier om.
///  2. **Geen kwadratisch gedrag** — een O(n²) regressie (bijvoorbeeld een
///     lineaire scan per slide over het hele document) is op 10 slides
///     onzichtbaar en op 500 slides fataal.
///
/// De tijdsbudgetten staan bewust ruim: ze vangen alleen catastrofale
/// algoritmische regressies, geen micro-timing. Metingen nemen het *minimum*
/// van meerdere runs, wat robuust is tegen planningsruis op een belaste
/// machine — een trager gemiddelde zegt niets, een trager minimum wel.
///
/// Waar twee metingen met elkáár worden vergeleken, dragen ze bovendien even
/// veel werk. Alleen dan raakt een belaste machine beide even hard en blijft
/// de verhouding een uitspraak over het algoritme in plaats van over de
/// machine.

/// Bouwt een realistisch deck van [slideCount] slides, met een mix van
/// slidetypes zodat de meting niet op één serialiser-pad blijft hangen.
Deck buildLargeDeck(int slideCount) {
  final slides = <Slide>[
    Slide(
      id: 'slide-0',
      type: SlideType.title,
      title: 'Grootschalige presentatie',
      subtitle: 'Prestatiemeting',
    ),
  ];

  for (var i = 1; i < slideCount; i++) {
    slides.add(_slideForIndex(i));
  }

  return Deck(
    title: 'Prestatiedeck',
    author: 'OciDeck testsuite',
    organization: 'OciDeck',
    slides: slides,
  );
}

Future<Duration> _fastestAsync(int runs, Future<void> Function() action) async {
  var best = const Duration(days: 1);
  for (var run = 0; run < runs; run++) {
    final stopwatch = Stopwatch()..start();
    await action();
    stopwatch.stop();
    if (stopwatch.elapsed < best) best = stopwatch.elapsed;
  }
  return best;
}

/// Eén slide per index, cyclisch over de gangbare types. De inhoud is bewust
/// niet triviaal: lege slides zouden de serialiser te makkelijk maken.
Slide _slideForIndex(int i) {
  switch (i % 6) {
    case 0:
      return Slide(
        id: 'slide-$i',
        type: SlideType.section,
        title: 'Hoofdstuk $i',
      );
    case 1:
      return Slide(
        id: 'slide-$i',
        type: SlideType.bullets,
        title: 'Bevindingen $i',
        bullets: List.generate(
          8,
          (b) => 'Punt $b van slide $i met wat aanvullende toelichting',
        ),
      );
    case 2:
      return Slide(
        id: 'slide-$i',
        type: SlideType.twoBullets,
        title: 'Vergelijking $i',
        columnTitle1: 'Voor',
        columnTitle2: 'Na',
        bullets: List.generate(5, (b) => 'Links $b op slide $i'),
        bullets2: List.generate(5, (b) => 'Rechts $b op slide $i'),
      );
    case 3:
      return Slide(
        id: 'slide-$i',
        type: SlideType.quote,
        quote: 'Een citaat op slide $i dat over meerdere woorden doorloopt.',
        quoteAuthor: 'Auteur $i',
      );
    case 4:
      return Slide(
        id: 'slide-$i',
        type: SlideType.table,
        title: 'Tabel $i',
        tableRows: [
          const ['Onderdeel', 'Status', 'Toelichting'],
          for (var r = 0; r < 6; r++)
            ['Rij $r', 'OK', 'Toelichting bij rij $r van slide $i'],
        ],
      );
    default:
      // `freeMarkdown` draagt géén `_class`-token: de parser leidt het type af
      // uit de inhoud (markdown_service_parse.dart). Een vrije-tekstslide
      // round-tript dus alleen als zodanig zonder kop of opsomming — met een
      // titel erbij is hij per ontwerp niet te onderscheiden van `bullets`.
      // Deze fixture houdt zich daar bewust aan.
      return Slide(
        id: 'slide-$i',
        type: SlideType.freeMarkdown,
        customMarkdown:
            'Een vrije alinea met **nadruk** en `code` op slide $i, '
            'lang genoeg om de serialiser echt werk te geven.',
      );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = MarkdownService();

  group('Grote decks (>100 slides)', () {
    test('round-trip van 150 slides verliest geen enkele slide', () {
      final deck = buildLargeDeck(150);
      final markdown = service.generateDeck(deck);
      final parsed = service.parseDeck(markdown);

      expect(parsed, isNotNull, reason: 'een deck van 150 slides moet parsen');
      expect(parsed!.slides, hasLength(deck.slides.length));

      // Types en titels moeten één-op-één terugkomen; dit is de functionele
      // kern van de test, de timings hieronder zijn slechts de vangrail.
      expect(
        parsed.slides.map((s) => s.type).toList(),
        deck.slides.map((s) => s.type).toList(),
      );
      expect(
        parsed.slides.map((s) => s.title).toList(),
        deck.slides.map((s) => s.title).toList(),
      );
    });

    test('inhoud van een grote deck blijft op detailniveau intact', () {
      final deck = buildLargeDeck(150);
      final parsed = service.parseDeck(service.generateDeck(deck))!;

      // Steekproef over elk slidetype in de cyclus, aan het staartje van het
      // deck — juist daar zou een schaalbug als eerste toeslaan.
      final bullets = parsed.slides[145];
      expect(bullets.type, SlideType.bullets);
      expect(bullets.bullets, hasLength(8));

      final twoBullets = parsed.slides[146];
      expect(twoBullets.type, SlideType.twoBullets);
      expect(twoBullets.bullets, hasLength(5));
      expect(twoBullets.bullets2, hasLength(5));

      final table = parsed.slides[148];
      expect(table.type, SlideType.table);
      expect(table.tableRows, hasLength(7));
    });

    test('serialiseren en parsen blijft binnen een ruim tijdsbudget', () {
      final deck = buildLargeDeck(150);

      final serialise = fastestOf(3, () => service.generateDeck(deck));
      expect(
        serialise,
        lessThan(const Duration(seconds: 2)),
        reason: 'serialiseren van 150 slides duurde $serialise',
      );

      final markdown = service.generateDeck(deck);
      final parse = fastestOf(3, () => service.parseDeck(markdown));
      expect(
        parse,
        lessThan(const Duration(seconds: 2)),
        reason: 'parsen van 150 slides duurde $parse',
      );
    });

    test('parsen schaalt niet kwadratisch met het aantal slides', () {
      // Zet twee even lange metingen naast elkaar. Vier keer een deck van 50
      // slides parsen is precies evenveel werk als één keer 200 slides zolang
      // het gedrag lineair is; bij O(n²) kost die ene grote parse vier keer
      // zoveel (16 eenheden tegen 4).
      //
      // De oude vorm vergeleek één parse van 50 slides met één van 200 en
      // liet 10x toe. Dat hield geen stand op een belaste machine. Het
      // minimum van drie doorlopen filtert een incidentele uitschieter weg,
      // maar geen aanhoudende belasting — en die treft de lángste meting het
      // hardst, simpelweg omdat daar meer gelegenheid is om onderbroken te
      // worden. Op de release-runner van v0.6.7 werd 50 slides 3,6 ms en 200
      // slides 59,7 ms (16,6x) terwijl dezelfde commit lokaal 3-4x haalde:
      // de poort sloeg rood en de hele release-keten viel stil. Even lange
      // metingen worden door belasting even hard geraakt, dus dán blijft de
      // verhouding overeind.
      const grootteFactor = 4; // 200 slides / 50 slides
      final smallMarkdown = service.generateDeck(buildLargeDeck(50));
      final largeMarkdown = service.generateDeck(buildLargeDeck(200));

      // Opwarmen: de eerste run betaalt eenmalige JIT- en cachekosten die de
      // verhouding anders vertekenen.
      service.parseDeck(smallMarkdown);
      service.parseDeck(largeMarkdown);

      // Gelijke werklast is de helft van het werk; de andere helft is dezelfde
      // redenering als in fastestOf, maar één niveau hoger. Ook een verhouding
      // heeft een beste meting: die waarin de machine er het minst tussen zat.
      // Gemeten op deze Mac wappert de oude vorm over een band van 1,0 tot 1,6
      // en deze over 0,05 tot 0,22 — en een drempel valt om door spreiding,
      // niet door het gemiddelde.
      var laagste = double.infinity;
      for (var poging = 0; poging < 3; poging++) {
        final small = fastestOf(3, () {
          for (var i = 0; i < grootteFactor; i++) {
            service.parseDeck(smallMarkdown);
          }
        });
        final large = fastestOf(3, () => service.parseDeck(largeMarkdown));
        final verhouding = large.inMicroseconds / small.inMicroseconds;
        if (verhouding < laagste) laagste = verhouding;
      }

      // Lineair gedrag ligt op 1x, kwadratisch op 4x; 2,5x ligt daar ruim
      // tussenin.
      expect(
        laagste,
        lessThan(2.5),
        reason:
            'parsen van 200 slides kostte ${laagste.toStringAsFixed(2)}x '
            'zoveel als $grootteFactor keer 50 slides; meer dan 2,5x wijst '
            'op superlineair gedrag',
      );
    });

    test(
      'lokaal opslaan schaalt niet met reeds opgeslagen afbeeldingsbytes',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'ocideck_save_perf_',
        );
        addTearDown(() => temp.delete(recursive: true));
        final small = Directory(p.join(temp.path, 'small'))..createSync();
        final large = Directory(p.join(temp.path, 'large'))..createSync();
        final storedImage = File(p.join(large.path, 'images', 'bestaand.png'))
          ..createSync(recursive: true);
        final handle = storedImage.openSync(mode: FileMode.write);
        handle.setPositionSync(ImageService.maxImageBytes - 1);
        handle.writeByteSync(0);
        handle.closeSync();

        final slides = List.generate(
          150,
          (i) => Slide.create(SlideType.image).copyWith(
            title: 'Afbeelding $i',
            imagePath: 'images/image-$i.png',
            imageCaption: 'Bronvermelding $i',
          ),
        );
        final deck = Deck(title: 'Opslagmeting', slides: slides);
        final files = FileService(
          MarkdownService(),
          ImageService(),
          () => const ThemeProfile(),
        );
        final smallPath = p.join(small.path, 'deck.md');
        final largePath = p.join(large.path, 'deck.md');
        await files.saveDeck(deck, smallPath);
        await files.saveDeck(deck, largePath);

        final smallSave = await _fastestAsync(3, () async {
          await files.saveDeck(deck, smallPath);
        });
        final largeSave = await _fastestAsync(3, () async {
          await files.saveDeck(deck, largePath);
        });

        expect(
          largeSave.inMicroseconds,
          lessThan(smallSave.inMicroseconds * 3 + 100000),
          reason:
              'opslaan ging van $smallSave zonder beeldarchief naar $largeSave '
              'met 64 MiB reeds opgeslagen beeld; bestaande bytes horen bij een '
              'tekstwijziging niet opnieuw gelezen en gehasht te worden',
        );
      },
    );
  });
}
