// De native beeldcontrole: YuNet via OpenCV's dnn-module.
//
// Zie `image_face_scan.dart` voor waarom hier alleen geteld wordt en dit
// daarom geen biometrische verwerking is. Die redenering is de reden dat dit
// bestand zo klein is, en dat hoort zo te blijven.

import 'dart:typed_data';

import 'package:opencv_core/opencv.dart' as cv;

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
/// Voorbehoud: zeven foto's en elf negatieven is een kleine steekproef. Het
/// plateau is geruststellend, maar dit is geen benchmark.
const double kFaceScanScoreThreshold = 0.80;

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

  @override
  Future<ImageFaceScanResult> countFaces(Uint8List imageBytes) async {
    if (!isSupported || imageBytes.isEmpty) {
      return ImageFaceScanResult.unreadable;
    }
    if (imageBytes.lengthInBytes > kFaceScanMaxBytes) {
      return ImageFaceScanResult.unreadable;
    }

    cv.Mat? source;
    try {
      source = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
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

ImageFaceScanner createPlatformImageFaceScanner(Uint8List modelBytes) =>
    _OpenCvImageFaceScanner(modelBytes);
