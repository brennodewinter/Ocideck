import 'package:material_ui/material_ui.dart';

import '../../models/attendee_input.dart';
import '../../models/exchange_rate.dart';
import '../../models/presentation_cost.dart';
import '../../services/presentation_cost_session.dart';
import '../dialogs/attendee_rates_dialog.dart';
import '../dialogs/currency_conversion_dialog.dart';

/// Uitkomst van de startschermen van de kostenmodus: de [seed] waarmee de
/// sessie rekent, of [cancelled] wanneer de presentator een scherm
/// annuleerde. Annuleren start de presentatie niet — anders draaide ze met een
/// misleidende nulprijs (#2436).
typedef CostStart = ({CostSessionSeed? seed, bool cancelled});

/// Vraagt vóór de presentatieroute wat de kostenmodus nodig heeft (#2436,
/// #2438). Het publieksscherm bestaat dan nog niet, dus wat hier verschijnt,
/// is alleen voor de presentator zichtbaar.
///
/// - Kostenmodus uit, of de oefenmodus (een soloopvoering): niets te vragen,
///   [CostStart.seed] is `null`.
/// - 'Per aanwezige': het privé-invulscherm met de tarieven.
/// - Een vreemde valuta — van aanwezigen-regels of de sessievaluta zelf —
///   vraagt om één koers per sessie. 'Zonder koers' laat de bedragen als
///   'koers ontbreekt' zichtbaar in plaats van verzonnen.
Future<CostStart> runCostStart(
  BuildContext context,
  PresentationCostConfig config, {
  required bool rehearsalMode,
}) async {
  const none = (seed: null, cancelled: false);
  const cancelled = (seed: null, cancelled: true);
  if (!config.isEnabled || rehearsalMode) return none;

  final sessionCurrency = config.currency;
  var inputs = const <AttendeeInput>[];
  var assumptions = const CostAssumptions();
  if (config.rateInput == CostRateInput.attendees) {
    if (!context.mounted) return cancelled;
    final result = await AttendeeRatesDialog.show(
      context,
      sessionCurrency: sessionCurrency,
    );
    if (result == null) return cancelled;
    inputs = result.attendees;
    assumptions = result.assumptions;
  }

  final needing = currenciesNeedingRate(inputs, sessionCurrency);
  var rates = const <String, ExchangeRate>{};
  if (needing.isNotEmpty) {
    if (!context.mounted) return cancelled;
    final got = await CurrencyConversionDialog.show(
      context,
      currencies: needing,
    );
    if (got == null) return cancelled;
    rates = got;
  }

  final seed = CostSessionSeed(
    hourlyRateMinor: config.rateInput == CostRateInput.group
        ? config.groupHourlyRateMinor
        : sumAttendeeRatesMinor(inputs, assumptions, sessionCurrency, rates),
    eurRate: rates[sessionCurrency.code],
    unconvertedAttendees: unconvertedRateCount(inputs, sessionCurrency, rates),
  );
  return (seed: seed, cancelled: false);
}
