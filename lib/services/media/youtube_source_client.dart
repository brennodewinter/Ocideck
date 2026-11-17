import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../models/asr_server_profile.dart';
import '../../utils/json_depth_guard.dart';
import '../transcription/asr_server_gate.dart';
import '../transcription/asr_transport.dart';
import '../transcription/media_sniff.dart';
import 'youtube_reference.dart';

enum YoutubeSourceFailure {
  configuration,
  consent,
  cancelled,
  network,
  protocol,
  unavailable,
  live,
  access,
  rateLimited,
  busy,
  captionsMissing,
  audioMissing,
  tooLarge,
  missingHelper,
}

class YoutubeSourceException implements Exception {
  const YoutubeSourceException(this.failure);
  final YoutubeSourceFailure failure;
}

/// Consent is tied to this destination and video, never a general opt-in.
class YoutubeSourceConsent {
  const YoutubeSourceConsent({
    required this.destination,
    required this.videoId,
  });
  final String destination;
  final String videoId;
}

class YoutubeCaptionTrack {
  const YoutubeCaptionTrack({
    required this.id,
    required this.language,
    required this.automatic,
  });
  final String id;
  final String language;
  final bool automatic;
}

class YoutubeSourceMetadata {
  const YoutubeSourceMetadata({
    required this.reference,
    required this.title,
    required this.duration,
    required this.tracks,
    required this.audioAvailable,
    required this.audioFragments,
  });
  final YoutubeReference reference;
  final String title;
  final Duration duration;
  final List<YoutubeCaptionTrack> tracks;
  final bool audioAvailable;
  final bool audioFragments;
}

class YoutubeCaptionText {
  const YoutubeCaptionText(this.text, this.track);
  final String text;
  final YoutubeCaptionTrack track;
}

class YoutubeAudioBytes {
  const YoutubeAudioBytes(this.bytes, this.extension, this.sourceOffset);
  final Uint8List bytes;
  final String extension;
  final Duration sourceOffset;
}

/// Explicit source server, independent of the selected ASR engine. Uses the
/// existing pinned/native or abortable/CORS browser transport and egress gate.
/// No default endpoint, automatic task, helper install or cloud fallback.
class YoutubeSourceClient {
  YoutubeSourceClient({
    required this.destination,
    required this.mayUseNetwork,
    AsrTransport? transport,
    bool? isWeb,
    this.apiKey,
  }) : _transport = transport ?? createAsrTransport(),
       _isWeb = isWeb ?? kIsWeb;

  final AsrServerProfile destination;
  final bool Function() mayUseNetwork;
  final String? apiKey;
  final AsrTransport _transport;
  final bool _isWeb;
  AsrSendHandle? _pending;
  bool _cancelled = false;
  Map<String, dynamic>? _capabilities;

  void cancel() {
    _cancelled = true;
    _pending?.cancel();
  }

  Future<YoutubeSourceMetadata> metadata(
    YoutubeReference reference,
    YoutubeSourceConsent consent,
  ) async {
    await _ensureCapabilities(reference, consent);
    final value = await _request('metadata', reference, consent, {});
    if (value['status'] != 'completed') {
      throw const YoutubeSourceException(YoutubeSourceFailure.live);
    }
    final title = value['title'];
    final millis = value['duration_ms'];
    final tracks = value['tracks'];
    if (title is! String ||
        title.length > 1000 ||
        millis is! int ||
        millis <= 0 ||
        millis > 48 * 3600 * 1000 ||
        tracks is! List ||
        tracks.length > 250) {
      _protocolError();
    }
    final parsed = <YoutubeCaptionTrack>[];
    final ids = <String>{};
    for (final raw in tracks) {
      if (raw is! Map) _protocolError();
      final id = raw['id'];
      final language = raw['language'];
      final kind = raw['kind'];
      if (id is! String ||
          !RegExp(r'^[A-Za-z0-9_.:-]{1,128}$').hasMatch(id) ||
          !ids.add(id) ||
          language is! String ||
          !RegExp(r'^[A-Za-z0-9_.-]{1,80}$').hasMatch(language) ||
          (kind != 'manual' && kind != 'automatic')) {
        _protocolError();
      }
      parsed.add(
        YoutubeCaptionTrack(
          id: id,
          language: language,
          automatic: kind == 'automatic',
        ),
      );
    }
    return YoutubeSourceMetadata(
      reference: reference,
      title: title,
      duration: Duration(milliseconds: millis),
      tracks: parsed,
      audioAvailable: _capabilities!['audio'] == true && value['audio'] == true,
      audioFragments: _capabilities!['audio_fragments'] == true,
    );
  }

  Future<YoutubeCaptionText> captions(
    YoutubeReference reference,
    YoutubeCaptionTrack track,
    YoutubeSourceConsent consent,
  ) async {
    await _ensureCapabilities(reference, consent);
    if (_capabilities!['captions'] != true) {
      throw const YoutubeSourceException(YoutubeSourceFailure.captionsMissing);
    }
    final value = await _request('captions', reference, consent, {
      'track': track.id,
    });
    final text = value['text'];
    if (value['track'] != track.id ||
        value['format'] != 'vtt' ||
        text is! String ||
        utf8.encode(text).length > 2 * 1024 * 1024) {
      _protocolError();
    }
    return YoutubeCaptionText(text, track);
  }

  Future<YoutubeAudioBytes> audio(
    YoutubeReference reference,
    YoutubeSourceConsent consent, {
    int startMs = 0,
    int endMs = 0,
  }) async {
    if (startMs < 0 || endMs < 0 || (endMs != 0 && endMs <= startMs)) {
      throw const YoutubeSourceException(YoutubeSourceFailure.configuration);
    }
    await _ensureCapabilities(reference, consent);
    if (_capabilities!['audio'] != true ||
        ((startMs != 0 || endMs != 0) &&
            _capabilities!['audio_fragments'] != true)) {
      throw const YoutubeSourceException(YoutubeSourceFailure.audioMissing);
    }
    final value = await _request('audio', reference, consent, {
      'start_ms': startMs,
      'end_ms': endMs,
    });
    final encoded = value['base64'];
    final extension = value['extension'];
    if (encoded is! String ||
        encoded.length > 12 * 1024 * 1024 ||
        extension != 'wav' ||
        value['source_offset_ms'] != startMs) {
      _protocolError();
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      _protocolError();
    }
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw const YoutubeSourceException(YoutubeSourceFailure.tooLarge);
    }
    final wav = parseWavHeader(bytes, bytes.length);
    if (wav == null ||
        wav.formatTag != 1 ||
        wav.sampleRate != 16000 ||
        wav.channels != 1 ||
        wav.bitsPerSample != 16 ||
        wav.dataBytes == 0) {
      _protocolError();
    }
    return YoutubeAudioBytes(
      bytes,
      extension as String,
      Duration(milliseconds: startMs),
    );
  }

  Future<void> _ensureCapabilities(
    YoutubeReference reference,
    YoutubeSourceConsent consent,
  ) async {
    _check(reference, consent);
    if (_capabilities != null) return;
    final value = await _request('capabilities', reference, consent, null);
    if (value['captions'] is! bool ||
        value['audio'] is! bool ||
        value['audio_fragments'] is! bool ||
        (value['audio'] == true && value['audio_encoding'] != 'pcm16-wav')) {
      _protocolError();
    }
    _capabilities = value;
  }

  AsrGateAllow _check(
    YoutubeReference reference,
    YoutubeSourceConsent consent,
  ) {
    if (_cancelled || !mayUseNetwork()) {
      throw const YoutubeSourceException(YoutubeSourceFailure.cancelled);
    }
    if (consent.videoId != reference.videoId ||
        consent.destination != destination.baseUrl) {
      throw const YoutubeSourceException(YoutubeSourceFailure.consent);
    }
    final gate = AsrServerGate.evaluate(destination, isWeb: _isWeb);
    if (gate is! AsrGateAllow || gate.uri.hasQuery || gate.uri.hasFragment) {
      throw const YoutubeSourceException(YoutubeSourceFailure.configuration);
    }
    if (apiKey != null &&
        apiKey!.isNotEmpty &&
        !AsrServerGate.keyMayTravel(gate)) {
      throw const YoutubeSourceException(YoutubeSourceFailure.configuration);
    }
    return gate;
  }

  Future<Map<String, dynamic>> _request(
    String action,
    YoutubeReference reference,
    YoutubeSourceConsent consent,
    Map<String, Object?>? fields,
  ) async {
    final gate = _check(reference, consent);
    if (_pending != null) {
      throw const YoutubeSourceException(YoutubeSourceFailure.busy);
    }
    final base = gate.uri.toString().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/ocideck-youtube/v1/$action');
    final handle = _transport.send(
      method: fields == null ? 'GET' : 'POST',
      url: uri,
      strategy: gate.strategy,
      body: fields == null
          ? null
          : Uint8List.fromList(
              utf8.encode(
                jsonEncode({'video_id': reference.videoId, ...fields}),
              ),
            ),
      headers: {
        'Content-Type': 'application/json',
        if (apiKey != null && apiKey!.isNotEmpty)
          'Authorization': 'Bearer $apiKey',
      },
      timeout: const Duration(minutes: 3),
    );
    _pending = handle;
    try {
      final response = await handle.done;
      _check(reference, consent);
      if (!response.isOk) throw YoutubeSourceException(_failure(response));
      if (response.body.length > 14 * 1024 * 1024) _protocolError();
      // The transport bounds bytes; the parser independently bounds nesting.
      final value = jsonDecodeGuarded(response.body, maxDepth: 32);
      if (value is! Map<String, dynamic> ||
          value['protocol'] != 'ocideck-youtube' ||
          value['version'] != 1 ||
          (fields != null && value['video_id'] != reference.videoId)) {
        _protocolError();
      }
      return value;
    } on AsrRequestException {
      throw YoutubeSourceException(
        _cancelled || !mayUseNetwork()
            ? YoutubeSourceFailure.cancelled
            : YoutubeSourceFailure.network,
      );
    } on FormatException {
      _protocolError();
    } finally {
      if (identical(_pending, handle)) _pending = null;
    }
  }
}

Never _protocolError() =>
    throw const YoutubeSourceException(YoutubeSourceFailure.protocol);

YoutubeSourceFailure _failure(AsrResponse response) {
  try {
    final value = jsonDecodeGuarded(response.body, maxDepth: 32);
    if (value is Map) {
      for (final failure in YoutubeSourceFailure.values) {
        if (value['error'] == failure.name) return failure;
      }
    }
  } on FormatException {
    // Untrusted upstream error bodies are never shown verbatim.
  }
  if (response.statusCode == 429) return YoutubeSourceFailure.rateLimited;
  if (response.statusCode == 413) return YoutubeSourceFailure.tooLarge;
  if (response.statusCode == 404) return YoutubeSourceFailure.unavailable;
  return YoutubeSourceFailure.network;
}
