import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Het fetch-hulppunt (`server/fetch-proxy/`) is Python en valt buiten elke
/// Dart-toets. Zijn zelftoets draait daarom hier, zodat hij in `make check`
/// meeloopt in plaats van alleen als je eraan denkt.
void main() {
  test('de zelftoets van het fetch-hulppunt slaagt', () {
    final result = Process.runSync('python3', [
      '-I',
      '-B',
      'server/fetch-proxy/test_ocideck_fetch_proxy.py',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
