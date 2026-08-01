import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/asset_rights.dart';
import '../utils/atomic_file.dart';

class AssetRightsStore {
  static const directoryName = 'asset-assessments';
  static const maxSidecarBytes = 1024 * 1024;

  final String repositoryRoot;

  const AssetRightsStore(this.repositoryRoot);

  static String repoPathFor(String sha256) =>
      p.posix.join('.ocideck', directoryName, '$sha256.json');

  File fileFor(String sha256) =>
      File(p.join(repositoryRoot, repoPathFor(sha256)));

  Future<AssetRightsAssessment?> read(String sha256) async {
    final file = fileFor(sha256);
    if (!await file.exists()) return null;
    if (await file.length() > maxSidecarBytes) {
      throw const FormatException('Assetrechten-sidecar is te groot');
    }
    final assessment = AssetRightsAssessment.decode(await file.readAsString());
    if (assessment.sha256 != sha256) {
      throw const FormatException(
        'Assetrechten-sidecar hoort bij andere bytes',
      );
    }
    return assessment;
  }

  Future<void> write(AssetRightsAssessment assessment) async {
    final file = fileFor(assessment.sha256);
    await file.parent.create(recursive: true);
    await writeStringAtomic(file, '${assessment.encode()}\n');
  }
}
