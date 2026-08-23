import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/mermaid_render_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/sanitize_svg.dart';
import '../slides/mermaid_diagram.dart' show MermaidRenderer;

/// Draws a ```mermaid fenced block in the in-app documentation reader, instead
/// of leaving its source sitting as monospace text (which is what the reader did
/// before — the diagrams shipped but were never rendered).
///
/// The reader is a plain vertical scroll of prose, so this widget follows the
/// same grain: the diagram is drawn at its natural, readable size and its block
/// scrolls **horizontally** when it is wider than the column, while its height
/// flows into the document's own vertical scroll. That deliberately avoids
/// nesting a second vertical scroller inside the page (which would fight the
/// page scroll for the same drag) yet still lets a wide flowchart be reached in
/// full.
///
/// Rendering runs on the shared [MermaidRenderService] — the same hidden-WebView
/// engine the slides use, so a diagram looks identical in the reader and on a
/// slide. When it cannot render (most notably under `flutter test`, where there
/// is no WebView, but also a genuine render failure) the widget shows
/// [fallback]: the reader's ordinary code block, so the source is still visible
/// rather than an empty frame.
///
/// Unlike a slide — a fixed white canvas in both app themes, rendered in a
/// theme-less export isolate — the reader is app chrome that follows the
/// light/dark appearance and is never exported. So here, and here alone, the
/// diagram tracks the app theme: in dark mode it renders with Mermaid's dark
/// theme (light strokes on a dark card) instead of dark-on-near-white, which
/// otherwise read as a harsh white card amid the dark prose. The slide renderer
/// ([MermaidDiagram]) deliberately keeps its near-white card regardless.
class DocMermaidView extends StatefulWidget {
  const DocMermaidView({
    super.key,
    required this.source,
    required this.fallback,
    this.dark = false,
    this.renderer,
  });

  /// The Mermaid definition (the text between the ```mermaid fences).
  final String source;

  /// Shown while rendering is impossible or has failed: the same monospace code
  /// block the reader uses for every other fence, so nothing is lost.
  final Widget fallback;

  /// Whether the reader is in dark mode. Drives both the Mermaid theme (a dark
  /// theme with light strokes) and the card colours; `false` keeps the original
  /// near-white card and dark-on-light diagram.
  final bool dark;

  /// Injectable for tests; defaults to the shared [MermaidRenderService].
  final MermaidRenderer? renderer;

  @override
  State<DocMermaidView> createState() => _DocMermaidViewState();
}

class _DocMermaidViewState extends State<DocMermaidView> {
  late Future<String?> _svg;
  final ScrollController _hScroll = ScrollController();

  MermaidRenderer get _render =>
      widget.renderer ?? MermaidRenderService.instance.render;

  /// The definition actually handed to the renderer: in dark mode it carries an
  /// init directive selecting Mermaid's dark theme, so the cache keys the two
  /// theme variants apart and a theme toggle re-renders rather than reusing the
  /// light SVG.
  String get _effectiveSource =>
      widget.dark ? mermaidWithDarkTheme(widget.source) : widget.source;

  @override
  void initState() {
    super.initState();
    _svg = _render(_effectiveSource);
  }

  @override
  void didUpdateWidget(DocMermaidView old) {
    super.didUpdateWidget(old);
    // A different document reuses this element for a new diagram, or the app
    // theme flipped: either way the effective source changes, so re-render.
    if (old.source != widget.source || old.dark != widget.dark) {
      _svg = _render(_effectiveSource);
    }
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _svg,
      builder: (context, snap) {
        final raw = snap.data;
        if (raw != null) {
          final safe = sanitizeMermaidSvg(raw);
          final size = safe == null ? null : _naturalSize(safe);
          // Only draw when we have both a clean SVG and its intrinsic size; a
          // sizeless SVG can't be laid out in the vertical column without a
          // height, so it falls through to the source rather than collapsing.
          if (safe != null && size != null) {
            return _diagram(context, safe, size);
          }
        }
        if (snap.connectionState != ConnectionState.done) return _loading();
        return widget.fallback;
      },
    );
  }

  /// The card backdrop behind the diagram. In light mode a near-white frame the
  /// dark-on-transparent diagram reads on; in dark mode a dark panel the
  /// dark-theme diagram (light strokes) reads on, so the reader shows a diagram
  /// that belongs to the surrounding prose rather than a glaring white cut-out.
  Color get _cardColor =>
      widget.dark ? AppTheme.docMermaidDarkCard : AppTheme.nearWhite;
  Color get _cardBorder =>
      widget.dark ? AppTheme.docMermaidDarkBorder : AppTheme.ghBorder;

  /// A slim, fixed-height frame while the (async) WebView render is in flight,
  /// so the document doesn't jump when the diagram arrives.
  Widget _loading() => Container(
    height: 64,
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: _cardColor,
      border: Border.all(color: _cardBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

  Widget _diagram(BuildContext context, String svg, Size natural) {
    // In light mode the diagram is dark-on-transparent and the frame is
    // near-white; in dark mode it renders with Mermaid's dark theme (light
    // strokes) and the frame is dark — see [_cardColor]. The slide renderer
    // stays near-white in both themes on purpose (a slide is a white canvas,
    // exported theme-lessly); the reader is the one app-themed surface.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardColor,
        border: Border.all(color: _cardBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final picture = SizedBox(
            width: natural.width,
            height: natural.height,
            child: SvgPicture.string(
              svg,
              width: natural.width,
              height: natural.height,
              fit: BoxFit.fill,
            ),
          );
          final overflows = natural.width > constraints.maxWidth + 0.5;
          if (!overflows) {
            // Fits the column: centre it, no scrolling needed.
            return Center(child: picture);
          }
          // Wider than the column: scroll horizontally, with a visible thumb so
          // it reads as scrollable rather than clipped.
          return Scrollbar(
            controller: _hScroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _hScroll,
              scrollDirection: Axis.horizontal,
              child: picture,
            ),
          );
        },
      ),
    );
  }
}

/// Prepends a Mermaid init directive selecting the built-in `dark` theme, so a
/// diagram rendered for the dark reader draws light strokes and text instead of
/// the default dark-on-light. `theme` is deliberately absent from
/// `kMermaidInitConfig`'s `secure` list, so a per-diagram directive may override
/// it without touching the locked-down security posture.
///
/// Skipped when the source already opens with its own directive (`%%{`) or with
/// YAML frontmatter (`---`) — both must stay the first line, and a diagram that
/// sets its own theme keeps it.
String mermaidWithDarkTheme(String source) {
  final head = source.trimLeft();
  if (head.startsWith('%%{') || head.startsWith('---')) return source;
  return '%%{init: {"theme":"dark"}}%%\n$source';
}

/// The diagram's intrinsic pixel size, read from the SVG `viewBox`
/// (`minX minY width height`). Mermaid always emits a `viewBox` and sets the
/// `width`/`height` attributes to `100%`, so the `viewBox` is the only reliable
/// source of the true size. Returns `null` when there is no usable `viewBox`.
Size? _naturalSize(String svg) {
  final match = RegExp(r'viewBox\s*=\s*"([^"]*)"').firstMatch(svg);
  if (match == null) return null;
  final parts = match.group(1)!.trim().split(RegExp(r'[\s,]+'));
  if (parts.length != 4) return null;
  final w = double.tryParse(parts[2]);
  final h = double.tryParse(parts[3]);
  if (w == null || h == null || w <= 0 || h <= 0) return null;
  return Size(w, h);
}
