import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/settings.dart';

/// Per-slide bullet-marker override picker. `null` = inherit the theme default
/// ([ThemeProfile.bulletMarker]); otherwise force a dot or a cat-paw on this
/// slide. Only meaningful for plain bullet lists, so callers show it for
/// [ListStyle.bullets] only.
class BulletMarkerSelector extends StatelessWidget {
  final BulletMarker? value;
  final ValueChanged<BulletMarker?> onChanged;

  const BulletMarkerSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const _inherit = 'inherit';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Text(
          l10n.d('Opsommingsteken'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(width: 12),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: _inherit,
              icon: const Icon(Icons.brush_outlined, size: 18),
              label: Text(l10n.d('Thema')),
            ),
            ButtonSegment(
              value: BulletMarker.dot.name,
              icon: const Icon(Icons.fiber_manual_record, size: 12),
              label: Text(l10n.d('Stip')),
            ),
            ButtonSegment(
              value: BulletMarker.paw.name,
              icon: const Icon(Icons.pets, size: 18),
              label: Text(l10n.d('Pootje')),
            ),
          ],
          selected: {value?.name ?? _inherit},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            final picked = selection.first;
            onChanged(
              picked == _inherit ? null : BulletMarker.values.byName(picked),
            );
          },
        ),
      ],
    );
  }
}
