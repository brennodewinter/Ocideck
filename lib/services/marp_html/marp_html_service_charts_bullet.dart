// Part of the marp_html_service library — see ../marp_html_service.dart.
// Split out for navigability (the bullet / target-and-actual chart) and to keep
// marp_html_service_charts.dart under the size ratchet; all imports live in the
// main library file.
part of '../marp_html_service.dart';

/// Norm en prestatie: banden voor de schaal, een meetbalk voor de werkelijke
/// waarde, en een streepje waar de afgesproken norm ligt. Dezelfde vorm als de
/// preview, zodat de HTML-export laat zien wat de editor toonde.
void _bulletSvg(
  StringBuffer b,
  ChartSpec spec,
  double top,
  ThemeProfile? theme,
) {
  const plotLeft = 170.0, right = 770.0, bottom = 382.0;
  final n = spec.x.length;
  if (n == 0 || spec.series.isEmpty) return;
  final maxX = spec.bulletAxisMax;
  final plotW = right - plotLeft;
  double at(double v) => plotLeft + plotW * (v / maxX).clamp(0.0, 1.0);
  for (var g = 0; g <= 4; g++) {
    final x = plotLeft + plotW * g / 4;
    b.write(
      '<text x="$x" y="${bottom + 18}" text-anchor="middle" font-size="13" '
      'fill="#64748b">${_num(maxX * g / 4)}</text>',
    );
  }
  final edges = <double>[...spec.bands]..sort();
  final rowH = (bottom - top) / n;
  final data = spec.series.first.data;
  for (var xi = 0; xi < n; xi++) {
    final rowTop = top + rowH * xi + rowH * 0.12;
    final rowBodyH = rowH * 0.76;
    final label = spec.x[xi].length > 16
        ? '${spec.x[xi].substring(0, 15)}…'
        : spec.x[xi];
    b.write(
      '<text x="${plotLeft - 12}" y="${rowTop + rowBodyH / 2 + 5}" '
      'text-anchor="end" font-size="13" fill="#334155">${_esc(label)}</text>',
    );
    // Banden van donker naar licht: de zwaarste tint is de slechtste zone, dus
    // de meetbalk springt er altijd bovenuit.
    for (var band = 0; band <= edges.length; band++) {
      final x0 = band == 0 ? plotLeft : at(edges[band - 1]);
      final x1 = band == edges.length ? right : at(edges[band]);
      final shade = 226 - (edges.length - band) * 14;
      b.write(
        '<rect x="$x0" y="$rowTop" width="${x1 - x0}" height="$rowBodyH" '
        'fill="rgb($shade,$shade,${shade + 6})"/>',
      );
    }
    final v = xi < data.length ? data[xi] : 0.0;
    b.write(
      '<rect x="$plotLeft" y="${rowTop + rowBodyH * 0.33}" '
      'width="${at(v) - plotLeft}" height="${rowBodyH * 0.34}" rx="3" '
      'fill="${_color(spec, 0, theme)}"/>',
    );
    final target = spec.targetAt(xi);
    if (target != null) {
      b.write(
        '<rect x="${at(target) - 1.5}" y="${rowTop + rowBodyH * 0.12}" '
        'width="3" height="${rowBodyH * 0.76}" fill="#0f172a"/>',
      );
    }
  }
}
