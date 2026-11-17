import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native permission ownership and key filtering contracts', () async {
    final directory = await Directory.systemTemp.createTemp('ocideck-webview-');
    try {
      for (final command in [
        [
          'cmake',
          '-S',
          'third_party/webview_win_floating/test/native',
          '-B',
          directory.path,
        ],
        ['cmake', '--build', directory.path, '--config', 'Release'],
        [
          'ctest',
          '--test-dir',
          directory.path,
          '-C',
          'Release',
          '--output-on-failure',
        ],
      ]) {
        final result = await Process.run(
          command.first,
          command.skip(1).toList(),
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
