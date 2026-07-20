import 'dart:typed_data';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// In-memory opslag voor afbeeldingen in de webversie.
///
/// Op web bestaat er geen bestandssysteem: een gekozen of geplakte afbeelding
/// leeft als bytes in het geheugen en krijgt een pad met het schema
/// `mem:<uuid>`. De renderlaag (media_previews_image) herkent dat schema en
/// tekent rechtstreeks uit deze store; de gewone pad-resolvers zien `mem:`
/// nooit. De store leeft zolang de pagina leeft — een los opgeslagen `.md` met
/// `mem:`-verwijzingen verliest zijn afbeeldingen dus bij herladen. Exporteren
/// als `.ocideck`-pakket neemt de `mem:`-assets wél mee (zie
/// file_service_package.dart).
class WebAssetStore {
  WebAssetStore._();

  static const scheme = 'mem:';

  static final Map<String, Uint8List> _bytes = {};
  static final Map<String, String> _names = {};

  static bool isMemPath(String path) => path.startsWith(scheme);

  /// Bewaar [bytes] onder een vers `mem:`-pad. [name] is de oorspronkelijke
  /// bestandsnaam (voor latere pakket-export en logregels). De aanroeper
  /// valideert de bytes (magic bytes + size-cap) vóór het bewaren.
  static String put(Uint8List bytes, {required String name}) {
    final path = '$scheme${_uuid.v4()}';
    _bytes[path] = bytes;
    _names[path] = name;
    return path;
  }

  /// Of de store leeg is. Op desktop is hij dat altijd (afbeeldingen gaan naar
  /// schijf), dus een sweep kan er goedkoop op afhaken.
  static bool get isEmpty => _bytes.isEmpty;

  /// Houd alleen de assets in [live] aan; gooi de rest weg. Retourneert hoeveel
  /// er zijn opgeruimd.
  ///
  /// Dit is de enige plek waar een asset wordt vergeten zonder dat de pagina
  /// herlaadt, dus [live] moet écht compleet zijn: elke `mem:`-verwijzing die
  /// nog terug kan komen — in een open tabblad, in de ongedaan-/opnieuw-stapel,
  /// of op het diaklembord. De aanroeper ([TabsNotifier.sweepWebAssets]) stelt
  /// die verzameling samen; hier vertrouwen we erop dat hij volledig is.
  static int retain(Set<String> live) {
    final dood = _bytes.keys.where((k) => !live.contains(k)).toList();
    for (final k in dood) {
      _bytes.remove(k);
      _names.remove(k);
    }
    return dood.length;
  }

  /// De bytes achter een `mem:`-pad, of null (geen mem-pad / niet aanwezig,
  /// bv. na een herlaad van de pagina).
  static Uint8List? bytesFor(String path) => _bytes[path];

  /// De oorspronkelijke bestandsnaam achter een `mem:`-pad.
  static String? nameFor(String path) => _names[path];

  /// Alles wissen — alleen voor tests.
  static void clear() {
    _bytes.clear();
    _names.clear();
  }
}
