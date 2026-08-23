import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/improvement_y01.dart';
import '../../theme/app_theme.dart';

/// Schakelaar om deck-Y-01 (USL/LSL) te gebruiken i.p.v. lokale limieten.
///
/// Buiten de chart-editor-State gehouden: alleen controllers en callbacks,
/// zodat die State onder het klasseplafond blijft (Y-01-propagatie).
class ChartHistogramY01Controls extends StatelessWidget {
  final AppLocalizations l10n;
  final bool useDeckY01;
  final ImprovementY01Metric deckY01;
  final TextEditingController usl;
  final TextEditingController lsl;
  final TextEditingController processTarget;
  final ValueChanged<bool> onUseDeckY01Changed;

  const ChartHistogramY01Controls({
    super.key,
    required this.l10n,
    required this.useDeckY01,
    required this.deckY01,
    required this.usl,
    required this.lsl,
    required this.processTarget,
    required this.onUseDeckY01Changed,
  });

  @override
  Widget build(BuildContext context) {
    final localLimits =
        usl.text.trim().isNotEmpty || lsl.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.d('Specificatielimieten van Y-01 (deck)'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Switch(value: useDeckY01, onChanged: onUseDeckY01Changed),
            ],
          ),
          if (useDeckY01 && deckY01.hasSpecLimits)
            Text(
              [
                if (deckY01.usl != null) 'USL ${deckY01.usl}',
                if (deckY01.lsl != null) 'LSL ${deckY01.lsl}',
              ].join(' · '),
              style: TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
          if (!useDeckY01 && localLimits && deckY01.hasSpecLimits)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.d(
                  'Dit deck heeft Y-01-limieten. Schakel bovenstaande schakelaar in om die te gebruiken in plaats van lokale waarden.',
                ),
                style: TextStyle(fontSize: 11, color: AppTheme.infoAccent),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lokale USL/LSL/procesdoel-velden wanneer de chart niet aan deck-Y-01 hangt.
class ChartHistogramLocalLimits extends StatelessWidget {
  final AppLocalizations l10n;
  final TextEditingController usl;
  final TextEditingController lsl;
  final TextEditingController processTarget;

  const ChartHistogramLocalLimits({
    super.key,
    required this.l10n,
    required this.usl,
    required this.lsl,
    required this.processTarget,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _limitField(
              key: const ValueKey('chart-usl'),
              controller: usl,
              label: l10n.d('USL (bovengrens, optioneel)'),
              emptyHint: l10n.d('geen'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _limitField(
              key: const ValueKey('chart-lsl'),
              controller: lsl,
              label: l10n.d('LSL (ondergrens, optioneel)'),
              emptyHint: l10n.d('geen'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _limitField(
              key: const ValueKey('chart-process-target'),
              controller: processTarget,
              label: l10n.d('Procesdoel (optioneel)'),
              emptyHint: l10n.d('geen'),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _limitField({
  required Key key,
  required TextEditingController controller,
  required String label,
  required String emptyHint,
}) => TextField(
  key: key,
  controller: controller,
  keyboardType: const TextInputType.numberWithOptions(
    decimal: true,
    signed: true,
  ),
  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
  style: const TextStyle(fontSize: 12),
  decoration: InputDecoration(
    labelText: label,
    labelStyle: TextStyle(fontSize: 12, color: AppTheme.slate500),
    hintText: emptyHint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    border: const OutlineInputBorder(),
  ),
);
