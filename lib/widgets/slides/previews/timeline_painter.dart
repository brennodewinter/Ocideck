part of '../slide_preview.dart';

/// Paints the shared rail, connectors and nodes underneath the event cards.
class _TimelineRailPainter extends CustomPainter {
  final List<_TlNode> nodes;
  final List<_TlSpine> spines;
  final List<double> reveal;
  final double spineProgress;
  final double nodeRadius;

  /// Node of the explicit current point; null = none. That node grows and gets
  /// a halo ring, replacing the size bump the last node gets by default.
  final int? currentIndex;
  final Color accent;
  final Color bg;

  _TimelineRailPainter({
    required this.nodes,
    required this.spines,
    required this.reveal,
    required this.spineProgress,
    required this.nodeRadius,
    required this.currentIndex,
    required this.accent,
    required this.bg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;
    final trackW = math.max(2.0, nodeRadius * 0.42);

    for (final spine in spines) {
      final progress = spines.length == 1 ? spineProgress : 1.0;
      final drawnEnd = Offset.lerp(spine.start, spine.end, progress)!;
      // Faint full-length track so you can see where the timeline is going.
      canvas.drawLine(
        spine.start,
        spine.end,
        Paint()
          ..color = accent.withValues(alpha: 0.16)
          ..strokeWidth = trackW
          ..strokeCap = StrokeCap.round,
      );
      // Soft glow under the drawn portion.
      canvas.drawLine(
        spine.start,
        drawnEnd,
        Paint()
          ..color = accent.withValues(alpha: 0.14)
          ..strokeWidth = nodeRadius * 1.5
          ..strokeCap = StrokeCap.round,
      );
      // Bright drawn spine.
      canvas.drawLine(
        spine.start,
        drawnEnd,
        Paint()
          ..color = accent
          ..strokeWidth = trackW * 1.4
          ..strokeCap = StrokeCap.round,
      );
    }

    // Connectors from each revealed node to its card.
    for (var i = 0; i < nodes.length; i++) {
      final r = reveal[i];
      if (r <= 0.01) continue;
      final node = nodes[i];
      canvas.drawLine(
        node.pos,
        Offset.lerp(node.pos, node.connector, r)!,
        Paint()
          ..color = accent.withValues(alpha: 0.35 * r)
          ..strokeWidth = math.max(1.0, nodeRadius * 0.16),
      );
    }

    // Nodes on top.
    for (var i = 0; i < nodes.length; i++) {
      final r = reveal[i];
      if (r <= 0.01) continue;
      final node = nodes[i];
      final current = i == currentIndex;
      // Without an explicit current point the last node keeps its subtle bump.
      final last = currentIndex == null && i == nodes.length - 1;
      final rad =
          nodeRadius *
          (0.55 + 0.45 * r) *
          (current
              ? 1.35
              : last
              ? 1.18
              : 1.0);
      canvas.drawCircle(
        node.pos,
        rad * 2.1,
        Paint()
          ..color = accent.withValues(
            alpha:
                (current
                    ? 0.24
                    : last
                    ? 0.18
                    : 0.12) *
                r,
          ),
      );
      if (current) {
        // Halo ring: the "you are here" marker around the current node.
        canvas.drawCircle(
          node.pos,
          rad * 1.9,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, rad * 0.28)
            ..color = accent.withValues(alpha: 0.55 * r),
        );
      }
      canvas.drawCircle(node.pos, rad, Paint()..color = accent);
      canvas.drawCircle(
        node.pos,
        rad,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, rad * 0.34)
          ..color = bg,
      );
      canvas.drawCircle(node.pos, rad * 0.32, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_TimelineRailPainter old) =>
      old.spineProgress != spineProgress ||
      !listEquals(old.reveal, reveal) ||
      old.nodeRadius != nodeRadius ||
      old.currentIndex != currentIndex ||
      old.accent != accent ||
      old.bg != bg ||
      old.nodes != nodes ||
      old.spines != spines;
}
