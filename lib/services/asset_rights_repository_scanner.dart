import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/asset_rights.dart';
import 'asset_rights_scanner.dart';
import 'asset_rights_store.dart';
import 'image_service.dart';
import '../utils/log.dart';

class AssetRightsRepositoryScanResult {
  final List<AssetRightsAssessment> assessments;
  final List<String> unreadablePaths;
  final int reused;

  const AssetRightsRepositoryScanResult({
    required this.assessments,
    required this.unreadablePaths,
    required this.reused,
  });
}

class AssetRightsRepositoryScanner {
  final AssetRightsScanner scanner;

  const AssetRightsRepositoryScanner({this.scanner = const _DefaultScanner()});

  Future<AssetRightsRepositoryScanResult> scan(String repositoryRoot) async {
    final assets = Directory(p.join(repositoryRoot, 'assets'));
    if (!await assets.exists()) {
      return const AssetRightsRepositoryScanResult(
        assessments: [],
        unreadablePaths: [],
        reused: 0,
      );
    }
    final store = AssetRightsStore(repositoryRoot);
    final results = <AssetRightsAssessment>[];
    final unreadable = <String>[];
    var reused = 0;
    await for (final entity in assets.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      try {
        if (await entity.length() <= 0 ||
            await entity.length() > ImageService.maxImageBytes) {
          continue;
        }
        final bytes = await entity.readAsBytes();
        if (!ImageService.looksLikeImage(bytes.take(16).toList())) continue;
        final hash = sha256.convert(bytes).toString();
        final previous = await store.read(hash);
        if (previous != null &&
            previous.scannerVersion == AssetRightsScanner.version) {
          results.add(previous);
          reused++;
          continue;
        }
        final assessment = await scanner.scan(
          Uint8List.fromList(bytes),
          filename: p.basename(entity.path),
          provenance: previous?.provenance ?? const AssetRightsProvenance(),
          dispositions: previous?.dispositions ?? const [],
        );
        await store.write(assessment);
        results.add(assessment);
      } catch (error, stackTrace) {
        logError(
          'AssetRightsRepositoryScanner: asset beoordelen',
          error,
          stackTrace,
        );
        unreadable.add(p.relative(entity.path, from: repositoryRoot));
      }
    }
    return AssetRightsRepositoryScanResult(
      assessments: results,
      unreadablePaths: unreadable,
      reused: reused,
    );
  }
}

class _DefaultScanner extends AssetRightsScanner {
  const _DefaultScanner();
}
