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
            return Container(
              width: double.infinity,
              margin: EdgeInsets.symmetric(vertical: widget.width * 0.008),
              padding: EdgeInsets.all(widget.width * 0.012),
              decoration: BoxDecoration(
                color: AppTheme.nearWhite,
                borderRadius: BorderRadius.circular(widget.width * 0.008),
                border: Border.all(color: AppTheme.ghBorder),
              ),
              child: SvgPicture.string(
                safe,
                fit: BoxFit.contain,
                width: widget.width * 0.84,
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
