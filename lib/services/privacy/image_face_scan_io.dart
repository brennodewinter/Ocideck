// De native beeldcontrole: YuNet via OpenCV's dnn-module.
//
// Zie `image_face_scan.dart` voor waarom hier alleen geteld wordt en dit
// daarom geen biometrische verwerking is. Die redenering is de reden dat dit
// bestand zo klein is, en dat hoort zo te blijven.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:dartcv4/dartcv.dart' as cv;

import '../../utils/log.dart';

import 'image_face_scan.dart';

/// De breedtes waarop gedetecteerd wordt, van grof naar fijn.
///
/// **Waarom meer dan één.** YuNet is getraind op gezichten van ongeveer 10 tot
/// 300 pixels. Op één vaste breedte hangt het dus volledig van de compositie af
/// of een gezicht in dat venster valt: een portret heeft een gezicht van halve
/// beeldhoogte, een groepsfoto op een startbaan heeft er acht van dertig pixels.
///
/// Dat is gemeten, niet beredeneerd. Op een reeks van zeven echte foto's vond
/// één vaste breedte van 640 er twee; per foto verschilde de béste breedte, en
/// geen enkele was overal goed:
///
///     foto            orig  1920  1280   640
///     startbaan          0     0     1     0
///     twee personen      3     3     1     0
///     portret staand     0     -     -     1
///
/// Drie schalen met het maximum eroverheen vindt er zes van zeven. De zevende is
/// een strandfoto waarop iemand omlaag kijkt met een zonnebril op — die hoort een
/// gezichtsdetector te missen, en dat is precies waarom de melding "herkenbaar
/// gezicht" zegt en niet "persoon".
///
/// De bovengrens van 1920 is er tegen de kosten: 4K doorrekenen levert boven deze
/// breedte niets extra's op, want de gezichten zitten dan ver boven het bereik
/// waar het model op getraind is.
const List<int> kFaceScanWidths = [1920, 1280, 640];

/// Boven deze bestandsgrootte slaan we een afbeelding over.
///
/// Een dia met een RAW-scan van 80 MB hoort de kwaliteitscontrole niet te laten
/// haperen. De grens is ruim: gewone dia-afbeeldingen zitten er ver onder.
const int kFaceScanMaxBytes = 24 * 1024 * 1024;

/// Boven dit aantal beeldpunten slaan we een afbeelding over — gemeten aan de
/// **kop** van het bestand, dus vóór er iets gedecodeerd is.
///
/// [kFaceScanMaxBytes] is hiervoor geen vervanging. Wat `cv.imdecode` alloceert
/// hangt niet aan de bestandsgrootte maar aan breedte × hoogte × 3: een egale
/// PNG van 30000 × 30000 is nog geen megabyte op schijf en wordt 2,7 GB in het
/// geheugen. Die allocatie gebeurt buiten de Dart-heap, dus een `try` eromheen
/// vangt hem niet — het proces valt om. En dit draait standaard, zodra een deck
/// met afbeeldingen open staat, op bestanden die uit dat deck komen.
///
/// 40 megapixel is ruim: een foto uit een moderne camera zit rond de 24, een
/// 4K-schermafdruk op 8. De gedecodeerde matrix blijft daarmee onder ~120 MB, en
/// alles wordt daarna toch teruggeschaald naar [kFaceScanWidths].
const int kFaceScanMaxPixels = 40 * 1000 * 1000;

/// Leest alléén de kop van [imageBytes] en zegt of de afmetingen binnen
/// [kFaceScanMaxPixels] vallen. Draait vóór `cv.imdecode`.
///
/// **Fail-closed.** Is de kop niet te lezen, dan is het antwoord nee. Dat kost
/// niets: een formaat waarvan wij de kop niet kunnen lezen, gaf hierna toch al
/// `unreadable` terug — HEIC is daarvan het voorbeeld in [ImageFaceScanner]. Het
/// alternatief, bij twijfel toch decoderen, laat precies het geval door waar
/// deze poort voor bestaat: de aanvaller kiest zijn eigen kop.
///
/// `startDecode` doet wat de naam belooft: het leest de kop (bij PNG de IHDR,
/// bij JPEG de SOF-markering) en zet nog geen enkel beeldpunt om. De
/// image-bibliotheek zat al in het project, dus dit kost geen afhankelijkheid.
///
/// Staat los van de klasse zodat de poort toetsbaar is zónder native laag: die
/// laadt niet onder `flutter test` (zie de kop van `image_face_scan_test.dart`),
/// en dan zou een test via `countFaces` vacuüm groen staan.
///
/// Geeft de afmetingen en geen bool: de decode-vlagkeuze in `countFaces` heeft
/// de bronbreedte nodig, en de pixelpoort is een afleiding daarvan.
({int width, int height})? faceScanHeaderDimensions(Uint8List imageBytes) {
  try {
    final info = img.findDecoderForData(imageBytes)?.startDecode(imageBytes);
    if (info == null || info.width <= 0 || info.height <= 0) return null;
    return (width: info.width, height: info.height);
  } catch (e, s) {
    // Bewust zonder pad of dianummer: zie de toelichting bij de catch in
    // [ImageFaceScanner.countFaces] — dit gaat over beeld mét personen erop.
    logError('faceScanHeaderDimensions', e, s);
    return null;
  }
}

/// Binnen [kFaceScanMaxPixels]? De kop-lezing van voorheen, nu bovenop
/// [faceScanHeaderDimensions].
bool faceScanDimensionsWithinBudget(Uint8List imageBytes) {
  final dims = faceScanHeaderDimensions(imageBytes);
  if (dims == null) return false;
  return dims.width * dims.height <= kFaceScanMaxPixels;
}

/// De `IMREAD_REDUCED_*`-vlag voor een bron van [sourceWidth] breed.
///
/// De grootste detectieschaal is 1920 breed (zie [kFaceScanWidths]), dus een
/// 24 MP-foto (6000×4000) hoeft nooit volledig gedecodeerd in het geheugen te
/// staan: `IMREAD_REDUCED_COLOR_2` laat de decoder bij JPEG al tijdens de DCT
/// de helft weg. Gekozen wordt de sterkste reductie die het gedecodeerde beeld
/// nog op of boven de 1920-schaal houdt — verder reduceren zou de fijnste
/// schaal stil kleiner maken, en daarmee precies de kleine gezichten kosten.
int faceScanDecodeFlag(int sourceWidth) {
  const finest = 1920;
  if (sourceWidth >= finest * 8) return cv.IMREAD_REDUCED_COLOR_8;
  if (sourceWidth >= finest * 4) return cv.IMREAD_REDUCED_COLOR_4;
  if (sourceWidth >= finest * 2) return cv.IMREAD_REDUCED_COLOR_2;
  return cv.IMREAD_COLOR;
}

/// De scoredrempel waarboven een treffer als gezicht telt.
///
/// **Het midden van een plateau, niet de rand ervan.** Gemeten op zeven echte
/// foto's plus elf mensloze app-assets:
///
///     drempel   gezichten   valse-positieven
///        0,95           0                  0
///        0,92           8                  0
///        0,90          11                  0
///        0,85          14                  0
///        0,80          14                  0
///        0,70          14                  0
///        0,60          15                  0
///        0,50          15                  2
///
/// Hier stond eerst 0,92, "om zeker te zijn" — en dat bleek drie honderdsten van
/// een detector die letterlijk niets meer vindt. Tussen 0,85 en 0,70 ligt een
/// vlak gebied waar het aantal niet verandert en er geen enkele valse positief
/// bijkomt; pas onder 0,60 begint de precisie te zakken. 0,80 ligt daar in het
/// midden en dus zo ver mogelijk van beide kliffen.
///
/// Wat híer níet in zit, ook gemeten: extra tussenschalen (960, 480) en
/// contrastnormalisatie (CLAHE, voor tegenlicht) leverden geen enkel extra
/// gezicht op. Die complexiteit is dus niet toegevoegd.
///
/// **Waar de klif werkelijk ligt (gemeten 20-07-2026).** Bovenstaande tabel zegt
/// hoevéél er gevonden wordt, niet mét welke score. Dat is later los gemeten, op
/// een echt deck van twaalf afbeeldingen:
///
///     wat                                   score       telt bij 0,85?
///     achtergrondgezicht in een café          0,869      ja
///     idem, tweede persoon                    0,884      ja
///     gezicht op een dia-afbeelding           0,926      ja
///     antropomorfe dierenkoppen (3×)      0,801-0,832    nee
///     echte kattenfoto's (3×)                  —         nee, niets gevonden
///
/// Twee dingen volgen hieruit. Ten eerste zit de klif bij 0,90 en niet bij 0,85:
/// daarboven verdwijnen die twee achtergrondgezichten, en dat verklaart de sprong
/// van 14 naar 11 in de tabel hierboven. Ten tweede is de verleiding om naar 0,85
/// te gaan reëel — dat gat tussen 0,832 en 0,869 is echt — maar de marge boven een
/// écht gezicht krimpt daarmee van 0,069 naar 0,019, en juist de gezichten die er
/// het meest toe doen (klein, onscherp, op de achtergrond, iemand die niet wist
/// dat hij op de foto stond) zijn de gezichten die daar het dichtst tegenaan
/// zitten. Daarom staat hij nog steeds op 0,80.
///
/// **Wat een echte kat níét is.** De negatieven hierboven zijn foto's van katten,
/// en die geven een schone nul. Een getekende of gegenereerde dierenkop mét
/// mensenlichaam is een heel ander geval: frontaal, gelijkmatig belicht, met naar
/// voren gerichte ogen — een uilengezicht is letterlijk een schijf met twee ogen
/// en een snavel ertussen. Die vallen hier net boven de drempel. Dat is geen
/// modelfout die je met een getal wegneemt; daarvoor is de dispositie op de dia
/// de uitweg, zie `_imagesOf` in `image_privacy_provider.dart`.
///
/// Voorbehoud: zeven foto's en elf negatieven is een kleine steekproef, en de
/// meting hierboven voegt er twaalf afbeeldingen uit één deck aan toe. Het
/// plateau is geruststellend, maar dit is geen benchmark.
const double kFaceScanScoreThreshold = 0.80;

/// Of de native laag werkelijk laadt.
///
/// Dit wordt actief getoetst en niet aangenomen. De aanleiding is concreet:
/// onder `flutter test` laadt `libdartcv.dylib` niet, elke aanroep viel in de
/// foutafhandeling, en de scanner meldde vrolijk nul gezichten terwijl er
/// níéts gedetecteerd was. Dat is precies de stille nul waar deze hele
/// controle niet in mag trappen: "wij vonden niets" en "hier is niet gekeken"
/// zijn verschillende uitspraken.
///
/// Staat top-level omdat zowel de directe scanner als de isolate-wrapper hem
/// gebruikt: de UI-isolate proeft één keer, de werk-isolate proeft nog eens in
/// zijn eigen context.
bool _probeNative() {
  try {
    // Eén triviale aanroep die door de native laag moet. Slaagt hij, dan
    // staat de bibliotheek; faalt hij, dan is er geen detector op deze machine.
    final probe = cv.Mat.zeros(1, 1, cv.MatType.CV_8UC1);
    final ok = probe.rows == 1;
    probe.dispose();
    return ok;
  } catch (e, s) {
    logError('ImageFaceScanner.probe', e, s);
    return false;
  }
}

class _OpenCvImageFaceScanner implements ImageFaceScanner {
  final Uint8List _modelBytes;
  cv.FaceDetectorYN? _detector;
  bool? _nativeAvailable;

  _OpenCvImageFaceScanner(this._modelBytes);

  /// Of de native laag werkelijk laadt.
  ///
  /// Dit wordt actief getoetst en niet aangenomen. De aanleiding is concreet:
  /// onder `flutter test` laadt `libdartcv.dylib` niet, elke aanroep viel in de
  /// foutafhandeling, en de scanner meldde vrolijk nul gezichten terwijl er
  /// níéts gedetecteerd was. Dat is precies de stille nul waar deze hele
  /// controle niet in mag trappen: "wij vonden niets" en "hier is niet gekeken"
  /// zijn verschillende uitspraken.
  @override
  bool get isSupported => _nativeAvailable ??= _probeNative();

  @override
  Future<ImageFaceScanResult> countFaces(Uint8List imageBytes) async {
    if (!isSupported || imageBytes.isEmpty) {
      return ImageFaceScanResult.unreadable;
    }
    if (imageBytes.lengthInBytes > kFaceScanMaxBytes) {
      return ImageFaceScanResult.unreadable;
    }
    final dims = faceScanHeaderDimensions(imageBytes);
    if (dims == null || dims.width * dims.height > kFaceScanMaxPixels) {
      return ImageFaceScanResult.unreadable;
    }

    cv.Mat? source;
    try {
      source = cv.imdecode(imageBytes, faceScanDecodeFlag(dims.width));
      // Een formaat dat OpenCV niet kent geeft een lege matrix. Dat is géén
      // "nul gezichten" — HEIC valt hier bijvoorbeeld in, en iPhone-foto's zijn
      // standaard HEIC. Een deck vol iPhone-portretten meldde daardoor niets.
      if (source.isEmpty || source.cols <= 0 || source.rows <= 0) {
        return ImageFaceScanResult.unreadable;
      }
      return ImageFaceScanResult(
        faces: _countAcrossScales(source),
        readable: true,
      );
    } catch (e, s) {
      // Eén kapotte afbeelding mag de hele controle niet meenemen. We zetten de
      // scanner niet stil: de volgende afbeelding kan prima leesbaar zijn.
      // Bewust zonder pad of slide-nummer: dit is de component die over
      // afbeeldingen mét personen gaat, en een logregel is ook een verwerking.
      logError('ImageFaceScanner.countFaces', e, s);
      return ImageFaceScanResult.unreadable;
    } finally {
      source?.dispose();
    }
  }

  /// Het hoogste aantal dat één van de schalen vindt.
  ///
  /// Het maximum en niet het gemiddelde: dit is een waarschuwing, en een gezicht
  /// dat op één schaal zichtbaar is, staat er ook werkelijk op. Bij twijfel
  /// melden is hier de goede kant om ernaast te zitten.
  int _countAcrossScales(cv.Mat source) {
    var best = 0;
    var previousWidth = 0;
    for (final target in kFaceScanWidths) {
      final width = target > source.cols ? source.cols : target;
      // Is de bron al smaller dan de volgende schaal, dan zou die schaal dezelfde
      // meting herhalen. Eén keer is genoeg.
      if (width == previousWidth) continue;
      previousWidth = width;

      final height = (source.rows * width / source.cols).round().clamp(
        1,
        1 << 20,
      );
      final scaled = width == source.cols
          ? source
          : cv.resize(source, (width, height));
      cv.Mat? faces;
      try {
        final detector = _detectorFor(width, height);
        if (detector == null) return best;
        faces = detector.detect(scaled);
        // **Hier zit de grens.** `faces` bevat per gezicht een kader, vijf
        // landmarks en een score. We lezen uitsluitend het aantal rijen; de
        // coördinaten worden nooit uitgelezen en de matrix wordt hieronder
        // vrijgegeven. Wie hier ooit `faces.at(...)` toevoegt, verandert de
        // juridische kwalificatie van deze functie — lees eerst de kop van
        // `image_face_scan.dart`.
        if (faces.rows > best) best = faces.rows;
      } finally {
        faces?.dispose();
        if (!identical(scaled, source)) scaled.dispose();
      }
    }
    return best;
  }

  cv.FaceDetectorYN? _detectorFor(int width, int height) {
    try {
      final detector = _detector ??= cv.FaceDetectorYN.fromBuffer(
        'onnx',
        _modelBytes,
        Uint8List(0),
        (width, height),
        scoreThreshold: kFaceScanScoreThreshold,
      );
      detector.setInputSize((width, height));
      return detector;
    } catch (e, s) {
      // Het model laadt niet — verkeerde OpenCV-build, beschadigde asset. Dan is
      // de controle op deze machine kapot en zeggen we dat via [isSupported],
      // in plaats van elke afbeelding stil op nul te zetten.
      _nativeAvailable = false;
      logError('ImageFaceScanner.load', e, s);
      return null;
    }
  }

  @override
  void dispose() {
    _detector?.dispose();
    _detector = null;
  }
}

/// De scanner zoals de app hem gebruikt: het echte detectiewerk draait in een
/// eigen, lang levende isolate.
///
/// `countFaces` op de UI-isolate is één synchrone OpenCV-keten (decode + YuNet
/// op drie schalen) die bij een gewone foto al snel honderden milliseconden
/// vasthoudt — en hij draait als achtergrondcontrole terwijl iemand typt. In
/// een eigen isolate kost elke afbeelding de renderer hooguit de korte
/// `TransferableTypedData`-overdracht; de UI-thread decodeert en detecteert
/// nooit.
///
/// De worker is lang levend en geen `Isolate.run` per foto: het ONNX-model
/// laden en de detector opzetten kost meer dan een gemiddelde detectie, en die
/// investering wil je één keer doen. Verzoeken gaan serieel — één
/// detector-instantie, één scan tegelijk, precies zoals de oude aanroep-lus
/// al deed.
class _IsolateImageFaceScanner implements ImageFaceScanner {
  _IsolateImageFaceScanner(this._modelBytes);

  final Uint8List _modelBytes;
  bool? _nativeAvailable;
  Isolate? _isolate;
  SendPort? _toWorker;
  Future<SendPort>? _starting;
  // Serieel afhandelen: de worker bewaart één detector-instantie.
  Future<void> _tail = Future<void>.value();
  var _disposed = false;

  /// De probe draait op de UI-isolate: `cv.Mat.zeros` kost microseconden en
  /// bewijst dat de native bibliotheek in dit proces laadt. Laadt hij hier,
  /// dan laadt hij ook in de werk-isolate; faalt hij, dan wordt die isolate
  /// nooit gestart.
  @override
  bool get isSupported => _nativeAvailable ??= _probeNative();

  @override
  Future<ImageFaceScanResult> countFaces(Uint8List imageBytes) {
    final run = _tail.then((_) => _scanInWorker(imageBytes));
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<ImageFaceScanResult> _scanInWorker(Uint8List imageBytes) async {
    if (!isSupported || _disposed) return ImageFaceScanResult.unreadable;
    try {
      final toWorker = await _ensureWorker();
      final replies = ReceivePort();
      toWorker.send((
        replies.sendPort,
        TransferableTypedData.fromList([imageBytes]),
      ));
      try {
        // Eén afbeelding mag de serieële rij niet voor eeuwig blokkeren —
        // hangt de worker in een decode of is hij weggevallen, dan wacht
        // `replies.first` letterlijk nooit. Na de grens laten we de worker
        // vallen; de volgende afbeelding start een nieuwe.
        final answer =
            await replies.first.timeout(const Duration(seconds: 90)) as List;
        return ImageFaceScanResult(
          faces: answer[0] as int,
          readable: answer[1] as bool,
        );
      } on TimeoutException {
        _dropWorker();
        return ImageFaceScanResult.unreadable;
      } finally {
        replies.close();
      }
    } catch (e, s) {
      // De worker start niet of is weggevallen: dan is de controle op deze
      // machine niet bruikbaar en zeggen we dat — geen stille nul, en zeker
      // geen terugval naar "maar dan draait de UI-thread het toch maar".
      _nativeAvailable = false;
      logError('ImageFaceScanner.worker', e, s);
      return ImageFaceScanResult.unreadable;
    }
  }

  /// Laat de huidige worker los zodat de volgende scan opnieuw spawnt. Voor
  /// een worker die een antwoord niet meer terugstuurt is killen de enige
  /// eerlijke actie — een hangend bericht "beantwoorden" kan niet.
  void _dropWorker() {
    _isolate?.kill();
    _isolate = null;
    _toWorker = null;
    _starting = null;
  }

  Future<SendPort> _ensureWorker() {
    final existing = _toWorker;
    if (existing != null) return Future.value(existing);
    return _starting ??= () async {
      final handshake = ReceivePort();
      _isolate = await Isolate.spawn(_faceScanWorkerMain, (
        handshake.sendPort,
        _modelBytes,
      ));
      final sendPort = await handshake.first as SendPort;
      handshake.close();
      return _toWorker = sendPort;
    }();
  }

  @override
  void dispose() {
    _disposed = true;
    _dropWorker();
  }
}

/// Inkomende berichten: (antwoordpoort, beeldbytes als [TransferableTypedData]).
/// Uitgaande: `[faces, readable]`. De scanner loopt hier synchroon door — zijn
/// `countFaces` heeft geen awaits — dus berichten worden vanzelf serieel
/// verwerkt.
void _faceScanWorkerMain((SendPort, Uint8List) init) {
  final (reply, modelBytes) = init;
  final scanner = _OpenCvImageFaceScanner(modelBytes);
  final requests = ReceivePort();
  reply.send(requests.sendPort);
  requests.listen((message) async {
    final (replyTo, payload) = message as (SendPort, TransferableTypedData);
    final result = await scanner.countFaces(
      payload.materialize().asUint8List(),
    );
    replyTo.send([result.faces, result.readable]);
  });
}

ImageFaceScanner createPlatformImageFaceScanner(Uint8List modelBytes) =>
    _IsolateImageFaceScanner(modelBytes);
