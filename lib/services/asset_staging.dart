import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/asset_destination.dart';
import '../utils/atomic_file.dart';
import '../utils/log.dart';
import 'recovery_service.dart';

/// De stagingmap: waar media landt van een deck dat nog geen eigen map op
/// schijf heeft.
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
/// De stagingmap leeft onder de tijdelijke map van het OS. Bij het opstarten
/// ruimt [pruneStale] sessiemappen op die niemand meer kan gebruiken, zodat
/// zwaar gebruik zonder opslaan zich niet stilletjes opstapelt.
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

  /// Hoe lang een sessiemap blijft staan.
  ///
  /// Bewust dezelfde termijn als de herstelbestanden: een niet-opgeslagen deck
  /// dat na een crash wordt teruggehaald verwijst naar paden in zijn oude
  /// sessiemap. Zou staging eerder opruimen dan herstel, dan kreeg je een deck
  /// terug met gaten waar de afbeeldingen zaten. Door dezelfde constante te
  /// gebruiken kunnen de twee niet uit elkaar lopen.
  static Duration get defaultMaxAge => RecoveryService.defaultMaxAge;

  /// Gooi sessiemappen weg waar niemand meer iets aan heeft.
  ///
  /// Best-effort en stil: dit draait bij het opstarten en mag nooit in de weg
  /// zitten. Geeft terug hoeveel mappen zijn verwijderd.
  ///
  /// De leeftijd is die van het jóngste bestand in de map, niet die van de map
  /// zelf. Een sessiemap krijgt zijn tijdstempel bij aanmaken en verandert
  /// daarna niet meer — de bestanden komen in `images/` en `media/` terecht —
  /// dus op de map zelf afgaan zou een sessie opruimen die vanochtend nog is
  /// gebruikt.
  ///
  /// Wat dit níet ziet: een app die al langer dan [maxAge] draait met een deck
  /// dat even lang niet is aangeraakt én nooit is opgeslagen. Die verliest zijn
  /// kopieën. Dat vraagt om een vergrendeling per sessie, en dat is meer
  /// machinerie dan dit randgeval waard is; het gevolg is bovendien zichtbaar
  /// (ontbrekend bestand in preview en kwaliteitspaneel) in plaats van stil.
  static Future<int> pruneStale({Duration? maxAge}) async {
    if (kIsWeb) return 0;
    await initialize();
    final root = _rootPath;
    if (root == null) return 0;
    final limit = maxAge ?? defaultMaxAge;
    final keep = _sessionDir?.path;
    var removed = 0;
    try {
      final dir = Directory(root);
      if (!dir.existsSync()) return 0;
      final now = DateTime.now();
      for (final entry in dir.listSync()) {
        if (entry is! Directory) continue;
        if (keep != null && p.equals(entry.path, keep)) continue;
        try {
          final touched = _newestModified(entry);
          if (touched == null || now.difference(touched) <= limit) continue;
          await entry.delete(recursive: true);
          removed++;
        } catch (e) {
          logWarning('AssetStaging.pruneStale: stat/delete', e);
        }
      }
    } catch (e) {
      logWarning('AssetStaging.pruneStale: list staging root', e);
    }
    return removed;
  }

  /// Het jongste wijzigingstijdstip van de béstanden in [dir].
  ///
  /// Alleen bestanden: de tijdstempel van een map zegt per platform iets
  /// anders en verspringt al bij het aanmaken van een submap, dus daarop
  /// afgaan zou een sessie te oud of te jong maken zonder dat er iets is
  /// gebeurd. Elk gestaged bestand krijgt bij het kopiëren zijn eigen verse
  /// tijdstempel, dus dat is de betrouwbare maat voor "hier is nog gewerkt".
  ///
  /// Staat er niets in — een sessie die is aangemaakt maar nooit gebruikt —
  /// dan is de map zelf de enige aanwijzing die er is. Null als er niets te
  /// lezen viel; dan blijft de map staan, want opruimen op grond van iets wat
  /// je niet hebt kunnen lezen is geen opruimen maar gokken.
  static DateTime? _newestModified(Directory dir) {
    DateTime? newest;
    try {
      for (final entry in dir.listSync(recursive: true, followLinks: false)) {
        if (entry is! File) continue;
        final modified = entry.statSync().modified;
        if (newest == null || modified.isAfter(newest)) newest = modified;
      }
      return newest ?? dir.statSync().modified;
    } catch (e) {
      logWarning('AssetStaging._newestModified: stat', e);
      return null;
    }
  }

  /// True als [path] in de stagingmap staat: gekopieerd en veilig, maar nog
  /// niet bij een opgeslagen deck ondergebracht.
  ///
  /// De toets kijkt naar de wortelmap en niet naar de sessiemap, zodat een deck
  /// dat na een herstart wordt teruggehaald zijn eerder gestagede afbeeldingen
  /// nog steeds als "in de stagingmap" herkent in plaats van als extern.
  static bool isStagedPath(String path) {
    final root = _rootPath;
    if (root == null || path.isEmpty || !p.isAbsolute(path)) return false;
    return p.isWithin(root, p.normalize(path));
  }

  /// Kopieer [sourcePath] naar `<stagingmap>/<subdir>/` en geef het absolute pad
  /// van de kopie terug.
  ///
  /// Null bij een onleesbare bron of als er geen stagingmap beschikbaar is; de
  /// aanroeper valt dan terug op het bronpad, wat het gedrag is van vóór deze
  /// stagingmap.
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

  /// Schrijf [bytes] als [filename] in `<stagingmap>/<subdir>/`. Voor materiaal
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

  /// Wijs de stagingmap elders aan en vergeet de huidige sessie. Tests hebben
  /// geen path_provider op de VM, en willen bovendien per test schoon
  /// beginnen.
  @visibleForTesting
  static void overrideRootForTest(String? root) {
    _rootPath = root;
    _sessionDir = null;
  }
}
