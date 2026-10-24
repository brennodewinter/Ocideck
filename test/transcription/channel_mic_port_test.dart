// Het method-channel naar de desktopbinding (#2516), met een script in
// plaats van CoreAudio of WASAPI. `describe` opent niets. Een ontbrekende
// binding is "niet beschikbaar", geen crash. PCM en een einde komen als
// gebeurtenissen binnen; stoppen is één keer.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/channel_mic_port.dart';
import 'package:ocideck/services/transcription/mic_capture_port.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('test/mic_capture');
  const events = EventChannel('test/mic_capture_pcm');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call)? answer;
  MockStreamHandlerEventSink? sink;

  ChannelMicPort port() => ChannelMicPort(methods: methods, events: events);

  setUp(() {
    calls = [];
    answer = null;
    sink = null;
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      final reply = answer;
      if (reply == null) return null;
      return reply(call);
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (Object? _, MockStreamHandlerEventSink events) {
          sink = events;
        },
      ),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
  });

  test('een ontbrekende binding beschrijft en weigert, zonder crash', () async {
    messenger.setMockMethodCallHandler(methods, null);
    final facts = await port().describe();
    expect(facts.availability, CaptureAvailability.unavailable);
    expect(facts.reason, 'geen microfoonbinding in deze build');
    expect(await port().freeBytes('/tmp'), isNull);

    await expectLater(
      port().open(),
      throwsA(
        isA<SourceUnavailable>().having(
          (e) => e.message,
          'message',
          'geen microfoonbinding in deze build',
        ),
      ),
    );
  });

  test('describe leest de lijst en opent het apparaat niet', () async {
    answer = (call) async {
      expect(call.method, 'describe');
      return <String, Object?>{
        'availability': 'tryAfterPermission',
        'reason': 'tcc',
        'inputs': [
          {
            'id': 'built-in',
            'label': 'MacBook',
            'transport': 'builtIn',
            'isDefault': true,
          },
          {'id': '', 'label': 'weg'},
        ],
      };
    };
    final facts = await port().describe();
    expect(facts.availability, CaptureAvailability.tryAfterPermission);
    expect(facts.reason, 'tcc');
    expect(facts.inputs, hasLength(1));
    expect(facts.inputs.single.id, 'built-in');
    expect(facts.inputs.single.isDefault, isTrue);
    expect(calls.map((c) => c.method), ['describe']);
  });

  test('een platformfout bij describe is niet beschikbaar', () async {
    answer = (_) async =>
        throw PlatformException(code: 'ioFailed', message: 'kapot');
    final facts = await port().describe();
    expect(facts.availability, CaptureAvailability.unavailable);
    expect(facts.reason, 'kapot');
    answer = (_) async => throw PlatformException(code: 'ioFailed');
    expect((await port().describe()).reason, 'ioFailed');
    answer = (_) async => throw PlatformException(code: 'ioFailed');
    expect(await port().freeBytes('/tmp/opname'), isNull);
  });

  test('open levert PCM en een einde, stop gaat één keer', () async {
    answer = (call) async {
      if (call.method == 'open') {
        return <String, Object?>{'sampleRate': 48000, 'channels': 2};
      }
      return null;
    };
    final live = await port().open(deviceId: 'usb-1');
    expect(live.format.sampleRate, 48000);
    expect(live.format.channels, 2);
    expect(calls.single.arguments, {'deviceId': 'usb-1'});

    final frames = <MicPcmFrame>[];
    final ended = <CaptureEndCause>[];
    live.frames.listen(frames.add);
    live.ended.listen(ended.add);
    sink!.success(Uint8List.fromList([1, 0, 2, 0]));
    sink!.success(<String, Object?>{'event': 'ended', 'cause': 'sourceLost'});
    sink!.success(<String, Object?>{'event': 'anders'});
    // Het nep-kanaal levert de gebeurtenis als microtaak. Een widgettest
    // pompt die niet; een gewone toets wel.
    await Future<void>.delayed(Duration.zero);

    expect(frames, hasLength(1));
    expect(frames.single.pcm, Uint8List.fromList([1, 0, 2, 0]));
    expect(ended, [CaptureEndCause.sourceLost]);

    await live.stop();
    sink!.success(Uint8List.fromList([9, 9]));
    await Future<void>.delayed(Duration.zero);
    expect(frames, hasLength(1));
    await live.stop();
    expect(calls.where((c) => c.method == 'stop'), hasLength(1));
  });

  test('toestemming intrekken en een streamfout eindigen de invoer', () async {
    answer = (call) async => <String, Object?>{
      'sampleRate': 16000,
      'channels': 1,
    };
    final live = await port().open();
    expect(calls.single.arguments, <String, Object?>{});
    final ended = <CaptureEndCause>[];
    live.ended.listen(ended.add);
    sink!.success(<String, Object?>{
      'event': 'ended',
      'cause': 'permissionRevoked',
    });
    sink!.error(code: 'permissionDenied', message: 'nee');
    sink!.error(code: 'deviceGone');
    await Future<void>.delayed(Duration.zero);
    expect(ended, [
      CaptureEndCause.permissionRevoked,
      CaptureEndCause.permissionRevoked,
      CaptureEndCause.sourceLost,
    ]);
    await live.stop();
  });

  test(
    'een open zonder klok of met een platformfout stopt het kanaal',
    () async {
      var stops = 0;
      answer = (call) async {
        if (call.method == 'stop') stops++;
        if (call.method == 'open') {
          return <String, Object?>{'sampleRate': 0, 'channels': 1};
        }
        return null;
      };
      await expectLater(port().open(), throwsA(isA<SourceUnavailable>()));
      expect(stops, 1);

      answer = (call) async {
        if (call.method == 'stop') stops++;
        throw PlatformException(code: 'permissionDenied', message: 'nee');
      };
      await expectLater(
        port().open(deviceId: 'bt'),
        throwsA(isA<PermissionDenied>()),
      );
      expect(stops, 2);

      answer = (call) async {
        if (call.method == 'stop') stops++;
        throw PlatformException(code: 'unsupported', message: 'float');
      };
      await expectLater(port().open(), throwsA(isA<UnsupportedSource>()));

      answer = (call) async {
        if (call.method == 'stop') stops++;
        throw PlatformException(code: 'ioFailed', message: '');
      };
      await expectLater(port().open(), throwsA(isA<IoFailed>()));

      answer = (call) async {
        if (call.method == 'stop') stops++;
        throw PlatformException(code: 'weird');
      };
      await expectLater(port().open(), throwsA(isA<SourceUnavailable>()));
      expect(stops, 5);
    },
  );

  test('vrije ruimte komt terug als getal', () async {
    answer = (call) async {
      expect(call.method, 'freeBytes');
      expect(call.arguments, {'path': '/tmp/ocideck'});
      return 32 * 1024 * 1024;
    };
    expect(await port().freeBytes('/tmp/ocideck'), 32 * 1024 * 1024);
  });
}
