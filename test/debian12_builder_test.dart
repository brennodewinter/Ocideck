@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Debian 12 archive gates publication and joins the signed release', () {
    final workflow = File('.forgejo/workflows/release.yml').readAsStringSync();
    final release = File('scripts/release_auto.sh').readAsStringSync();
    final dockerfile = File(
      'scripts/debian12_builder/Dockerfile',
    ).readAsStringSync();
    expect(workflow, contains('linux-debian12:'));
    expect(workflow, contains('scripts/build_debian12_release.sh'));
    expect(workflow, contains('consumer-debian12:'));
    expect(workflow, contains('needs: linux-debian12'));
    expect(workflow, contains('needs: [web, linux, linux-debian12,'));
    expect(workflow, contains('consumer-deb, consumer-debian12, consumer-rpm'));
    expect(workflow, contains('name: ocideck-linux-debian12, path: dist'));
    expect(
      release,
      contains('ocideck-linux-debian12-x86_64-\$NEW_VERSION.tar.gz'),
    );
    expect(dockerfile, contains('sha256sum -c -'));
  });

  test('Debian 12 builder accepts a Git worktree as its source', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck-builder-');
    addTearDown(() => temp.delete(recursive: true));
    final base = Directory('${temp.path}/base')..createSync();
    File(
      '${base.path}/.tool-versions',
    ).writeAsStringSync('flutter 3.47.7-stable\n');
    File('${base.path}/pubspec.yaml').writeAsStringSync('version: 9.9.9\n');
    await Process.run('git', ['init', '-q', base.path]);
    await Process.run('git', ['-C', base.path, 'add', '.']);
    await Process.run('git', [
      '-C',
      base.path,
      '-c',
      'user.name=Test',
      '-c',
      'user.email=test@example.invalid',
      'commit',
      '-qm',
      'source',
    ]);
    final source = Directory('${temp.path}/source');
    await Process.run('git', [
      '-C',
      base.path,
      'worktree',
      'add',
      '-q',
      source.path,
    ]);
    expect(File('${source.path}/.git').existsSync(), isTrue);
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
    expect(log.readAsStringSync(), contains('/work/ocideck-snapshot.'));
    expect(log.readAsStringSync(), isNot(contains('${source.path}:/src')));
    expect(log.readAsStringSync(), contains('--platform linux/amd64'));
  });

  test('release builder exports the tagged Debian 12 archive', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck-release-');
    addTearDown(() => temp.delete(recursive: true));
    final scripts = Directory('${temp.path}/scripts')..createSync();
    Directory('${scripts.path}/debian12_builder').createSync();
    File('${temp.path}/pubspec.yaml').writeAsStringSync('version: 9.9.9+42\n');
    File(
      '${temp.path}/.tool-versions',
    ).writeAsStringSync('flutter 3.47.7-stable\n');
    final releaseScript = File('${scripts.path}/build_debian12_release.sh');
    File('scripts/build_debian12_release.sh').copySync(releaseScript.path);
    await Process.run('git', ['init', '-q', temp.path]);
    await Process.run('git', ['-C', temp.path, 'add', '.']);
    await Process.run('git', [
      '-C',
      temp.path,
      '-c',
      'user.name=Test',
      '-c',
      'user.email=test@example.invalid',
      'commit',
      '-qm',
      'source',
    ]);
    final log = File('${temp.path}/docker.log');
    final docker = File('${temp.path}/docker')
      ..writeAsStringSync('''#!/bin/sh
printf '%s\\n' "\$*" >> "${log.path}"
case "\$1" in
  create) echo test-container ;;
  inspect) echo 0 ;;
  cp) case "\$2" in -) cat > "${temp.path}/source.tar" ;; *:/out/*) echo archive > "\$3" ;; esac ;;
esac
''');
    await Process.run('chmod', ['+x', docker.path]);

    final result = await Process.run(
      'bash',
      [releaseScript.path, '9.9.9'],
      environment: {'PATH': '${temp.path}:${Platform.environment['PATH']}'},
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      File(
        '${temp.path}/dist/ocideck-linux-debian12-x86_64-9.9.9.tar.gz',
      ).existsSync(),
      isTrue,
    );
    expect(log.readAsStringSync(), contains('cp - test-container:/src'));
    final archive = await Process.run('tar', [
      '-tf',
      '${temp.path}/source.tar',
    ]);
    expect(archive.exitCode, 0);
    expect(archive.stdout, isNot(contains('.git')));
  });
}
