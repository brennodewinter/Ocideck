// Desktophelft van de platformprobe (#2514): wat `dart:io` passief weet.
import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'environment_probe.dart';

Future<TranscriptionEnvironment> probeTranscriptionEnvironment() async {
  final abi = Abi.current().toString();
  return TranscriptionEnvironment(
    platformLabel: switch (Platform.operatingSystem) {
      'macos' => 'macOS',
      'windows' => 'Windows',
      'linux' => 'Linux',
      final other => other,
    },
    // 'macos_arm64' → 'arm64' — het tweede deel is de processor.
    architecture: abi.contains('_') ? abi.split('_').last : abi,
  );
}
