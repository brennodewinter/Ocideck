import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native Windows/Linux identity resolver rejects stale snapshots',
    () async {
      final temp = Directory.systemTemp.createTempSync(
        'ocideck-display-selection-',
      );
      try {
        final executable = '${temp.path}/selection';
        final compile = await Process.run('c++', [
          '-std=c++11',
          '-Wall',
          '-Wextra',
          '-Werror',
          'test/fixtures/native_display_selection.cc',
          '-o',
          executable,
        ]);
        expect(
          compile.exitCode,
          0,
          reason: '${compile.stdout}\n${compile.stderr}',
        );
        final run = await Process.run(executable, []);
        expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
    skip: Platform.isWindows
        ? 'The portable helper runs under macOS/Linux c++; Win32 integration is compiled by the Windows build.'
        : false,
  );
}
