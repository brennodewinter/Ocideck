part of '../slide_preview.dart';

class _CockpitPreview extends StatefulWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;
  final CockpitColorScheme scheme;
  final bool presentationMode;

  const _CockpitPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    required this.scheme,
    required this.presentationMode,
  });

  @override
  State<_CockpitPreview> createState() => _CockpitPreviewState();
}

class _CockpitPreviewState extends State<_CockpitPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Parsed cockpit spec, cached so rebuilds (and the per-frame animation)
  /// don't re-parse the cockpit JSON. Re-parsed only when the slide's cockpit
  /// markdown changes.
  late CockpitSpec _spec;

  @override
  void initState() {
    super.initState();
    _spec = CockpitSpec.parse(widget.slide.customMarkdown);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: cockpitDefaultAnimationDurationMs),
      value: 1,
    );
    _maybeStart();
  }

  @override
  void didUpdateWidget(_CockpitPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.id != widget.slide.id ||
        oldWidget.slide.customMarkdown != widget.slide.customMarkdown ||
        oldWidget.profile.animationDurationMs !=
            widget.profile.animationDurationMs ||
        oldWidget.presentationMode != widget.presentationMode) {
      if (oldWidget.slide.customMarkdown != widget.slide.customMarkdown) {
        _spec = CockpitSpec.parse(widget.slide.customMarkdown);
      }
      _maybeStart();
    }
  }

  void _maybeStart() {
    final spec = _spec;
    // null override = inherit the theme's shared activation duration.
    final ms = (spec.animationDurationMs ?? widget.profile.animationDurationMs)
        .clamp(cockpitMinAnimationDurationMs, cockpitMaxAnimationDurationMs);
    _controller.duration = Duration(milliseconds: ms);
    if (widget.presentationMode && spec.animateOnEnter) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    final meters = spec.meters.isEmpty
        ? CockpitSpec.samplePreset().meters
        : spec.meters.take(cockpitMaxMeters).toList();
    final bg = AppTheme.parseHexColor(widget.profile.slideBackgroundColor);
    final accent = AppTheme.parseHexColor(widget.profile.accentColor);
    final textColor = AppTheme.parseHexColor(widget.profile.textColor);
    final pad = widget.w * 0.04;
    final logoSafe = widget.slide.showLogo
        ? _logoSafeInsets(widget.w, widget.profile)
        : EdgeInsets.zero;
    final outerPadding = EdgeInsets.fromLTRB(
      pad + logoSafe.left,
      pad + logoSafe.top,
      pad + logoSafe.right,
      _logoAwareBottomPadding(pad, logoSafe.bottom),
    );
    return Container(
      color: bg,
      padding: outerPadding,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final boot = widget.scheme.visualStyle == CockpitVisualStyle.authentic
              ? _controller.value
              : Curves.easeOutCubic.transform(_controller.value);
          final title = widget.slide.title.trim();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title.isNotEmpty) ...[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: widget.w * 0.036,
                    fontFamily: widget.font,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.none,
                    height: 1.08,
                  ),
                ),
                SizedBox(height: widget.w * 0.022),
              ],
              Expanded(
                child: _CockpitGrid(
                  meters: meters,
                  accent: accent,
                  surface: bg,
                  textColor: textColor,
                  // 0,75 in plaats van 0,62: eenheid en schaalcijfers in
                  // klassiek halen dan AA op de dia-achtergrond.
                  mutedColor: textColor.withValues(alpha: 0.75),
                  scheme: widget.scheme,
                  bootProgress: boot,
                  font: widget.font,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Het instrumentenraster. De rekenkern (`CockpitGridPlan`/`CockpitCellPlan`
/// in services/cockpit_layout.dart) bepaalt cellen, wijzerplaat, venster en
/// label; hier worden de cellen alleen neergezet. Dezelfde rekenkern voedt de
/// SVG van de HTML-export, zodat beide werelden dezelfde indeling tekenen.
class _CockpitGrid extends StatelessWidget {
  final List<CockpitMeterSpec> meters;
  final Color accent;
  final Color surface;
  final Color textColor;
  final Color mutedColor;
  final CockpitColorScheme scheme;
  final double bootProgress;
  final String font;

  const _CockpitGrid({
    required this.meters,
    required this.accent,
    required this.surface,
    required this.textColor,
    required this.mutedColor,
    required this.scheme,
    required this.bootProgress,
    required this.font,
  });

  @override
  Widget build(BuildContext context) {
    final count = meters.length.clamp(1, cockpitMaxMeters);
    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(1.0, constraints.maxWidth);
        final height = math.max(1.0, constraints.maxHeight);
        final gridPlan = CockpitGridPlan.compute(
          count: count,
          width: width,
          height: height,
        );
        final cellPlan = CockpitCellPlan.compute(
          width: gridPlan.cellWidth,
          height: gridPlan.cellHeight,
          longestDigits: cockpitLongestDigits(meters),
        );
        // Eén krimpfactor voor de hele dia, zodat een cel met twee
        // eenheidregels niet als enige een kleiner getal krijgt.
        final readoutScale = cockpitReadoutScale(
          meters,
          cellPlan,
          attitudeTemplate: context.l10n.d('P {pitch}  B {bank}'),
          actualTemplate: context.l10n.d('ACT {value}°'),
          targetTemplate: context.l10n.d('TGT {heading}°'),
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < count; i++)
              Positioned(
                left: gridPlan.cells[i].x,
                top: gridPlan.cells[i].y,
                width: gridPlan.cells[i].w,
                height: gridPlan.cells[i].h,
                child: _CockpitInstrument(
                  meter: meters[i],
                  plan: cellPlan,
                  readoutScale: readoutScale,
                  progress: _stagger(
                    bootProgress,
                    i,
                    count,
                    scheme.visualStyle,
                  ),
                  visualStyle: scheme.visualStyle,
                  accent: accent,
                  surface: surface,
                  textColor: textColor,
                  mutedColor: mutedColor,
                  good: AppTheme.parseHexColor(scheme.good),
                  warning: AppTheme.parseHexColor(scheme.warning),
                  critical: AppTheme.parseHexColor(scheme.critical),
                  cold: AppTheme.parseHexColor(scheme.cold),
                  sky: AppTheme.parseHexColor(scheme.sky),
                  ground: AppTheme.parseHexColor(scheme.ground),
                  font: font,
                ),
              ),
          ],
        );
      },
    );
    if (scheme.visualStyle == CockpitVisualStyle.classic) return grid;
    final palette = AppTheme.cockpitPaletteFor(surface);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.panelBorder, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: grid,
    );
  }

  double _stagger(double t, int index, int count, CockpitVisualStyle style) {
    final delay = count <= 1 ? 0.0 : index * 0.055;
    final scaled = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
    if (style == CockpitVisualStyle.authentic) {
      return Curves.easeInOutCubic.transform(scaled);
    }
    return Curves.easeOutBack.transform(scaled);
  }
}

/// Eén cel: de painter tekent instrument en uitleesvenster; het label is een
/// `Text` in de labelstrook, al door de cascade gehaald (grootte en regelval
/// uit `CockpitCellPlan.fitLabel`), zodat het nooit over de bezel valt.
class _CockpitInstrument extends StatelessWidget {
  final CockpitMeterSpec meter;
  final CockpitCellPlan plan;
  final double readoutScale;
  final double progress;
  final CockpitVisualStyle visualStyle;
  final Color accent;
  final Color surface;
  final Color textColor;
  final Color mutedColor;
  final Color good;
  final Color warning;
  final Color critical;
  final Color cold;
  final Color sky;
  final Color ground;
  final String font;

  const _CockpitInstrument({
    required this.meter,
    required this.plan,
    required this.readoutScale,
    required this.progress,
    required this.visualStyle,
    required this.accent,
    required this.surface,
    required this.textColor,
    required this.mutedColor,
    required this.good,
    required this.warning,
    required this.critical,
    required this.cold,
    required this.sky,
    required this.ground,
    required this.font,
  });

  @override
  Widget build(BuildContext context) {
    final label = meter.label.isEmpty
        ? cockpitMeterTypeLabel(meter.type).toUpperCase()
        : meter.label;
    final fit = plan.fitLabel(label);
    final box = plan.labelBox;
    final labelColor = visualStyle == CockpitVisualStyle.authentic
        ? AppTheme.cockpitPaletteFor(surface).label.withValues(alpha: 0.92)
        : mutedColor;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _CockpitInstrumentPainter(
              meter: meter,
              plan: plan,
              readoutScale: readoutScale,
              progress: progress.clamp(0, 1).toDouble(),
              visualStyle: visualStyle,
              accent: accent,
              surface: surface,
              textColor: textColor,
              mutedColor: mutedColor,
              good: good,
              warning: warning,
              critical: critical,
              cold: cold,
              sky: sky,
              ground: ground,
              font: font,
              faceText: (
                attitude: context.l10n.d('P {pitch}  B {bank}'),
                actual: context.l10n.d('ACT {value}°'),
                target: context.l10n.d('TGT {heading}°'),
              ),
            ),
          ),
        ),
        // In de miniatuur van de slidestrook is een label van een paar pixels
        // alleen een streep; dan liever een eerlijke mini-meter zonder tekst.
        if (fit.size >= cockpitMinTextPx && fit.lines.isNotEmpty)
          Positioned(
            left: box.x,
            top: box.y,
            width: box.w,
            height: box.h,
            child: Center(
              child: Text(
                fit.lines.join('\n'),
                maxLines: fit.lines.length,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: labelColor,
                  fontSize: fit.size,
                  fontFamily: font,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                  height: cockpitLineHeight,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
