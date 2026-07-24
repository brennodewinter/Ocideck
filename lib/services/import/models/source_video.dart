import 'dart:typed_data';

import 'source_image.dart';

/// A video extracted from a source slide.
class SourceVideo {
  const SourceVideo({
    required this.kind,
    required this.ref,
    this.thumbnail,
    this.bytes,
  });

  /// Where the video lives.
  final SourceVideoKind kind;

  /// Local file name inside the archive, or a remote URL. For embedded video
  /// the writer copies [bytes] to `media/<name>` and this becomes that path.
  final String ref;

  /// Optional poster frame as a [SourceImage].
  final SourceImage? thumbnail;

  /// Raw bytes for embedded video; `null` for URL/YouTube/Vimeo references.
  final Uint8List? bytes;
}

/// How a [SourceVideo] is referenced.
enum SourceVideoKind { local, url, youtube, vimeo }
