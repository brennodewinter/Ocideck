import '../../models/slide.dart';
import '../../utils/content_hash.dart';
import '../markdown_service.dart';

/// Bewijst of een OpenKAT-dia nog bytegelijk is aan het gegenereerde origineel.
///
/// De fingerprint is SHA-512 over de canonieke Markdown van de dia zonder de
/// provenancecomment. Daardoor blijft een ongewijzigd origineel herkenbaar na
/// opslaan en heropenen, maar stopt een extern gekopieerde en bewerkte dia
/// fail-closed in plaats van gebruikerswerk te vervangen.
class OpenKatSlideProvenance {
  OpenKatSlideProvenance._();

  static final RegExp _marker = RegExp(
    '<!--\\s*$openKatGeneratedOriginMarker:\\s*([a-f0-9]{128})\\s*-->',
  );

  static final MarkdownService _markdown = MarkdownService();

  static Slide markGeneratedOrigin(Slide slide) {
    final clean = slide.copyWith(notes: _withoutOriginMarker(slide.notes));
    final fingerprint = _fingerprint(clean);
    final notes = clean.notes.isEmpty
        ? '<!-- $openKatGeneratedOriginMarker: $fingerprint -->'
        : '${clean.notes}\n'
              '<!-- $openKatGeneratedOriginMarker: $fingerprint -->';
    return clean.copyWith(notes: notes);
  }

  static bool isUnchangedGeneratedOrigin(Slide slide) {
    final match = _marker.firstMatch(slide.notes);
    if (match == null) return false;
    final clean = slide.copyWith(notes: _withoutOriginMarker(slide.notes));
    return match.group(1) == _fingerprint(clean);
  }

  static String _fingerprint(Slide slide) => sha512HexOfText(
    _markdown.generateSlide(
      slide.copyWith(clearPrivacy: true),
      themeProfile: null,
    ),
  );

  static String _withoutOriginMarker(String notes) => notes
      .split('\n')
      .where(
        (line) =>
            !line.trim().startsWith('<!-- $openKatGeneratedOriginMarker:'),
      )
      .join('\n');
}
