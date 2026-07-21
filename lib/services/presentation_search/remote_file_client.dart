import 'dart:typed_data';

/// Eén item uit een remote listing, losgemaakt van de WebDAV- en S3-eigen
/// types zodat de scanlogica er maar één keer hoeft te bestaan.
class RemoteFileEntry {
  const RemoteFileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.isMarkdown,
    required this.isPackage,
  });

  /// Pad relatief aan de wortel van de verbinding, zonder leidende slash.
  final String path;
  final String name;
  final bool isDirectory;

  /// Een los `.md`-bestand.
  final bool isMarkdown;

  /// Een `.ocideck`/zip-pakket (draagt zijn eigen afbeeldingen mee).
  final bool isPackage;
}

/// De minimale leesbewerkingen die 'Slide zoeken' van een remote opslag nodig
/// heeft. WebDAV en S3 leveren hier allebei een dunne adapter voor.
///
/// Bewust klein: lijsten en downloaden is alles wat een scan doet. Schrijven,
/// verplaatsen en verwijderen horen bij de opslagdiensten zelf en blijven
/// buiten deze interface.
abstract class RemoteFileClient {
  /// Som één map/prefix op — niet recursief. Gooit bij een netwerk- of
  /// autorisatiefout.
  Future<List<RemoteFileEntry>> list(String path);

  /// Haal de bytes van één bestand op. Gooit bij een netwerk- of
  /// autorisatiefout.
  Future<Uint8List> download(String path);
}
