// De beeldcontrole, met echte afbeeldingen uit de eigen assets.
//
// ── Lees dit voordat je deze test vertrouwt ──────────────────────────────────
//
// De native OpenCV-laag laadt **niet** onder `flutter test`: die draait op de
// Dart-VM zonder de frameworks die een app-bundel wél meekrijgt. Alles hier
// bewaakt daarom het *contract*, niet de detectiekwaliteit:
//
//   * draait de native laag niet, dan moet `isSupported` dat zeggen en mag
//     `countFaces` geen stille nul teruggeven die op "niets gevonden" lijkt;
//   * draait ze wél (een integratierun, een ontwikkelaar met de dylib op zijn
//     pad), dan horen katten en logo's nul gezichten op te leveren.
//
// Dat de detector werkelijk gezichten víndt, is met deze test niet aangetoond.
// Dat vraagt een echte app-run met een afbeelding waar iemand op staat — zie
// OCIWACHT.md, fase beeldcontrole.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/privacy/image_face_scan.dart';
import 'package:ocideck/services/privacy/image_face_scan_io.dart'
    show faceScanDimensionsWithinBudget;
// Rechtstreeks, want op desktop kiest de voorwaardelijke import de native kant.
import 'package:ocideck/services/privacy/image_face_scan_stub.dart';

/// Een PNG met niets dan een geldige signatuur en een IHDR die [width] × [height]
/// claimt. Precies wat een aanvaller stuurt: een paar tientallen bytes op schijf
/// die een decoder gigabytes laten reserveren. Zonder IDAT, want de poort hoort
/// toe te slaan lang voordat er iets te decoderen valt.
///
/// Twee dingen moeten écht kloppen, anders toetst de test niets: de afsluitende
/// IEND (zonder die chunk loopt de koplezer voorbij het einde van de bytes en
/// gooit hij) en de CRC van elke chunk (de PNG-lezer controleert die wél). In
/// beide gevallen weigert de poort dan nog steeds — maar om de verkéérde reden,
/// en dan zou deze groep groen staan met een kapotte grens. Allebei één keer
/// gebeurd tijdens het schrijven hiervan.
Uint8List pngHeader(int width, int height) {
  List<int> chunk(String type, List<int> data) {
    final typed = [...ascii.encode(type), ...data];
    return [..._uint32(data.length), ...typed, ..._uint32(getCrc32(typed))];
  }

  return Uint8List.fromList([
    137, 80, 78, 71, 13, 10, 26, 10, // PNG-signatuur
    ...chunk('IHDR', [
      ..._uint32(width),
      ..._uint32(height),
      8, 0, 0, 0, 0, // bitdiepte 8, grijswaarden, geen interlace
    ]),
    ...chunk('IEND', const []),
  ]);
}

List<int> _uint32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

void main() {
  late ImageFaceScanner scanner;

  setUpAll(() {
    final model = File(
      'assets/models/face_detection_yunet_2023mar.onnx',
    ).readAsBytesSync();
    scanner = createImageFaceScanner(model);
  });

  tearDownAll(() => scanner.dispose());

  Uint8List asset(String name) => File('assets/images/$name').readAsBytesSync();

  test('het model zit in de repo en is niet leeggelopen', () {
    // Een LFS-pointer van 131 bytes ziet er in git precies zo uit als een model.
    // Deze test is er omdat dat de eerste poging was.
    final model = File('assets/models/face_detection_yunet_2023mar.onnx');
    expect(model.existsSync(), isTrue);
    expect(model.lengthSync(), 232589);
  });

  test('een onbeschikbare detector zegt dat, in plaats van nul te melden', () {
    // De kern van het contract. Faalt dit, dan meldt de app "geen gezichten
    // gevonden" op een machine waar niet gekeken is — en dat is precies de
    // stille nul waar deze hele controle niet in mag trappen.
    if (scanner.isSupported) return;
    expect(scanner.isSupported, isFalse);
  });

  group('met een werkende native laag', () {
    setUp(() {
      if (!scanner.isSupported) {
        markTestSkipped(
          'native OpenCV-laag niet beschikbaar onder flutter test',
        );
      }
    });

    test('een kat is geen persoon', () async {
      // Een detector die hierop aanslaat, meldt straks een persoonsgegeven op
      // elke dia met een huisdier.
      if (!scanner.isSupported) return;
      expect((await scanner.countFaces(asset('cat-keiko.jpg'))).faces, 0);
      expect((await scanner.countFaces(asset('cat-otis.jpg'))).faces, 0);
    });

    test('een logo is geen persoon', () async {
      if (!scanner.isSupported) return;
      expect((await scanner.countFaces(asset('ocideck-logo.png'))).faces, 0);
      expect((await scanner.countFaces(asset('librekat-logo.png'))).faces, 0);
    });
  });

  group('robuustheid — geldt met en zonder native laag', () {
    test('lege bytes geven nul, geen fout', () async {
      final r = await scanner.countFaces(Uint8List(0));
      expect(r.faces, 0);
      // En het zegt dat het niet gekeken heeft, in plaats van "niets gevonden".
      expect(r.readable, isFalse);
    });

    test('onleesbare bytes geven nul, geen fout', () async {
      // Een .svg of een half gedownload bestand hoort de kwaliteitscontrole
      // niet te breken.
      final r = await scanner.countFaces(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(r.faces, 0);
      expect(r.readable, isFalse);
    });

    test('een absurd groot bestand wordt overgeslagen', () async {
      // Niet gedecodeerd, dus ook niet traag: de grens wordt op de byte-lengte
      // getrokken, vóór het decoderen.
      final r = await scanner.countFaces(Uint8List(25 * 1024 * 1024));
      expect(r.faces, 0);
      expect(r.readable, isFalse);
    });

    test('een afbeelding met absurde afmetingen wordt overgeslagen', () async {
      final r = await scanner.countFaces(pngHeader(30000, 30000));
      expect(r.faces, 0);
      expect(r.readable, isFalse);
    });
  });

  // De bytecap is géén afmetingscap. Wat `cv.imdecode` alloceert hangt aan
  // breedte × hoogte × 3, niet aan de bestandsgrootte: een egale PNG van
  // 30000 × 30000 blijft ruim onder de 24 MiB en wordt 2,7 GB in het geheugen —
  // buiten de Dart-heap, dus geen `try` vangt dat. Deze poort leest de kop en
  // weigert vóór het decoderen.
  //
  // Rechtstreeks getoetst en niet via `countFaces`, omdat die zonder native
  // laag al bij `isSupported` afslaat en de test dan vacuüm groen zou staan.
  group('afmetingspoort vóór het decoderen', () {
    test('een kop die 30000 × 30000 claimt komt er niet door', () {
      expect(faceScanDimensionsWithinBudget(pngHeader(30000, 30000)), isFalse);
    });

    test('ook een langgerekte kop telt op oppervlak, niet op één as', () {
      // 40000 × 2000 = 80 Mpx: geen enkele as is absurd, het product wel.
      expect(faceScanDimensionsWithinBudget(pngHeader(40000, 2000)), isFalse);
    });

    test('een gewone afbeelding uit de assets komt er wél door', () {
      expect(faceScanDimensionsWithinBudget(asset('cat-keiko.jpg')), isTrue);
      expect(faceScanDimensionsWithinBudget(asset('ocideck-logo.png')), isTrue);
    });

    test('vlak onder de grens mag, vlak erboven niet', () {
      expect(faceScanDimensionsWithinBudget(pngHeader(6000, 6000)), isTrue);
      expect(faceScanDimensionsWithinBudget(pngHeader(6500, 6500)), isFalse);
    });

    test('een onleesbare kop wordt geweigerd, niet gegokt', () {
      // Fail-closed: wie de kop niet kan lezen, weet de afmeting niet, en dan
      // is doorlopen naar imdecode precies het gat.
      expect(faceScanDimensionsWithinBudget(Uint8List(0)), isFalse);
      expect(
        faceScanDimensionsWithinBudget(Uint8List.fromList([1, 2, 3, 4, 5])),
        isFalse,
      );
    });

    test('een kop die nul beeldpunten claimt telt niet als "past"', () {
      expect(faceScanDimensionsWithinBudget(pngHeader(0, 0)), isFalse);
    });
  });

  // ── Beschadigde invoer, met een échte kop ─────────────────────────────────
  //
  // De groep hierboven toetst verzonnen koppen en losse rommel. Dat is niet de
  // invoer waar een decoder op omvalt: die ziet er van voren normaal uit en gaat
  // pas verderop stuk. Dit is de niet-geheugenveilige laag — `cv.imdecode` is
  // C++, en het is de enige plek in dit project waar niet-vertrouwde bytes een
  // native decoder bereiken (QA.05, #553).
  //
  // **Wat hier gemeten is, en niet aangenomen.** De poort en de twee formaten
  // gedragen zich verschillend, en dat verschil is de kern van het verhaal:
  //
  //   * **PNG faalt altijd dicht.** Elke afkapping en elke verminking — ook
  //     alleen de laatste honderd bytes — laat de koplezer weigeren, want PNG
  //     heeft een CRC per chunk en een verplichte IEND. Beschadigde PNG-bytes
  //     bereiken `cv.imdecode` dus nooit.
  //   * **JPEG komt er wél doorheen.** De afmetingen staan in de SOF-markering
  //     vooraan en er is geen checksum, dus een JPEG met een verminkt beeldveld
  //     is voor de poort een gewone afbeelding. Die bytes gáán de C++-decoder in.
  //
  // Dat is geen gat maar de grens van wat deze poort ís: hij begrenst de
  // *allocatie* (breedte × hoogte), niet de *inhoud*. Wat de inhoud opvangt is
  // de `try` in `countFaces` plus het onleesbaar-contract hieronder.
  group('beschadigde afbeeldingen', () {
    /// De eerste [keep] bytes van een echte asset — een halve upload, of een
    /// bestand dat een transportfout niet heeft overleefd.
    Uint8List truncated(String name, int keep) =>
        Uint8List.sublistView(asset(name), 0, keep);

    /// Een echte kop met bewust verminkt beeldveld erachter.
    Uint8List corruptBody(String name) {
      final bytes = Uint8List.fromList(asset(name));
      for (var i = bytes.length ~/ 2; i < bytes.length; i++) {
        bytes[i] = (i * 37 + 11) & 0xFF;
      }
      return bytes;
    }

    test('een afgekapt bestand komt nooit door de poort', () {
      // Ook ruim voorbij de kop niet: 4 KiB is lang na de IHDR/SOF, en het
      // antwoord blijft nee. Gemeten op beide formaten, 8 t/m 4096 bytes.
      for (final name in const ['ocideck-logo.png', 'cat-keiko.jpg']) {
        for (final keep in const [8, 32, 64, 512, 4096]) {
          expect(
            faceScanDimensionsWithinBudget(truncated(name, keep)),
            isFalse,
            reason: '$name afgekapt op $keep bytes',
          );
        }
      }
    });

    test('een verminkte PNG faalt dicht, een verminkte JPEG niet', () {
      // Geen bug, maar de grens van de poort — en juist daarom vastgelegd: gaat
      // dit ooit stilletjes de andere kant op, dan verandert er iets aan welke
      // bytes de C++-decoder bereiken, en dat hoort niemand per ongeluk te doen.
      expect(
        faceScanDimensionsWithinBudget(corruptBody('ocideck-logo.png')),
        isFalse,
        reason: 'PNG heeft een CRC per chunk en een verplichte IEND',
      );
      expect(
        faceScanDimensionsWithinBudget(corruptBody('cat-keiko.jpg')),
        isTrue,
        reason:
            'JPEG draagt zijn afmetingen in de SOF zonder checksum; deze bytes '
            'gaan dus wél de native decoder in, en dat is wat de try in '
            'countFaces moet opvangen',
      );
    });

    test('een kapotte afbeelding levert onleesbaar op, en geen worp', () async {
      // Het gedrag dat telt: één stukgelopen afbeelding mag de controle niet
      // meenemen, en mag al helemaal geen nul melden alsof er gekeken is.
      //
      // Zonder native laag valt dit op `isSupported` en is het een contracttest;
      // mét native laag (DARTCV_LIB_PATH gezet) gaat de verminkte JPEG hierboven
      // werkelijk door de C++-decoder heen. Dát is de run waar dit voor bedoeld
      // is, en de reden dat de JPEG in deze lijst staat.
      for (final bytes in [
        truncated('ocideck-logo.png', 64),
        truncated('cat-keiko.jpg', 512),
        corruptBody('ocideck-logo.png'),
        corruptBody('cat-keiko.jpg'),
      ]) {
        final result = await scanner.countFaces(bytes);
        expect(result.faces, 0);
        expect(
          result.readable,
          isFalse,
          reason:
              'een beschadigde afbeelding hoort "hier kon ik niet kijken" te '
              'zeggen, niet "ik heb gekeken en niets gevonden"',
        );
      }
    });
  });

  group('de webvariant', () {
    // Op het web bestaat FFI niet en is er dus geen detector. Deze helft moet
    // dat zéggen in plaats van nul gezichten te melden — anders leest een lege
    // uitslag daar als "niets gevonden".
    final web = createPlatformImageFaceScanner(Uint8List(0));

    test('meldt zichzelf als niet-beschikbaar', () {
      expect(web.isSupported, isFalse);
    });

    test('telt niets, en gooit niet', () async {
      expect((await web.countFaces(Uint8List.fromList([1, 2, 3]))).faces, 0);
      web.dispose();
    });
  });
}
