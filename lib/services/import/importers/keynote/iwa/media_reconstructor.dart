import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../models/source_image.dart';
import '../../../models/source_video.dart';
import '../../../utils/safe_extensions.dart';
import '../key_context.dart';
import 'iwa_archive.dart';
import 'iwa_document.dart';
import 'proto_wire.dart';

/// Reconstruct media references from a Keynote IWA `TSD.MovieArchive` drawable.
///
/// A `MovieArchive` represents either embedded/local video or audio, or a
/// remote streaming URL (YouTube, Vimeo, or a generic URL). Embedded media is
/// pointed at by `movieData` (field 14) as a `TSP.DataReference`; the optional
/// poster image is `posterImageData` (field 15). Audio-only media is flagged
/// by `audioOnly` (field 9) and is reported on the "not converted" note slide
/// because OciDeck has no audio slide type.
class MediaReconstructor {
  MediaReconstructor(this.doc, {this.ctx});

  final IwaDocument doc;
  final KeyContext? ctx;

  /// Extracts a [SourceVideo] and/or an audio file name from [mediaDrawable].
  ({SourceVideo? video, String? audioFileName}) extract(
    IwaObject mediaDrawable,
    int slideIndex,
  ) {
    final msg = mediaDrawable.message;
    // Newer iWork stores the actual media data in a separate object referenced
    // by `database_movieData` (field 2). Fall back to the drawable itself when
    // that field is absent.
    final dbTarget = _resolveDatabaseMovieData(mediaDrawable);
    final effectiveMsg = dbTarget?.message ?? msg;

    final isAudio = (msg.varint(9) ?? effectiveMsg.varint(9)) == 1;
    final remoteUrl = _effectiveString(msg, effectiveMsg, 17);

    if (isAudio) {
      final audioFile = _firstMediaDataFileName(msg, effectiveMsg);
      return (
        video: null,
        audioFileName: audioFile == null ? null : p.basename(audioFile),
      );
    }

    if (remoteUrl != null && _isRemoteUrl(remoteUrl)) {
      return (video: _videoFromUrl(remoteUrl), audioFileName: null);
    }

    final videoFile = _firstMediaDataFileName(msg, effectiveMsg);
    if (videoFile == null) return (video: null, audioFileName: null);

    final safeName = normalizeVideoFileName(p.basename(videoFile));
    final bytes = _readBytes(videoFile);
    final thumbnail = _posterImage(msg, effectiveMsg);
    return (
      video: SourceVideo(
        kind: SourceVideoKind.local,
        ref: 'media/$safeName',
        bytes: bytes,
        thumbnail: thumbnail,
      ),
      audioFileName: null,
    );
  }

  SourceVideo _videoFromUrl(String url) {
    SourceVideoKind kind;
    final uri = _urlWithHost(url);
    if (uri != null && uri.host.isNotEmpty) {
      final host = uri.host.toLowerCase();
      if (host == 'youtu.be' ||
          host == 'youtube.com' ||
          host == 'www.youtube.com' ||
          host == 'm.youtube.com' ||
          host == 'youtube-nocookie.com' ||
          host == 'www.youtube-nocookie.com' ||
          host.endsWith('.youtube.com')) {
        kind = SourceVideoKind.youtube;
      } else if (host == 'vimeo.com' ||
          host == 'www.vimeo.com' ||
          host == 'player.vimeo.com' ||
          host.endsWith('.vimeo.com')) {
        kind = SourceVideoKind.vimeo;
      } else {
        kind = SourceVideoKind.url;
      }
    } else {
      final lower = url.toLowerCase();
      if (lower.contains('youtube') || lower.contains('youtu.be')) {
        kind = SourceVideoKind.youtube;
      } else if (lower.contains('vimeo.com')) {
        kind = SourceVideoKind.vimeo;
      } else {
        kind = SourceVideoKind.url;
      }
    }
    return SourceVideo(kind: kind, ref: url);
  }

  Uri? _urlWithHost(String url) {
    var u = Uri.tryParse(url.trim());
    if (u == null) return null;
    if (u.scheme.isEmpty && !url.contains('://') && !url.startsWith('//')) {
      u = Uri.tryParse('https://$url');
    }
    return u;
  }

  /// Resolve the `database_movieData` reference (field 2) on [drawable], if any.
  IwaObject? _resolveDatabaseMovieData(IwaObject drawable) {
    final ref = drawable.message.message(2);
    final refId = ref?.varint(1);
    if (refId == null) return null;
    return doc.resolveReference(drawable, refId);
  }

  /// Returns [field] from [primary] if present, otherwise from [fallback].
  String? _effectiveString(
    ProtoMessage primary,
    ProtoMessage fallback,
    int field,
  ) {
    return primary.string(field) ?? fallback.string(field);
  }

  /// Returns the data file name for [field] from [primary] if present, otherwise
  /// from [fallback].
  String? _effectiveDataFileName(
    ProtoMessage primary,
    ProtoMessage fallback,
    int field,
  ) {
    return _dataFileName(primary, field) ?? _dataFileName(fallback, field);
  }

  /// Returns the first video/audio data file found in the common MovieArchive
  /// / TSP.Movie DataReference fields. The MovieArchive itself uses fields 14
  /// and 22; the object referenced by `database_movieData` (field 2) may store
  /// the data in fields 11 or 12, so we only check those on the fallback.
  String? _firstMediaDataFileName(ProtoMessage primary, ProtoMessage fallback) {
    for (final field in const [14, 22]) {
      final name = _effectiveDataFileName(primary, fallback, field);
      if (name != null) return name;
    }
    if (!identical(primary, fallback)) {
      for (final field in const [11, 12]) {
        final name = _dataFileName(fallback, field);
        if (name != null) return name;
      }
    }
    return null;
  }

  /// True when [url] is a non-trivial remote URL (not just a word like "Media").
  bool _isRemoteUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final uri = _urlWithHost(trimmed);
    if (uri == null) return false;
    if (uri.scheme == 'file') return false;
    if (uri.host.isNotEmpty) {
      // For http(s), require a real host (not just a single word like "Media").
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return uri.host.contains('.') || uri.host == 'localhost';
      }
      return true;
    }
    // Custom schemes (e.g. youtube://) without a host are still remote URLs.
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return true;
    }
    return false;
  }

  String? _dataFileName(ProtoMessage msg, int field) {
    final dataRef = msg.message(field);
    if (dataRef == null) return null;
    final dataId = dataRef.varint(1);
    if (dataId == null) return null;
    return doc.dataFileName(dataId);
  }

  Uint8List? _readBytes(String fileName) {
    if (ctx == null) return null;
    final bytes = ctx!.readPartBytes('Data/$fileName');
    if (bytes == null || bytes.isEmpty) return null;
    return Uint8List.fromList(bytes);
  }

  SourceImage? _posterImage(ProtoMessage primary, ProtoMessage fallback) {
    final posterFile =
        _dataFileName(primary, 15) ?? _dataFileName(fallback, 15);
    if (posterFile == null) return null;
    final bytes = _readBytes(posterFile);
    if (bytes == null) return null;
    return SourceImage(bytes: bytes, ext: _ext(posterFile), name: posterFile);
  }

  String _ext(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return 'jpg';
    final ext = name.substring(dot + 1).toLowerCase();
    return ext.isEmpty ? 'jpg' : ext;
  }
}
