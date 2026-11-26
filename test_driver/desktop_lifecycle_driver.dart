import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';
import 'package:path/path.dart' as p;

import 'desktop_smoke_process.dart';
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
        if (!{'write', 'reopen', ...nativeRoundtripPhases}.contains(phase)) {
          throw StateError('Invalid phase');
        }
        await File(p.join(root, 'close-$phase.request')).writeAsString('close');
        await waitForDesktopExit(data['pid'] as int);
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
