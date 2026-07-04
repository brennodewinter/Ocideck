import 'package:flutter/material.dart';
import '../../models/annotation.dart';

/// A transparent drawing plane that sits on top of a 16:9 slide canvas. It is
/// used both interactively (presenter laptop) and display-only (beamer).
///
/// All stroke coordinates are normalized to this box (0..1), so the same data
/// renders identically wherever the slide is shown.
class AnnotationLayer extends StatefulWidget {
  /// Committed strokes for the current slide.
  final List<InkStroke> strokes;

  /// Active tool, or null when annotation is off (pointer passes through to the
  /// slide so clicks still advance).
  final InkTool? tool;

  /// Current pen colour (ARGB) and width (fraction of slide width).
  final int color;
  final double width;

  /// Whether this layer captures pointer input (presenter) or only renders
  /// (beamer).
  final bool interactive;

  /// Laser position to display (normalized), used by the beamer.
  final Offset? laserPoint;

  /// Called with the new committed list after a draw or erase.
  final ValueChanged<List<InkStroke>>? onStrokesChanged;

  /// Called as the laser moves (normalized), or null when it leaves.
  final ValueChanged<Offset?>? onLaserMove;

  /// Called as the in-progress stroke grows, so a presenter can mirror the
  /// live drawing to the beamer instead of only the committed result. Carries
  /// the current partial stroke, or null when it commits or is cancelled.
  final ValueChanged<InkStroke?>? onActiveStrokeChanged;

  /// Identifies the surface being drawn on (slide + page). When it changes,
  /// any in-progress stroke and laser point are dropped as a safety net, so a
  /// half-drawn line can never end up on the wrong slide. Navigation paths
  /// call [AnnotationLayerState.commitActiveStroke] first, which commits the
  /// stroke to the old slide instead of losing it.
  final Object? resetToken;

  const AnnotationLayer({
    super.key,
    required this.strokes,
    this.tool,
    this.color = 0xFFEF4444,
    this.width = 0.004,
    this.interactive = false,
    this.laserPoint,
    this.onStrokesChanged,
    this.onLaserMove,
    this.onActiveStrokeChanged,
    this.resetToken,
  });

  @override
  State<AnnotationLayer> createState() => AnnotationLayerState();
}

class AnnotationLayerState extends State<AnnotationLayer> {
  List<Offset> _active = const [];
  Offset? _laser;
  Size _size = Size.zero;

  /// Rond een streek-in-uitvoering nu af (bijv. vlak vóór een slidewissel),
  /// zodat auto-advance of navigatie een half getekende lijn niet weggooit.
  void commitActiveStroke() {
    if (_drawing && _active.isNotEmpty) _commitActive();
  }

  @override
  void didUpdateWidget(AnnotationLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      // Vangnet: op een nieuwe slide/pagina nooit doortekenen met de oude
      // punten. De beamer wist zijn live-preview zelf bij het 'update'-bericht.
      _active = const [];
      _laser = null;
    }
  }

  bool get _drawing =>
      widget.tool == InkTool.pen || widget.tool == InkTool.highlighter;

  /// The in-progress stroke as a committable [InkStroke], or null when there is
  /// nothing being drawn. Used to mirror live drawing to the beamer.
  InkStroke? _activeStroke() {
    if (!_drawing || _active.isEmpty) return null;
    return InkStroke(
      tool: widget.tool!,
      color: widget.color,
      width: widget.width,
      points: List<Offset>.from(_active),
    );
  }

  Offset _norm(Offset local) => _size.shortestSide == 0
      ? Offset.zero
      : Offset(
          (local.dx / _size.width).clamp(0.0, 1.0),
          (local.dy / _size.height).clamp(0.0, 1.0),
        );

  void _commitActive() {
    if (_active.length < 2) {
      setState(() => _active = const []);
      widget.onActiveStrokeChanged?.call(null);
      return;
    }
    final stroke = InkStroke(
      tool: widget.tool!,
      color: widget.color,
      width: widget.width,
      points: List<Offset>.from(_active),
    );
    final next = [...widget.strokes, stroke];
    setState(() => _active = const []);
    widget.onStrokesChanged?.call(next);
    // Clear the beamer's live preview; the committed stroke arrives via strokes.
    widget.onActiveStrokeChanged?.call(null);
  }

  void _eraseAt(Offset norm) {
    const threshold = 0.025;
    final kept = [
      for (final s in widget.strokes)
        if (!s.points.any((p) => (p - norm).distance < threshold)) s,
    ];
    if (kept.length != widget.strokes.length) {
      widget.onStrokesChanged?.call(kept);
    }
  }

  void _down(Offset local) {
    final n = _norm(local);
    switch (widget.tool) {
      case InkTool.pen:
      case InkTool.highlighter:
        setState(() => _active = [n]);
        widget.onActiveStrokeChanged?.call(_activeStroke());
      case InkTool.eraser:
        _eraseAt(n);
      case InkTool.laser:
        setState(() => _laser = n);
        widget.onLaserMove?.call(n);
      case null:
        break;
    }
  }

  void _move(Offset local) {
    final n = _norm(local);
    switch (widget.tool) {
      case InkTool.pen:
      case InkTool.highlighter:
        if (_active.isNotEmpty) {
          setState(() => _active = [..._active, n]);
          widget.onActiveStrokeChanged?.call(_activeStroke());
        }
      case InkTool.eraser:
        _eraseAt(n);
      case InkTool.laser:
        setState(() => _laser = n);
        widget.onLaserMove?.call(n);
      case null:
        break;
    }
  }

  void _up() {
    if (_drawing) _commitActive();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        final painter = CustomPaint(
          size: _size,
          painter: _InkPainter(
            strokes: widget.strokes,
            active: _active,
            activeTool: widget.tool,
            activeColor: widget.color,
            activeWidth: widget.width,
            laser: widget.interactive ? _laser : widget.laserPoint,
          ),
        );

        // Off, or non-interactive: let pointer fall through to the slide.
        if (!widget.interactive || widget.tool == null) {
          return IgnorePointer(child: painter);
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _down(e.localPosition),
          onPointerMove: (e) => _move(e.localPosition),
          onPointerHover: widget.tool == InkTool.laser
              ? (e) => _move(e.localPosition)
              : null,
          onPointerUp: (_) => _up(),
          child: MouseRegion(
            cursor: widget.tool == InkTool.laser
                ? SystemMouseCursors.none
                : SystemMouseCursors.precise,
            onExit: widget.tool == InkTool.laser
                ? (_) {
                    setState(() => _laser = null);
                    widget.onLaserMove?.call(null);
                  }
                : null,
            child: painter,
          ),
        );
      },
    );
  }
}

class _InkPainter extends CustomPainter {
  final List<InkStroke> strokes;
  final List<Offset> active;
  final InkTool? activeTool;
  final int activeColor;
  final double activeWidth;
  final Offset? laser;

  _InkPainter({
    required this.strokes,
    required this.active,
    required this.activeTool,
    required this.activeColor,
    required this.activeWidth,
    required this.laser,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _drawStroke(canvas, size, s.points, s.tool, s.color, s.width);
    }
    if (active.length >= 2 &&
        (activeTool == InkTool.pen || activeTool == InkTool.highlighter)) {
      _drawStroke(canvas, size, active, activeTool!, activeColor, activeWidth);
    }
    if (laser != null) _drawLaser(canvas, size, laser!);
  }

  void _drawStroke(
    Canvas canvas,
    Size size,
    List<Offset> pts,
    InkTool tool,
    int color,
    double width,
  ) {
    if (pts.isEmpty) return;
    final highlighter = tool == InkTool.highlighter;
    final paint = Paint()
      ..color = Color(color).withValues(alpha: highlighter ? 0.35 : 1.0)
      ..strokeWidth = width * size.width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (pts.length < 2) return;
    final path = Path()
      ..moveTo(pts.first.dx * size.width, pts.first.dy * size.height);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx * size.width, pts[i].dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  void _drawLaser(Canvas canvas, Size size, Offset n) {
    final c = Offset(n.dx * size.width, n.dy * size.height);
    final r = size.width * 0.012;
    canvas.drawCircle(
      c,
      r * 2.2,
      Paint()
        ..color = const Color(0xFFFF3B30).withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r),
    );
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFF3B30));
    canvas.drawCircle(
      c,
      r * 0.45,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_InkPainter old) =>
      // Streken- en puntenlijsten worden bij elke wijziging vervangen (nooit
      // in-place gemuteerd), dus een identiteitsvergelijking volstaat en
      // voorkomt hertekenen bij elke onafhankelijke rebuild of laser-tick.
      old.strokes != strokes ||
      old.active != active ||
      old.activeTool != activeTool ||
      old.activeColor != activeColor ||
      old.activeWidth != activeWidth ||
      old.laser != laser;
}
