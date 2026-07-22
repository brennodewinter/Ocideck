import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/atomic_file.dart';
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
    if (!file.existsSync()) return null;
    try {
      if (!await _withinCap(file)) return null;
      final data = jsonDecode(await file.readAsString()) as Map;
      final value = data[p.basename(resolvedImagePath)];
      return value is String ? value : null;
    } catch (e) {
      logWarning('$logLabel: read sidecar', e);
      return null;
    }
  }

  /// Zet — of verwijder, bij lege [value] — de tekst voor [resolvedImagePath].
  /// De sidecar zelf wordt verwijderd zodra de laatste entry verdwijnt.
  Future<void> write(String resolvedImagePath, String value) async {
    final file = fileFor(resolvedImagePath);
    Map<String, dynamic> data = {};
    if (file.existsSync()) {
      try {
        // Boven de grens niet lezen, en dus ook niet schrijven: doorgaan met een
        // lege map zou het bestand overschrijven en alle andere bijschriften in
        // deze map wissen — precies de fout die het catch-blok hieronder
        // beschrijft, alleen met een andere aanleiding.
        if (!await _withinCap(file)) return;
        data = Map<String, dynamic>.from(
          jsonDecode(await file.readAsString()) as Map,
        );
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
    }
    final key = p.basename(resolvedImagePath);
    if (value.trim().isEmpty) {
      data.remove(key);
    } else {
      data[key] = value.trim();
    }
    if (data.isEmpty) {
      if (file.existsSync()) await file.delete();
    } else {
      await writeStringAtomic(
        file,
        const JsonEncoder.withIndent('  ').convert(data),
      );
    }
  }

  /// Alle entries van de sidecar in [dir]: bestandsnaam → tekst.
  Future<Map<String, String>> readDir(String dir) async {
    final file = File(p.join(dir, sidecarName));
    if (!file.existsSync()) return const {};
    try {
      if (!await _withinCap(file)) return const {};
      final data = jsonDecode(await file.readAsString()) as Map;
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
    final length = await file.length();
    if (length <= maxImageSidecarBytes) return true;
    logWarning(
      '$logLabel: sidecar van $length bytes overschrijdt de grens van '
      '$maxImageSidecarBytes — overgeslagen',
    );
    return false;
  }
}
