import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/presentation_cost.dart';

/// De kostenmodus-keuze uit de presentatie-info-dialoog (#2435).
///
/// Wat hier wordt gekozen is een deck-voorkeur en reist mee in de front
/// matter (`ocideck_cost_*`). Wat hier bewust níét kan: individuele
/// tarieven — die vraagt het startscherm (#2436), en ze verdwijnen met de
/// sessie.
class PresentationCostPicker extends StatefulWidget {
  const PresentationCostPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PresentationCostConfig value;
  final ValueChanged<PresentationCostConfig> onChanged;

  @override
  State<PresentationCostPicker> createState() => _PresentationCostPickerState();
}

class _PresentationCostPickerState extends State<PresentationCostPicker> {
  late final TextEditingController _rate;

  @override
  void initState() {
    super.initState();
    final minor = widget.value.groupHourlyRateMinor;
    _rate = TextEditingController(
      text: minor > 0 ? formatCostRateMajor(minor, widget.value.currency) : '',
    );
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  void _emit(PresentationCostConfig config) => widget.onChanged(config);

  void _rateChanged(String text) {
    final minor = parseAmountMinor(text, widget.value.currency);
    if (minor == null) return;
    _emit(widget.value.copyWith(groupHourlyRateMinor: minor));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<PresentationCostMode>(
          key: const ValueKey('cost-mode'),
          initialValue: value.mode,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.d('Kosten van aanwezigen'),
            border: const OutlineInputBorder(),
            helperText: l10n.d(
              'Een schatting van de tijd die aanwezigen kwijt zijn — een indicatie, geen boekhoudkundige kostprijs.',
            ),
          ),
          items: [
            DropdownMenuItem(
              value: PresentationCostMode.off,
              child: Text(l10n.d('Uit')),
            ),
            DropdownMenuItem(
              value: PresentationCostMode.normal,
              child: Text(l10n.d('Gewoon — alleen in het eindoverzicht')),
            ),
            DropdownMenuItem(
              value: PresentationCostMode.explicit,
              child: Text(l10n.d('Expliciet — lopend bedrag én eindoverzicht')),
            ),
          ],
          onChanged: (v) =>
              _emit(value.copyWith(mode: v ?? PresentationCostMode.off)),
        ),
        if (value.isEnabled) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<CostRateInput>(
            key: const ValueKey('cost-input'),
            initialValue: value.rateInput,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.d('Uurtarief'),
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: CostRateInput.group,
                child: Text(l10n.d('Eén tarief voor de hele groep')),
              ),
              DropdownMenuItem(
                value: CostRateInput.attendees,
                child: Text(l10n.d('Per aanwezige, bij de start invullen')),
              ),
            ],
            onChanged: (v) =>
                _emit(value.copyWith(rateInput: v ?? CostRateInput.group)),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: value.rateInput == CostRateInput.group
                    ? TextField(
                        key: const ValueKey('cost-rate'),
                        controller: _rate,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.d('Groepsuurtarief'),
                          helperText: l10n.d(
                            'Kosten = verstreken tijd × tarief.',
                          ),
                        ),
                        onChanged: _rateChanged,
                      )
                    : InputDecorator(
                        decoration: InputDecoration(
                          labelText: l10n.d('Groepsuurtarief'),
                          border: const OutlineInputBorder(),
                        ),
                        child: Text(
                          l10n.d(
                            'Wordt bij de start ingevuld en niet opgeslagen.',
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('cost-currency'),
                  initialValue: value.currencyCode,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.d('Valuta'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in kCostCurrencies)
                      DropdownMenuItem(
                        value: c.code,
                        child: Text('${c.code} ${c.symbol.trim()}'),
                      ),
                  ],
                  onChanged: (v) =>
                      _emit(value.copyWith(currencyCode: v ?? 'EUR')),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
