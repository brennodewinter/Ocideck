import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/atomic_file.dart';
import '../utils/log.dart';

/// Gedeelde opslaglaag voor beeld-sidecars: één plat JSON-bestand per map
/// ([sidecarName]), keyed op bestandsnaam van de afbeelding. Caption- en
/// descriptionservice verschillen alleen in bestandsnaam en in hun
/// pad-resolutiestrategie (die blijft bij de services); lezen, muteren,
/// atomisch schrijven en opruimen-bij-leeg staan hier één keer.
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
        data = Map<String, dynamic>.from(
          jsonDecode(await file.readAsString()) as Map,
        );
      } catch (e, s) {
        logError('$logLabel: parse existing sidecar', e, s);
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
      final data = jsonDecode(await file.readAsString()) as Map;
      return {
        for (final entry in data.entries)
          if (entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (e) {
      logWarning('$logLabel: read sidecar', e);
      return const {};
    }
  }
}
