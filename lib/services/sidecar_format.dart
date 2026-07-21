import 'dart:convert';

import '../utils/log.dart';

/// Het versiecontract van de sidecars naast een `.md` (`.ink.json`,
/// `.user-notes.json`, `.miauw.json`).
///
/// Bewust een losse module zonder verdere afhankelijkheden: elke codec schreef
/// al een `version`, maar deed er iets anders mee — de een las hem helemaal
/// niet, de ander behandelde een onbekende `3` als een bekende `2`. Half
/// inlezen is het gevaarlijke geval: wat deze build niet begreep verdwijnt bij
/// de eerstvolgende opslag, en dat is niet meer terug te halen.

/// De sleutel waaronder een sidecar zijn formaatversie draagt.
const String kSidecarVersionKey = 'version';

/// De oudste sidecar-versie. Ontbreekt de sleutel, dan is het bestand er een:
/// dat is niet uitzonderlijk maar de normale toestand van het eerste formaat.
const int kOldestSidecarVersion = 1;

/// De versie die de al ontlede payload [data] declareert.
///
/// Alles wat geen bruikbaar versienummer is telt als [kOldestSidecarVersion].
/// Een sidecar weigeren op een onleesbare versiesleutel zou werk laten liggen
/// om een reden die de gebruiker niet kan zien.
int declaredSidecarVersion(Object? data) {
  final raw = data is Map ? data[kSidecarVersionKey] : null;
  final n = raw is num ? raw.toInt() : int.tryParse('$raw');
  return (n == null || n < kOldestSidecarVersion) ? kOldestSidecarVersion : n;
}

/// Of het sidecar-bestand [json] uit een nieuwere OciDeck komt dan de
/// [supported] versie van deze build.
///
/// Onleesbare JSON is níét "van later": die valt onder de gewone
/// foutafhandeling van de codec, die er dan niets uit haalt. Alleen een
/// bestand dat zichzélf een hogere versie noemt is onaanraakbaar — het draagt
/// aantoonbaar iets wat deze build niet kent.
bool sidecarIsFromNewerBuild(String json, int supported) {
  try {
    return declaredSidecarVersion(jsonDecode(json)) > supported;
  } on FormatException catch (e) {
    logWarning('sidecarIsFromNewerBuild: sidecar is not valid JSON', e);
    return false;
  }
}
