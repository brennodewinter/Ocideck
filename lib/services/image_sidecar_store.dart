import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/atomic_file.dart';
import '../utils/json_depth_guard.dart';
import '../utils/log.dart';

/// De grens waarboven een sidecar niet meer wordt gelezen.
///
/// Een sidecar hoort bij een deck en reist er dus mee, ook uit een pakket, een
/// repo of een map die iemand anders heeft gemaakt. Zonder grens leest een
/// gemanipuleerd bestand van een gigabyte zich zo het geheugen in — en `jsonDecode`
/// erna doet er nog een kopie bovenop. Het gaat om een platte map van
/// bestandsnaam naar bijschrift: één MiB is ruim voor duizenden afbeeldingen.
const int maxImageSidecarBytes = 1024 * 1024;

/// Gedeelde opslaglaag voor beeld-sidecars: één plat JSON-bestand per map
/// ([sidecarName]), keyed op bestandsnaam van de afbeelding. Caption- en
/// descriptionservice verschillen alleen in bestandsnaam en in hun
/// pad-resolutiestrategie (die blijft bij de services); lezen, muteren,
/// atomisch schrijven en opruimen-bij-leeg staan hier één keer.
/// De sidecar bestaat maar is niet te lezen.
///
/// Losgetrokken van een gewone schrijffout omdat de afhandeling anders is: hier
/// staat er ándermans werk in het bestand, en dat mag een nieuwe schrijfbeurt
/// niet overschrijven.
class SidecarUnreadable implements Exception {
  final String path;
  final Object cause;
  const SidecarUnreadable(this.path, this.cause);

  @override
  String toString() => 'Sidecar niet leesbaar: $path';
}

class ImageSidecarStore {
  final String sidecarName;

  /// Prefix voor logmeldingen, bv. 'CaptionService'.
  final String logLabel;

  const ImageSidecarStore({required this.sidecarName, required this.logLabel});

  File fileFor(String resolvedImagePath) =>
      File(p.join(p.dirname(resolvedImagePath), sidecarName));

  /// De tekst voor [resolvedImagePath], of null zonder sidecar of entry.
  Future<String?> read(String resolvedImagePath) async {
    final file = fileFor(resolvedImagePath);
    try {
      // existsSync staat bewust ín de vangst: File.existsSync gooit bij een
      // I/O-fout (geen bestand is `false`, geen toegang is een uitzondering),
      // en zo'n fout mag het openen van het deck evenmin blokkeren als een
      // leesfout (#2885).
      if (!file.existsSync()) return null;
      if (!await _withinCap(file)) return null;
      final data = jsonDecodeGuarded(await file.readAsString()) as Map;
      final value = data[p.basename(resolvedImagePath)];
      return value is String ? value : null;
    } catch (e) {
      logWarning('$logLabel: read sidecar', e);
      return null;
    }
  }

  /// Zet — of verwijder, bij lege [value] — de tekst voor [resolvedImagePath].
  /// De sidecar zelf wordt verwijderd zodra de laatste entry verdwijnt.
  Future<void> write(String resolvedImagePath, String value) => _writeEntries(
    fileFor(resolvedImagePath),
    {p.basename(resolvedImagePath): value},
  );

  /// Zet meerdere waarden met hoogstens één lees- en schrijfbeurt per map.
  /// Deck-opslag biedt alle bijschriften tegelijk aan; ze één voor één verwerken
  /// las, parseerde en flushte dezelfde groeiende JSON-sidecar voor elke dia.
  Future<void> writeAll(Map<String, String> valuesByResolvedPath) async {
    final entriesByFile = <String, Map<String, String>>{};
    for (final entry in valuesByResolvedPath.entries) {
      final file = fileFor(entry.key);
      entriesByFile.putIfAbsent(file.path, () => {})[p.basename(entry.key)] =
          entry.value;
    }
    for (final entry in entriesByFile.entries) {
      await _writeEntries(File(entry.key), entry.value);
    }
  }

  Future<void> _writeEntries(
    File file,
    Map<String, String> replacements,
  ) async {
    Map<String, dynamic> data = {};
    try {
      // existsSync ín de vangst: gooit de toegangscontrole (weggevallen
      // volume), dan moeten we óók niet met een lege map doorgaan — die zou
      // het bestaande bestand hieronder overschrijven (#2885).
      if (file.existsSync()) {
        // Boven de grens niet lezen, en dus ook niet schrijven: doorgaan met een
        // lege map zou het bestand overschrijven en alle andere bijschriften in
        // deze map wissen — precies de fout die het catch-blok hieronder
        // beschrijft, alleen met een andere aanleiding.
        if (!await _withinCap(file)) return;
        data = Map<String, dynamic>.from(
          jsonDecodeGuarded(await file.readAsString()) as Map,
        );
      }
    } catch (e, s) {
      // Niet dóórgaan met een lege map: die wordt hieronder over het bestand
      // heen geschreven, en dan zijn alle andere bijschriften in deze map weg
      // — of het bestand wordt in zijn geheel verwijderd wanneer de gebruiker
      // net een bijschrift wíste. Eén beschadigde sidecar (een
      // synchronisatieconflict, een halve kopie) kostte zo alle andere.
      // Liever niets doen dan de rest slopen; de aanroeper krijgt het te zien.
      logError('$logLabel: parse existing sidecar', e, s);
      throw SidecarUnreadable(file.path, e);
    }
    for (final entry in replacements.entries) {
      if (entry.value.trim().isEmpty) {
        data.remove(entry.key);
      } else {
        data[entry.key] = entry.value.trim();
      }
    }
    if (data.isEmpty) {
      // Opruimen mag de schrijfbeurt niet breken: een existsSync- of
      // delete-fout is een waarschuwing, geen verloren bijschrift.
      try {
        if (file.existsSync()) await file.delete();
      } catch (e) {
        logWarning('$logLabel: delete empty sidecar', e);
      }
    } else {
      await writeStringAtomicIfChanged(
        file,
        const JsonEncoder.withIndent('  ').convert(data),
      );
    }
  }

  /// Alle entries van de sidecar in [dir]: bestandsnaam → tekst.
  Future<Map<String, String>> readDir(String dir) async {
    final file = File(p.join(dir, sidecarName));
    try {
      if (!file.existsSync()) return const {};
      if (!await _withinCap(file)) return const {};
      final data = jsonDecodeGuarded(await file.readAsString()) as Map;
      return {
        for (final entry in data.entries)
          if (entry.value is String) entry.key as String: entry.value as String,
      };
    } catch (e) {
      logWarning('$logLabel: read sidecar', e);
      return const {};
    }
  }

  /// Of [file] onder [maxImageSidecarBytes] blijft. Meldt het overschot, want
  /// stil overslaan laat de gebruiker denken dat zijn bijschriften weg zijn
  /// terwijl ze er nog staan.
  Future<bool> _withinCap(File file) async {
    final int length;
    try {
      length = await file.length();
    } on FileSystemException catch (e) {
      // Niet te meten = niet te vertrouwen, en toch doorgeven: de lezers
      // vangen dit als "overgeslagen", `_writeEntries` als SidecarUnreadable
      // — aan beide kanten fail closed, aan de schrijfkant ook luid (#2885).
      logWarning('$logLabel: sidecar niet te meten', e);
      rethrow;
    }
    if (length <= maxImageSidecarBytes) return true;
    logWarning(
      '$logLabel: sidecar van $length bytes overschrijdt de grens van '
      '$maxImageSidecarBytes — overgeslagen',
    );
    return false;
  }
}
