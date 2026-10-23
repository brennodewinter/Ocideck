// Stubhelft van de platformprobe (#2514): geen dart:io, geen browser —
// alleen de eerlijke melding dat er niets passiefs te zeggen valt.
import 'environment_probe.dart';

Future<TranscriptionEnvironment> probeTranscriptionEnvironment() async =>
    const TranscriptionEnvironment(platformLabel: 'dit platform');
