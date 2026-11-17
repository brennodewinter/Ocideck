// Het optionele OciDeck ASR v1-contract; legacy /inference blijft apart.
// Een capability is geen kwaliteitsclaim. Alleen de server kan verklaren
// dat diarisatie werkelijk is uitgevoerd, met opnamegebonden cluster-IDs.
import 'dart:convert';

import 'transcription_engine.dart';
import 'transcription_errors.dart';

const asrBatchV1Path = 'ocideck-asr/v1';

Map<String, Object?> _object(String body) {
  try {
    final value = jsonDecode(body);
    if (value is Map<String, Object?> &&
        value['protocol'] == 'ocideck-asr' &&
        value['version'] == 1) {
      return value;
    }
  } on FormatException {
    // De fout bevat nooit de antwoordtekst of eventuele servergeheimen.
  }
  throw const ServerRefused('ongeldig OciDeck ASR v1-antwoord');
}

EngineCapabilities parseAsrBatchCapabilities(String body) {
  if (utf8.encode(body).length > 64 * 1024) {
    throw const ServerRefused('capabilityantwoord te groot');
  }
  final data = _object(body);
  final languages = data['languages'];
  final features = data['features'];
  if (languages is! List ||
      languages.length > 256 ||
      languages.any((v) => v is! String || !_language.hasMatch(v)) ||
      features is! Map ||
      features['timestamps'] is! bool ||
      features['diarization'] is! bool ||
      (features['language_detection'] != null &&
          features['language_detection'] is! bool) ||
      (features['language_switching'] != null &&
          features['language_switching'] is! bool)) {
    throw const ServerRefused('ongeldige ASR-capabilities');
  }
  return EngineCapabilities(
    languages: Set.unmodifiable(languages.cast<String>()),
    automaticLanguage: features['language_detection'] == true,
    languageSwitching: features['language_switching'] == true,
    timestamps: features['timestamps'] == true,
    diarization: features['diarization'] == true,
  );
}

final _language = RegExp(r'^[a-z]{2,3}(-[A-Za-z0-9]{2,8}){0,3}$');
final _speakerId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$');

TranscriptResult parseAsrBatchResponse(
  String body, {
  required bool diarize,
  bool languageSwitching = false,
}) {
  final data = _object(body);
  if (data['diarization_applied'] != diarize) {
    throw const ServerRefused('diarisatiekeuze niet uitgevoerd');
  }
  if ((data['language_switching_applied'] ?? false) != languageSwitching) {
    throw const ServerRefused('taalwisselkeuze niet uitgevoerd');
  }
  final segments = data['segments'];
  if (segments is! List || segments.length > 100000) {
    throw const ServerRefused('ongeldige ASR-segmenten');
  }
  final result = <TranscriptSegment>[];
  var previous = Duration.zero;
  for (final segment in segments) {
    final parsed = _segment(segment, diarize: diarize);
    if (parsed.start != null && parsed.start! < previous) {
      throw const ServerRefused('ASR-segmenten niet op tijd gesorteerd');
    }
    previous = parsed.start ?? previous;
    result.add(parsed);
  }
  return TranscriptResult(segments: List.unmodifiable(result));
}

TranscriptSegment _segment(Object? raw, {required bool diarize}) {
  if (raw is! Map || raw['text'] is! String) {
    throw const ServerRefused('ongeldig ASR-segment');
  }
  final start = _time(raw['start']);
  final end = _time(raw['end']);
  if ((end != null && (start == null || end < start)) ||
      (diarize && (start == null || end == null))) {
    throw const ServerRefused('ongeldig ASR-tijdvak');
  }
  final language = raw['language'];
  final languageUncertain = raw['language_uncertain'];
  if ((language != null &&
          (language is! String ||
              (language != 'mixed' && !_language.hasMatch(language)))) ||
      (languageUncertain != null && languageUncertain is! bool)) {
    throw const ServerRefused('ongeldige segmenttaal');
  }
  final ids = raw['speaker_ids'];
  final uncertain = raw['speaker_uncertain'];
  if (diarize &&
      (ids is! List ||
          ids.length > 8 ||
          ids.any((v) => v is! String || !_speakerId.hasMatch(v)) ||
          ids.toSet().length != ids.length ||
          uncertain is! bool)) {
    throw const ServerRefused('ongeldige sprekerindeling');
  }
  // Uitgeschakeld betekent geen labels, ook niet als een server ze meestuurt.
  return TranscriptSegment(
    text: raw['text'] as String,
    language: language as String?,
    languageUncertain: languageUncertain as bool? ?? (language != null),
    start: start,
    end: end,
    speakerIds: diarize
        ? List.unmodifiable((ids as List).cast<String>())
        : const [],
    speakerUncertain: diarize && (uncertain == true || (ids as List).isEmpty),
  );
}

Duration? _time(Object? value) {
  if (value == null) return null;
  if (value is! num || !value.isFinite || value < 0 || value > 7 * 24 * 3600) {
    throw const ServerRefused('ongeldige ASR-tijd');
  }
  return Duration(
    microseconds: (value * Duration.microsecondsPerSecond).round(),
  );
}
