import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/deck.dart';
import '../../services/display_window_service.dart';
import '../../services/markdown_service.dart';
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

  /// Leest en normaliseert een OpenKAT-map zonder er iets in te wijzigen.
  ///
  /// De huidige mappenstructuur zet exports onder `raw-data/`. Voor bestaande
  /// installaties waar de gekozen map zelf de exports bevat, blijft die map de
  /// bron. Deze voorbereidende stap maakt een feitelijke wizard mogelijk
  /// zonder al een deck of sidecars te schrijven.
  Future<({OpenKatManifest manifest, List<OpenKatOrganization> organizations})>
  prepareDirectory(String directory) async {
    final rawDirectory = Directory(p.join(directory, 'raw-data'));
    final sourceDirectory = await rawDirectory.exists()
        ? rawDirectory.path
        : directory;
    final (:manifest, :groups) = await scanner.scan(sourceDirectory);
    return (manifest: manifest, organizations: _normalize(groups));
  }

  /// Imports a directory into a fresh deck.
  ///
  /// The [directory] is the designated OpenKAT directory with three
  /// subdirectories: `raw-data` (JSON exports), `processed-data` (full deck)
  /// and `presentations` (trimmed deck for distribution). All three are
  /// created if absent.
  Future<({Deck deck, OpenKatManifest manifest, String sidecarDirectory})>
  importDirectory(
    String directory, {
    String? outputPath,
    String title = 'OpenKAT managementoverzicht',
  }) async {
    final rawDir = p.join(directory, 'raw-data');
    final processedDir = p.join(directory, 'processed-data');
    final presentationsDir = p.join(directory, 'presentations');
    await Directory(rawDir).create(recursive: true);
    await Directory(processedDir).create(recursive: true);
    await Directory(presentationsDir).create(recursive: true);

    final (:manifest, :organizations) = await prepareDirectory(directory);
    final deck = generator.generate(
      organizations,
      title: title,
      outputPath: p.join(processedDir, _safeFileName(title)),
    );
    await _writeDeck(deck, processedDir);
    await _writeDeck(_trimDeck(deck), presentationsDir);
    final sidecarDir = await _writeSidecars(
      deck: deck,
      manifest: manifest,
      organizations: organizations,
      processedDir: processedDir,
    );
    return (deck: deck, manifest: manifest, sidecarDirectory: sidecarDir);
  }

  /// Re-imports a directory and updates [existing], preserving manual slides.
  ///
  /// Same three-subdirectory structure as [importDirectory].
  Future<({Deck deck, OpenKatManifest manifest, String sidecarDirectory})>
  updateDeck(Deck existing, String directory) async {
    final rawDir = p.join(directory, 'raw-data');
    final processedDir = p.join(directory, 'processed-data');
    final presentationsDir = p.join(directory, 'presentations');
    await Directory(rawDir).create(recursive: true);
    await Directory(processedDir).create(recursive: true);
    await Directory(presentationsDir).create(recursive: true);

    final (:manifest, :organizations) = await prepareDirectory(directory);
    final deck = generator.update(existing, organizations);
    await _writeDeck(deck, processedDir);
    await _writeDeck(_trimDeck(deck), presentationsDir);
    final sidecarDir = await _writeSidecars(
      deck: deck,
      manifest: manifest,
      organizations: organizations,
      processedDir: processedDir,
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
    required String processedDir,
  }) async {
    final dataDir = p.join(processedDir, 'data', 'openkat');
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
          'usable': s.usable,
          'sourceFeatures': [
            for (final feature in s.sourceFeatures) feature.name,
          ],
          if (s.measurementScopeId != null)
            'measurementScopeId': s.measurementScopeId,
          'systems': [
            for (final sys in s.systems)
              {
                'id': sys.id,
                if (sys.hostname != null) 'hostname': sys.hostname,
                if (sys.ip != null) 'ip': sys.ip,
                'oois': sys.oois,
                'stableIdentity': sys.stableIdentity,
                if (sys.monitoringStatus != null)
                  'monitoringStatus': sys.monitoringStatus!.name,
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
                'stableIdentity': f.stableIdentity,
                'cveIds': f.cveIds,
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

  /// Past de weergavelimiet per dia destructief toe: de volledige data in
  /// `processed-data` blijft intact, maar de presentatie in `presentations`
  /// draagt alleen wat op de dia past. De [DisplayWindowSpec] wordt gewist
  /// want de onderliggende data is nu echt ingekort — een limiet op een
  /// tabel die al gekort is zou dubbel tellen.
  Deck _trimDeck(Deck deck) => deck.copyWith(
    slides: [
      for (final slide in deck.slides)
        slide.projectionWithViewLimit().copyWith(clearViewLimit: true),
    ],
  );

  Future<void> _writeDeck(Deck deck, String dir) async {
    final file = File(p.join(dir, '${_safeFileName(deck.title)}.md'));
    await writeStringAtomic(file, MarkdownService().generateDeck(deck));
  }

  String _safeFileName(String title) =>
      title.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
}
