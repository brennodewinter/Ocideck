import 'dart:io';

// Observe the actual process exit before a second app is started.
Future<void> waitForDesktopExit(int pid) async {
  if (pid <= 0) throw StateError('Invalid app PID: $pid');
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    final check = Platform.isWindows
        ? await Process.run('tasklist', [
            '/FI',
            'PID eq $pid',
            '/FO',
            'CSV',
            '/NH',
          ])
        : await Process.run('/bin/kill', ['-0', '$pid']);
    if (Platform.isWindows && check.exitCode != 0) {
      throw StateError('Cannot verify app process exit: ${check.stderr}');
    }
    final alive = Platform.isWindows
        ? check.stdout.toString().contains('"$pid"')
        : check.exitCode == 0;
    if (!alive) return;
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('App process $pid did not finish native shutdown');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
