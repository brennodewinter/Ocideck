import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/recovery_process_io.dart';

void main() {
  final supported = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  test('a cold first query distinguishes dead and live processes', () {
    // This must be the first query in this test isolate: a warm error reader
    // can hide first-use FFI initialization that overwrites Windows errors.
    expect(recoveryProcessIsAlive(0x7fffffff), isFalse);
    expect(recoveryProcessIsAlive(0x7fffffff), isFalse);
    expect(recoveryProcessIsAlive(pid), isTrue);
    for (final invalid in [0, -1, 0x80000000]) {
      expect(recoveryProcessIsAlive(invalid), isNull);
    }
  }, skip: !supported);
}
