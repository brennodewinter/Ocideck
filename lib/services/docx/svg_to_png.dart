// SVG → hoog-DPI PNG voor de .docx-export.
//
// Rasteriseert een inline-SVG (van [MermaidRenderService] of de
// wiskunde-renderer) naar een PNG-bytebuffer, headless — zonder zichtbaar
// venster. Dat is het verschil met `slide_rasterizer.dart`, die een live
// `RepaintBoundary` vastlegt en wél een venster op de voorgrond nodig heeft.
// Hier gaat de SVG door dezelfde `flutter_svg`-pijplijn als op het scherm
// (`SvgPicture.string` in `mermaid_diagram.dart`), maar dan via de lagere
// `vg.loadPicture`-API die een `dart:ui Picture` oplevert. `Picture.toImage`
// draait op de rasterizer-thread en werkt zonder venster, zoals Flutter-tests
// laten zien.
//
// De resolutie is zo gekozen dat een diagram op kolombreedte (A4, ~16 cm
// bruikbaar) op ten minste 300 dpi uitkomt — scherp voor drukwerk en beeld-
// scherm. Een plafond vangt pathologisch grote diagrammen op.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart'
    show PictureInfo, SvgStringLoader, vg;

import '../../utils/log.dart';

/// Doel-resolutie in dpi voor een diagram op kolombreedte.
const double _targetDpi = 300;

/// Bruikbare kolombreedte op A4 met standaardmarges, in duim (~16 cm).
const double _columnWidthInches = 6.3;

/// Minimale pixelbreedte voor een gerasteriseerd diagram — de doel-dpi op
/// kolombreedte. Diagrammen smaller dan dit worden opgeschaald; brede
/// diagrammen behouden hun natuurlijke maat × de schaalfactor.
final int _minWidthPx = (_targetDpi * _columnWidthInches).round(); // ~1890

/// ponytail: plafond op de pixelbreedte, anders kan een pathologisch breed
/// diagram (een tijdlijn met 200 kolommen) een tientallen-megabyte-PNG
/// opleveren die Word traag maakt. Boven dit plafond wordt de hoogte
/// meegeschaald. Upgrade-pad: tegelsgewijs rasteren of SVG-embed in docx
/// (Word 2016+ ondersteunt `<a:svgBlip>`).
const int _maxWidthPx = 4096;

/// Rasteriseert [svg] naar een PNG-bytebuffer, of `null` als de SVG niet
/// geparseerd of gerasteriseerd kon worden. De aanroeper valt dan terug op
/// de brontekst — dezelfde afspraak als de PDF-export.
Future<Uint8List?> svgToPng(String svg) async {
  if (svg.trim().isEmpty) return null;
  try {
    final PictureInfo info = await vg.loadPicture(SvgStringLoader(svg), null);
    final ui.Picture picture = info.picture;
    try {
      final natural = info.size;
      var pxW = natural.width.isFinite && natural.width > 0
          ? natural.width
          : _minWidthPx.toDouble();
      var pxH = natural.height.isFinite && natural.height > 0
          ? natural.height
          : pxW * 0.6;

      // Schaal op naar minstens de doelbreedte, met een ×2-factor op de
      // natuurlijke maat zodat ook kleine diagrammen scherp uitvallen.
      final scale = math.max(2.0, _minWidthPx / pxW);
      pxW = (pxW * scale).roundToDouble();
      pxH = (pxH * scale).roundToDouble();

      // ponytail: plafond op de breedte; hoogte meegeschaald.
      if (pxW > _maxWidthPx) {
        final r = _maxWidthPx / pxW;
        pxW = _maxWidthPx.toDouble();
        pxH = (pxH * r).roundToDouble();
      }
      if (pxH > _maxWidthPx) {
        final r = _maxWidthPx / pxH;
        pxH = _maxWidthPx.toDouble();
        pxW = (pxW * r).roundToDouble();
      }

      final int w = pxW.round();
      final int h = pxH.round();
      if (w <= 0 || h <= 0) return null;

      final ui.Image image = await picture.toImage(w, h);
      try {
        final ByteData? data = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null) return null;
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  } catch (e) {
    logWarning('svgToPng: rasterisatie mislukt', e);
    return null;
  }
}
