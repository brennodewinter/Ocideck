import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../models/openkat/openkat_models.dart';
import 'openkat_json_adapter.dart';

/// Scans a directory for OpenKAT JSON exports, builds a manifest and groups
/// recognised files by organisation and report date.
class OpenKatDirectoryScanner {
  /// Bovengrens per rapportbestand. Zelfde orde als de sidecar-grenzen
  /// elders: ruim voor élke echte OpenKAT-export, krap voor onzin.
  static const int maxReportBytes = 16 * 1024 * 1024; // 16 MiB

  const OpenKatDirectoryScanner();

  Future<({OpenKatManifest manifest, List<OpenKatSnapshotGroup> groups})> scan(
    String directory, {
    DateTime? fallbackDate,
  }) async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      return (
        manifest: OpenKatManifest(
          parserVersion: '1.0.0',
          importedAt: DateTime.now().toUtc(),
          directory: directory,
          entries: [
            OpenKatManifestEntry(
              path: directory,
              hash: '',
              status: 'error: directory not found',
            ),
          ],
        ),
        groups: const <OpenKatSnapshotGroup>[],
      );
    }

    final entries = <OpenKatManifestEntry>[];
    final byOrgDate = <String, List<OpenKatSnapshotCandidate>>{};
    final seenHashes = <String, OpenKatManifestEntry>{};

    // followLinks uit: een symlink in andermans exportmap mag de scan niet
    // buiten de gekozen map laten lezen (bewaker-notitie #767).
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!p.extension(entity.path).toLowerCase().endsWith('.json')) continue;

      final relative = p.relative(entity.path, from: directory);
      // Invoerpoort (P5-lijn): de map komt van buiten, en jsonDecode kopieert
      // alles nog eens. Een rapportage van tientallen megabytes is geen
      // OpenKAT-export maar iets anders — begrenzen vóór het lezen, en het
      // manifest zegt eerlijk wat er overgeslagen is.
      final size = await entity.length();
      if (size > OpenKatDirectoryScanner.maxReportBytes) {
        entries.add(
          OpenKatManifestEntry(
            path: relative,
            hash: '',
            status:
                'error: too large ($size bytes, max ${OpenKatDirectoryScanner.maxReportBytes})',
          ),
        );
        continue;
      }
      final bytes = await entity.readAsBytes();
      final hash = sha256.convert(bytes).toString();

      if (seenHashes.containsKey(hash)) {
        entries.add(
          OpenKatManifestEntry(
            path: relative,
            hash: hash,
            organizationCode: seenHashes[hash]!.organizationCode,
            organizationName: seenHashes[hash]!.organizationName,
            reportDate: seenHashes[hash]!.reportDate,
            schema: seenHashes[hash]!.schema,
            status: 'duplicate',
          ),
        );
        continue;
      }

      Map<String, dynamic>? json;
      try {
        json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>?;
      } catch (e) {
        entries.add(
          OpenKatManifestEntry(
            path: relative,
            hash: hash,
            status: 'error: invalid json',
            error: e.toString(),
          ),
        );
        continue;
      }

      final adapter = _detectAdapter(json!);
      if (adapter == null) {
        entries.add(
          OpenKatManifestEntry(
            path: relative,
            hash: hash,
            status: 'unrecognized',
          ),
        );
        continue;
      }

      final code = adapter.organizationCode(json) ?? 'unknown';
      final name = adapter.organizationName(json) ?? code;
      final date =
          adapter.reportDate(json) ??
          OpenKatJsonAdapter.dateFromFilename(p.basename(entity.path)) ??
          fallbackDate ??
          DateTime.now().toUtc();

      final candidate = OpenKatSnapshotCandidate(
        path: relative,
        hash: hash,
        organizationCode: code,
        organizationName: name,
        reportDate: date,
        schema: adapter.name,
        adapter: adapter,
        json: json,
      );

      final key = '$code|${date.toIso8601String()}';
      byOrgDate.putIfAbsent(key, () => []).add(candidate);
      seenHashes[hash] = OpenKatManifestEntry(
        path: relative,
        hash: hash,
        organizationCode: code,
        organizationName: name,
        reportDate: date,
        schema: adapter.name,
        status: 'ok',
      );
      entries.add(seenHashes[hash]!);
    }

    final groups = _buildGroups(byOrgDate, entries);

    return (
      manifest: OpenKatManifest(
        parserVersion: '1.0.0',
        importedAt: DateTime.now().toUtc(),
        directory: directory,
        entries: entries,
      ),
      groups: groups,
    );
  }

  /// Eén groep per organisatie/datum; extra kandidaten worden als conflict in
  /// het manifest gemeld en de eerste wint — deterministisch, want de sleutels
  /// zijn gesorteerd.
  List<OpenKatSnapshotGroup> _buildGroups(
    Map<String, List<OpenKatSnapshotCandidate>> byOrgDate,
    List<OpenKatManifestEntry> entries,
  ) {
    final groups = <OpenKatSnapshotGroup>[];
    for (final key in byOrgDate.keys.toList()..sort()) {
      final candidates = byOrgDate[key]!;
      if (candidates.length > 1) {
        final first = candidates.first;
        for (var i = 1; i < candidates.length; i++) {
          entries.add(
            OpenKatManifestEntry(
              path: candidates[i].path,
              hash: candidates[i].hash,
              organizationCode: candidates[i].organizationCode,
              organizationName: candidates[i].organizationName,
              reportDate: candidates[i].reportDate,
              schema: candidates[i].schema,
              status: 'conflict',
              error: 'Same organisation and date as ${first.path}',
            ),
          );
        }
        groups.add(OpenKatSnapshotGroup.fromCandidates([first]));
      } else {
        groups.add(OpenKatSnapshotGroup.fromCandidates(candidates));
      }
    }
    return groups;
  }

  OpenKatJsonAdapter? _detectAdapter(Map<String, dynamic> json) {
    for (final adapter in openKatAdapters) {
      if (adapter.recognizes(json)) return adapter;
    }
    return null;
  }
}

class OpenKatSnapshotCandidate {
  final String path;
  final String hash;
  final String organizationCode;
  final String organizationName;
  final DateTime reportDate;
  final String schema;
  final OpenKatJsonAdapter adapter;
  final Map<String, dynamic> json;

  const OpenKatSnapshotCandidate({
    required this.path,
    required this.hash,
    required this.organizationCode,
    required this.organizationName,
    required this.reportDate,
    required this.schema,
    required this.adapter,
    required this.json,
  });
}

/// A group of candidate files for one organisation/date. At most one file is
/// kept per group; conflicts are reported in the manifest.
class OpenKatSnapshotGroup {
  final String organizationCode;
  final String organizationName;
  final DateTime reportDate;
  final OpenKatSnapshotCandidate candidate;

  const OpenKatSnapshotGroup({
    required this.organizationCode,
    required this.organizationName,
    required this.reportDate,
    required this.candidate,
  });

  factory OpenKatSnapshotGroup.fromCandidates(
    List<OpenKatSnapshotCandidate> candidates,
  ) {
    final c = candidates.first;
    return OpenKatSnapshotGroup(
      organizationCode: c.organizationCode,
      organizationName: c.organizationName,
      reportDate: c.reportDate,
      candidate: c,
    );
  }
}
