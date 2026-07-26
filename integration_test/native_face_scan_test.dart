// Integratietest: de ECHTE native OpenCV-laag, in een echte app-engine.
//
// ── Waarom dit bestaat naast test/image_face_scan_test.dart ──────────────────
//
// Onder `flutter test` laadt dartcv4 2.x zijn native code-assets niet: die
// `@Native`/`@DefaultAsset`-bindingen worden niet in de test-VM geladen, dus de
// native gezichtsscan slaat zich daar over (zie de kop van die unit-test). Die
// test bewaakt het *contract* zonder native laag; dit bestand bewaakt de laag
// zélf.
//
// Een integratietest draait als een echte app op een echt platform (desktop),
// en dáár laden de native-assets wél — precies zoals de app bij de gebruiker.
// Dit is de enige plek waar het volgende werkelijk wordt aangetoond i.p.v.
// overgeslagen:
//
//   * de native laag is beschikbaar (`isSupported`) — de regressiewachter tegen
//     een wijziging die de detector stil uitzet, zoals de dartcv4-migratie deed;
//   * echte scans doen het juiste: katten en logo's leveren nul gezichten;
//   * niet-vertrouwde, verminkte bytes gaan écht de C++-decoder in en falen
//     dicht — "hier kon ik niet kijken", geen stille nul (QA.05, #553).
//
// Draaien:
//   flutter test integration_test/native_face_scan_test.dart -d macos
//   flutter test integration_test/native_face_scan_test.dart -d linux
//   flutter test integration_test/native_face_scan_test.dart -d windows

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ocideck/services/privacy/image_face_scan.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ImageFaceScanner scanner;

  // rootBundle.load geeft een ByteData die een *view* op een gedeelde buffer kan
  // zijn; `.buffer.asUint8List()` zonder offset/lengte levert dan de hele buffer
  // (met vreemde bytes erachter) en laat imdecode falen. Lees exact de asset.
  Uint8List bytesOf(ByteData d) =>
      d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);

  setUpAll(() async {
    final model = bytesOf(
      await rootBundle.load('assets/models/face_detection_yunet_2023mar.onnx'),
    );
    scanner = createImageFaceScanner(model);
  });

  tearDownAll(() => scanner.dispose());

  Future<Uint8List> asset(String name) async =>
      bytesOf(await rootBundle.load('assets/images/$name'));

  test('de native OpenCV-laag laadt echt op dit platform', () {
    // De kern van deze hele test. Op een echt platform MOET de native laag er
    // zijn; is die er niet, dan is de detector uitgevallen (zoals hij onder
    // flutter test op elk platform stil uit stond) en meldt de app straks
    // "geen gezichten" zonder gekeken te hebben.
    expect(
      scanner.isSupported,
      isTrue,
      reason: 'native OpenCV hoort op desktop beschikbaar te zijn',
    );
  });

  test('een kat is geen persoon', () async {
    // Een detector die hierop aanslaat, meldt straks een persoonsgegeven op elke
    // dia met een huisdier.
    expect((await scanner.countFaces(await asset('cat-keiko.jpg'))).faces, 0);
    expect((await scanner.countFaces(await asset('cat-otis.jpg'))).faces, 0);
  });

  test('een logo is geen persoon', () async {
    expect(
      (await scanner.countFaces(await asset('ocideck-logo.png'))).faces,
      0,
    );
    expect(
      (await scanner.countFaces(await asset('librekat-logo.png'))).faces,
      0,
    );
  });

  test('een leesbare afbeelding wordt als leesbaar gerapporteerd', () async {
    // Bewijst dat decoder én detector werkelijk lopen (readable == true): een nul
    // die uit "gekeken en niets gevonden" komt, niet uit "niet kunnen kijken".
    // Deze test viel om zolang de OpenCV-build `objdetect`/`dnn` miste: dan
    // klapte de scanner na de eerste afbeelding om naar niet-beschikbaar.
    final r = await scanner.countFaces(await asset('cat-keiko.jpg'));
    expect(r.readable, isTrue);
    expect(r.faces, 0);
  });

  test('een verminkte JPEG faalt dicht in de native decoder', () async {
    // De enige plek waar niet-vertrouwde bytes een C++-decoder bereiken: een
    // JPEG draagt zijn afmetingen zonder checksum, dus verminkte body-bytes
    // komen door de afmetingspoort en gaan écht de native imdecode in. Dat mag
    // de controle niet meenemen en geen stille nul melden.
    final bytes = Uint8List.fromList(await asset('cat-keiko.jpg'));
    for (var i = bytes.length ~/ 2; i < bytes.length; i++) {
      bytes[i] = (i * 37 + 11) & 0xFF;
    }
    final r = await scanner.countFaces(bytes);
    expect(r.faces, 0);
    expect(
      r.readable,
      isFalse,
      reason:
          'een kapotte afbeelding hoort "hier kon ik niet kijken" te zeggen',
    );
  });
}
