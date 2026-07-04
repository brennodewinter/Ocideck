import 'dart:typed_data';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// In-memory opslag voor afbeeldingen in de webversie.
///
/// Op web bestaat er geen bestandssysteem: een gekozen of geplakte afbeelding
/// leeft als bytes in het geheugen en krijgt een pad met het schema
/// `mem:<uuid>`. De renderlaag (media_previews_image) herkent dat schema en
/// tekent rechtstreeks uit deze store; de gewone pad-resolvers zien `mem:`
/// nooit. De store leeft zolang de pagina leeft — een opgeslagen `.md` met
/// `mem:`-verwijzingen verliest zijn afbeeldingen dus bij herladen. Assets
/// meenemen in een pakket (.ocideck) is de vervolgstap.
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
