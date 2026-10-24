// De webopname achter een nep-browser. Peilen opent niets. Een weigering
// geeft de microfoonpoort terug. Een leeg tabblad en een vol geheugen
// zijn benoemde fouten, geen stille file.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/mic_session_gate.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/services/transcription/web_media_source.dart';
import 'package:ocideck/services/web_asset_store.dart';

class _Browser implements WebMediaBrowser {
  _Browser({this.deny = false, this.empty = false});

  final bool deny;
  final bool empty;
  var probes = 0;
  var opens = 0;

  @override
  Future<CaptureAvailability> probeMicrophone() async {
    probes++;
    return CaptureAvailability.tryAfterPermission;
  }

  @override
  Future<CaptureAvailability> probeDisplay() async {
    probes++;
    return CaptureAvailability.tryAfterPermission;
  }

  @override
  Future<WebMediaLive> openMicrophone() => _open();

  @override
  Future<WebMediaLive> openDisplay() => _open();

  Future<WebMediaLive> _open() async {
    opens++;
    if (deny) throw const PermissionDenied('nee');
    final chunks = StreamController<Uint8List>();
    return WebMediaLive(
      chunks: chunks.stream,
      mime: 'audio/webm;codecs=opus',
      stop: () async {
        if (!empty) chunks.add(Uint8List.fromList([1, 2, 3, 4]));
        if (!chunks.isClosed) await chunks.close();
      },
    );
  }
}

void main() {
  const consent = RecordingConsent(participantNoticeAcknowledged: true);

  tearDown(WebAssetStore.clear);

  test('firefox en safari leveren geen tabgeluid', () {
    expect(
      displayAvailability(
        secure: true,
        hasRecorder: true,
        hasDisplayMedia: true,
        userAgent: 'Mozilla/5.0 Firefox/120',
      ),
      CaptureAvailability.unavailable,
    );
    expect(
      displayAvailability(
        secure: true,
        hasRecorder: true,
        hasDisplayMedia: true,
        userAgent: 'Mozilla/5.0 Safari/17',
      ),
      CaptureAvailability.unavailable,
    );
    expect(
      displayAvailability(
        secure: true,
        hasRecorder: true,
        hasDisplayMedia: true,
        userAgent: 'Mozilla/5.0 Chrome/120 Safari/537',
      ),
      CaptureAvailability.tryAfterPermission,
    );
    expect(
      microphoneAvailability(
        secure: false,
        hasRecorder: true,
        hasUserMedia: true,
      ),
      CaptureAvailability.unavailable,
    );
  });

  test('peilen opent de microfoon niet', () async {
    final browser = _Browser();
    final gate = MicSessionGate();
    final source = WebMediaSource.microphone(browser: browser, gate: gate);
    expect(await source.probe(), CaptureAvailability.tryAfterPermission);
    expect(browser.opens, 0);
    expect(gate.holder, isNull);
  });

  test(
    'een weigering geeft de poort terug en laat geen bestand achter',
    () async {
      final browser = _Browser(deny: true);
      final gate = MicSessionGate();
      final source = WebMediaSource.microphone(browser: browser, gate: gate);
      await expectLater(
        source.start(
          const CaptureRequest(
            kinds: {CaptureSourceKind.microphone},
            consent: consent,
          ),
        ),
        throwsA(isA<PermissionDenied>()),
      );
      expect(gate.holder, isNull);
      expect(WebAssetStore.isEmpty, isTrue);
    },
  );

  test('een opname belandt in het browsergeheugen', () async {
    final browser = _Browser();
    final source = WebMediaSource.microphone(browser: browser);
    final session = await source.start(
      const CaptureRequest(
        kinds: {CaptureSourceKind.microphone},
        consent: consent,
      ),
    );
    final audio = await session.stop();
    expect(audio.durablePath, startsWith('mem:'));
    expect(WebAssetStore.bytesFor(audio.durablePath), [1, 2, 3, 4]);
  });

  test('een tab zonder geluid is een benoemde fout', () async {
    final browser = _Browser(empty: true);
    final source = WebMediaSource.display(browser: browser);
    final session = await source.start(
      const CaptureRequest(
        kinds: {CaptureSourceKind.systemAudio},
        consent: consent,
      ),
    );
    await expectLater(
      session.stop(),
      throwsA(
        isA<SourceUnavailable>().having(
          (error) => error.message,
          'message',
          webDisplaySilentMessage,
        ),
      ),
    );
  });

  test('een vol browsergeheugen stopt zonder bestand', () async {
    WebAssetStore.overrideTotalBudgetForTest(2);
    addTearDown(() => WebAssetStore.overrideTotalBudgetForTest(null));
    final browser = _Browser();
    final source = WebMediaSource.microphone(browser: browser);
    final session = await source.start(
      const CaptureRequest(
        kinds: {CaptureSourceKind.microphone},
        consent: consent,
      ),
    );
    await expectLater(session.stop(), throwsA(isA<CapacityExceeded>()));
  });
}
