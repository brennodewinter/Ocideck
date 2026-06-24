import '../utils/net_guard.dart';

/// Where a slide's video comes from. The single source string lives in
/// [Slide.videoPath]; this type interprets it so the preview, the markdown
/// serializer and the exporter all classify it the same way.
enum VideoSourceKind {
  /// Empty — nothing to play.
  none,

  /// A local file path (relative to the project or an absolute path).
  localFile,

  /// A direct `http(s)` URL to a video file (`.mp4`/`.mov`/…), played live.
  remoteFile,

  /// A YouTube watch/short/embed URL, played via an embedded iframe player.
  youtube,

  /// A Vimeo URL, played via an embedded iframe player.
  vimeo,
}

/// Parsed view of a video source string. Construct with [VideoSource.parse];
/// it never throws and falls back to [VideoSourceKind.localFile] for anything
/// that isn't recognised as a URL.
class VideoSource {
  final VideoSourceKind kind;

  /// The original source string (unchanged), e.g. `media/clip.mp4` or a URL.
  final String raw;

  /// For [VideoSourceKind.youtube]/[VideoSourceKind.vimeo]: the bare video id.
  final String? embedId;

  const VideoSource._(this.kind, this.raw, [this.embedId]);

  bool get isEmbed =>
      kind == VideoSourceKind.youtube || kind == VideoSourceKind.vimeo;

  /// Any source whose bytes come over the network (live file or embed). These
  /// are the sources that must pass the remote-media gate before they render.
  bool get isRemote => kind != VideoSourceKind.localFile && kind != VideoSourceKind.none;

  static final RegExp _youTubeId = RegExp(r'^[A-Za-z0-9_-]{6,20}$');
  static final RegExp _vimeoId = RegExp(r'^\d{6,12}$');

  factory VideoSource.parse(String videoPath) {
    final raw = videoPath.trim();
    if (raw.isEmpty) return const VideoSource._(VideoSourceKind.none, '');

    final uri = Uri.tryParse(raw);
    final scheme = uri?.scheme.toLowerCase();
    final isWeb = uri != null &&
        uri.hasAuthority &&
        (scheme == 'http' || scheme == 'https');
    if (uri == null || !isWeb) {
      return VideoSource._(VideoSourceKind.localFile, raw);
    }

    final host = uri.host.toLowerCase();
    final yt = _youTubeIdOf(uri, host);
    if (yt != null) return VideoSource._(VideoSourceKind.youtube, raw, yt);
    final vimeo = _vimeoIdOf(uri, host);
    if (vimeo != null) return VideoSource._(VideoSourceKind.vimeo, raw, vimeo);

    return VideoSource._(VideoSourceKind.remoteFile, raw);
  }

  static String? _youTubeIdOf(Uri uri, String host) {
    final h = host.startsWith('www.') ? host.substring(4) : host;
    if (h == 'youtu.be') {
      final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
      return _youTubeId.hasMatch(id) ? id : null;
    }
    if (h == 'youtube.com' || h == 'm.youtube.com' || h == 'youtube-nocookie.com') {
      final v = uri.queryParameters['v'];
      if (v != null && _youTubeId.hasMatch(v)) return v;
      final segs = uri.pathSegments;
      // /embed/<id> or /shorts/<id> or /v/<id>
      if (segs.length >= 2 &&
          (segs[0] == 'embed' || segs[0] == 'shorts' || segs[0] == 'v') &&
          _youTubeId.hasMatch(segs[1])) {
        return segs[1];
      }
    }
    return null;
  }

  static String? _vimeoIdOf(Uri uri, String host) {
    final h = host.startsWith('www.') ? host.substring(4) : host;
    if (h != 'vimeo.com' && h != 'player.vimeo.com') return null;
    // Last numeric path segment: vimeo.com/123, vimeo.com/channels/x/123,
    // player.vimeo.com/video/123.
    for (final seg in uri.pathSegments.reversed) {
      if (_vimeoId.hasMatch(seg)) return seg;
    }
    return null;
  }

  /// Builds the embeddable player URL for an embed source, with the trim window
  /// ([startMs]/[endMs], 0 = open) and [autoplay] folded into provider params.
  /// Returns null for non-embed sources.
  Uri? embedUri({
    required int startMs,
    required int endMs,
    required bool autoplay,
  }) {
    final id = embedId;
    if (id == null) return null;
    final startSec = (startMs / 1000).floor();
    final endSec = (endMs / 1000).ceil();
    switch (kind) {
      case VideoSourceKind.youtube:
        return Uri.https('www.youtube-nocookie.com', '/embed/$id', {
          if (startSec > 0) 'start': '$startSec',
          if (endSec > 0) 'end': '$endSec',
          'autoplay': autoplay ? '1' : '0',
          'rel': '0',
          'modestbranding': '1',
          'playsinline': '1',
          'enablejsapi': '1',
        });
      case VideoSourceKind.vimeo:
        final base = Uri.https('player.vimeo.com', '/video/$id', {
          'autoplay': autoplay ? '1' : '0',
          'title': '0',
          'byline': '0',
          'portrait': '0',
          'pip': '0',
        });
        // Vimeo takes the start offset as a #t fragment; the end is enforced
        // in JS by the embed host (no native `end` param).
        return startSec > 0 ? base.replace(fragment: 't=${startSec}s') : base;
      default:
        return null;
    }
  }

  /// True when [url] is an `http(s)` URL that passes the insert-time SSRF gate.
  /// Used by the image fields, which accept either a local path or a URL.
  static bool isAllowedRemoteUrl(String url) => NetGuard.isAllowedMediaUrl(url);

  /// True when [value] looks like an `http(s)` URL at all (scheme present),
  /// regardless of host — used to branch rendering between file and network.
  static bool looksLikeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    final scheme = uri?.scheme.toLowerCase();
    return uri != null &&
        uri.hasAuthority &&
        (scheme == 'http' || scheme == 'https');
  }
}
