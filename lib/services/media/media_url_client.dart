import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../utils/literal_loopback.dart';
import '../transcription/asr_transport.dart';
import '../transcription/media_sniff.dart';
import '../transcription/transcription_errors.dart';

bool isDirectMediaUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      mediaFileExtensions.contains(
        p.extension(uri.path).replaceFirst('.', '').toLowerCase(),
      );
}

bool mayProbeMediaMetadata(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      !const [
        '.md',
        '.ocideck',
        '.xml',
        '.rss',
        '.atom',
        '.json',
        '.html',
        '.htm',
        '.zip',
        '.pdf',
      ].contains(p.extension(uri.path).toLowerCase());
}

class MediaUrlPayload {
  const MediaUrlPayload(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

/// An explicit bounded download, using the same pinned native/CORS browser
/// transport. Every native redirect is validated again; credentials never
/// travel in a URL. No consent is inferred from merely recognising a link.
class MediaUrlClient {
  MediaUrlClient({required this.mayUseNetwork, AsrTransport? transport})
    : _transport =
          transport ?? createAsrTransport(maxResponseBytes: 8 * 1024 * 1024);
  final bool Function() mayUseNetwork;
  final AsrTransport _transport;
  AsrSendHandle? _pending;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _pending?.cancel();
  }

  void _check(Uri uri) {
    if (_cancelled || !mayUseNetwork()) {
      throw const Cancelled('media ophalen geannuleerd');
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    final numericAlias =
        (RegExp(r'^[0-9.]+$').hasMatch(host) && host.split('.').length != 4) ||
        RegExp(r'(^|\.)0x[0-9a-f]+($|\.)').hasMatch(host);
    if (!const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        numericAlias ||
        host.endsWith('.local') ||
        isLiteralInternalHost(host)) {
      throw const UnsupportedSource('ongeldige of interne mediabron');
    }
  }

  Future<MediaUrlPayload> download(Uri source) async {
    final response = await _fetch(source);
    final bytes = response.bytes;
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw const CapacityExceeded(
        'media overschrijdt de bronlimiet van 8 MiB',
      );
    }
    final extension = switch (sniffContainer(
      bytes,
      extension: p.extension((response.finalUrl ?? source).path),
    )) {
      MediaContainer.wav => 'wav',
      MediaContainer.mpeg4 => 'm4a',
      MediaContainer.ogg => 'ogg',
      MediaContainer.flac => 'flac',
      MediaContainer.mp3 => 'mp3',
      MediaContainer.aac => 'aac',
      MediaContainer.aiff => 'aiff',
      MediaContainer.caf => 'caf',
      MediaContainer.ebml => 'webm',
      MediaContainer.avi => 'avi',
      _ => throw const UnsupportedSource('de URL bevat geen herkenbare media'),
    };
    return MediaUrlPayload(bytes, extension);
  }

  /// Recognition only: HEAD never retrieves audio. A failed/unsupported HEAD
  /// leaves ordinary URL import available; it never starts a media GET.
  Future<bool> looksLikeMedia(Uri source) async {
    final response = await _fetch(
      source,
      method: 'HEAD',
      timeout: const Duration(seconds: 5),
    );
    final type = response.headers['content-type']?.toLowerCase() ?? '';
    return type.startsWith('audio/') || type.startsWith('video/');
  }

  Future<AsrResponse> _fetch(
    Uri source, {
    String method = 'GET',
    Duration timeout = const Duration(minutes: 3),
  }) async {
    var uri = source;
    final clock = Stopwatch()..start();
    for (var hop = 0; hop <= 5; hop++) {
      _check(uri);
      final remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) {
        throw const ServerRefused('download verlopen');
      }
      final handle = _transport.send(
        method: method,
        url: uri,
        strategy: AiResolveStrategy.publicGuarded,
        body: null,
        timeout: remaining,
      );
      _pending = handle;
      final AsrResponse response;
      try {
        response = await handle.done;
      } on AsrRequestException {
        if (_cancelled || !mayUseNetwork()) {
          throw const Cancelled('media ophalen geannuleerd');
        }
        throw const ServerRefused('media kon niet worden opgehaald');
      } finally {
        if (identical(_pending, handle)) _pending = null;
      }
      _check(response.finalUrl ?? uri);
      if (uri.scheme == 'https' && response.finalUrl?.scheme == 'http') {
        throw const UnsupportedSource('onveilige mediaomleiding');
      }
      if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null || hop == 5) {
          throw const ServerRefused('ongeldige omleiding');
        }
        final target = uri.resolve(location);
        if (uri.scheme == 'https' && target.scheme != 'https') {
          throw const UnsupportedSource('onveilige mediaomleiding');
        }
        uri = target;
        continue;
      }
      if (!response.isOk) throw const ServerRefused('media niet beschikbaar');
      return response;
    }
    throw const ServerRefused('te veel mediaomleidingen');
  }
}
