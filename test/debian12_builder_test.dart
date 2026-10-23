@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Debian 12 builder accepts a Git worktree as its source', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck-builder-');
    addTearDown(() => temp.delete(recursive: true));
    final source = Directory('${temp.path}/source')..createSync();
    File('${source.path}/.git').writeAsStringSync('gitdir: elsewhere\n');
    File(
      '${source.path}/.tool-versions',
    ).writeAsStringSync('flutter 3.47.7-stable\n');
    final log = File('${temp.path}/engine.log');
    final engine = File('${temp.path}/docker')
      ..writeAsStringSync('#!/bin/sh\nprintf "%s\\n" "\$*" >> "${log.path}"\n');
    await Process.run('chmod', ['+x', engine.path]);

    final result = await Process.run(
      'bash',
      ['scripts/debian12_builder/build.sh'],
      environment: {
        'OCIDECK_SOURCE_DIR': source.path,
        'OCIDECK_OUTPUT_DIR': '${temp.path}/out',
        'OCIDECK_PUB_CACHE_DIR': '${temp.path}/cache',
        'CONTAINER_ENGINE': engine.path,
      },
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(log.readAsStringSync(), contains('${source.path}:/src'));
  });
}
