import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'channel workflow is manual and publishes only consumer-checked bytes',
    () {
      final workflow = File(
        '.forgejo/workflows/release-channel.yml',
      ).readAsStringSync();
      expect(workflow, contains('workflow_dispatch:'));
      final legacy = File('.forgejo/workflows/release.yml').readAsStringSync();
      expect(legacy, isNot(contains('  push:')));
      expect(legacy, contains('workflow_dispatch:'));
      expect(workflow, isNot(contains('push:')));
      expect(workflow, isNot(contains('runs-on: macos')));
      expect(workflow, contains('name: channel-candidate-'));
      for (final channel in ['deb', 'rpm', 'appimage', 'flatpak', 'tar']) {
        expect(
          workflow,
          contains("needs.consumer-$channel.result == 'success'"),
        );
      }
      expect(workflow, contains('timeout 20 xvfb-run'));
      expect(workflow, contains('flatpak --user install'));
      expect(workflow, isNot(contains('make package-linux')));
      expect(workflow, contains("github.ref == 'refs/heads/main'"));
      expect(workflow, contains('retention-days: 90'));
      expect(workflow, contains('channel-native-linux-x64-'));
      for (final input in [
        'source/.tool-versions',
        'source/pubspec.lock',
        'source/third_party/**',
        'controller/.forgejo/workflows/release-channel.yml',
      ]) {
        expect(workflow, contains(input));
      }
      expect(
        workflow.indexOf('Vaste bron controleren'),
        lessThan(workflow.indexOf('path: source')),
      );
      expect(
        workflow,
        contains('bash ../controller/scripts/build_release_channel.sh'),
      );
      expect(workflow, contains('ref: \${{ github.sha }}'));
    },
  );

  test('invalid source identity stops before any build command', () async {
    final result = await Process.run('bash', [
      'scripts/build_release_channel.sh',
      'v0.7.7',
      'main',
      'codex/release-candidate-v0.7.7-main',
      'web',
    ]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr.toString(), contains('full lowercase commit SHA'));
  });
}
