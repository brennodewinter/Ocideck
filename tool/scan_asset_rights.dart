import 'dart:convert';
import 'dart:io';

import 'package:ocideck/services/asset_rights_repository_scanner.dart';

Future<void> main(List<String> args) async {
  final json = args.contains('--format=json') || args.contains('--json');
  final root = args.where((a) => !a.startsWith('--')).firstOrNull ?? '.';
  final result = await const AssetRightsRepositoryScanner().scan(root);
  final open = result.assessments
      .where((assessment) => assessment.openSignals.isNotEmpty)
      .toList();

  if (json) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'scanned': result.assessments.length,
        'reused': result.reused,
        'needs_review': open.length,
        'unreadable': result.unreadablePaths,
        'assessments': result.assessments.map((a) => a.toJson()).toList(),
      }),
    );
  } else {
    stdout.writeln(
      '${result.assessments.length} afbeeldingen gecontroleerd; '
      '${result.reused} bestaande resultaten hergebruikt.',
    );
    stdout.writeln('${open.length} afbeeldingen vragen om beoordeling.');
    if (result.unreadablePaths.isNotEmpty) {
      stderr.writeln(
        '${result.unreadablePaths.length} afbeeldingen konden niet worden gelezen.',
      );
    }
  }
  if (result.unreadablePaths.isNotEmpty) exitCode = 2;
}
