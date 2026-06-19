import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/mermaid_render_service.dart';

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
          return Container(
            width: double.infinity,
            margin: EdgeInsets.symmetric(vertical: widget.width * 0.008),
            padding: EdgeInsets.all(widget.width * 0.012),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFBFC),
              borderRadius: BorderRadius.circular(widget.width * 0.008),
              border: Border.all(color: const Color(0xFFE1E4E8)),
            ),
            child: SvgPicture.string(
              svg,
              fit: BoxFit.contain,
              width: widget.width * 0.84,
            ),
          );
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
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(widget.width * 0.008),
        border: Border.all(color: const Color(0xFFE1E4E8)),
      ),
      child: Text(
        widget.source,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: widget.width * 0.02,
          height: 1.3,
          color: const Color(0xFF24292E),
        ),
      ),
    );
  }
}
