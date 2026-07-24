import 'package:xml/xml.dart';

import '../../models/source_theme.dart';
import 'pptx_context.dart';

/// Salvage a [SourceTheme] from `ppt/theme/themeN.xml`.
///
/// DrawingML colour schemes name their slots `dk1`/`lt1`/`accent1`..`accent6`
/// (and `hlink`/`folHlink`). We map the most useful ones onto OciDeck's style
/// profile: `accent1` -> accent colour, `dk1` -> text colour. The font
/// scheme's major Latin typeface becomes the deck font family. Everything
/// else (minor font, effect schemes, bevels) is dropped — OciDeck's fixed
/// layouts do not carry them.
SourceTheme parseTheme(String xml) {
  try {
    final doc = XmlDocument.parse(xml);
    final clrScheme = descendantsLocal(doc, 'clrScheme').firstOrNull;
    final fontScheme = descendantsLocal(doc, 'fontScheme').firstOrNull;

    return SourceTheme(
      accentColor: _schemeColor(clrScheme, 'accent1'),
      textColor:
          _schemeColor(clrScheme, 'dk1') ?? _schemeColor(clrScheme, 'tx1'),
      fontFamily:
          _latinTypeface(fontScheme, 'majorFont') ??
          _latinTypeface(fontScheme, 'minorFont'),
    );
  } on Exception {
    return const SourceTheme();
  }
}

String? _schemeColor(XmlElement? clrScheme, String slot) {
  if (clrScheme == null) return null;
  final slotEl = childLocal(clrScheme, slot);
  if (slotEl == null) return null;
  // Colors are children like <a:srgbClr val="RRGGBB"/> or <a:sysClr val="..."
  // lastClr="RRGGBB"/>.
  final srgb = descendantsLocal(slotEl, 'srgbClr').firstOrNull;
  if (srgb != null) return _normalizeHex(srgb.getAttribute('val'));
  final sys = descendantsLocal(slotEl, 'sysClr').firstOrNull;
  if (sys != null) return _normalizeHex(sys.getAttribute('lastClr'));
  return null;
}

String? _latinTypeface(XmlElement? fontScheme, String fontEl) {
  if (fontScheme == null) return null;
  final font = childLocal(fontScheme, fontEl);
  if (font == null) return null;
  final latin = childLocal(font, 'latin');
  return latin?.getAttribute('typeface');
}

String? _normalizeHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final h = hex.startsWith('#') ? hex.substring(1) : hex;
  return '#${h.toUpperCase()}';
}
