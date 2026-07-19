// De beeldcontrole: staat er een herkenbaar gezicht op deze afbeelding?
//
// ── Waarom dit een privacycontrole is ────────────────────────────────────────
//
// Een afbeelding waarop iemand herkenbaar staat, ís een persoonsgegeven — het
// hoeft er geen naam bij te hebben. De tekstscanner ziet dat nooit: die leest
// `mem:11162735-…` en concludeert terecht dat daar geen BSN in staat.
//
// ── Waarom dit géén biometrie is, en dat met opzet ───────────────────────────
//
// Dit is de gevoeligste ontwerpkeuze van de hele controle, dus expliciet.
//
// De EDPB stelt (Richtsnoeren 3/2019 §74-76) dat beeldmateriaal van een persoon
// op zichzelf *geen* biometrisch gegeven in de zin van artikel 9 is — dat wordt
// het pas als het "specifically technically processed in order to contribute to
// the identification of an individual" wordt, en verwerkt "for the purpose of
// uniquely identifying a natural person".
//
// Wij detecteren dus *aanwezigheid*, nooit identiteit. Het model levert per
// gezicht een kader, vijf landmarks en een score; daarvan houden we **alleen het
// aantal** over. De rest wordt onmiddellijk weggegooid en verlaat deze functie
// niet. Er wordt geen sjabloon berekend, niets opgeslagen, niets vergeleken met
// iets anders.
//
// Dat onderscheid is niet cosmetisch: een privacycontrole die gezichtssjablonen
// aanlegt om je voor gezichtssjablonen te waarschuwen, creëert precies de
// categorie gegevens waar artikel 9 het zwaarst op zit. Zou deze code ooit
// landmarks gaan bewaren of gezichten gaan vergelijken, dan verandert de
// juridische kwalificatie van OciDeck zelf — en dan is dit bestand de plek waar
// dat moet worden tegengehouden.
//
// ── Draagwijdte, eerlijk ─────────────────────────────────────────────────────
//
// Dit vindt *gezichten*, geen personen. Systematisch gemist: iemand van
// achteren, in profiel voorbij ongeveer 60 graden, een silhouet in tegenlicht,
// iemand met mondkapje of helm, en een lichaam waarvan het hoofd buiten de
// uitsnede valt. De melding zegt daarom "herkenbaar gezicht" en niet "persoon".

import 'dart:typed_data';

import 'image_face_scan_stub.dart'
    if (dart.library.io) 'image_face_scan_io.dart';

/// Telt gezichten in afbeeldingen. Zie de kop van dit bestand voor waarom er
/// alleen geteld wordt.
abstract interface class ImageFaceScanner {
  /// Of deze build werkelijk kan detecteren.
  ///
  /// Op het web is dit `false`: de detector draait op een native bibliotheek via
  /// FFI, en die bestaat daar niet. De controle degradeert dan naar niets — en
  /// zegt dat ook, want een stille nul is niet hetzelfde als "niets gevonden".
  bool get isSupported;

  /// Het aantal herkenbare gezichten in [imageBytes]. Nul bij een onleesbare of
  /// niet-ondersteunde afbeelding: een beeldcontrole hoort geen scan te breken.
  Future<int> countFaces(Uint8List imageBytes);

  void dispose();
}

/// Bouwt de scanner voor dit platform. [modelBytes] is het YuNet-model
/// (`assets/models/face_detection_yunet_2023mar.onnx`).
ImageFaceScanner createImageFaceScanner(Uint8List modelBytes) =>
    createPlatformImageFaceScanner(modelBytes);
