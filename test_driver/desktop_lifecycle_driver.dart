import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';
import 'package:path/path.dart' as p;

import 'desktop_smoke_process.dart';
import 'desktop_recovery_plan.dart';
import 'desktop_roundtrip_plan.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 5),
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final path = Platform.environment['DESKTOP_SMOKE_RESULT'];
    final root = Platform.environment['DESKTOP_SMOKE_ROOT'];
    if (path == null || root == null) {
      throw StateError('Desktop smoke environment missing');
    }
    try {
      // integrationDriver has collected assertions and closed its VM connection.
      // Ask the app to finish its production shutdown path before starting again.
      if (data?['ready_to_close'] == true) {
        final phase = data!['phase'] as String;
        if (!{
          'write',
          'reopen',
          ...nativeRoundtripPhases,
          ...nativeRecoveryPhases,
        }.contains(phase)) {
          throw StateError('Invalid phase');
        }
        final pid = data['pid'] as int;
        if (isForcedExitPhase(phase)) {
          if (pid <= 0 || !Process.killPid(pid, ProcessSignal.sigkill)) {
            throw StateError('Could not forcibly terminate the fixture app');
          }
          await waitForDesktopExit(pid);
          data['force_killed'] = true;
          data['process_exited'] = true;
          return;
        }
        await File(p.join(root, 'close-$phase.request')).writeAsString('close');
        try {
          await waitForDesktopExit(pid);
        } on StateError {
          if (Platform.isLinux) {
            for (final name in ['stat', 'status', 'wchan']) {
              final kernel = File('/proc/${data['pid']}/$name');
              if (kernel.existsSync()) {
                data['linux_$name'] = kernel.readAsStringSync();
              }
            }
          }
          rethrow;
        }
        data['process_exited'] = true;
        if (Platform.isMacOS) {
          final marker = File(p.join(root, 'clean-exit-$phase.txt'));
          data['clean_exit'] =
              marker.existsSync() &&
              marker.readAsStringSync() == 'clean-exit\n';
          if (data['clean_exit'] != true) {
            throw StateError(
              'App exited without its native atexit marker (crash or forced shutdown)',
            );
          }
        }
      }
    } finally {
      await File(
        path,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    }
  },
);
