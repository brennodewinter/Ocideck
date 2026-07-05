import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/mermaid_render_service.dart';
import '../../utils/sanitize_svg.dart';

/// Renders a Mermaid diagram definition as inline SVG in slide previews.
class MermaidDiagram extends StatefulWidget {
  final String source;
  final double width;

  const MermaidDiagram({super.key, required this.source, required this.width});

  @override
  State<MermaidDiagram> createState() => _MermaidDiagramState();
}

class _MermaidDiagramState extends State<MermaidDiagram> {
  late Future<String?> _svgFuture;

  @override
  void initState() {
    super.initState();
    _svgFuture = MermaidRenderService.instance.render(widget.source);
  }

  @override
  void didUpdateWidget(MermaidDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _svgFuture = MermaidRenderService.instance.render(widget.source);
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
