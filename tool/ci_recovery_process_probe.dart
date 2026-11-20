import 'dart:convert';
import 'dart:io';

import '../lib/services/recovery_process_io.dart';

void main() {
  final first = recoveryProcessIsAlive(0x7fffffff);
  final second = recoveryProcessIsAlive(0x7fffffff);
  final alive = recoveryProcessIsAlive(pid);
  stdout.writeln(
    jsonEncode({
      'platform': Platform.operatingSystem,
      'sdk': Platform.version,
      'dead_first': first,
      'dead_second': second,
      'own_pid_alive': alive,
    }),
  );
  if (first != false || second != false || alive != true) {
    throw StateError('Cold native process query returned incorrect liveness');
  }
}
