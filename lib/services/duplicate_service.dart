import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../utils/log.dart';
import 'file_service.dart';

/// Eén vermelding in een open-lijst, verrijkt met wat er elders op schijf van
/// te vinden is: byte-identieke kopieën (zelfde presentatie, andere plek) en
/// naamgenoten met afwijkende inhoud (verwarrend, maar géén duplicaat — die
/// mogen nooit stilzwijgend worden samengevoegd).
class DuplicateInfo<T> {
  final T primary;

  /// Andere vindplaatsen met byte-identieke inhoud, in lijstvolgorde.
  final List<T> identical;

  /// Vermeldingen met dezelfde weergavetitel maar afwijkende inhoud.
  final List<T> sameTitle;

  const DuplicateInfo({
    required this.primary,
    this.identical = const [],
    this.sameTitle = const [],
  });

  bool get hasIdenticalCopies => identical.isNotEmpty;
  bool get hasTitleConflict => sameTitle.isNotEmpty;

  /// De hele identieke groep, primaire vermelding voorop.
  List<T> get all => [primary, ...identical];
}

/// Detecteert exacte duplicaten tussen gevonden presentaties. Identiteit is
/// de SHA-256 van de markdown-bytes; sidecars (aantekeningen, notities)
/// tellen bewust niet mee — zelfde md is dezelfde presentatie, hooguit met
/// andere aantekeningen eroverheen.
class DuplicateService {
  /// SHA-256 over [bytes], als hex-string.
  static String contentHash(List<int> bytes) =>
      sha256.convert(bytes).toString();

  /// Groepeer scan-treffers op identieke bestandsinhoud. Leest alléén
  /// bestanden waarvan de grootte meer dan eens voorkomt (alleen even grote
  /// bestanden kúnnen identiek zijn), dus de extra I/O blijft verwaarloosbaar
  /// ten opzichte van de scan zelf.
  Future<List<DuplicateInfo<ScanHit>>> groupScanHits(List<ScanHit> hits) async {
    final bySize = <int, List<ScanHit>>{};
    for (final hit in hits) {
      (bySize[hit.size] ??= []).add(hit);
    }
    final hashByPath = <String, String>{};
    for (final sameSize in bySize.values) {
      if (sameSize.length < 2) continue;
      for (final hit in sameSize) {
        try {
          hashByPath[hit.path] = contentHash(
            await File(hit.path).readAsBytes(),
          );
        } catch (e) {
          // Onleesbaar = niet aantoonbaar identiek; de treffer blijft een
          // gewone losse vermelding.
          logWarning('DuplicateService.groupScanHits: hash failed', e);
        }
      }
    }
    return _group(
      hits,
      (hit) => hashByPath[hit.path] ?? 'los:${hit.path}',
      (hit) => hit.displayTitle,
    );
  }

  /// Voor de openen-dialoog: de markdown is daar al volledig in het geheugen
  /// gelezen, dus groeperen is puur rekenwerk zonder extra I/O.
  List<DuplicateInfo<ScannedPresentation>> groupScanned(
    List<ScannedPresentation> presentations,
  ) {
    return _group(
      presentations,
      (pres) => contentHash(utf8.encode(pres.content)),
      (pres) => pres.displayTitle,
    );
  }

  /// Groepeer [items] op inhoudssleutel, in invoervolgorde (de eerste van een
  /// groep wordt de zichtbare vermelding). Titelconflicten worden daarna
  /// tussen de primaire vermeldingen onderling bepaald: twee groepen zijn per
  /// definitie inhoudelijk verschillend, dus een gedeelde titel dáár is
  /// precies het "zelfde naam, andere inhoud"-geval.
  static List<DuplicateInfo<T>> _group<T>(
    List<T> items,
    String Function(T) keyOf,
    String Function(T) titleOf,
  ) {
    final byKey = <String, List<T>>{};
    final order = <String>[];
    for (final item in items) {
      final key = keyOf(item);
      final group = byKey[key];
      if (group == null) {
        byKey[key] = [item];
        order.add(key);
      } else {
        group.add(item);
      }
    }

    final byTitle = <String, List<T>>{};
    for (final key in order) {
      final primary = byKey[key]!.first;
      (byTitle[titleOf(primary).trim().toLowerCase()] ??= []).add(primary);
    }

    return [
      for (final key in order)
        DuplicateInfo(
          primary: byKey[key]!.first,
          identical: byKey[key]!.skip(1).toList(),
          sameTitle: byTitle[titleOf(byKey[key]!.first).trim().toLowerCase()]!
              .where((other) => !identical(other, byKey[key]!.first))
              .toList(),
        ),
    ];
  }

  /// Zoek voor een zojuist geopend bestand een byte-identieke kopie onder
  /// [candidatePaths] (typisch de recente lijst). Grootte-voorfilter zoals in
  /// [groupScanHits]; geeft het pad van de eerste identieke kopie, of null.
  Future<String?> findIdenticalCopy(
    String openedPath,
    List<String> candidatePaths,
  ) async {
    try {
      final opened = File(openedPath);
      final size = await opened.length();
      List<int>? openedBytes;
      for (final candidate in candidatePaths) {
        if (p.equals(candidate, openedPath)) continue;
        final file = File(candidate);
        try {
          if (!await file.exists() || await file.length() != size) continue;
          openedBytes ??= await opened.readAsBytes();
          final bytes = await file.readAsBytes();
          if (contentHash(bytes) == contentHash(openedBytes)) return candidate;
        } catch (e) {
          logWarning('DuplicateService.findIdenticalCopy: candidate', e);
        }
      }
    } catch (e) {
      logWarning('DuplicateService.findIdenticalCopy: opened file', e);
    }
    return null;
  }
}
