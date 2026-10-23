// De ASR-serverengine (docs/design/TRANSCRIPTION.md §4.3, #2524): een
// `batchServer`-engine die een voltooide opname of gekozen bestand naar
// een door de gebruiker geconfigureerd endpoint stuurt.
//
// Drie harde regels, hier afgedwongen:
//  * niets vertrekt zonder de egresspoort (`AsrServerGate`) én een
//    per-taak [ServerConsent] die host én audio exact benoemt — geen
//    consent, verkeerde host of ander bestand is [ConsentRequired];
//  * geen stille fallback: een lokale route valt nooit op dit ding terug,
//    en deze engine doet zelf ook geen retry — een nieuwe poging is een
//    nieuwe gebruikerskeuze, niet een achtergronddoorgang (idempotentie:
//    whisper-server heeft geen idempotency-sleutel, dus is "niet stil
//    opnieuw sturen" de enige eerlijke regel);
//  * het antwoord is onbetrouwbare invoer: begrensd, defensief geparsed,
//    en de API-sleutel komt nooit in URL, fout of provenance terecht.
//
// De engine is zuiver Dart: het transport en de audiolezer worden
// geïnjecteerd (de fabriek `asr_engine_factory.dart` levert de
// platformhelften), zodat elke regel hier op de VM te toetsen is.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../models/asr_server_profile.dart';
import 'asr_server_gate.dart';
import 'asr_transport.dart';
import 'capture_source.dart' show AudioChunk;
import 'transcription_engine.dart';
import 'transcription_errors.dart';

/// Wat een verbindingstest zonder audio terugmeldt. Geen claims over
/// transcriptiecapaciteit — die is pas zeker na een echte upload.
class AsrServerProbe {
  const AsrServerProbe({required this.status, required this.detail});

  final AsrProbeStatus status;

  /// Diagnosecode voor de UI (geen host, geen sleutel, geen proza): een
  /// stabiele identifier die de instellingskaart (#2514) via `l10n.d`
  /// naar een benoemde herstelstap vertaalt.
  final String detail;
}

enum AsrProbeStatus {
  /// Endpoint bereikbaar en antwoordde als HTTP-server.
  reachable,

  /// Bereikbaar maar eiste authenticatie (401/403) — er is een sleutel
  /// nodig, of de ingevulde klopt niet.
  authRequired,

  /// De server weigerde of was onbereikbaar (netwerk/TLS/CORS/timeout).
  unreachable,

  /// De poort weigerde al vóór het netwerk — de melding draagt de reden.
  refused,
}

typedef AsrAudioReader = Future<Uint8List> Function(String path);

/// De batch-engine voor een serverprofiel. [cancel] breekt een lopende
/// [transcribe] af — de interface kent geen annuleringstoken, dus hangt
/// Stop aan de concrete klasse (zelfde vorm als `LocalWhisperEngine`).
class AsrServerEngine implements TranscriptionEngine {
  AsrServerEngine({
    required this.profile,
    required this.transport,
    required this.audioReader,
    Future<String?> Function()? apiKeyReader,
    bool? isWeb,
  }) : _apiKeyReader = apiKeyReader ?? (() async => null),
       _isWeb = isWeb ?? kIsWeb;

  /// Het injecteerbare transport — de enige plek die het netwerk op gaat.
  final AsrTransport transport;

  final AsrServerProfile profile;

  /// Leest de API-sleutel van dit profiel — per verzoek, zodat een
  /// vervangen sleutel meteen geldt en de sleutel nooit in een veld of
  /// stack blijft hangen. Komt alleen in de `Authorization`-header terecht.
  final Future<String?> Function() _apiKeyReader;

  /// Leest de bytes achter een `AudioRef` — mem:-sleutel of bestandspad,
  /// geïnjecteerd zodat de engine zelf platformvrij blijft.
  final AsrAudioReader audioReader;
  final bool _isWeb;

  AsrSendHandle? _current;

  /// Bovengrens voor de upload. `whisper-server` kent zelf geen grens, maar
  /// een onbegrensde upload is ook hier een onbegrensde belofte — een
  /// opname van ~2 uur (16 kHz mono WAV ≈ 3,5 MB/min) past ruim.
  static const maxUploadBytes = 400 * 1024 * 1024;

  @override
  EngineKind get kind => EngineKind.batchServer;

  @override
  Future<EngineCapabilities> capabilities() async {
    return const EngineCapabilities(
      // verbose_json levert segment-tijdstempels; sprekerlabels alleen als
      // de server diariseert, en dat claimen we niet (§2.4).
      timestamps: true,
    );
  }

  /// De poortuitslag voor dit profiel — zodat de UI kan uitleggen waarom
  /// een taak niet kan vóór hij gestart wordt. Geen netwerk, geen audio.
  AsrGateDecision gate() => AsrServerGate.evaluate(profile, isWeb: _isWeb);

  /// Verbindingstest zónder audio: één GET op de basis-URL. Bewijst
  /// bereikbaarheid, TLS en (op web) CORS — niet meer.
  Future<AsrServerProbe> probe() async {
    final decision = gate();
    if (decision is! AsrGateAllow) {
      // Alleen de gecodeerde reden — geen URL of host in de melding.
      final reason = decision is AsrGateDeny ? decision.reason.name : '?';
      return AsrServerProbe(status: AsrProbeStatus.refused, detail: reason);
    }
    final allow = decision;
    try {
      final result = await transport
          .send(
            method: 'GET',
            url: allow.uri,
            strategy: allow.strategy,
            body: null,
            headers: await _headers(),
            timeout: const Duration(seconds: 20),
          )
          .done;
      if (result.statusCode == 401 || result.statusCode == 403) {
        return const AsrServerProbe(
          status: AsrProbeStatus.authRequired,
          detail: 'auth',
        );
      }
      return AsrServerProbe(
        status: AsrProbeStatus.reachable,
        detail: 'http:${result.statusCode}',
      );
    } on AsrRequestException catch (e) {
      return AsrServerProbe(
        status: AsrProbeStatus.unreachable,
        detail: e.message,
      );
    }
  }

  @override
  Future<TranscriptResult> transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  ) async {
    final allow = _allowOrThrow();

    // Per-taaktoestemming: host én deze specifieke audio moeten in de
    // bevestiging zijn benoemd (§4.3). Strikte vergelijking — een consent
    // voor een ander bestand dekt deze taak niet.
    final consent = options.serverConsent;
    if (consent == null ||
        consent.host != profile.host ||
        consent.audioPath != audio.path) {
      throw const ConsentRequired('serverupload niet bevestigd voor deze taak');
    }

    final bytes = await audioReader(audio.path);
    if (bytes.length > maxUploadBytes) {
      throw const CapacityExceeded('audio groter dan de uploadgrens');
    }

    final handle = transport.send(
      method: 'POST',
      url: _endpoint(allow.uri, 'inference'),
      strategy: allow.strategy,
      headers: {
        'content-type': 'multipart/form-data; boundary=$_boundary',
        ...await _headers(),
      },
      body: buildMultipartBody(
        fields: {
          'response_format': 'verbose_json',
          if (options.language != null) 'language': options.language!,
        },
        fileField: 'file',
        fileName: _audioFileName(audio.path),
        fileContentType: 'audio/wav',
        fileBytes: bytes,
      ),
    );
    _current = handle;
    try {
      final response = await handle.done;
      if (!response.isOk) {
        throw ServerRefused('HTTP ${response.statusCode}');
      }
      return parseWhisperServerResponse(response.body);
    } on AsrRequestException catch (e) {
      if (e.message == 'afgebroken') {
        throw const Cancelled('upload afgebroken');
      }
      throw ServerRefused(e.message);
    } finally {
      _current = null;
    }
  }

  @override
  Stream<PartialTranscript>? transcribeLive(Stream<AudioChunk> chunks) => null;

  /// Breekt een lopende upload af; `transcribe` voltooit met [Cancelled].
  @override
  void cancel() => _current?.cancel();

  AsrGateAllow _allowOrThrow() {
    final decision = gate();
    if (decision is AsrGateDeny) {
      throw switch (decision.reason) {
        AsrGateDenial.disabled ||
        AsrGateDenial.modeNone ||
        AsrGateDenial.notConfigured => const EngineUnavailable(
          'serverprofiel niet bruikbaar',
        ),
        AsrGateDenial.cloudNotConfirmed => const ConsentRequired(
          'externe server niet bevestigd',
        ),
        _ => ServerRefused('egress geweigerd: ${decision.reason.name}'),
      };
    }
    return decision as AsrGateAllow;
  }

  Future<Map<String, String>> _headers() async {
    final key = (await _apiKeyReader())?.trim() ?? '';
    return {if (key.isNotEmpty) 'authorization': 'Bearer $key'};
  }

  /// `…/base` + `inference` — dezelfde padvorming als `AiClientService`.
  static Uri _endpoint(Uri base, String path) {
    final trimmed = base.path.replaceAll(RegExp(r'/+$'), '');
    return base.replace(path: '$trimmed/$path');
  }

  /// De bestandsnaam die de server te zien krijgt. `mem:`-sleutels hebben
  /// geen pad; we geven een vaste naam — de server doet er niets mee maar
  /// een echte padnaam zou op web niets betekenen.
  static String _audioFileName(String path) {
    if (path.startsWith('mem:')) return 'audio.wav';
    final idx = path.lastIndexOf('/');
    final name = idx >= 0 ? path.substring(idx + 1) : path;
    return name.isEmpty ? 'audio.wav' : name;
  }
}

/// Vaste multipart-boundary. Geen geheim — deterministisch maakt de body in
/// tests exact controleerbaar, en per-request randomness beschermt hier
/// niets dat een vaste grens niet ook afzet.
const _boundary = '----ocideck-asr-boundary';

/// Bouwt een `multipart/form-data`-body: eerst de tekstvelden, dan het
/// bestanddeel. Puur, zodat de test de exacte bytes kan toetsen — een
/// afwijkend format faalt bij elke whisper.cpp-achtige server hetzelfde.
Uint8List buildMultipartBody({
  required Map<String, String> fields,
  required String fileField,
  required String fileName,
  required String fileContentType,
  required Uint8List fileBytes,
}) {
  final out = BytesBuilder(copy: false);
  void line(String s) => out.add(utf8.encode('$s\r\n'));

  fields.forEach((name, value) {
    line('--$_boundary');
    line('Content-Disposition: form-data; name="$name"');
    line('');
    line(value);
  });
  line('--$_boundary');
  line(
    'Content-Disposition: form-data; name="$fileField"; '
    'filename="$fileName"',
  );
  line('Content-Type: $fileContentType');
  line('');
  out.add(fileBytes);
  out.add(utf8.encode('\r\n--$_boundary--\r\n'));
  return out.takeBytes();
}

/// Parseert het `verbose_json`-antwoord van een whisper.cpp-achtige server
/// naar een [TranscriptResult]. Defensief: elk veld dat mist of van een
/// ander type is wordt overgeslagen in plaats van te crashen — de server
/// is een externe dienst, zijn antwoord is invoer. `json` (zonder
/// `verbose_`) levert alleen `text`; dat wordt één segmentloze tekst.
TranscriptResult parseWhisperServerResponse(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, Object?>) {
    throw const ServerRefused('antwoord is geen JSON-object');
  }
  final segments = decoded['segments'];
  if (segments is! List) {
    final text = decoded['text'];
    if (text is String) {
      return TranscriptResult(segments: [TranscriptSegment(text: text)]);
    }
    throw const ServerRefused('antwoord mist segments en text');
  }
  final out = <TranscriptSegment>[];
  for (final raw in segments) {
    if (raw is! Map) continue;
    final text = raw['text'];
    if (text is! String) continue;
    final start = raw['start'];
    out.add(
      TranscriptSegment(
        text: text,
        start: start is num
            ? Duration(milliseconds: (start * 1000).round())
            : null,
        speaker: raw['speaker'] is String ? raw['speaker'] as String : null,
      ),
    );
  }
  return TranscriptResult(segments: out);
}
