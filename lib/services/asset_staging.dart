import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/asset_destination.dart';
import '../utils/atomic_file.dart';
import '../utils/log.dart';

/// De wachtkamer voor media van een deck dat nog geen eigen map op schijf heeft.
///
/// Een niet-opgeslagen deck heeft geen `projectPath`, en dat betekende tot nu
/// toe: de slide houdt het pad van het bronbestand vast en er wordt niets
/// gekopieerd. Verplaatst, hernoemt of verwijdert iemand dat bronbestand vóór
/// de eerste opslag, dan is de verwijzing stuk — en de gebruiker zag daar
/// alleen een grijs vlak van.
///
/// Daarom krijgt elke sessie hier een tijdelijke map met exact de indeling van
/// een echt project: `images/` en `media/`. De bytes staan daarmee meteen
/// veilig. En omdat een gestagede verwijzing een absoluut pad is, tilt de
/// bestaande kopieerslag bij opslaan (`copyImagesToProject` /
/// `copyMediaToProject`) hem vanzelf naar zijn definitieve plek — de layout is
/// immers al dezelfde.
///
/// De wachtkamer leeft onder de tijdelijke map van het OS en wordt niet zelf
/// opgeruimd; dat volgt de lijn van de geplakte-afbeeldingencache die hieraan
/// voorafging.
class AssetStaging {
  AssetStaging._();

  /// Naam van de gedeelde wortelmap. Elke sessie maakt daarbinnen een eigen
  /// submap, zodat twee tegelijk draaiende vensters elkaars kopieën niet
  /// overschrijven.
  static const rootDirName = 'ocideck_staging';

  static String? _rootPath;
  static Directory? _sessionDir;

  /// Bepaal de wortelmap alvast bij het opstarten.
  ///
  /// [isStagedPath] moet synchroon kunnen oordelen — de UI classificeert per
  /// frame en kan niet op een tijdelijke map wachten. Blijft de map onbekend
  /// (bijvoorbeeld op web), dan gedraagt alles zich als voorheen.
  static Future<void> initialize() async {
    if (kIsWeb || _rootPath != null) return;
    try {
      final temp = await getTemporaryDirectory();
      _rootPath = p.join(temp.path, rootDirName);
    } catch (e) {
      logWarning('AssetStaging.initialize: geen tijdelijke map beschikbaar', e);
    }
  }

  /// De wortelmap, of null zolang die niet bepaald kon worden.
  static String? get rootPath => _rootPath;

  /// True als [path] in de wachtkamer staat: gekopieerd en veilig, maar nog
  /// niet bij een opgeslagen deck ondergebracht.
  ///
  /// De toets kijkt naar de wortelmap en niet naar de sessiemap, zodat een deck
  /// dat na een herstart wordt teruggehaald zijn eerder gestagede afbeeldingen
  /// nog steeds als "in de wachtkamer" herkent in plaats van als extern.
  static bool isStagedPath(String path) {
    final root = _rootPath;
    if (root == null || path.isEmpty || !p.isAbsolute(path)) return false;
    return p.isWithin(root, p.normalize(path));
  }

  /// Kopieer [sourcePath] naar `<wachtkamer>/<subdir>/` en geef het absolute pad
  /// van de kopie terug.
  ///
  /// Null bij een onleesbare bron of als er geen wachtkamer beschikbaar is; de
  /// aanroeper valt dan terug op het bronpad, wat het gedrag is van vóór deze
  /// wachtkamer.
  static Future<String?> stage(
    String sourcePath, {
    required String subdir,
  }) async {
    if (kIsWeb) return null;
    try {
      final src = File(sourcePath);
      if (!await src.exists()) return null;
      final dir = await _subdir(subdir);
      if (dir == null) return null;
      final dest = await resolveAssetDestination(
        dir,
        p.basename(sourcePath),
        src,
      );
      if (dest == null) return null;
      if (!dest.alreadyPresent) await src.copy(dest.file.path);
      return dest.file.path;
    } on FileSystemException catch (e) {
      logWarning('AssetStaging.stage: kopiëren mislukt', e);
      return null;
    }
  }

  /// Schrijf [bytes] als [filename] in `<wachtkamer>/<subdir>/`. Voor materiaal
  /// dat geen bronbestand heeft — een geplakte afbeelding bestaat alleen op het
  /// klembord.
  static Future<String?> stageBytes(
    Uint8List bytes, {
    required String subdir,
    required String filename,
  }) async {
    if (kIsWeb) return null;
    try {
      final dir = await _subdir(subdir);
      if (dir == null) return null;
      final file = File(p.join(dir.path, filename));
      await writeBytesAtomic(file, bytes);
      return file.path;
    } on FileSystemException catch (e) {
      logWarning('AssetStaging.stageBytes: schrijven mislukt', e);
      return null;
    }
  }

  static Future<Directory?> _subdir(String subdir) async {
    final session = await _session();
    if (session == null) return null;
    final dir = Directory(p.join(session.path, subdir));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory?> _session() async {
    final existing = _sessionDir;
    if (existing != null) return existing;
    await initialize();
    final root = _rootPath;
    if (root == null) return null;
    final base = Directory(root);
    await base.create(recursive: true);
    final dir = await base.createTemp('deck_');
    _sessionDir = dir;
    return dir;
  }

  /// Zet de wachtkamer op een map naar keuze en vergeet de huidige sessie.
  /// Tests hebben geen path_provider op de VM, en willen bovendien per test een
  /// schone map.
  @visibleForTesting
  static void overrideRootForTest(String? root) {
    _rootPath = root;
    _sessionDir = null;
  }
}
