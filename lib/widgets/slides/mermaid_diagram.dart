import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/mermaid_render_service.dart';
import '../../utils/sanitize_svg.dart';

/// Zet Mermaid-brontekst om in SVG-opmaak, of `null` als dat niet lukt.
/// Standaard de gedeelde [MermaidRenderService].
///
/// Eén dunne indirectie, in hetzelfde patroon als `FileService.saveDestination`:
/// de renderer draait op een verborgen [WebView] die onder `flutter test` niet
/// bestaat, en zonder deze naad is alles eráchter onbereikbaar — het opschonen
/// van de SVG, het kader eromheen, en de terugval op de brontekst wanneer de
/// opmaak wordt geweigerd.
typedef MermaidRenderer = Future<String?> Function(String source);

/// Renders a Mermaid diagram definition as inline SVG in slide previews.
class MermaidDiagram extends StatefulWidget {
  final String source;
  final double width;

  /// Zie [MermaidRenderer]. `null` betekent: de gedeelde renderdienst.
  final MermaidRenderer? renderer;

  const MermaidDiagram({
    super.key,
    required this.source,
    required this.width,
    this.renderer,
  });

  @override
  State<MermaidDiagram> createState() => _MermaidDiagramState();
}

class _MermaidDiagramState extends State<MermaidDiagram> {
  late Future<String?> _svgFuture;

  MermaidRenderer get _render =>
      widget.renderer ?? MermaidRenderService.instance.render;

  @override
  void initState() {
    super.initState();
    _svgFuture = _render(widget.source);
  }

  @override
  void didUpdateWidget(MermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _svgFuture = _render(widget.source);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _svgFuture,
      builder: (context, snapshot) {
        final svg = snapshot.data;
        if (svg != null) {
          final safe = sanitizeMermaidSvg(svg);
          if (safe != null) {
            final size = _fittedDiagramSize(safe, widget.width);
            return Container(
              width: double.infinity,
              margin: EdgeInsets.symmetric(vertical: widget.width * 0.008),
              padding: EdgeInsets.all(widget.width * 0.012),
              decoration: BoxDecoration(
                color: AppTheme.nearWhite,
                borderRadius: BorderRadius.circular(widget.width * 0.008),
                border: Border.all(color: AppTheme.ghBorder),
              ),
              // `heightFactor: 1.0` centreert het diagram horizontaal zonder het
              // kader verticaal te laten uitzetten: de Container blijft even hoog
              // als het (begrensde) diagram, zodat het kader zelf niet onder de
              // slide uit groeit.
              child: Center(
                heightFactor: 1.0,
                child: SvgPicture.string(
                  safe,
                  fit: BoxFit.contain,
                  width: size.width,
                  height: size.height,
                ),
              ),
            );
          }
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: widget.width * 0.02),
            child: Center(
              child: SizedBox(
                width: widget.width * 0.04,
                height: widget.width * 0.04,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _fallbackCode();
      },
    );
  }

  Widget _fallbackCode() {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: widget.width * 0.008),
      padding: EdgeInsets.all(widget.width * 0.018),
      decoration: BoxDecoration(
        color: AppTheme.ghSurface,
        borderRadius: BorderRadius.circular(widget.width * 0.008),
        border: Border.all(color: AppTheme.ghBorder),
      ),
      child: Text(
        widget.source,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: widget.width * 0.02,
          height: 1.3,
          color: AppTheme.ghInk,
        ),
      ),
    );
  }
}

/// De maat waarin het diagram binnen het slidekader past.
///
/// `SvgPicture` met alléén een breedte leidt de hoogte af uit de beeldverhouding
/// en kent geen plafond: een hoge flowchart (veel niveaus) groeit dan onbeperkt
/// door en loopt onder uit de slide (#868). Hier begrenzen we beide maten en
/// schalen we het diagram zo groot mogelijk binnen `maxW × maxH`, met behoud van
/// verhouding. Een breed, laag diagram houdt zijn natuurlijke maat; een hoog
/// diagram schaalt mee omlaag in plaats van eruit te lopen. `maxH` is een
/// fractie van de slidebreedte (net als alle maten hier), zodat de begrenzing
/// meeschaalt met preview, thumbnail en presentatie.
Size _fittedDiagramSize(String svg, double w) {
  final maxW = w * 0.84;
  // Ruim onder de 16:9-hoogte (0.5625·w) blijven: er staat meestal een titel
  // boven het diagram, plus de rand en marge van het kader zelf. Empirisch op de
  // beslisboom-slide teruggebracht tot 0.32, zodat ook de onderste rij knopen
  // binnen het kader valt in plaats van eronder weg te vallen.
  final maxH = w * 0.32;
  final ratio = _diagramAspectRatio(svg);
  if (ratio == null || ratio <= 0) return Size(maxW, maxH);
  var width = maxW;
  var height = width / ratio;
  if (height > maxH) {
    height = maxH;
    width = height * ratio;
  }
  return Size(width, height);
}

/// Breedte/hoogte van het diagram, afgelezen uit de `viewBox`.
///
/// Mermaid zet de echte maten in de `viewBox` (`minX minY breedte hoogte`); de
/// `width`/`height`-attributen zijn `100%` en zeggen niets. `null` als er geen
/// bruikbare `viewBox` is — dan valt de aanroeper terug op het volle kader.
double? _diagramAspectRatio(String svg) {
  final match = RegExp(r'viewBox\s*=\s*"([^"]*)"').firstMatch(svg);
  if (match == null) return null;
  final parts = match.group(1)!.trim().split(RegExp(r'[\s,]+'));
  if (parts.length != 4) return null;
  final width = double.tryParse(parts[2]);
  final height = double.tryParse(parts[3]);
  if (width == null || height == null || height <= 0) return null;
  return width / height;
}
