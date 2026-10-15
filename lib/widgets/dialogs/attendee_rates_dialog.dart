import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/attendee_input.dart';
import '../../models/presentation_cost.dart';

/// Uitkomst van het startscherm: de ingevoerde regels mét de aannames waarmee
/// ze omgerekend zijn — sessiegegevens, nooit bewaard (#2436).
class AttendeeRatesResult {
  final List<AttendeeInput> attendees;
  final CostAssumptions assumptions;

  const AttendeeRatesResult({
    required this.attendees,
    required this.assumptions,
  });
}

/// Het privé-inulscherm vóór de eerste dia bij 'tarieven per aanwezige'
/// (#2436).
///
/// Privé omdat hij op het presentatorscherm verschijnt, vóórdat de
/// presentatie-route — en daarmee het publieksscherm — start. Annuleren
/// (`null`) laat de roeper de presentatie niet beginnen; er bestaat dan
/// geen sessie met een misleidend nul-tarief.
class AttendeeRatesDialog extends StatefulWidget {
  /// De sessievaluta uit de deck-instelling — de rekeneenheid van het totaal.
  final CostCurrency sessionCurrency;

  const AttendeeRatesDialog({super.key, required this.sessionCurrency});

  /// Toont het scherm; `null` bij annuleren.
  static Future<AttendeeRatesResult?> show(
    BuildContext context, {
    required CostCurrency sessionCurrency,
  }) {
    return showDialog<AttendeeRatesResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AttendeeRatesDialog(sessionCurrency: sessionCurrency),
    );
  }

  @override
  State<AttendeeRatesDialog> createState() => _AttendeeRatesDialogState();
}

class _RowState {
  final TextEditingController amount = TextEditingController();
  CostPeriod period = CostPeriod.hour;
  late CostCurrency currency;
  void dispose() => amount.dispose();
}

class _AttendeeRatesDialogState extends State<AttendeeRatesDialog> {
  final List<_RowState> _rows = [];
  late final TextEditingController _hoursPerWeek;
  late final TextEditingController _weeksPerYear;
  late final TextEditingController _markup;

  @override
  void initState() {
    super.initState();
    const d = CostAssumptions();
    _hoursPerWeek = TextEditingController(text: d.hoursPerWeekLabel);
    _weeksPerYear = TextEditingController(text: '${d.weeksPerYear}');
    _markup = TextEditingController(text: '${d.employerMarkupPercent}');
    _addRow();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _hoursPerWeek.dispose();
    _weeksPerYear.dispose();
    _markup.dispose();
    super.dispose();
  }

  void _addRow() {
    setState(() {
      final row = _RowState()..currency = widget.sessionCurrency;
      _rows.add(row);
    });
  }

  /// De aannames zoals ze nu ingevuld staan; `null` bij rotte invoer.
  CostAssumptions? get _assumptions {
    final hours = _parseTenths(_hoursPerWeek.text);
    final weeks = int.tryParse(_weeksPerYear.text.trim());
    final markup = int.tryParse(_markup.text.trim());
    if (hours == null || hours <= 0) return null;
    if (weeks == null || weeks <= 0 || weeks > 366) return null;
    if (markup == null || markup < 0 || markup > 1000) return null;
    return CostAssumptions(
      paidHoursPerWeekTenths: hours,
      weeksPerYear: weeks,
      employerMarkupPercent: markup,
    );
  }

  /// "37,5" / "37.5" → 375 tienden; `null` bij rotte invoer.
  int? _parseTenths(String text) {
    final clean = text.trim().replaceAll(',', '.');
    final match = RegExp(r'^([0-9]+)(?:\.([0-9]))?$').firstMatch(clean);
    if (match == null) return null;
    final whole = int.parse(match.group(1)!);
    final tenth = int.tryParse(match.group(2) ?? '0') ?? 0;
    return whole * 10 + tenth;
  }

  /// Het afgeleide uurtarief van één regel in sessie-eenheden; `null` bij
  /// rotte of lege invoer. Vreemde valuta hoort bij #2438 — daar komt de
  /// omrekening; tot dan telt alleen de sessievaluta mee in het totaal.
  int? _rowRateMinor(_RowState row, CostAssumptions assumptions) {
    final amount = parseAmountMinor(row.amount.text, row.currency);
    if (amount == null) return null;
    return hourlyRateMinorFor(
      AttendeeInput(
        amountMinor: amount,
        period: row.period,
        currency: row.currency,
      ),
      assumptions,
    );
  }

  /// De sessie kan starten zodra minstens één geldige regel staat én geen
  /// enkele regel rot is — ook in een vreemde valuta, die wordt bij de
  /// sessiestart omgerekend (#2438). Leeg-of-rot starten zou een
  /// presentatie met een misleidende nulprijs betekenen (#2436).
  bool get _canStart {
    final assumptions = _assumptions;
    if (assumptions == null) return false;
    var any = false;
    for (final row in _rows) {
      final text = row.amount.text.trim();
      if (text.isEmpty) continue;
      if (_rowRateMinor(row, assumptions) == null) return false;
      any = true;
    }
    return any;
  }

  int get _totalMinor {
    final assumptions = _assumptions;
    if (assumptions == null) return 0;
    return sumAttendeeRatesMinor(
      [
        for (final row in _rows)
          AttendeeInput(
            amountMinor: parseAmountMinor(row.amount.text, row.currency) ?? 0,
            period: row.period,
            currency: row.currency,
          ),
      ],
      assumptions,
      widget.sessionCurrency,
    );
  }

  void _confirm() {
    final assumptions = _assumptions!;
    Navigator.of(context).pop(
      AttendeeRatesResult(
        assumptions: assumptions,
        attendees: [
          for (final row in _rows)
            if (row.amount.text.trim().isNotEmpty)
              AttendeeInput(
                amountMinor: parseAmountMinor(row.amount.text, row.currency)!,
                period: row.period,
                currency: row.currency,
              ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int i, CostAssumptions? assumptions) {
    final l10n = context.l10n;
    final row = _rows[i];
    final rate = assumptions == null ? null : _rowRateMinor(row, assumptions);
    final foreign = row.currency.code != widget.sessionCurrency.code;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: TextField(
              key: ValueKey('attendee-amount-$i'),
              controller: row.amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: l10n.d('Bedrag'),
                errorText: row.amount.text.trim().isNotEmpty && rate == null
                    ? ' '
                    : null,
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<CostPeriod>(
              key: ValueKey('attendee-period-$i'),
              initialValue: row.period,
              isDense: true,
              decoration: const InputDecoration(),
              items: [
                DropdownMenuItem(
                  value: CostPeriod.hour,
                  child: Text(l10n.d('Per uur')),
                ),
                DropdownMenuItem(
                  value: CostPeriod.month,
                  child: Text(l10n.d('Per maand')),
                ),
                DropdownMenuItem(
                  value: CostPeriod.year,
                  child: Text(l10n.d('Per jaar')),
                ),
              ],
              onChanged: (v) =>
                  setState(() => row.period = v ?? CostPeriod.hour),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<String>(
              key: ValueKey('attendee-currency-$i'),
              initialValue: row.currency.code,
              isDense: true,
              decoration: InputDecoration(
                labelText: l10n.d('Valuta'),
                isDense: true,
              ),
              items: [
                for (final c in kCostCurrencies)
                  DropdownMenuItem(value: c.code, child: Text(c.code)),
              ],
              onChanged: (v) => setState(
                () => row.currency =
                    costCurrencyByCode(v ?? 'EUR') ?? kCostCurrencies.first,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                rate == null
                    ? (foreign && row.amount.text.trim().isNotEmpty
                          ? l10n.d('Wordt omgerekend')
                          : '')
                    : '≈ ${formatAmountMinor(rate, row.currency)}'
                          ' ${l10n.d('per uur')}',
                style: const TextStyle(
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.d('Verwijderen'),
            icon: const Icon(Icons.close, size: 18),
            onPressed: _rows.length > 1
                ? () => setState(() => _rows.removeAt(i).dispose())
                : null,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final assumptions = _assumptions;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.groups_outlined, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.d('Aanwezigen en tarieven'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.d(
                    'Vul per aanwezige een uurtarief, maandloon of jaarloon in. Dit blijft op dit scherm en wordt nergens opgeslagen.',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < _rows.length; i++)
                  _row(context, i, assumptions),
                TextButton.icon(
                  key: const ValueKey('attendee-add'),
                  onPressed: _addRow,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.d('Voeg een aanwezige toe')),
                ),
                const Divider(height: 24),
                Text(
                  l10n.d('Aanname voor de omrekening'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('cost-assumption-hours'),
                        controller: _hoursPerWeek,
                        decoration: InputDecoration(
                          labelText: l10n.d('Betaalde uren per week'),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('cost-assumption-weeks'),
                        controller: _weeksPerYear,
                        decoration: InputDecoration(
                          labelText: l10n.d('Weken per jaar'),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('cost-assumption-markup'),
                        controller: _markup,
                        decoration: InputDecoration(
                          labelText: l10n.d('Opslag werkgeverslasten (%)'),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.d(
                    'Bruto of netto maakt hier niet uit — de opslag voor werkgeverslasten staat er los bij.',
                  ),
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 12),
                Text(
                  '${l10n.d('Samen')}: '
                  '${formatAmountMinor(_totalMinor, widget.sessionCurrency)}'
                  ' ${l10n.d('per uur')}',
                  key: const ValueKey('attendee-total'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('attendee-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.d('Annuleren')),
          ),
          FilledButton(
            key: const ValueKey('attendee-start'),
            onPressed: _canStart ? _confirm : null,
            child: Text(l10n.d('Start presentatie')),
          ),
        ],
      ),
    );
  }
}
