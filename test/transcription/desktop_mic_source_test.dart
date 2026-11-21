// De desktop-microfoon (#2516) achter een script, zonder apparaat:
// describe opent niets, een weigering laat geen file achter, de
// doorvoer houdt de poort dicht, en een vertrokken bron wordt niet
// opnieuw geopend.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/desktop_mic_source.dart';
import 'package:ocideck/services/transcription/linux_mic_recorder_io.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';
import 'package:ocideck/services/transcription/mic_capture_port.dart';
import 'package:ocideck/services/transcription/mic_session_gate.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/services/transcription/wav_sink_io.dart';
import 'package:path/path.dart' as p;

class _Live implements MicCaptureLive {
  final framesCtrl = StreamController<MicPcmFrame>.broadcast(sync: true);
  final endedCtrl = StreamController<CaptureEndCause>.broadcast();
  var stops = 0;

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
    stops++;
    if (!framesCtrl.isClosed) await framesCtrl.close();
    if (!endedCtrl.isClosed) await endedCtrl.close();
  }
}

class _Port extends MicCapturePort {
  _Port(this.facts);

  MicPlatformFacts facts;
  var describeCalls = 0;
  var openCalls = 0;
  Object? openError;
  final opened = <String?>[];
  final live = _Live();

  @override
  Future<MicPlatformFacts> describe() async {
    describeCalls++;
    return facts;
  }

  @override
  Future<MicCaptureLive> open({String? deviceId}) async {
    openCalls++;
    opened.add(deviceId);
    final error = openError;
    if (error != null) throw error;
    return live;
  }
}

void main() {
  const consent = RecordingConsent(participantNoticeAcknowledged: true);
  const facts = MicPlatformFacts(availability: CaptureAvailability.available);

  late Directory dir;
  late _Port port;
  late MicSessionGate gate;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ocideck_mic_test');
    port = _Port(facts);
    gate = MicSessionGate();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  DesktopMicrophoneSource source({
    int? free,
    int maxBytes = maxRecordingWavBytes,
    int maxQueuedBytes = maxQueuedRecordingBytes,
  }) {
    return DesktopMicrophoneSource(
      port: port,
      gate: gate,
      freeBytes: (_) async => free,
      maxRecordingBytes: maxBytes,
      maxQueuedBytes: maxQueuedBytes,
    );
  }

  CaptureRequest request({String? deviceId}) => CaptureRequest(
    kinds: const {CaptureSourceKind.microphone},
    consent: consent,
    stagingDir: dir.path,
    inputDeviceId: deviceId,
  );

  test('probe beschrijft en opent niet', () async {
    final mic = source();
    expect(await mic.probe(), CaptureAvailability.available);
    expect(port.describeCalls, 1);
    expect(port.openCalls, 0);
  });

  test(
    'geweigerde toestemming geeft de poort terug en laat geen file achter',
    () async {
      port.openError = const PermissionDenied('nee');
      await expectLater(
        source().start(request()),
        throwsA(isA<PermissionDenied>()),
      );
      expect(port.openCalls, 1);
      expect(gate.holder, isNull);
      expect(File(p.join(dir.path, recordingWavName)).existsSync(), isFalse);
    },
  );

  test('doorvoer op de poort opent de microfoon niet', () async {
    expect(gate.tryAcquire(MicHolder.monitor), isTrue);
    await expectLater(
      source().start(request()),
      throwsA(
        isA<SourceUnavailable>().having(
          (e) => e.message,
          'message',
          micHeldByMonitorMessage,
        ),
      ),
    );
    expect(port.openCalls, 0);
    expect(gate.holder, MicHolder.monitor);
  });

  test('te weinig vrije ruimte is CapacityExceeded vóór open', () async {
    await expectLater(
      source(free: 1024).start(request()),
      throwsA(isA<CapacityExceeded>()),
    );
    expect(port.openCalls, 0);
    expect(gate.holder, isNull);
  });

  test('het gekozen apparaat gaat mee, de standaard als null', () async {
    final chosen = await source().start(request(deviceId: 'usb-1'));
    expect(port.opened, ['usb-1']);
    await chosen.stop();

    final again = _Port(facts);
    port = again;
    final standard = await source().start(request());
    expect(again.opened, [null]);
    await standard.stop();
  });

  test(
    'frames worden een afspeelbare WAV en een vertrokken bron heropent niet',
    () async {
      final mic = source();
      final session = await mic.start(request());
      final ended = session.ended!.first;
      final pcm = Uint8List(3200);
      ByteData.sublistView(pcm).setInt16(0, 1600, Endian.little);
      final written = session.liveChunks!.first;
      port.live.framesCtrl.add(MicPcmFrame(pcm));
      expect((await written).bytes, pcm);
      final file = File(session.durablePath);
      expect(await file.length(), 44 + pcm.length);

      port.live.endedCtrl.add(CaptureEndCause.sourceLost);
      expect(await ended, CaptureEndCause.sourceLost);
      expect(port.openCalls, 1);

      final audio = await session.stop();
      expect(port.openCalls, 1);
      expect(port.live.stops, 1);
      expect(gate.holder, isNull);
      final bytes = await File(audio.durablePath).readAsBytes();
      final info = parseWavHeader(bytes, bytes.length);
      expect(info!.sampleRate, 16000);
      expect(info.channels, 1);
      expect(info.bitsPerSample, 16);
      expect(bytes.length, 44 + 3200);
    },
  );

  test('Stop schrijft alle 100 al ontvangen frames in volgorde af', () async {
    final session = await source().start(request());
    final chunks = <AudioChunk>[];
    final sub = session.liveChunks!.listen(chunks.add);
    final accepted = <int>[];
    for (var i = 0; i < 100; i++) {
      final pcm = Uint8List(640)..fillRange(0, 640, i);
      accepted.addAll(pcm);
      port.live.framesCtrl.add(MicPcmFrame(pcm));
    }
    // Geen wachtpunt voor de schrijver: de queue staat vol bij Stop.
    final first = session.stop();
    final second = session.stop();
    expect(identical(first, second), isTrue);
    final audio = await first;
    await second;
    await sub.cancel();
    final bytes = await File(audio.durablePath).readAsBytes();
    expect(bytes.sublist(44), accepted);
    expect(audio.duration, const Duration(seconds: 2));
    expect(parseWavHeader(bytes, bytes.length)!.duration, audio.duration);
    expect(chunks.expand((chunk) => chunk.bytes), accepted);
    expect(chunks.last.offset, const Duration(milliseconds: 1980));
    expect(port.live.stops, 1);
    expect(gate.holder, isNull);
  });

  test('de live-only schrijver verwerkt ook opeenvolgende bursts', () async {
    final session = await source().start(
      CaptureRequest(
        kinds: const {CaptureSourceKind.microphone},
        consent: consent,
        persistFile: false,
      ),
    );
    final chunks = <AudioChunk>[];
    final firstChunk = Completer<void>();
    final sub = session.liveChunks!.listen((chunk) {
      chunks.add(chunk);
      if (!firstChunk.isCompleted) firstChunk.complete();
    });
    port.live.framesCtrl.add(MicPcmFrame(Uint8List(640)));
    await firstChunk.future;
    port.live.framesCtrl.add(MicPcmFrame(Uint8List(640)));
    final result = await session.stop();
    await sub.cancel();
    expect(result.duration, const Duration(milliseconds: 40));
    expect(chunks, hasLength(2));
    expect(gate.holder, isNull);
  });

  test(
    'buffer-overloop meldt capaciteit en bewaart geaccepteerde audio',
    () async {
      final session = await source(maxQueuedBytes: 1280).start(request());
      final causes = <CaptureEndCause>[];
      final sub = session.ended!.listen(causes.add);
      for (var i = 0; i < 5; i++) {
        port.live.framesCtrl.add(MicPcmFrame(Uint8List(640)));
      }
      await expectLater(session.stop(), throwsA(isA<CapacityExceeded>()));
      await sub.cancel();
      expect(causes, [CaptureEndCause.storageFailed]);
      final bytes = await File(session.durablePath).readAsBytes();
      expect(bytes.length, 44 + 1280);
      expect(
        parseWavHeader(bytes, bytes.length)!.duration,
        const Duration(milliseconds: 40),
      );
      expect(port.live.stops, 1);
      expect(gate.holder, isNull);
    },
  );

  test('een volgelopen opname stopt en laat het buurbestand staan', () async {
    final sibling = File(p.join(dir.path, 'older.wav'))
      ..writeAsBytesSync([9, 9, 9]);
    final session = await source(maxBytes: 32).start(request());
    final ended = session.ended!.first;
    final pcm = Uint8List.fromList(List<int>.generate(16, (i) => i));
    final written = session.liveChunks!.first;
    port.live.framesCtrl.add(MicPcmFrame(pcm));
    // Live chunks acknowledge the completed WAV write, including its flush.
    expect((await written).bytes, pcm);
    expect(await File(session.durablePath).length(), 44 + pcm.length);
    port.live.framesCtrl.add(MicPcmFrame(Uint8List(64)));
    expect(await ended, CaptureEndCause.storageFailed);
    expect(await sibling.readAsBytes(), [9, 9, 9]);
    expect(port.openCalls, 1);
    final audio = await session.stop();
    final bytes = await File(audio.durablePath).readAsBytes();
    expect(bytes.sublist(44), pcm);
    expect(parseWavHeader(bytes, bytes.length)!.duration, audio.duration);
    expect(await sibling.readAsBytes(), [9, 9, 9]);
    expect(port.live.stops, 1);
    expect(gate.holder, isNull);
  });

  test(
    'Linux-argv is een lijst, geen shell, en monitors zijn geen microfoon',
    () {
      expect(planLinuxRecording(parecordPath: null), isNull);
      expect(
        planLinuxRecording(parecordPath: '/usr/bin/parecord', deviceId: 'a b'),
        isNull,
      );
      expect(isSafePulseDevice(''), isFalse);
      expect(isSafePulseDevice('-default'), isFalse);
      expect(isSafePulseDevice('alsa_input.usb-mic'), isTrue);

      final plan = planLinuxRecording(
        parecordPath: '/usr/bin/parecord',
        deviceId: 'alsa_input.usb-mic',
      );
      expect(plan!.executable, '/usr/bin/parecord');
      expect(plan.args, contains('--raw'));
      expect(plan.args, contains('--format=s16le'));
      expect(plan.args, contains('--rate=48000'));
      expect(plan.args, contains('--channels=2'));
      expect(plan.args, contains('--device=alsa_input.usb-mic'));
      expect(plan.args.join(' '), isNot(contains('|')));

      final standard = planLinuxRecording(parecordPath: '/usr/bin/parecord');
      expect(standard!.args.where((a) => a.startsWith('--device=')), isEmpty);

      const listing = '''
Source #0
	Name: alsa_output.pci.monitor
	Description: Monitor of Built-in
	device.bus = "pci"
Source #1
	Name: alsa_input.usb-mic
	Description: USB Microphone
	device.bus = "usb"
Source #2
	Name: bluez_input.headset
	Description: Headset
	device.bus = "bluetooth"
''';
      final sources = parsePactlSources(listing);
      expect(sources.map((s) => s.name), [
        'alsa_input.usb-mic',
        'bluez_input.headset',
      ]);
      expect(sources[0].transport, MicTransport.usb);
      expect(sources[1].transport, MicTransport.bluetooth);

      final env = linuxRecorderEnvironment();
      expect(env['LC_ALL'], 'C');
      const allow = {
        'HOME',
        'USER',
        'LOGNAME',
        'XDG_RUNTIME_DIR',
        'XDG_CONFIG_HOME',
        'PULSE_SERVER',
        'PULSE_COOKIE',
        'DBUS_SESSION_BUS_ADDRESS',
        'PIPEWIRE_RUNTIME_DIR',
        'LANG',
        'LC_ALL',
        'PATH',
      };
      expect(env.keys.every(allow.contains), isTrue);
    },
  );

  test('een onveilige apparaatnaam start geen parecord', () async {
    final linux = LinuxMicPort(
      lookup: () async => const LinuxMicTools(
        parecordPath: '/usr/bin/parecord',
        pactlPath: null,
        sourcesText: null,
      ),
    );
    final described = await linux.describe();
    expect(described.availability, CaptureAvailability.tryAfterPermission);
    await expectLater(
      linux.open(deviceId: 'a b'),
      throwsA(isA<UnsupportedSource>()),
    );
  });
}
