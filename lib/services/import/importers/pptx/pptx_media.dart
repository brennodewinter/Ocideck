import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../models/source_image.dart';
import '../../models/source_video.dart';
import 'pptx_context.dart';

const _videoExts = {
  'mp4',
  'mov',
  'avi',
  'mkv',
  'webm',
  'm4v',
  'wmv',
  'mpg',
  'mpeg',
};
const _audioExts = {'mp3', 'wav', 'aac', 'm4a', 'ogg', 'wma', 'flac'};

class Media {
  const Media({this.video, this.audioFileName});
  final SourceVideo? video;
  final String? audioFileName;
}

/// Scan the slide's relationships for embedded or linked video/audio media.
///
/// The first video target wins (OciDeck has one video per slide); an audio
/// target is recorded as a file name for the note slide (OciDeck has no audio
/// slide). Embedded bytes are carried so the writer can copy them to
/// `media/`; `http(s)` targets become URL videos.
Media scanMedia(PptxContext ctx, Map<String, String> rels, String slidePath) {
  SourceVideo? video;
  String? audio;
  for (final entry in rels.entries) {
    final resolved = ctx.resolveRel(rels, entry.key, slidePath);
    if (resolved == null) continue;
    final ext = _extFromPath(resolved);
    if (video == null && _videoExts.contains(ext)) {
      video = _videoFor(ctx, entry.key, resolved, slidePath, rels);
    } else if (audio == null && _audioExts.contains(ext)) {
      audio = p.url.basename(resolved);
    }
  }
  return Media(video: video, audioFileName: audio);
}

SourceVideo _videoFor(
  PptxContext ctx,
  String rId,
  String resolved,
  String slidePath,
  Map<String, String> rels,
) {
  final name = p.url.basename(resolved);
  // External link (r:link) -> URL video.
  final linkTarget = _linkTarget(ctx, rels, rId, slidePath);
  if (linkTarget != null &&
      (linkTarget.startsWith('http://') || linkTarget.startsWith('https://'))) {
    final kind = linkTarget.contains('youtu') || linkTarget.contains('youtube')
        ? SourceVideoKind.youtube
        : (linkTarget.contains('vimeo.com')
              ? SourceVideoKind.vimeo
              : SourceVideoKind.url);
    return SourceVideo(kind: kind, ref: linkTarget);
  }
  // Embedded -> copy bytes to media/<name> via the writer.
  final bytes = ctx.readPartBytes(resolved);
  return SourceVideo(
    kind: SourceVideoKind.local,
    ref: 'media/$name',
    bytes: bytes == null ? null : Uint8List.fromList(bytes),
  );
}

/// Look up an `r:link` target for [rId] (external videos are linked, not
/// embedded). Returns `null` when the relationship is embed-only.
String? _linkTarget(
  PptxContext ctx,
  Map<String, String> rels,
  String rId,
  String slidePath,
) {
  // The rels map already holds the target; for external links it is an
  // absolute URL (Targets that start with http are stored verbatim). Resolve
  // defensively: if it doesn't look like a path inside the package, return it
  // as-is.
  final target = rels[rId];
  if (target == null) return null;
  if (target.startsWith('http://') || target.startsWith('https://')) {
    return target;
  }
  return null;
}

/// Parse a `p:pic` picture shape into a [SourceImage] by following its
/// `a:blip` `r:embed` to the media part. Linked-only pictures (`r:link`)
/// are dropped for now (M2) — the bytes are not in the package.
///
/// Very small images (logos, footer icons) are ignored so they don't take
/// over a slide layout.
SourceImage? parsePic(
  XmlElement pic,
  PptxContext ctx,
  Map<String, String> rels,
  String slidePath,
) {
  final blip = descendantsLocal(pic, 'blip').firstOrNull;
  if (blip == null) return null;
  final rId = blip.getAttribute('embed', namespaceUri: relsNs);
  if (rId == null) return null;

  // Skip small logos/footer icons.
  final spPr = descendantsLocal(pic, 'spPr').firstOrNull;
  final xfrm = spPr != null ? childLocal(spPr, 'xfrm') : null;
  final ext = xfrm != null ? childLocal(xfrm, 'ext') : null;
  if (ext != null && !_isSignificantImageSize(ext, ctx.slideSize)) {
    return null;
  }

  final bytes = ctx.readRelBytes(rels, rId, slidePath);
  if (bytes == null) return null;
  final resolved = ctx.resolveRel(rels, rId, slidePath) ?? '';
  final name = descendantsLocal(pic, 'cNvPr').firstOrNull?.getAttribute('name');

  // PowerPoint slaat rotatie op als `rot` op `<a:xfrm>` in 60000sten van een
  // graad (10800000 = 180°). Bak de rotatie in de bytes bij import, zodat de
  // rest van de pipeline (weergave, opslaan, dedup) de afbeelding correct ziet.
  final rot60000 = xfrm?.getAttribute('rot');
  final rotDegrees = rot60000 == null
      ? 0.0
      : (int.tryParse(rot60000) ?? 0) / 60000.0;
  final imageBytes = rotDegrees != 0 && rotDegrees % 360 != 0
      ? _rotateImage(Uint8List.fromList(bytes), rotDegrees, resolved)
      : Uint8List.fromList(bytes);

  return SourceImage(
    bytes: imageBytes,
    ext: _extFromPath(resolved),
    name: name ?? p.url.basename(resolved),
  );
}

/// True wanneer [pic] wél naar een ingesloten afbeelding verwijst maar de bytes
/// ontbreken — echt verlies, geen weggefilterd logo (dat draagt zijn bytes wél).
///
/// [parsePic] geeft ook `null` terug voor een te klein logo of een `pic` zonder
/// blip; dat is géén verlies. Alleen een aanwezige `r:embed`-verwijzing zonder
/// leesbare bytes telt als een ontbrekend media-onderdeel (#877).
bool picReferencesMissingMedia(
  XmlElement pic,
  PptxContext ctx,
  Map<String, String> rels,
  String slidePath,
) {
  final blip = descendantsLocal(pic, 'blip').firstOrNull;
  if (blip == null) return false;
  final rId = blip.getAttribute('embed', namespaceUri: relsNs);
  if (rId == null) return false;
  return ctx.readRelBytes(rels, rId, slidePath) == null;
}

/// Returns true when the picture occupies at least ~3% of the slide area or
/// at least one side is 25% of the slide, to avoid logos being promoted to
/// full slide images.
bool _isSignificantImageSize(
  XmlElement ext,
  ({int width, int height})? slideSize,
) {
  if (slideSize == null) return true;
  final cx = int.tryParse(ext.getAttribute('cx') ?? '') ?? 0;
  final cy = int.tryParse(ext.getAttribute('cy') ?? '') ?? 0;
  if (cx <= 0 || cy <= 0) return true;

  final widthFraction = cx / slideSize.width;
  final heightFraction = cy / slideSize.height;
  final areaFraction = widthFraction * heightFraction;

  return areaFraction >= 0.03 ||
      widthFraction >= 0.25 ||
      heightFraction >= 0.25;
}

String _extFromPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return 'png';
  final ext = path.substring(dot + 1).toLowerCase();
  return ext.isEmpty ? 'png' : ext;
}

/// Roteer [bytes] met [degrees] en codeer opnieuw in het oorspronkelijke formaat.
/// Geeft de originele bytes ongewijzigd terug als decoderen of roteren faalt —
/// een onleesbare afbeelding is beter dan geen afbeelding.
Uint8List _rotateImage(Uint8List bytes, double degrees, String path) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final rotated = img.copyRotate(decoded, angle: degrees);
    final ext = _extFromPath(path);
    final encoded = ext == 'jpg' || ext == 'jpeg'
        ? img.encodeJpg(rotated)
        : ext == 'gif'
        ? img.encodeGif(rotated)
        : img.encodePng(rotated);
    return Uint8List.fromList(encoded);
  } on Object {
    return bytes;
  }
}
