import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../models/deck.dart';
import '../../models/slide.dart';
import '../markdown_service.dart';

/// Authenticeert een OpenKAT-dia als ongewijzigd origineel uit deze appsessie.
///
/// De marker is een HMAC-SHA-512 over de canonieke Markdown van de dia zonder
/// provenancecomment. De willekeurige sleutel verlaat het proces niet. Daardoor
/// kan tekst uit een deck nooit zelf vervangingsrecht fabriceren. Na een
/// appherstart is die sleutel bewust weg en stopt bijwerken fail-closed; een
/// ongekeyde legacyhash is alleen tekst en wordt nooit als autorisatie gezien.
class OpenKatSlideProvenance {
  OpenKatSlideProvenance._();

  static final RegExp _marker = RegExp(
    '<!--\\s*$openKatGeneratedOriginMarker:\\s*([a-f0-9]{128})\\s*-->',
  );

  static final MarkdownService _markdown = MarkdownService();
  static final Random _random = Random.secure();
  static final Hmac _authenticator = Hmac(
    sha512,
    List<int>.generate(64, (_) => _random.nextInt(256)),
  );

  static Slide markGeneratedOrigin(Slide slide) {
    final clean = slide.copyWith(notes: _withoutOriginMarker(slide.notes));
    final fingerprint = _authenticationCode(clean);
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
    return match.group(1) == _authenticationCode(clean);
  }

  static bool hasGeneratedOriginMarker(Slide slide) =>
      _marker.hasMatch(slide.notes);

  static String _authenticationCode(Slide slide) => _authenticator
      .convert(
        utf8.encode(
          _markdown.generateSlide(
            slide.copyWith(clearPrivacy: true),
            themeProfile: null,
          ),
        ),
      )
      .toString();

  static String _withoutOriginMarker(String notes) => notes
      .split('\n')
      .where(
        (line) =>
            !line.trim().startsWith('<!-- $openKatGeneratedOriginMarker:'),
      )
      .join('\n');
}
