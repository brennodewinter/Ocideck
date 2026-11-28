// Independent flutter-drive launches sharing only an isolated disk fixture.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../test_driver/desktop_smoke_process.dart';
import '../test_driver/desktop_recovery_plan.dart';
import '../test_driver/desktop_roundtrip_plan.dart';

Future<void> main(List<String> args) async {
  final roundtrip = args.contains('--roundtrip');
  final recovery = args.contains('--recovery');
  if (roundtrip && recovery) throw ArgumentError('Choose one desktop scenario');
  final positional = args
      .where((arg) => arg != '--roundtrip' && arg != '--recovery')
      .toList();
  final device = positional.isEmpty
      ? Platform.operatingSystem
      : positional.single;
  if (!{'macos', 'linux', 'windows'}.contains(device) ||
      device != Platform.operatingSystem) {
    throw ArgumentError('Run on the matching macos, linux or windows host');
  }
  final root = Directory.systemTemp.createTempSync('ocideck-desktop-smoke-');
  final evidence = Directory(
    p.join(
      'build',
      recovery
          ? 'desktop-recovery'
          : roundtrip
          ? 'desktop-roundtrip'
          : 'desktop-smoke',
    ),
  )..createSync(recursive: true);
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
    if (roundtrip) prepareRoundtripAssets(root.path);
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
    // that app for every phase. The isolated runtime path is not a compile-time define.
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
    final phases = recovery
        ? nativeRecoveryPhases
        : roundtrip
        ? nativeRoundtripPhases
        : ['write', 'reopen'];
    for (final phase in phases) {
      if (roundtrip) prepareRoundtripPhase(root.path, phase);
      File(p.join(root.path, 'phase.txt')).writeAsStringSync(phase);
      final resultPath = p.absolute(evidence.path, '$phase.json');
      final stallResult = File(p.join(evidence.path, '$phase-stalls.json'));
      for (final old in [File(resultPath), stallResult]) {
        if (old.existsSync()) old.deleteSync();
      }
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
          'DESKTOP_SMOKE_SCENARIO': roundtrip ? 'roundtrip' : 'basic',
        },
      );
      final result = Map<String, dynamic>.from(
        jsonDecode(File(resultPath).readAsStringSync()) as Map,
      );
      if (recovery) {
        _validateRecovery(result, phase, root);
      } else if (result['phase'] != phase ||
          result['dirty'] != false ||
          (roundtrip
              ? (result['slides'] as int) <= 0
              : result['slides'] != 2) ||
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
      if (device == 'macos' &&
          !isForcedExitPhase(phase) &&
          result['clean_exit'] != true) {
        throw StateError('No native clean-exit evidence for $phase');
      }
      result['source_commit'] = source;
      result['working_tree_dirty'] = dirty;
      await File(
        resultPath,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
      final support = recovery
          ? recoveryAppSupport(root.path, phase)
          : root.path;
      final name = recovery ? 'journey-recovery' : 'journey-$phase';
      final appLog = Directory(p.join(support, 'logs'));
      final currentLog = File(p.join(appLog.path, '$name.log'));
      final rotatedLog = File(p.join(appLog.path, '$name.1.log'));
      final stalls = [
        if (rotatedLog.existsSync())
          ...desktopStallLines(rotatedLog.readAsLinesSync()),
        ...desktopStallLines(currentLog.readAsLinesSync()),
      ];
      stallResult.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(stalls),
      );
      if (stalls.isNotEmpty) {
        throw StateError(
          'UI isolate stalled during $phase:\n${stalls.join('\n')}',
        );
      }
      results[phase] = result;
    }
    if (results.values.map((result) => result['pid']).toSet().length !=
        results.length) {
      throw StateError('Reopen must use a new app process');
    }
    if (roundtrip) {
      final authored =
          jsonDecode(
                File(p.join(root.path, 'expected.json')).readAsStringSync(),
              )
              as List;
      for (final entry in results.entries) {
        if (entry.value['slides'] != authored.length ||
            (entry.key != 'write' &&
                entry.value['fields_compared'] !=
                    authored.fold<int>(
                      0,
                      (n, row) => n + (row as Map).length,
                    ))) {
          throw StateError('Incomplete field-by-field evidence: ${entry.key}');
        }
      }
    }
    completed = true;
    final label = recovery
        ? 'forced exit and recovery'
        : roundtrip
        ? 'file roundtrip'
        : 'open/add/save/close/reopen';
    stderr.writeln(
      'PASS: native $label ($device), ${results.length} app processes.',
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

void _validateRecovery(
  Map<String, dynamic> result,
  String phase,
  Directory root,
) {
  final forced = isForcedExitPhase(phase);
  final support = recoveryAppSupport(root.path, phase);
  final marker = File(p.join(support, 'logs', 'journey-recovery.sessie'));
  if (result['phase'] != phase ||
      result['ready_to_close'] != true ||
      result['process_exited'] != true ||
      marker.existsSync() != forced) {
    throw StateError('Incomplete $phase evidence: $result');
  }
  if (forced) {
    final snapshots = Directory(p.join(support, 'recovery'));
    final snapshotExists =
        snapshots.existsSync() &&
        snapshots.listSync().any(
          (entry) => entry is File && entry.path.endsWith('.json'),
        );
    if (result['force_killed'] != true ||
        result['snapshot_written'] != snapshotExists ||
        snapshotExists != (phase == 'document-crash')) {
      throw StateError('Incomplete forced-exit evidence for $phase: $result');
    }
  } else if (result['unclean_exit_detected'] != true ||
      result['offered_recovery'] != (phase == 'document-restore') ||
      (phase == 'document-restore' && result['recovered_text'] != true)) {
    throw StateError('Incomplete restart evidence for $phase: $result');
  }
}
