// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability (the bullet / target-and-actual chart) and to keep
// chart_preview_extra.dart under the size ratchet; all imports live in the main
// library file. These _ChartPreviewState chart builders are an extension in the
// same library.
part of '../slide_preview.dart';

extension _ChartPreviewBullet on _ChartPreviewState {
  // ── Bullet: norm en prestatie ────────────────────────────────────────────

  /// Eén rij per label: grijze achtergrondbanden voor de schaal waartegen je
  /// oordeelt, een dunne meetbalk voor de werkelijke waarde, en een streepje
  /// waar de afgesproken norm ligt.
  ///
  /// Het punt van deze vorm is dat de norm als *norm* wordt getekend — een
  /// streepje op de meetlat — en niet als tweede staaf. Bij een SLA-verhaal is
  /// dat het verschil tussen "twee getallen" en "gehaald of niet gehaald".
  /// Zonder streefwaarden zakt hij netjes terug tot een gewone horizontale
  /// staaf, dus een half ingevulde grafiek toont nog steeds iets zinnigs.
  Widget _bulletChart(ChartSpec spec, Color textColor) {
    final n = spec.x.length;
    if (n == 0 || spec.series.isEmpty) {
      return _placeholderText(context.l10n.d('Geen grafiekgegevens'));
    }
    final labelStyle = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.0115 * _labelScale,
        color: textColor.withValues(alpha: 0.88),
        fontWeight: presentationMode ? FontWeight.w600 : FontWeight.normal,
      ),
    );
    return _customGrow((t) {
      return LayoutBuilder(
        builder: (context, c) {
          final labelW = math.max(w * 0.12, c.maxWidth * 0.24);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: labelW,
                child: Column(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: w * 0.008),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              spec.x[i],
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: labelStyle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: _bulletRow(spec, i, textColor, labelStyle, t),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    });
  }

  /// Eén rij: banden, meetbalk, streefstreepje en de waarde erachter.
  Widget _bulletRow(
    ChartSpec spec,
    int i,
    Color textColor,
    TextStyle labelStyle,
    double t,
  ) {
    final maxX = spec.bulletAxisMax;
    final data = spec.series.first.data;
    final value = i < data.length ? data[i] : 0.0;
    final target = spec.targetAt(i);
    final measureColor = _seriesColor(spec.series.first, 0);
    // Banden van donker naar licht, oplopend: de slechtste zone is de zwaarste
    // grijstint, zodat de meetbalk er altijd bovenuit springt.
    final edges = <double>[...spec.bands]..sort();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * 0.004),
      child: LayoutBuilder(
        builder: (context, c) {
          final plotW = c.maxWidth;
          final rowH = c.maxHeight;
          double at(double v) => (v / maxX).clamp(0.0, 1.0) * plotW;
          // Élk kind is gepositioneerd én de stack vult zijn rij: anders krimpt
          // de Stack tot de meetbalk en krijgt iedere rij zijn eigen nulpunt,
          // zodat de banden niet meer onder elkaar liggen.
          return Stack(
            fit: StackFit.expand,
            children: [
              for (var b = 0; b <= edges.length; b++)
                Positioned(
                  left: b == 0 ? 0 : at(edges[b - 1]),
                  width:
                      (b == edges.length ? plotW : at(edges[b])) -
                      (b == 0 ? 0 : at(edges[b - 1])),
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(
                    color: textColor.withValues(
                      alpha: 0.18 - b * (0.12 / (edges.length + 1)),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                top: rowH * 0.33,
                height: rowH * 0.34,
                width: at(value) * t,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: measureColor,
                    borderRadius: BorderRadius.circular(rowH * 0.06),
                  ),
                ),
              ),
              if (target != null)
                Positioned(
                  left: math.max(0.0, at(target) - 1.25),
                  top: rowH * 0.1,
                  height: rowH * 0.8,
                  width: 2.5,
                  child: ColoredBox(color: textColor),
                ),
            ],
          );
        },
      ),
    );
  }
}
