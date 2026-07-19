// De native beeldcontrole: YuNet via OpenCV's dnn-module.
//
// Zie `image_face_scan.dart` voor waarom hier alleen geteld wordt en dit
// daarom geen biometrische verwerking is. Die redenering is de reden dat dit
// bestand zo klein is, en dat hoort zo te blijven.

import 'dart:typed_data';

import 'package:opencv_core/opencv.dart' as cv;

import '../../utils/log.dart';

import 'image_face_scan.dart';

/// De werkbreedte waarop gedetecteerd wordt.
///
/// YuNet is getraind op gezichten van ongeveer 10 tot 300 pixels. Een foto van
/// 6000 pixels breed heeft gezichten die dáár ruim boven zitten, en die worden
/// juist *slechter* gevonden — plus het kost onnodig veel rekentijd. Terugbrengen
/// naar deze breedte houdt gezichten in het bereik waar het model goed is, en
/// scheelt op een gewone dia-afbeelding een veelvoud aan tijd.
const int kFaceScanWorkingWidth = 640;

/// Boven deze bestandsgrootte slaan we een afbeelding over.
///
/// Een dia met een RAW-scan van 80 MB hoort de kwaliteitscontrole niet te laten
/// haperen. De grens is ruim: gewone dia-afbeeldingen zitten er ver onder.
const int kFaceScanMaxBytes = 24 * 1024 * 1024;

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
  Future<int> countFaces(Uint8List imageBytes) async {
    if (!isSupported || imageBytes.isEmpty) return 0;
    if (imageBytes.lengthInBytes > kFaceScanMaxBytes) return 0;

    cv.Mat? source;
    cv.Mat? working;
    cv.Mat? faces;
    try {
      source = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
      // Een niet-ondersteund formaat (SVG, een kapot bestand) geeft een lege
      // matrix. Dat is geen fout om over te klagen — er valt alleen niets te
      // bekijken.
      if (source.isEmpty || source.cols <= 0 || source.rows <= 0) return 0;

      working = _fitForDetection(source);
      final detector = _detectorFor(working.cols, working.rows);
      if (detector == null) return 0;

      faces = detector.detect(working);
      // **Hier zit de grens.** `faces` bevat per gezicht een kader, vijf
      // landmarks en een score. We lezen uitsluitend het aantal rijen; de
      // coördinaten worden nooit uitgelezen en de matrix wordt hieronder
      // vrijgegeven. Wie hier ooit `faces.at(...)` toevoegt, verandert de
      // juridische kwalificatie van deze functie — lees eerst de kop van
      // `image_face_scan.dart`.
      return faces.rows;
    } catch (e, s) {
      // Eén kapotte afbeelding mag de hele controle niet meenemen. We zetten de
      // scanner niet stil: de volgende afbeelding kan prima leesbaar zijn.
      // Bewust zonder pad of slide-nummer: dit is de component die over
      // afbeeldingen mét personen gaat, en een logregel is ook een verwerking.
      logError('ImageFaceScanner.countFaces', e, s);
      return 0;
    } finally {
      faces?.dispose();
      if (!identical(working, source)) working?.dispose();
      source?.dispose();
    }
  }

  /// Verkleint naar [kFaceScanWorkingWidth] als dat winst oplevert. Geeft
  /// anders de bron terug — dan is er niets te kopiëren en niets te ruimen.
  cv.Mat _fitForDetection(cv.Mat source) {
    if (source.cols <= kFaceScanWorkingWidth) return source;
    final scale = kFaceScanWorkingWidth / source.cols;
    final height = (source.rows * scale).round().clamp(1, 1 << 20);
    return cv.resize(source, (kFaceScanWorkingWidth, height));
  }

  cv.FaceDetectorYN? _detectorFor(int width, int height) {
    try {
      final detector = _detector ??= cv.FaceDetectorYN.fromBuffer(
        'onnx',
        _modelBytes,
        Uint8List(0),
        (width, height),
        // Bewust hoger dan de standaard 0,9. Deze controle onderbreekt de
        // auteur, dus een twijfelgeval mag hier niet doorheen: liever een
        // gezicht missen dan de gebruiker leren dat de melding onzin is.
        scoreThreshold: 0.92,
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
