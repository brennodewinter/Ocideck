import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import '../utils/log.dart';

/// Isolate-werkfunctie: md5 per pad. Onleesbare bestanden vallen weg
/// (zelfde gedrag als voorheen); dart:developer-logging werkt ook in isolates.
Future<Map<String, String>> _md5Worker(List<String> paths) async {
  final result = <String, String>{};
  for (final path in paths) {
    try {
      final digest = await md5.bind(File(path).openRead()).single;
      result[path] = digest.toString();
    } catch (e) {
      logWarning('ImageDedupService: md5 hash in isolate', e);
    }
  }
  return result;
}

/// Vindt exacte duplicaten tussen afbeeldingen op basis van hun md5-checksum,
/// zodat de bibliotheek opgeschoond kan worden. Bestanden worden eerst op
/// grootte gegroepeerd; alleen gelijke groottes worden daadwerkelijk gehasht,
/// dus grote bibliotheken blijven snel.
class ImageDedupService {
  /// Groepeer [imagePaths] op identieke inhoud (md5). Elke teruggegeven groep
  /// bevat twee of meer paden naar byte-voor-byte gelijke bestanden, in de
  /// volgorde waarin ze in [imagePaths] stonden. Onleesbare bestanden worden
  /// stilletjes overgeslagen.
  Future<List<List<String>>> findDuplicateGroups(
    Iterable<String> imagePaths, {
    void Function(int done, int total)? onProgress,
  }) async {
    // Stap 1: op bestandsgrootte groeperen — verschillend groot is nooit gelijk.
    final bySize = <int, List<String>>{};
    for (final path in imagePaths) {
      try {
        final size = File(path).statSync().size;
        bySize.putIfAbsent(size, () => []).add(path);
      } catch (e) {
        logWarning('ImageDedupService.findDuplicateGroups: stat for size', e);
      }
    }

    // Stap 2: alleen binnen gelijke groottes de md5 berekenen — in een
    // isolate (compute), in porties zodat de voortgang zichtbaar blijft en
    // een grote bibliotheek de UI niet bevriest.
    final toHash = <String>[
      for (final candidates in bySize.values)
        if (candidates.length >= 2) ...candidates,
    ];
    onProgress?.call(0, toHash.length);
    const chunkSize = 32;
    final hashes = <String, String>{};
    for (var i = 0; i < toHash.length; i += chunkSize) {
      final end = math.min(i + chunkSize, toHash.length);
      hashes.addAll(await compute(_md5Worker, toHash.sublist(i, end)));
      onProgress?.call(end, toHash.length);
    }

    final groups = <List<String>>[];
    for (final candidates in bySize.values) {
      if (candidates.length < 2) continue;
      final byHash = <String, List<String>>{};
      for (final path in candidates) {
        final hash = hashes[path];
        if (hash == null) continue; // onleesbaar: overgeslagen in de isolate
        byHash.putIfAbsent(hash, () => []).add(path);
      }
      for (final group in byHash.values) {
        if (group.length >= 2) groups.add(group);
      }
    }
    return groups;
  }

  /// Kies binnen een groep duplicaten het pad dat behouden blijft. Voorkeur:
  /// het meest in slides gebruikte bestand, daarna het oudste (vermoedelijk
  /// het origineel), daarna de volgorde in de groep.
  String chooseKeeper(
    List<String> group, {
    int Function(String path)? usageCountOf,
  }) {
    DateTime modifiedOf(String path) {
      try {
        return File(path).statSync().modified;
      } catch (e) {
        logWarning('ImageDedupService.chooseKeeper: stat modified time', e);
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    var keeper = group.first;
    var keeperUsages = usageCountOf?.call(keeper) ?? 0;
    var keeperModified = modifiedOf(keeper);
    for (final candidate in group.skip(1)) {
      final usages = usageCountOf?.call(candidate) ?? 0;
      final modified = modifiedOf(candidate);
      final wins =
          usages > keeperUsages ||
          (usages == keeperUsages && modified.isBefore(keeperModified));
      if (wins) {
        keeper = candidate;
        keeperUsages = usages;
        keeperModified = modified;
      }
    }
    return keeper;
  }

  /// Voeg metadata-teksten (tags/beschrijvingen of opmerkingen/captions) van
  /// duplicaten samen tot één waarde: unieke, niet-lege teksten gescheiden
  /// door [separator]. Een tekst die al letterlijk in een eerdere voorkomt
  /// (zoals dezelfde tag op beide duplicaten) wordt niet herhaald.
  String mergeMetadata(Iterable<String?> values, {String separator = ' · '}) {
    final merged = <String>[];
    for (final value in values) {
      final text = value?.trim() ?? '';
      if (text.isEmpty) continue;
      final isDuplicate = merged.any(
        (existing) => existing.toLowerCase().contains(text.toLowerCase()),
      );
      if (!isDuplicate) merged.add(text);
    }
    return merged.join(separator);
  }
}
