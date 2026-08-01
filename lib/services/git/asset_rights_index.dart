import 'dart:convert';
import 'dart:typed_data';

import '../../models/asset_rights.dart';
import '../asset_rights_scanner.dart';
import '../asset_rights_store.dart';
import '../image_service.dart';
import '../../utils/log.dart';
import 'git_forge.dart';

class RepoAssetRightsSnapshot {
  final List<AssetRightsAssessment> assessments;
  final List<String> unreadable;
  final int newlyScanned;

  const RepoAssetRightsSnapshot({
    required this.assessments,
    required this.unreadable,
    required this.newlyScanned,
  });
}

/// Repositorybrede lokale rechtencontrole. Alleen afbeeldingsbytes en
/// sidecars worden gelezen; er gaat niets naar een externe beeldzoekdienst.
class RepoAssetRightsIndex {
  final GitForge forge;
  final String branch;

  const RepoAssetRightsIndex({required this.forge, required this.branch});

  Future<RepoAssetRightsSnapshot> scanAndPersist() async {
    final entries = await forge.listTree(branch, 'assets', recursive: true);
    final assessments = <AssetRightsAssessment>[];
    final unreadable = <String>[];
    final upserts = <String, Uint8List>{};

    for (final entry in entries) {
      if (entry.type != RepoEntryType.file) continue;
      try {
        final name = entry.name;
        final dot = name.lastIndexOf('.');
        if (dot <= 0) continue;
        final hash = name.substring(0, dot).toLowerCase();
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) continue;
        final sidecarPath = AssetRightsStore.repoPathFor(hash);
        AssetRightsAssessment? previous;
        try {
          final sidecar = await forge.readBlob(branch, sidecarPath);
          if (sidecar.length > AssetRightsStore.maxSidecarBytes) {
            unreadable.add(sidecarPath);
            continue;
          }
          previous = AssetRightsAssessment.decode(utf8.decode(sidecar));
          if (previous.sha256 != hash) {
            unreadable.add(sidecarPath);
            continue;
          }
          if (previous.scannerVersion == AssetRightsScanner.version) {
            assessments.add(previous);
            continue;
          }
        } on GitForgeException catch (e) {
          if (e.kind != GitForgeError.notFound) rethrow;
        } on FormatException {
          // Onleesbaar is niet "afwezig": niet overschrijven, wel melden.
          unreadable.add(sidecarPath);
          continue;
        }

        final bytes = await forge.readBlob(branch, entry.path);
        if (!ImageService.looksLikeImage(bytes.take(16).toList())) continue;
        final assessment = await const AssetRightsScanner().scan(
          bytes,
          filename: name,
          provenance: previous?.provenance ?? const AssetRightsProvenance(),
          dispositions: previous?.dispositions ?? const [],
        );
        if (assessment.sha256 != hash) {
          unreadable.add(entry.path);
          continue;
        }
        assessments.add(assessment);
        upserts[sidecarPath] = Uint8List.fromList(
          utf8.encode('${assessment.encode()}\n'),
        );
      } catch (error, stackTrace) {
        logError('RepoAssetRightsIndex: asset beoordelen', error, stackTrace);
        unreadable.add(entry.path);
      }
    }

    if (upserts.isNotEmpty) {
      final head = await forge.headSha(branch);
      await forge.commitFiles(
        branch: branch,
        message: 'Scan afbeeldingsrechten',
        upserts: upserts,
        deletes: const [],
        baseSha: head,
      );
    }
    return RepoAssetRightsSnapshot(
      assessments: assessments,
      unreadable: unreadable,
      newlyScanned: upserts.length,
    );
  }

  Future<AssetRightsAssessment> decide(
    AssetRightsAssessment assessment,
    AssetRightsSignal signal, {
    required AssetRightsDispositionStatus status,
    required String reason,
    String? note,
    String? decidedBy,
  }) async {
    final latest = await _latestAssessment(assessment);
    final currentSignal = latest.signals.where(
      (item) => item.key == signal.key,
    );
    if (currentSignal.isEmpty) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Het te beoordelen signaal staat niet meer in de repository',
      );
    }
    final updated = latest.copyWith(
      dispositions: [
        ...latest.dispositions,
        AssetRightsDisposition(
          signalKey: signal.key,
          status: status,
          reason: reason,
          note: note,
          decidedBy: decidedBy,
          decidedAt: DateTime.now().toUtc(),
        ),
      ],
    );
    final head = await forge.headSha(branch);
    await forge.commitFiles(
      branch: branch,
      message: 'Beoordeel afbeeldingsrechten',
      upserts: {
        AssetRightsStore.repoPathFor(updated.sha256): Uint8List.fromList(
          utf8.encode('${updated.encode()}\n'),
        ),
      },
      deletes: const [],
      baseSha: head,
    );
    return updated;
  }

  Future<AssetRightsAssessment> _latestAssessment(
    AssetRightsAssessment fallback,
  ) async {
    final bytes = await forge.readBlob(
      branch,
      AssetRightsStore.repoPathFor(fallback.sha256),
    );
    if (bytes.length > AssetRightsStore.maxSidecarBytes) {
      throw const GitForgeException(
        GitForgeError.tooLarge,
        'De assetrechten-sidecar is te groot',
      );
    }
    final latest = AssetRightsAssessment.decode(utf8.decode(bytes));
    if (latest.sha256 != fallback.sha256) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'De assetrechten-sidecar hoort bij andere bytes',
      );
    }
    return latest;
  }
}
