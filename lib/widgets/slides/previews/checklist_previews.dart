// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

class _ChecklistProgress extends StatelessWidget {
  final List<String> bullets;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _ChecklistProgress({
    required this.bullets,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final items = bullets
        .where((bullet) => checklistItemText(bullet).trim().isNotEmpty)
        .toList();
    final checked = items.where(checklistItemChecked).length;
    final total = items.length;
    final checkedPercent = total == 0 ? 0 : ((checked / total) * 100).round();
    final openPercent = total == 0 ? 0 : 100 - checkedPercent;
    final textColor = _hexColor(profile.textColor);
    final checkedColor = _hexColor(profile.checklistCheckedColor);
    final openColor = _hexColor(profile.checklistUncheckedColor);
    final labelStyle = _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.0125,
        height: 1.2,
        color: textColor,
        fontWeight: FontWeight.w600,
      ),
    );

    final interaction = _ChecklistInteractionScope.maybeOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Grow the pie to fill the width it is handed instead of staying at a
        // fixed, tiny size. Every caller gives this widget a bounded column
        // width, so the chart now scales with the space that is actually
        // available next to (or above) the bullets.
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : w * 0.4;
        // Cap the pie so it stays a balanced companion to the bullet column
        // rather than dominating it: a smaller chart keeps the visual split
        // closer to 50/50 and, crucially, never forces the surrounding text to
        // shrink to fit the chart's height when a slide has many bullets.
        final diameter = maxW.clamp(w * 0.22, w * 0.30).toDouble();
        final baseRadius = diameter * 0.44;
        final hoverRadius = diameter * 0.48;
        final pieTitleStyle = _applyFont(
          font,
          TextStyle(
            fontSize: diameter * 0.085,
            height: 1.1,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        );

        Widget pie(bool? hovered) => PieChart(
          key: const ValueKey('checklist-progress-pie'),
          PieChartData(
            sectionsSpace: w * 0.002,
            centerSpaceRadius: 0,
            startDegreeOffset: -90,
            sections: [
              if (checkedPercent > 0)
                PieChartSectionData(
                  value: checkedPercent.toDouble(),
                  color: checkedColor,
                  radius: hovered == true ? hoverRadius : baseRadius,
                  title: '$checkedPercent%',
                  titleStyle: pieTitleStyle.copyWith(color: Colors.white),
                ),
              if (openPercent > 0)
                PieChartSectionData(
                  value: openPercent.toDouble(),
                  color: openColor,
                  radius: hovered == false ? hoverRadius : baseRadius,
                  title: '$openPercent%',
                  titleStyle: pieTitleStyle,
                ),
            ],
            pieTouchData: PieTouchData(
              enabled: interaction?.enabled == true,
              touchCallback: (event, response) {
                if (interaction?.enabled != true) return;
                final index = event.isInterestedForInteractions
                    ? response?.touchedSection?.touchedSectionIndex
                    : null;
                if (index == null) {
                  interaction!.hovered.value = null;
                } else if (checkedPercent == 0) {
                  interaction!.hovered.value = false;
                } else {
                  interaction!.hovered.value = index == 0;
                }
              },
            ),
          ),
          duration: Duration.zero,
        );

        return Semantics(
          label:
              '${context.l10n.d('Afgevinkt')} $checkedPercent%, '
              '${context.l10n.d('Niet afgevinkt')} $openPercent%',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: diameter,
                height: diameter,
                child: interaction == null
                    ? pie(null)
                    : ValueListenableBuilder<bool?>(
                        valueListenable: interaction.hovered,
                        builder: (_, hovered, _) => pie(hovered),
                      ),
              ),
              SizedBox(height: w * 0.008),
              MouseRegion(
                key: const ValueKey('checklist-progress-checked'),
                onEnter: interaction?.enabled != true
                    ? null
                    : (_) => interaction!.hovered.value = true,
                onExit: interaction?.enabled != true
                    ? null
                    : (_) => interaction!.hovered.value = null,
                child: Text(
                  '${context.l10n.d('Afgevinkt')} $checkedPercent%',
                  style: labelStyle,
                ),
              ),
              MouseRegion(
                key: const ValueKey('checklist-progress-unchecked'),
                onEnter: interaction?.enabled != true
                    ? null
                    : (_) => interaction!.hovered.value = false,
                onExit: interaction?.enabled != true
                    ? null
                    : (_) => interaction!.hovered.value = null,
                child: Text(
                  '${context.l10n.d('Niet afgevinkt')} $openPercent%',
                  style: labelStyle.copyWith(
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChecklistBulletRow extends StatelessWidget {
  final List<String> bullets;
  final int itemIndex;
  final int column;
  final ListStyle listStyle;
  final bool checked;
  final String text;
  final int level;
  final double fontSize;
  final double bulletSize;
  final double bulletGap;
  final double scale;
  final String font;
  final ThemeProfile profile;

  const _ChecklistBulletRow({
    required this.bullets,
    required this.itemIndex,
    required this.column,
    required this.listStyle,
    required this.checked,
    required this.text,
    required this.level,
    required this.fontSize,
    required this.bulletSize,
    required this.bulletGap,
    required this.scale,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final interaction = _ChecklistInteractionScope.maybeOf(context);
    Widget row(bool highlighted) => AnimatedContainer(
      key: ValueKey('checklist-preview-item-$column-$itemIndex'),
      duration: const Duration(milliseconds: 140),
      padding: EdgeInsets.symmetric(horizontal: highlighted ? wScale(6) : 0),
      decoration: BoxDecoration(
        color: highlighted
            ? _hexColor(profile.accentColor).withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(wScale(5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            key: ValueKey('checklist-preview-toggle-$column-$itemIndex'),
            behavior: HitTestBehavior.opaque,
            onTap:
                listStyle == ListStyle.checklist && interaction?.enabled == true
                ? () => interaction!.onToggle?.call(column, itemIndex)
                : null,
            child: MouseRegion(
              cursor:
                  listStyle == ListStyle.checklist &&
                      interaction?.enabled == true
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              child: Text(
                '${_listMarker(bullets, itemIndex, listStyle)} ',
                style: TextStyle(
                  fontSize: fontSize,
                  color: _hexColor(profile.accentColor),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: _md(
              context,
              text,
              _applyFont(
                font,
                TextStyle(
                  fontSize: fontSize,
                  height: _kBulletLineHeight,
                  color: _hexColor(profile.textColor),
                  decoration: checked && profile.checklistStrikeThrough
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: _hexColor(profile.textColor),
                ),
              ),
              linkColor: _hexColor(profile.accentColor),
            ),
          ),
        ],
      ),
    );

    final padded = Padding(
      padding: EdgeInsets.only(
        left: level * bulletSize * 1.05 * scale,
        top: bulletGap * scale,
        bottom: bulletGap * scale,
      ),
      child: interaction == null || listStyle != ListStyle.checklist
          ? row(false)
          : ValueListenableBuilder<bool?>(
              valueListenable: interaction.hovered,
              builder: (_, hovered, _) => row(hovered == checked),
            ),
    );
    return padded;
  }

  double wScale(double value) => value * scale;
}

class _ChecklistInteractionHost extends StatefulWidget {
  final bool enabled;
  final void Function(int column, int itemIndex)? onToggle;
  final Widget child;

  const _ChecklistInteractionHost({
    required this.enabled,
    required this.onToggle,
    required this.child,
  });

  @override
  State<_ChecklistInteractionHost> createState() =>
      _ChecklistInteractionHostState();
}

class _ChecklistInteractionHostState extends State<_ChecklistInteractionHost> {
  final ValueNotifier<bool?> hovered = ValueNotifier(null);

  @override
  void dispose() {
    hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ChecklistInteractionScope(
      enabled: widget.enabled,
      hovered: hovered,
      onToggle: widget.onToggle,
      child: widget.child,
    );
  }
}

class _ChecklistInteractionScope extends InheritedWidget {
  final bool enabled;
  final ValueNotifier<bool?> hovered;
  final void Function(int column, int itemIndex)? onToggle;

  const _ChecklistInteractionScope({
    required this.enabled,
    required this.hovered,
    required this.onToggle,
    required super.child,
  });

  static _ChecklistInteractionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ChecklistInteractionScope>();

  @override
  bool updateShouldNotify(_ChecklistInteractionScope oldWidget) =>
      enabled != oldWidget.enabled || onToggle != oldWidget.onToggle;
}
