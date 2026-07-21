import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/document_signature.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/slide_rasterizer.dart';
import 'package:ocideck/services/web_asset_store.dart';

/// De rasterizer is de ENIGE renderweg naar PDF en PPTX — en naar "dia als
/// afbeelding kopiëren". Wat hier uitkomt is letterlijk het artefact dat de
/// klant in handen krijgt; de HTML-export loopt er langs (die krijgt markdown)
/// en raakt hem dus niet.
///
/// Deze tests roepen `rasterize` echt aan en kijken naar de bytes: aantal,
/// afmetingen, en dat er ook werkelijk iets ánders op dia 2 staat dan op dia 1.
/// Stil nul dia's teruggeven, tweemaal hetzelfde beeld capturen of een lege
/// buffer opleveren moet rood worden — dat zijn precies de manieren waarop een
/// export leeg bij de ontvanger aankomt zonder dat er iets klapt.

Deck _deck() => Deck(
  title: 'Pentestrapport',
  slides: [
    Slide.create(
      SlideType.title,
    ).copyWith(title: 'Beveiligingsonderzoek', subtitle: 'Eindrapportage'),
    Slide.create(SlideType.bullets).copyWith(
      title: 'Belangrijkste bevindingen',
      bullets: const [
        'Verouderde TLS-configuratie op de portal',
        'Sessiecookie zonder HttpOnly',
        'Geen snelheidsbegrenzing op het aanmeldformulier',
      ],
    ),
    Slide.create(SlideType.table).copyWith(
      title: 'Planning',
      tableRows: const [
        ['Fase', 'Start', 'Eind'],
        ['Verkenning', '2026-01-05', '2026-01-09'],
        ['Uitbuiting', '2026-01-12', '2026-01-16'],
      ],
    ),
    Slide.create(SlideType.quote).copyWith(
      title: 'Zonder bewijs is het een mening.',
      subtitle: 'De tester',
    ),
  ],
);

/// Pompt een gastboom en geeft een context terug met een root-[Overlay] — dat
/// is wat de rasterizer nodig heeft om zijn onzichtbare diahost in te hangen.
Future<BuildContext> _hostContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return captured;
}

/// Draait `rasterize` en pompt ondertussen frames.
///
/// Beide zijn nodig en geen van beide alleen is genoeg: het capturen
/// (`boundary.toImage`) is echt asynchroon werk en vraagt dus [runAsync], maar
/// de rasterizer wacht per dia op `endOfFrame` en die komt onder de testbinding
/// alleen als iemand pompt. Dus: de future starten, niet meteen afwachten, en
/// pompen tot hij klaar is. De lus is begrensd — blijft de rasterizer hangen,
/// dan valt de test om in plaats van de suite op te hangen.
Future<List<Uint8List>> _rasterize(
  WidgetTester tester,
  Deck deck, {
  int targetWidth = 640,
  void Function(int done, int total)? onProgress,
  void Function(String phase, int done, int total)? onStage,
  bool Function()? isCancelled,
}) async {
  final context = await _hostContext(tester);
  final audience = PrivacyProjection.forAudience(deck);

  List<Uint8List>? result;
  Object? failure;
  await tester.runAsync(() async {
    unawaited(
      SlideRasterizer.rasterize(
        context: context,
        audience: audience,
        targetWidth: targetWidth,
        onProgress: onProgress,
        onStage: onStage,
        isCancelled: isCancelled,
      ).then(
        (value) => result = value,
        onError: (Object error) => failure = error,
      ),
    );
    for (var i = 0; i < 900 && result == null && failure == null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  });

  if (failure != null) fail('rasterize wierp: $failure');
  expect(result, isNotNull, reason: 'rasterize werd niet klaar binnen de lus');
  return result!;
}

/// Decodeert [png] echt — een lege of afgekapte buffer komt hier niet doorheen.
Future<({int width, int height, Uint8List rgba})> _decode(
  WidgetTester tester,
  Uint8List png,
) async {
  late ({int width, int height, Uint8List rgba}) out;
  await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final rgba = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    out = (
      width: frame.image.width,
      height: frame.image.height,
      rgba: rgba!.buffer.asUint8List(),
    );
    frame.image.dispose();
    codec.dispose();
  });
  return out;
}

/// Schrijft een effen PNG van 64x64 naar [dir] en geeft het bestand terug.
Future<File> _writeSolidPng(Directory dir, String name, Color colour) async {
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(await _solidPngBytes(colour));
  return file;
}

Future<Uint8List> _solidPngBytes(Color colour) async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = colour);
  final image = await recorder.endRecording().toImage(64, 64);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Een ingebedde handtekening-tekening, zoals het tekenvenster hem opslaat.
Future<String> _signatureDataUri() async {
  final bytes = await _solidPngBytes(const Color(0xFF102030));
  return 'data:image/png;base64,${base64Encode(bytes)}';
}

/// Of [colour] ergens in het beeld voorkomt (met wat speling voor schaling en
/// anti-aliasing).
bool _hasColourNear(
  ({int width, int height, Uint8List rgba}) img,
  Color colour, {
  int tolerance = 40,
}) {
  final wantR = (colour.r * 255).round();
  final wantG = (colour.g * 255).round();
  final wantB = (colour.b * 255).round();
  for (var i = 0; i + 3 < img.rgba.length; i += 4) {
    if ((img.rgba[i] - wantR).abs() <= tolerance &&
        (img.rgba[i + 1] - wantG).abs() <= tolerance &&
        (img.rgba[i + 2] - wantB).abs() <= tolerance &&
        img.rgba[i + 3] > 200) {
      return true;
    }
  }
  return false;
}

/// Hoeveel verschillende kleuren er in het beeld staan. Eén betekent: een
/// egale vlakte, dus niets getekend.
int _distinctColours(Uint8List rgba) {
  final seen = <int>{};
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    seen.add(
      (rgba[i] << 24) | (rgba[i + 1] << 16) | (rgba[i + 2] << 8) | rgba[i + 3],
    );
    if (seen.length > 8) break;
  }
  return seen.length;
}

void main() {
  testWidgets('levert per dia decodeerbare PNG-bytes in 16:9', (tester) async {
    final deck = _deck();
    final images = await _rasterize(tester, deck);

    expect(
      images.length,
      deck.slides.length,
      reason: 'elke dia hoort één afbeelding op te leveren',
    );

    for (var i = 0; i < images.length; i++) {
      final png = images[i];
      expect(png, isNotEmpty, reason: 'dia $i leverde een lege buffer');
      // PNG-magie: \x89PNG. Een willekeurige byte-brij komt hier niet langs.
      expect(png.sublist(0, 4), [
        0x89,
        0x50,
        0x4E,
        0x47,
      ], reason: 'dia $i is geen PNG');

      final img = await _decode(tester, png);
      expect(img.width, 640);
      expect(img.height, 360, reason: '16:9 hoort bij 640 breed 360 hoog');
      expect(
        _distinctColours(img.rgba),
        greaterThan(1),
        reason: 'dia $i is een egale vlakte — er is niets getekend',
      );
    }
  });

  testWidgets('elke dia krijgt zijn eigen beeld, niet steeds hetzelfde', (
    tester,
  ) async {
    final deck = _deck();
    final images = await _rasterize(tester, deck);
    // Eerst het aantal: met een lege lijst is "alles uniek" triviaal waar.
    expect(images, hasLength(deck.slides.length));

    // De rasterizer hangt één diahost op en wisselt de dia daarin om. Wisselt
    // hij niet (of capture hij vóór de herbouw), dan komen er N identieke
    // afbeeldingen uit en ziet niemand dat aan de bestandsgrootte.
    final unique = images.map(Object.hashAll).toSet();
    expect(
      unique.length,
      images.length,
      reason: 'vier verschillende diatypen mogen geen identiek beeld geven',
    );
  });

  testWidgets('de standaardbreedte is de gedocumenteerde 1920x1080', (
    tester,
  ) async {
    final deck = Deck(
      title: 'Eén dia',
      slides: [
        Slide.create(SlideType.title).copyWith(title: 'Volledige resolutie'),
      ],
    );

    late List<Uint8List> images;
    // targetWidth niet meegeven: dit toetst de standaardwaarde uit de API.
    final context = await _hostContext(tester);
    final audience = PrivacyProjection.forAudience(deck);
    await tester.runAsync(() async {
      List<Uint8List>? result;
      unawaited(
        SlideRasterizer.rasterize(
          context: context,
          audience: audience,
        ).then((value) => result = value),
      );
      for (var i = 0; i < 900 && result == null; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      images = result!;
    });

    final img = await _decode(tester, images.single);
    expect(img.width, 1920);
    expect(img.height, 1080);
  });

  testWidgets('meldt voortgang tot en met de laatste dia', (tester) async {
    final progress = <int>[];
    final stages = <String>{};
    final deck = _deck();

    final images = await _rasterize(
      tester,
      deck,
      onProgress: (done, _) => progress.add(done),
      onStage: (phase, _, _) => stages.add(phase),
    );

    expect(images.length, deck.slides.length);
    expect(progress, [
      for (var i = 1; i <= deck.slides.length; i++) i,
    ], reason: 'de voortgang loopt op van 1 tot het aantal dias');
    // De fasen die het exportvenster als tekst toont; valt er één weg, dan
    // blijft de gebruiker naar "renderen…" kijken zonder dat er iets beweegt.
    expect(stages, containsAll(['precache', 'prepare', 'render', 'done']));
  });

  testWidgets('afbreken stopt en geeft een onvolledige lijst terug', (
    tester,
  ) async {
    final deck = _deck();
    var rendered = 0;

    final images = await _rasterize(
      tester,
      deck,
      onProgress: (done, _) => rendered = done,
      // Na de eerste dia vragen om te stoppen.
      isCancelled: () => rendered >= 1,
    );

    expect(images, hasLength(1));
    expect(
      images.length,
      lessThan(deck.slides.length),
      reason: 'de aanroeper hoort een onvolledige lijst te herkennen',
    );
  });

  testWidgets('een deck zonder dias levert niets op', (tester) async {
    final images = await _rasterize(tester, const Deck(title: 'Leeg'));
    expect(images, isEmpty);
  });

  // De beeldweg is de plek waar het één keer echt is misgegaan: de globale
  // beeldcache heeft een bescheiden budget, dus bij een deck met foto's werden
  // de eerste dia's uit de cache gegooid voordat de latere gecaptured waren en
  // verdween élke afbeelding na een handvol dia's. Vandaar dat het voorladen
  // hier ook echt door de rasterizer heen loopt, met bestanden op schijf.
  testWidgets('laadt dia-afbeeldingen en het logo voor en tekent ze', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ocideck_raster');
    addTearDown(() => dir.deleteSync(recursive: true));

    late Deck deck;
    await tester.runAsync(() async {
      await _writeSolidPng(dir, 'foto.png', const Color(0xFFE10000));
      await _writeSolidPng(dir, 'logo.png', const Color(0xFF00A0FF));
      deck = Deck(
        title: 'Met beeld',
        projectPath: dir.path,
        themeProfile: const ThemeProfile(logoPath: 'logo.png', logoSize: 48),
        // Een tekening als handtekening: een ingebedde data-URI, dus geen
        // bestandspad. Die gaat via een eigen tak door het voorladen.
        signature: DocumentSignature(
          name: 'A. Tester',
          role: 'Onderzoeker',
          imagePath: await _signatureDataUri(),
        ),
        slides: [
          Slide.create(SlideType.image).copyWith(
            title: 'Bewijsmateriaal',
            imagePath: 'foto.png',
            imageCaption: 'Schermafdruk van de portal',
          ),
          Slide.create(SlideType.bullets).copyWith(
            title: 'Toelichting',
            bullets: const ['De afdruk hierboven hoort bij bevinding 1'],
          ),
        ],
      );
    });

    final images = await _rasterize(tester, deck, targetWidth: 640);
    expect(images, hasLength(2));

    final withPhoto = await _decode(tester, images.first);
    expect(withPhoto.width, 640);
    expect(withPhoto.height, 360);
    expect(
      _hasColourNear(withPhoto, const Color(0xFFE10000)),
      isTrue,
      reason:
          'de dia-afbeelding staat niet in het raster — precies het geval '
          'waarin de export leeg oogt zonder dat er iets klapt',
    );
    expect(
      _hasColourNear(withPhoto, const Color(0xFF00A0FF)),
      isTrue,
      reason: 'het logo uit het stijlprofiel ontbreekt in het raster',
    );
  });

  // Een afbeelding in de vrije tekst moet net zo goed voorgeladen worden als
  // eentje in een afbeeldingsveld: zonder precache is hij nog niet gedecodeerd
  // wanneer het beeldje wordt vastgelegd, en staat er een leeg vak in de PDF.
  // Het voorladen meldt zijn totaal via onStage, dus dáár is te zien of hij
  // meegeteld is.
  testWidgets('laadt ook een afbeelding uit de vrije tekst voor', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ocideck_raster_inline');
    addTearDown(() => dir.deleteSync(recursive: true));

    late Deck deck;
    await tester.runAsync(() async {
      await _writeSolidPng(dir, 'tekstfoto.png', const Color(0xFF7B1FA2));
      deck = Deck(
        title: 'Tekst met beeld',
        projectPath: dir.path,
        slides: [
          Slide.create(SlideType.freeMarkdown).copyWith(
            title: 'Verhaal',
            customMarkdown: 'Kijk:\n\n![w:400 de foto](tekstfoto.png)\n',
          ),
        ],
      );
    });

    var precacheTotal = 0;
    await _rasterize(
      tester,
      deck,
      targetWidth: 640,
      onStage: (phase, _, total) {
        if (phase == 'precache') precacheTotal = total;
      },
    );

    expect(
      precacheTotal,
      1,
      reason: 'de afbeelding uit de tekst hoort in het voorladen te zitten',
    );
  });

  // Twee paden die géén bestand op schijf zijn en die de gewone padresolutie
  // dus ongemoeid moet laten: een `mem:`-afbeelding (webversie, bytes in het
  // geheugen) en een `asset:`-logo (ingebouwd stijlprofiel). Gaat een van beide
  // toch door `resolveSlideAssetPath`, dan valt hij eruit als "buiten het
  // project" en rastert de dia zonder beeld.
  testWidgets('mem:- en asset:-paden overleven de padresolutie', (
    tester,
  ) async {
    addTearDown(() => WebAssetStore.retain(const {}));

    late Deck deck;
    await tester.runAsync(() async {
      final memPath = WebAssetStore.put(
        await _solidPngBytes(const Color(0xFF00C853)),
        name: 'geheugen.png',
      );
      deck = Deck(
        title: 'Zonder schijf',
        // Bewust géén projectPath: een mem:-pad hoort ook zonder project door
        // te komen.
        themeProfile: ThemeProfile.libreKat,
        slides: [
          Slide.create(
            SlideType.image,
          ).copyWith(title: 'Uit het geheugen', imagePath: memPath),
        ],
      );
    });

    final images = await _rasterize(tester, deck);
    final img = await _decode(tester, images.single);

    expect(
      _hasColourNear(img, const Color(0xFF00C853)),
      isTrue,
      reason: 'de mem:-afbeelding staat niet in het raster',
    );
  });
}
