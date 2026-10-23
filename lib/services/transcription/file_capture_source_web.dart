// Webhelft van de bestandsbron (#2515): het gekozen bestand leeft al als
// bytes in de `mem:`-assetstore (de bestandskiezer leverde bytes, geen
// pad), PCM-WAV gaat direct naar de engine, en elke andere container
// wordt gedecodeerd door `decodeAudioData` — dezelfde browserroute die
// de web-engine zelf gebruikt, via `web/whisper/bridge.js`.
//
// Twee eerlijke grenzen die dit platform stelt:
//  * `decodeAudioData` is één browsercall — niet af te breken halverwege;
//    `cancel()` landt dus ná de decode, vóór de engine draait;
//  * bron én gedecodeerde WAV delen het 256 MiB-`mem:`-budget — de
//    budgetfout van de store wordt de getypte [CapacityExceeded].
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import '../web_asset_store.dart';
import '../../utils/log.dart';
import 'capture_source.dart';
import 'file_capture_source.dart';
import 'media_sniff.dart';
import 'transcription_errors.dart';

@JS('ocideckWhisper')
external _JsWhisperBridge? get _bridge;

extension type _JsWhisperBridge(JSObject _) implements JSObject {
  external JSPromise<JSFloat32Array> decodeAudio(JSUint8Array bytes);
}

class WebFileCaptureSource extends FileCaptureSource {
  const WebFileCaptureSource();

  @override
  CaptureSourceKind get kind => CaptureSourceKind.file;

  @override
  Future<CaptureAvailability> probe() async {
    // Geen bridge = geen decode; WAV-only is dan de stand — de bron zelf
    // bestaat wél, de dekking volgt per bestand uit `describe`.
    return CaptureAvailability.available;
  }

  @override
  Future<FileSourceInfo> describe(String sourcePath) async {
    final bytes = WebAssetStore.bytesFor(sourcePath);
    if (bytes == null) {
      throw const SourceUnavailable(
        'de gekozen bytes zijn niet meer in de tab aanwezig',
      );
    }
    if (bytes.isEmpty) {
      throw const DecodeFailed('het bestand is leeg');
    }
    final head = headOf(bytes);
    final container = sniffContainer(
      head,
      extension: WebAssetStore.nameFor(sourcePath)?.split('.').last,
    );
    if (container == MediaContainer.wav) {
      final info = parseWavHeader(head, bytes.length);
      if (info == null) {
        throw const DecodeFailed('WAV-header is beschadigd of onleesbaar');
      }
      return FileSourceInfo(
        path: sourcePath,
        sizeBytes: bytes.length,
        container: container,
        duration: info.duration,
        engineReadsDirectly: true,
        decodable: true,
      );
    }
    return FileSourceInfo(
      path: sourcePath,
      sizeBytes: bytes.length,
      container: container,
      engineReadsDirectly: false,
      decodable: _bridge != null,
      // Welke codec de browser dekt is per browser anders (§5.1 noot 6) —
      // de decode zelf is de uitspraak, dit is de eerlijke aankondiging.
      decodeNote: _bridge == null
          ? 'whisper/bridge.js ontbreekt in deze bundle — geen decode'
          : 'codecdekking hangt van deze browser af',
    );
  }

  /// De leesbare kop voor de sniffer, nooit groter dan [sniffHeadBytes].
  static Uint8List headOf(Uint8List bytes) =>
      bytes.length <= sniffHeadBytes ? bytes : bytes.sublist(0, sniffHeadBytes);

  @override
  Future<FileCaptureSession> start(CaptureRequest request) async {
    if (request.kinds.length != 1 ||
        request.kinds.single != CaptureSourceKind.file) {
      throw const UnsupportedSource(
        'de bestandsbron kent alleen {file} als invoer',
      );
    }
    final sourcePath = request.sourcePath;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw const IoFailed('geen bronbestand meegegeven');
    }
    final info = await describe(sourcePath);
    if (!info.engineReadsDirectly && !info.decodable) {
      throw UnsupportedSource(info.decodeNote ?? 'geen decode mogelijk');
    }
    return WebFileCaptureSession._(info);
  }
}

class WebFileCaptureSession extends FileCaptureSession {
  WebFileCaptureSession._(this._info) : durablePath = _info.path;

  final FileSourceInfo _info;

  Future<RecordedAudio>? _stopping;
  var _cancelled = false;

  /// De `mem:`-sleutel waar het duurzame resultaat (gaat) staan: bij WAV
  /// de sleutel van de bron zelf, anders de sleutel die de decode bij
  /// `stop()` aanmaakt.
  @override
  late String durablePath;

  @override
  Stream<AudioChunk>? get liveChunks => null;

  @override
  Stream<CaptureEndCause>? get ended => null;

  /// `decodeAudioData` is niet af te breken; de vlag laat [stop] ná de
  /// decode alsnog in [Cancelled] eindigen, vóór de engine draait.
  @override
  void cancel() => _cancelled = true;

  @override
  Future<RecordedAudio> stop() => _stopping ??= _run();

  Future<RecordedAudio> _run() async {
    if (_cancelled) throw const Cancelled('de taak is afgebroken');
    if (_info.engineReadsDirectly) {
      return RecordedAudio(
        durablePath: durablePath,
        duration: _info.duration ?? Duration.zero,
        kinds: const {CaptureSourceKind.file},
      );
    }
    final bridge = _bridge;
    if (bridge == null) {
      throw const UnsupportedSource('geen decodebrug in deze bundle');
    }
    final bytes = WebAssetStore.bytesFor(_info.path);
    if (bytes == null) {
      throw const SourceUnavailable(
        'de bronbytes zijn niet meer in de tab aanwezig',
      );
    }
    final Float32List pcm;
    try {
      final view = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      pcm = (await bridge.decodeAudio(view.toJS).toDart).toDart;
    } on Object catch (e, s) {
      logError('WebFileCaptureSession: audiodecode', e, s);
      throw DecodeFailed(
        mayBeVideo(_info.container)
            ? 'geen decodeerbare audiotrack in deze container'
            : 'de browser kon het bestand niet decoderen',
      );
    }
    if (_cancelled) throw const Cancelled('de decode is afgebroken');
    if (pcm.isEmpty) {
      throw const DecodeFailed('de decode leverde lege audio op');
    }
    final wav = encodePcmWav(pcm);
    if (wav.length > maxDecodedWavBytes) {
      throw const CapacityExceeded(
        'de gedecodeerde audio overschrijdt de duurgrens',
      );
    }
    final String key;
    try {
      key = WebAssetStore.put(
        wav,
        name: '${WebAssetStore.nameFor(_info.path) ?? 'audio'}.wav',
      );
    } on WebAssetBudgetExceeded {
      throw const CapacityExceeded(
        'de gedecodeerde audio past niet in het geheugenbudget',
      );
    }
    durablePath = key;
    return RecordedAudio(
      durablePath: key,
      duration: Duration(microseconds: (pcm.length / 16000 * 1e6).round()),
      kinds: const {CaptureSourceKind.file},
    );
  }
}

FileCaptureSource createFileCaptureSource() => const WebFileCaptureSource();
