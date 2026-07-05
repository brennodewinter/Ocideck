import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// A per-slide activation-duration slider shared by the animated-slide editors
/// (cockpit, chart). The value is the duration itself (left = fast, right =
/// slow) with a seconds readout. When the slide inherits the theme's duration
/// ([overrideMs] is null) the readout is muted/italic and the reset button is
/// disabled; dragging the slider starts a per-slide override.
class AnimationDurationControl extends StatelessWidget {
  /// Per-slide override; null = inherit the theme's [themeMs].
  final int? overrideMs;
  final int themeMs;
  final int minMs;
  final int maxMs;

  /// Reports a new override, or null to reset to the theme's duration.
  final ValueChanged<int?> onChanged;

  const AnimationDurationControl({
    super.key,
    required this.overrideMs,
    required this.themeMs,
    required this.minMs,
    required this.maxMs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final inheritsTheme = overrideMs == null;
    final effectiveMs = (overrideMs ?? themeMs).clamp(minMs, maxMs);
    final seconds = effectiveMs / 1000;
    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 18, color: AppTheme.slate500),
        const SizedBox(width: 8),
        Text(
          context.l10n.d('Activatieduur'),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Slider(
            min: minMs.toDouble(),
            max: maxMs.toDouble(),
            divisions: (maxMs - minMs) ~/ 200,
            label: '${seconds.toStringAsFixed(1)}s',
            value: effectiveMs.toDouble(),
            onChanged: (value) => onChanged((value / 100).round() * 100),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            '${seconds.toStringAsFixed(1)}s',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: inheritsTheme ? AppTheme.slate400 : AppTheme.slate500,
              fontStyle: inheritsTheme ? FontStyle.italic : FontStyle.normal,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.restart_alt, size: 18),
          visualDensity: VisualDensity.compact,
          tooltip: context.l10n.d('Volg thema-animatieduur'),
          color: AppTheme.navy,
          onPressed: inheritsTheme ? null : () => onChanged(null),
        ),
      ],
    );
  }
}
