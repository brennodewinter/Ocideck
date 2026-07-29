import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/improvement/chart_derivation.dart';
import '../../theme/app_theme.dart';

/// Dialoog die een DOE-ontwerptabel (Yates) in het chart-raster zet.
///
/// Los van [ChartEditor] gehouden: de dialoog is een eigen widget en mag niet
/// meetellen in het klasseplafond van de editor-State.
class DoeDesignDialog extends StatefulWidget {
  const DoeDesignDialog({super.key});

  @override
  State<DoeDesignDialog> createState() => _DoeDesignDialogState();
}

class _DoeDesignDialogState extends State<DoeDesignDialog> {
  int _factors = 3;
  bool _fractional = false;
  int _fraction = 1;

  void _generate() {
    final grid = generateDoeDesignGrid(
      factorCount: _factors,
      fractional: _fractional,
      fraction: _fraction,
    );
    if (grid == null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, grid);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final runs = _fractional ? (1 << (_factors - _fraction)) : (1 << _factors);
    return AlertDialog(
      title: Text(l10n.d('DOE-proefopzet')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Genereert een ontwerptabel met gecodeerde factoren (−1/+1) en een lege Y-kolom in het raster.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(l10n.d('Aantal factoren')),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: _factors,
                  isDense: true,
                  items: [
                    for (var k = 2; k <= 7; k++)
                      DropdownMenuItem(value: k, child: Text('$k')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _factors = v;
                      if (_fraction >= _factors - 1) _fraction = 1;
                    });
                  },
                ),
              ],
            ),
            RadioGroup<bool>(
              groupValue: _fractional,
              onChanged: (v) {
                if (v == null) return;
                if (v && _factors < 3) return;
                setState(() => _fractional = v);
              },
              child: Column(
                children: [
                  RadioListTile<bool>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.d('Volledig factorial (2^k)')),
                    value: false,
                  ),
                  RadioListTile<bool>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.d('Fractioneel (2^(k−p))')),
                    value: true,
                    enabled: _factors >= 3,
                  ),
                ],
              ),
            ),
            if (_fractional && _factors >= 3)
              Row(
                children: [
                  Text(l10n.d('Fractie p')),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _fraction.clamp(1, _factors - 2),
                    isDense: true,
                    items: [
                      for (var p = 1; p <= _factors - 2; p++)
                        DropdownMenuItem(value: p, child: Text('$p')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _fraction = v);
                    },
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              '$runs ${l10n.d('runs in standaard Yates-volgorde')}',
              style: TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: _generate,
          child: Text(l10n.d('In raster zetten')),
        ),
      ],
    );
  }
}
