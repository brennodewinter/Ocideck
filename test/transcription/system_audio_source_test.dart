// Systeemgeluid en de combinatie, zonder een apparaat. Linux houdt alleen
// `.monitor`-bronnen. De combinatie schrijft stereo: links de microfoon,
// rechts het systeemgeluid. De microfoonpoort blijft van het kind.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/combination_source.dart';
import 'package:ocideck/services/transcription/desktop_mic_source.dart';
import 'package:ocideck/services/transcription/linux_mic_recorder.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';
import 'package:ocideck/services/transcription/mic_capture_port.dart';
import 'package:ocideck/services/transcription/mic_session_gate.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:path/path.dart' as p;

class _Live implements MicCaptureLive {
  final framesCtrl = StreamController<MicPcmFrame>.broadcast();
  final endedCtrl = StreamController<CaptureEndCause>.broadcast();

  @override
  MicStreamFormat format = const MicStreamFormat(
    sampleRate: 16000,
    channels: 1,
  );

  @override
  Stream<MicPcmFrame> get frames => framesCtrl.stream;

  @override
  Stream<CaptureEndCause> get ended => endedCtrl.stream;

  @override
  Future<void> stop() async {
    if (!framesCtrl.isClosed) await framesCtrl.close();
    if (!endedCtrl.isClosed) await endedCtrl.close();
  }
}

class _Port extends MicCapturePort {
  _Port(this.live);

  final _Live live;
  var openCalls = 0;

  @override
  Future<MicPlatformFacts> describe() async =>
      const MicPlatformFacts(availability: CaptureAvailability.available);

  @override
  Future<MicCaptureLive> open({String? deviceId}) async {
    openCalls++;
    return live;
  }
}

Uint8List s16(List<int> samples) {
  final bytes = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes;
}

void main() {
  const listing = '''
Source #0
	Name: alsa_output.pci.monitor
	Description: Monitor of Built-in
	device.bus = "pci"
Source #1
	Name: alsa_input.usb-mic
	Description: USB Microphone
	device.bus = "usb"
''';

  test('een monitorlijst laat de microfoon weg', () async {
    final port = LinuxMonitorPort(
      lookup: () async => const LinuxMicTools(
        parecordPath: null,
        pactlPath: '/usr/bin/pactl',
        sourcesText: listing,
      ),
    );
    final facts = await port.describe();
    expect(facts.availability, CaptureAvailability.unavailable);

    final listed = LinuxMonitorPort(
      lookup: () async => const LinuxMicTools(
        parecordPath: '/usr/bin/parecord',
        pactlPath: '/usr/bin/pactl',
        sourcesText: listing,
      ),
    );
    final ready = await listed.describe();
    expect(ready.inputs.map((input) => input.id), ['alsa_output.pci.monitor']);
    await expectLater(
      listed.open(deviceId: 'alsa_input.usb-mic'),
      throwsA(isA<SourceUnavailable>()),
    );
  });

  test('systeemgeluid neemt de microfoonpoort niet in', () async {
    final gate = MicSessionGate();
    final live = _Live();
    final port = _Port(live);
    final source = DesktopMicrophoneSource.system(
      port: port,
      freeBytes: (_) async => null,
    );
    expect(await source.probe(), CaptureAvailability.available);
    expect(port.openCalls, 0);
    expect(gate.holder, isNull);

    final dir = Directory.systemTemp.createTempSync('ocideck_sys');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final session = await source.start(
      CaptureRequest(
        kinds: const {CaptureSourceKind.systemAudio},
        consent: const RecordingConsent(participantNoticeAcknowledged: true),
        stagingDir: dir.path,
      ),
    );
    expect(gate.holder, isNull);
    final heard = <AudioChunk>[];
    final sub = session.liveChunks!.listen(heard.add);
    live.framesCtrl.add(MicPcmFrame(s16([7, 8])));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final audio = await session.stop();
    await sub.cancel();
    expect(heard, isNotEmpty);
    final file = File(audio.durablePath);
    final head = await file
        .openRead(0, 44)
        .fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    final info = parseWavHeader(Uint8List.fromList(head), await file.length());
    expect(info!.channels, 1);
    expect(audio.kinds, {CaptureSourceKind.systemAudio});
  });

  test('de combinatie houdt de kanalen uit elkaar', () async {
    final gate = MicSessionGate();
    final micLive = _Live();
    final sysLive = _Live();
    final mic = DesktopMicrophoneSource(
      port: _Port(micLive),
      gate: gate,
      freeBytes: (_) async => null,
    );
    final system = DesktopMicrophoneSource.system(
      port: _Port(sysLive),
      freeBytes: (_) async => null,
    );
    final combo = CombinationSource(microphone: mic, systemAudio: system);
    expect(await combo.probe(), CaptureAvailability.available);
    expect(gate.holder, isNull);

    final dir = Directory.systemTemp.createTempSync('ocideck_combo');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final session = await combo.start(
      CaptureRequest(
        kinds: const {
          CaptureSourceKind.microphone,
          CaptureSourceKind.systemAudio,
        },
        consent: const RecordingConsent(participantNoticeAcknowledged: true),
        stagingDir: dir.path,
      ),
    );
    expect(gate.holder, MicHolder.recording);
    micLive.framesCtrl.add(MicPcmFrame(s16([1, 2])));
    sysLive.framesCtrl.add(MicPcmFrame(s16([3, 4])));
    final file = File(p.join(dir.path, 'recording.wav'));
    for (
      var i = 0;
      i < 50 && (!file.existsSync() || file.lengthSync() <= 44);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final audio = await session.stop();
    expect(gate.holder, isNull);
    expect(audio.kinds, {
      CaptureSourceKind.microphone,
      CaptureSourceKind.systemAudio,
    });
    final bytes = await File(audio.durablePath).readAsBytes();
    final info = parseWavHeader(bytes.sublist(0, 44), bytes.length);
    expect(info!.channels, 2);
    final pcm = ByteData.sublistView(bytes, 44);
    expect(pcm.getInt16(0, Endian.little), 1);
    expect(pcm.getInt16(2, Endian.little), 3);
    expect(pcm.getInt16(4, Endian.little), 2);
    expect(pcm.getInt16(6, Endian.little), 4);
  });
}
