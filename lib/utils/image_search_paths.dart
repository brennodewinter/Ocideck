import 'package:path/path.dart' as p;

/// Zoekwortels voor de afbeeldingscarrousel bij een presentatie: `images/` en
/// de projectmap eerst (wat bij dit deck hoort), daarna de bibliotheken uit
/// Instellingen. De scanner loopt de lijst op volgorde en stopt bij de
/// bestandsgrens — project eerst voorkomt dat een volle bibliotheek het deck
/// verdringt.
List<String> deckImageSearchPaths(
  String? projectPath,
  List<String> libraryPaths,
) {
  final projectImages = projectPath == null
      ? null
      : p.join(projectPath, 'images');
  return _unique([?projectImages, ?projectPath, ...libraryPaths]);
}

/// Zoekwortels voor de carrousel in documentmodus.
///
/// Volgorde:
/// 1. bibliotheken uit Instellingen (zelfde bron als "Afbeeldingen beheren");
/// 2. open presentatietabs — `images/` én projectmap, zoals in presentatiemodus;
/// 3. `images/` en `logos/` van recente presentaties (niet de hele map: een
///    presentatie op Desktop mag de Desktop niet leegzuigen);
/// 4. `images/` naast het document zelf.
///
/// Bewust zonder de ouder-map van het document: die vulde eerder de
/// bestandsgrens (Desktop) vóór de bibliotheek ooit aan de beurt kwam.
List<String> documentImageSearchPaths(
  String? documentDirectory,
  List<String> libraryPaths, {
  List<String> openDeckProjectPaths = const [],
  List<String> recentPresentationDirectories = const [],
}) {
  final besideImages = documentDirectory == null
      ? null
      : p.join(documentDirectory, 'images');
  return _unique([
    ...libraryPaths,
    for (final project in openDeckProjectPaths) ...[
      p.join(project, 'images'),
      project,
    ],
    for (final dir in recentPresentationDirectories) ...[
      p.join(dir, 'images'),
      p.join(dir, 'logos'),
    ],
    ?besideImages,
  ]);
}

List<String> _unique(Iterable<String?> paths) {
  final seen = <String>{};
  final out = <String>[];
  for (final path in paths) {
    if (path == null || path.isEmpty) continue;
    if (seen.add(path)) out.add(path);
  }
  return out;
}
