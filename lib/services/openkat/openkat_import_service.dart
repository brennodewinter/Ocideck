import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/deck.dart';
import '../../utils/atomic_file.dart';
import '../../models/openkat/openkat_models.dart';
import 'openkat_aggregator.dart';
import 'openkat_deck_generator.dart';
import 'openkat_directory_scanner.dart';
import 'openkat_normalizer.dart';

/// End-to-end OpenKAT import: from directory to OciDeck deck.
///
/// Produces the deck, the import manifest, and sidecar JSON/CSV files under
/// [outputDirectory]/data/openkat/ when an output path is provided. The same
/// directory re-imported with an existing deck updates only the generated
/// OpenKAT slides, leaving manual slides untouched.
class OpenKatImportService {
  final OpenKatDirectoryScanner scanner;
  final OpenKatNormalizer normalizer;
  final OpenKatAggregator aggregator;
  final OpenKatDeckGenerator generator;

  const OpenKatImportService({
    this.scanner = const OpenKatDirectoryScanner(),
    this.normalizer = const OpenKatNormalizer(),
    this.aggregator = const OpenKatAggregator(),
    this.generator = const OpenKatDeckGenerator(),
  });

  /// Imports a directory into a fresh deck.
  Future<({Deck deck, OpenKatManifest manifest, String sidecarDirectory})>
  importDirectory(
    String directory, {
    String? outputPath,
    String title = 'OpenKAT managementoverzicht',
  }) async {
    final (:manifest, :groups) = await scanner.scan(directory);
    final organizations = _normalize(groups);
    final deck = generator.generate(
      organizations,
      title: title,
      outputPath: outputPath,
    );
    final sidecarDir = await _writeSidecars(
      deck: deck,
      manifest: manifest,
      organizations: organizations,
      outputPath: outputPath,
    );
    return (deck: deck, manifest: manifest, sidecarDirectory: sidecarDir);
  }

  /// Re-imports a directory and updates [existing], preserving manual slides.
  Future<({Deck deck, OpenKatManifest manifest, String sidecarDirectory})>
  updateDeck(Deck existing, String directory) async {
    final (:manifest, :groups) = await scanner.scan(directory);
    final organizations = _normalize(groups);
    final deck = generator.update(existing, organizations);
    final sidecarDir = await _writeSidecars(
      deck: deck,
      manifest: manifest,
      organizations: organizations,
      outputPath: existing.projectPath,
    );
    return (deck: deck, manifest: manifest, sidecarDirectory: sidecarDir);
  }

  List<OpenKatOrganization> _normalize(List<OpenKatSnapshotGroup> groups) {
    final byOrg = <String, OpenKatOrganization>{};
    final orderedGroups = groups.toList()
      ..sort((a, b) => a.reportDate.compareTo(b.reportDate));

    for (final group in orderedGroups) {
      final older = byOrg[group.organizationCode]?.snapshots ?? const [];
      final snapshot = normalizer.normalize(group, olderSnapshots: older);
      final existing = byOrg[group.organizationCode];
      if (existing != null) {
        byOrg[group.organizationCode] = existing.copyWith(
          snapshots: [...existing.snapshots, snapshot],
        );
      } else {
        byOrg[group.organizationCode] = OpenKatOrganization(
          code: group.organizationCode,
          name: group.organizationName,
          snapshots: [snapshot],
        );
      }
    }
    return byOrg.values.toList();
  }

  Future<String> _writeSidecars({
    required Deck deck,
    required OpenKatManifest manifest,
    required List<OpenKatOrganization> organizations,
    required String? outputPath,
  }) async {
    if (outputPath == null || outputPath.isEmpty) {
      return '';
    }
    final dir = p.dirname(outputPath);
    final dataDir = p.join(dir, 'data', 'openkat');
    await Directory(dataDir).create(recursive: true);

    final manifestFile = File(p.join(dataDir, 'manifest.json'));
    await writeStringAtomic(
      manifestFile,
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
    );

    for (final org in organizations) {
      final safe = _safe(org.code);
      final orgFile = File(p.join(dataDir, '$safe.json'));
      await writeStringAtomic(
        orgFile,
        const JsonEncoder.withIndent('  ').convert(_orgToJson(org)),
      );
    }

    return dataDir;
  }

  Map<String, dynamic> _orgToJson(OpenKatOrganization org) => {
    'code': org.code,
    'name': org.name,
    'snapshots': [
      for (final s in org.snapshots)
        {
          'reportDate': s.reportDate.toIso8601String(),
          'sourceFile': s.sourceFile,
          'sourceHash': s.sourceHash,
          if (s.schema != null) 'schema': s.schema,
          'systems': [
            for (final sys in s.systems)
              {
                'id': sys.id,
                if (sys.hostname != null) 'hostname': sys.hostname,
                if (sys.ip != null) 'ip': sys.ip,
                'oois': sys.oois,
              },
          ],
          'findings': [
            for (final f in s.findings)
              {
                'id': f.id,
                'findingTypeId': f.findingTypeId,
                if (f.findingTypeName != null)
                  'findingTypeName': f.findingTypeName,
                'severity': f.severity,
                if (f.systemId != null) 'systemId': f.systemId,
                if (f.openedAt != null)
                  'openedAt': f.openedAt!.toIso8601String(),
                if (f.recommendation != null)
                  'recommendation': f.recommendation,
                if (f.impact != null) 'impact': f.impact,
                'sourceReports': f.sourceReports,
              },
          ],
          'controls': {
            for (final entry in s.controls.entries)
              entry.key: {
                'name': entry.value.name,
                'compliant': entry.value.compliant,
                'total': entry.value.total,
              },
          },
        },
    ],
  };

  String _safe(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
}
