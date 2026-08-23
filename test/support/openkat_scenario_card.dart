import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:ocideck/models/openkat/openkat_wizard_models.dart';

class OpenKatScenarioCard extends StatefulWidget {
  final OpenKatWizardScenarioAvailability scenario;
  final OpenKatWizardPreviewFacts facts;
  final String title;
  final String description;
  final String recommendedLabel;
  final String selectedLabel;
  final String? unavailableReason;
  final bool selected;
  final ValueChanged<OpenKatWizardScenarioId> onSelected;

  const OpenKatScenarioCard({
    super.key,
    required this.scenario,
    required this.facts,
    required this.title,
    required this.description,
    required this.recommendedLabel,
    required this.selectedLabel,
    required this.selected,
    required this.onSelected,
    this.unavailableReason,
  });

  @override
  State<OpenKatScenarioCard> createState() => _OpenKatScenarioCardState();
}

class _OpenKatScenarioCardState extends State<OpenKatScenarioCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final available = widget.scenario.available;
    final colors = Theme.of(context).colorScheme;
    final focusColor = colors.primary;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 1)
        : const Duration(milliseconds: 190);
    return Semantics(
      container: true,
      button: true,
      checked: widget.selected,
      enabled: available,
      inMutuallyExclusiveGroup: true,
      label: _semanticsLabel(available),
      child: FocusableActionDetector(
        enabled: available,
        mouseCursor: available
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onSelected(widget.scenario.descriptor.id);
              return null;
            },
          ),
        },
        child: AnimatedContainer(
          key: ValueKey(
            'openkat-scenario-${widget.scenario.descriptor.id.name}',
          ),
          duration: duration,
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 250),
          decoration: _cardDecoration(context, available, focusColor),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: available
                  ? () => widget.onSelected(widget.scenario.descriptor.id)
                  : null,
              child: _cardContent(context, available, focusColor),
            ),
          ),
        ),
      ),
    );
  }

  String _semanticsLabel(bool available) => [
    widget.title,
    widget.description,
    if (widget.selected) widget.selectedLabel,
    if (!available && widget.unavailableReason != null)
      widget.unavailableReason!,
  ].join('. ');

  BoxDecoration _cardDecoration(
    BuildContext context,
    bool available,
    Color focusColor,
  ) => BoxDecoration(
    color: widget.selected
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.22)
        : Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: widget.selected || _focused
          ? focusColor
          : _hovered && available
          ? focusColor.withValues(alpha: 0.72)
          : Theme.of(context).colorScheme.outlineVariant,
      width: widget.selected || _focused ? 2 : 1,
    ),
    boxShadow: [
      if (_focused)
        BoxShadow(color: focusColor, spreadRadius: 4, blurRadius: 0),
      if (_focused)
        BoxShadow(
          color: Theme.of(context).colorScheme.surface,
          spreadRadius: 2,
          blurRadius: 0,
        ),
    ],
  );

  Widget _cardContent(BuildContext context, bool available, Color focusColor) =>
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.scenario.descriptor.recommended && available)
                  _Badge(text: widget.recommendedLabel, color: focusColor),
                if (widget.selected)
                  Icon(
                    Icons.check_circle,
                    color: focusColor,
                    semanticLabel: widget.selectedLabel,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ExcludeSemantics(
              child: SizedBox(
                height: 72,
                width: double.infinity,
                child: _ScenarioVisual(
                  kind: widget.scenario.descriptor.previewKind,
                  facts: widget.facts,
                  available: available,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            if (!available && widget.unavailableReason != null)
              _unavailableReason(context),
          ],
        ),
      );

  Widget _unavailableReason(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.lock_outline,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.unavailableReason!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onPrimary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _ScenarioVisual extends StatelessWidget {
  final OpenKatWizardPreviewKind kind;
  final OpenKatWizardPreviewFacts facts;
  final bool available;

  const _ScenarioVisual({
    required this.kind,
    required this.facts,
    required this.available,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = available ? colors.primary : colors.outline;
    final registry = <OpenKatWizardPreviewKind, Widget Function()>{
      OpenKatWizardPreviewKind.summary: () => _Heatmap(
        values: facts.findingsByOrganization.values.toList(),
        color: color,
      ),
      OpenKatWizardPreviewKind.comparison: () => _Heatmap(
        values: facts.findingsByOrganization.values.toList(),
        color: color,
      ),
      OpenKatWizardPreviewKind.trend: () => CustomPaint(
        painter: _TrendPainter(
          values: facts.findingTrend.map((value) => value.toDouble()).toList(),
          color: color,
        ),
      ),
      OpenKatWizardPreviewKind.findings: () => _Heatmap(
        values: facts.findingsByOrganization.values.toList(),
        color: color,
      ),
      OpenKatWizardPreviewKind.systems: () => _NetworkVisual(
        count: math.max(3, math.min(8, facts.organizationCount)),
        color: color,
      ),
      OpenKatWizardPreviewKind.controls: () =>
          _StatusPoints(dates: facts.measurementDates, color: color),
      OpenKatWizardPreviewKind.cve: () => _NetworkVisual(
        count: math.max(3, math.min(8, facts.organizationCount)),
        color: color,
      ),
      OpenKatWizardPreviewKind.monitoring: () =>
          _StatusPoints(dates: facts.measurementDates, color: color),
      OpenKatWizardPreviewKind.accountability: () =>
          _StatusPoints(dates: facts.measurementDates, color: color),
    };
    return registry[kind]!();
  }
}

class _Heatmap extends StatelessWidget {
  final List<int> values;
  final Color color;

  const _Heatmap({required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    final cells = values.isEmpty ? const [0] : values;
    final maxValue = math.max(1, cells.reduce(math.max));
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var index = 0; index < math.min(18, cells.length); index++)
          Container(
            width: 22,
            height: 18,
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: 0.18 + 0.72 * cells[index] / maxValue,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  const _TrendPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final points = values;
    if (points.isEmpty) return;
    final minValue = points.reduce(math.min);
    final maxValue = points.reduce(math.max);
    final range = math.max(1.0, maxValue - minValue);
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final x = size.width * index / math.max(1, points.length - 1);
      final y =
          size.height -
          8 -
          (size.height - 16) * (points[index] - minValue) / range;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(
        Offset(x, y),
        3.2,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _NetworkVisual extends StatelessWidget {
  final int count;
  final Color color;

  const _NetworkVisual({required this.count, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _NetworkPainter(count: count, color: color),
  );
}

class _NetworkPainter extends CustomPainter {
  final int count;
  final Color color;

  const _NetworkPainter({required this.count, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.38;
    final line = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;
    final dot = Paint()..color = color;
    for (var index = 0; index < count; index++) {
      final angle = math.pi * 2 * index / count;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(center, point, line);
      canvas.drawCircle(point, 5, dot);
    }
    canvas.drawCircle(center, 12, dot);
  }

  @override
  bool shouldRepaint(covariant _NetworkPainter oldDelegate) =>
      oldDelegate.count != count || oldDelegate.color != color;
}

class _StatusPoints extends StatelessWidget {
  final List<DateTime> dates;
  final Color color;

  const _StatusPoints({required this.dates, required this.color});

  @override
  Widget build(BuildContext context) {
    final count = math.max(1, math.min(12, dates.length));
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var row = 0; row < 3; row++)
          Row(
            children: [
              for (var index = 0; index < count; index++) ...[
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: color.withValues(
                        alpha: 0.28 + 0.65 * ((index + row) % 3) / 2,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                if (index != count - 1) const SizedBox(width: 5),
              ],
            ],
          ),
      ],
    );
  }
}
