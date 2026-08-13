import 'package:flutter/widgets.dart';

/// Which element of a chart the pointer is over, in a form small and stable
/// enough to mirror to the audience (beamer) window over a method channel.
///
/// [series] is a series/legend index (bar, line, area, scatter, combo, radar,
/// and every chart that carries the shared legend). [category] is an x-axis or
/// pie/donut-slice index. Either may be null: a legend hover carries only a
/// [series]; a pie-slice hover only a [category]; a bar or point hover carries
/// both. An all-null hover means "nothing" and is normalised away.
@immutable
class ChartHover {
  const ChartHover({this.series, this.category});

  final int? series;
  final int? category;

  bool get isEmpty => series == null && category == null;

  /// Short keys: this crosses a method channel on every pointer move, and the
  /// receiver ([fromJson]) reads the same two letters.
  Map<String, dynamic> toJson() => {'s': series, 'c': category};

  /// Tolerant decode of a channel payload; null for anything that isn't a hover
  /// (a malformed map, or one that decodes to nothing).
  static ChartHover? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final s = (raw['s'] as num?)?.toInt();
    final c = (raw['c'] as num?)?.toInt();
    if (s == null && c == null) return null;
    return ChartHover(series: s, category: c);
  }

  @override
  bool operator ==(Object other) =>
      other is ChartHover &&
      other.series == series &&
      other.category == category;

  @override
  int get hashCode => Object.hash(series, category);

  @override
  String toString() => 'ChartHover(series: $series, category: $category)';
}

/// Shared bus for mirroring a chart's hover between the presenter and the
/// audience (beamer) window, the way [MermaidViewController] mirrors a diagram's
/// view (#930).
///
/// Each window owns one controller. [local] is what THIS window's pointer is
/// over — the bridge listens and forwards it to the other window. [external] is
/// what the OTHER window's pointer is over — the chart shows it when it has no
/// local hover of its own. Applying [external] never touches [local], so the two
/// windows can't echo one another into a feedback loop.
class ChartHoverController extends ChangeNotifier {
  ChartHover? _local;

  /// This window's own pointer hover; the bridge forwards it to the other side.
  ChartHover? get local => _local;

  ChartHover? _external;

  /// The other window's pointer hover; the chart displays it when idle.
  ChartHover? get external => _external;

  /// Reported by the chart when its own pointer hover changes. Normalises an
  /// empty hover to null and skips a no-op so listeners (and the channel) don't
  /// fire for an unchanged value.
  void setLocal(ChartHover? hover) {
    final v = (hover?.isEmpty ?? true) ? null : hover;
    if (v == _local) return;
    _local = v;
    notifyListeners();
  }

  /// Applied from the other window's message; the chart displays it. Passive: it
  /// leaves [local] untouched, so it is never rebroadcast.
  void setExternal(ChartHover? hover) {
    final v = (hover?.isEmpty ?? true) ? null : hover;
    if (v == _external) return;
    _external = v;
    notifyListeners();
  }
}

/// Inherited handle to the [ChartHoverController] for the current slide's chart,
/// mirroring [MermaidRenderScope]. Only the presenter's current-slide canvas and
/// the beamer wrap one; the presenter's next-slide thumbnail deliberately does
/// not, so a thumbnail chart never joins the mirror.
class ChartHoverScope extends InheritedWidget {
  const ChartHoverScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final ChartHoverController controller;

  /// The nearest controller, or null when no scope stands above — then a chart
  /// keeps its hover to itself (editor preview, thumbnails, export).
  static ChartHoverController? of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ChartHoverScope>();
    return scope?.controller;
  }

  @override
  bool updateShouldNotify(ChartHoverScope oldWidget) =>
      controller != oldWidget.controller;
}
