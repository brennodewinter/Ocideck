// Two independent flutter-drive launches, sharing only an isolated disk fixture.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../test_driver/desktop_smoke_process.dart';

Future<void> main(List<String> args) async {
  final device = args.isEmpty ? Platform.operatingSystem : args.single;
  if (!{'macos', 'linux', 'windows'}.contains(device) ||
      device != Platform.operatingSystem) {
    throw ArgumentError('Run on the matching macos, linux or windows host');
  }
  final root = Directory.systemTemp.createTempSync('ocideck-desktop-smoke-');
  final evidence = Directory(p.join('build', 'desktop-smoke'))
    ..createSync(recursive: true);
  final revision = await Process.run('git', ['rev-parse', 'HEAD']);
  final status = await Process.run('git', ['status', '--porcelain']);
  if (revision.exitCode != 0 || status.exitCode != 0) {
    throw StateError('Cannot record probe source state');
  }
  final source = revision.stdout.toString().trim();
  final dirty = status.stdout.toString().isNotEmpty;
  stderr.writeln('Probe source: $source (working tree dirty: $dirty)');
  stderr.writeln('Native lifecycle fixture: ${root.path}');
  var completed = false;
  try {
    File(p.join(root.path, 'journey.md')).writeAsStringSync('''---
marp: true
title: Native lifecycle
---
<!-- _class: title -->
# Native lifecycle
''');
    if (device == 'macos') {
      await _run('xcrun', [
        'clang',
        '-dynamiclib',
        '-arch',
        'arm64',
        '-arch',
        'x86_64',
        '-framework',
        'AppKit',
        'test_driver/macos_quit_probe.m',
        '-o',
        p.join(root.path, 'quit-probe.dylib'),
      ]);
    }
    // Build macOS once with the existing framework fix, then launch precisely
    // that app twice. The isolated runtime path is not a compile-time define.
    const target = 'integration_test/desktop_lifecycle_test.dart';
    const macosApp = 'build/macos/Build/Products/Profile/OciDeck.app';
    if (device == 'macos') {
      await _run('scripts/with_macos_flutter_semantics_fix.sh', [
        'build',
        'macos',
        '--profile',
        '--target=$target',
      ]);
    }
    final results = <String, Map<String, dynamic>>{};
    for (final phase in ['write', 'reopen']) {
      File(p.join(root.path, 'phase.txt')).writeAsStringSync(phase);
      final resultPath = p.absolute(evidence.path, '$phase.json');
      final oldResult = File(resultPath);
      if (oldResult.existsSync()) oldResult.deleteSync();
      await _run(
        'flutter',
        [
          'drive',
          '--profile',
          '-d',
          device,
          '--driver=test_driver/desktop_lifecycle_driver.dart',
          '--target=$target',
          if (device == 'macos') '--use-application-binary=$macosApp',
        ],
        environment: {
          'DESKTOP_SMOKE_RESULT': resultPath,
          'DESKTOP_SMOKE_ROOT': root.path,
        },
      );
      final result = Map<String, dynamic>.from(
        jsonDecode(File(resultPath).readAsStringSync()) as Map,
      );
      if (result['phase'] != phase ||
          result['dirty'] != false ||
          result['slides'] != 2 ||
          result['ready_to_close'] != true ||
          result['process_exited'] != true) {
        throw StateError('Incomplete $phase evidence: $result');
      }
      if (device == 'macos' &&
          phase == 'write' &&
          result['cmd_q_guard'] != true) {
        throw StateError('Cmd+Q guard was not tested');
      }
      await waitForDesktopExit(result['pid'] as int);
      if (device == 'macos' && result['clean_exit'] != true) {
        throw StateError('No native clean-exit evidence for $phase');
      }
      result['source_commit'] = source;
      result['working_tree_dirty'] = dirty;
      await File(
        resultPath,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
      results[phase] = result;
    }
    if (results['write']!['pid'] == results['reopen']!['pid']) {
      throw StateError('Reopen must use a new app process');
    }
    completed = true;
    stderr.writeln(
      'PASS: native open/add/save/close/reopen ($device), two app processes.',
    );
  } finally {
    if (completed) {
      root.deleteSync(recursive: true);
    } else {
      stderr.writeln('Failed probe fixture retained: ${root.path}');
    }
  }
}

Future<void> _run(
  String command,
  List<String> args, {
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    command,
    args,
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(command, args, 'Native smoke command failed', code);
  }
}
