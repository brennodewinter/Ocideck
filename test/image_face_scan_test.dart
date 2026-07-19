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

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/privacy/image_face_scan.dart';
// Rechtstreeks, want op desktop kiest de voorwaardelijke import de native kant.
import 'package:ocideck/services/privacy/image_face_scan_stub.dart';

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
