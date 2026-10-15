import 'package:flutter/foundation.dart';

import 'exchange_rate.dart';
import 'presentation_cost.dart';

/// De periode waarover een ingevuld bedrag gaat (#2436).
enum CostPeriod {
  /// Het bedrag ís al het uurtarief — geen omrekening.
  hour,

  /// Maandloon → uurtarief via [CostAssumptions].
  month,

  /// Jaarloon → uurtarief via [CostAssumptions].
  year,
}

/// De aannames waarmee een maand- of jaarsalaris naar een uurtarief wordt
/// omgezet. Zichtbaar en aanpasbaar in het startscherm — OciDeck raadt
/// stilzwijgend geen arbeidscontract.
///
/// `paidHoursPerWeekTenths` staat in tienden van een uur (400 = 40,0 uur) om
/// de rekenkund geheel in [BigInt] te houden: "37,5 uur" is invoer die een
/// float nooit mag zien.
@immutable
class CostAssumptions {
  /// Betaalde werkuren per week, in tienden van een uur.
  final int paidHoursPerWeekTenths;

  /// Betaalde weken per jaar (vakantie is betaald → standaard 52).
  final int weeksPerYear;

  /// Opslag op het loon voor werkgeverslasten, in procenten. `0` = het
  /// ingevoerde bedrag geldt als kostprijs.
  final int employerMarkupPercent;

  const CostAssumptions({
    this.paidHoursPerWeekTenths = 400,
    this.weeksPerYear = 52,
    this.employerMarkupPercent = 0,
  });

  /// Uren per week als leesbaar getal (`40`, `37,5`).
  String get hoursPerWeekLabel {
    final whole = paidHoursPerWeekTenths ~/ 10;
    final tenth = paidHoursPerWeekTenths % 10;
    return tenth == 0 ? '$whole' : '$whole,$tenth';
  }
}

/// Één regel invoer uit het startscherm: bedrag in kleinste eenheden van
/// [currency], over [period]. Namen staan hier bewust niet — het scherm vraagt
/// er niet om en de sessie bewaart ze niet (#2436).
@immutable
class AttendeeInput {
  final int amountMinor;
  final CostPeriod period;
  final CostCurrency currency;

  const AttendeeInput({
    required this.amountMinor,
    required this.period,
    required this.currency,
  });
}

/// Het afgeleide uurtarief van één aanwezige in kleinste eenheden van zijn/haar
/// eigen valuta — hele BigInt-rekenkund, geen floats.
///
/// - `per uur`: het bedrag zelf.
/// - `per maand`: bedrag × 12 / (urenPerWeek × wekenPerJaar).
/// - `per jaar`: bedrag / (urenPerWeek × wekenPerJaar).
///
/// Voor salarissen geldt bovendien de werkgeverslasten-opslag uit
/// [assumptions]; een uurtarief wordt letterlijk genomen. `null` bij nul-
/// werkuren — het scherm valideert dat weg, maar de rekenfunctie verdedigt
/// zichzelf óók als een roepende laag die check mist.
int? hourlyRateMinorFor(AttendeeInput input, CostAssumptions assumptions) {
  if (input.period == CostPeriod.hour) return input.amountMinor;
  final hoursTimesWeeks =
      BigInt.from(assumptions.paidHoursPerWeekTenths) *
      BigInt.from(assumptions.weeksPerYear);
  if (hoursTimesWeeks == BigInt.zero) return null;
  final markup = BigInt.from(100 + assumptions.employerMarkupPercent);
  final hundred = BigInt.from(100);
  final numerator =
      BigInt.from(input.amountMinor) *
      markup *
      (input.period == CostPeriod.month ? BigInt.from(12) : BigInt.one) *
      BigInt.from(10);
  // deler: tienden-van-uur × weken × 100 (de markup is een percentage)
  final denominator = hoursTimesWeeks * hundred;
  return ((numerator + denominator ~/ BigInt.two) ~/ denominator).toInt();
}

/// De vreemde valuta waarvoor de sessie een EUR-koers nodig heeft (#2438):
/// de valuta van aanwezigen-regels die niet in [sessionCurrency] staan, plus
/// de sessievaluta zelf wanneer die niet EUR is (voor de EUR-weergave). EUR
/// heeft nooit een koers nodig — het ís de spil.
List<CostCurrency> currenciesNeedingRate(
  List<AttendeeInput> inputs,
  CostCurrency sessionCurrency,
) {
  final codes = {
    for (final input in inputs)
      if (input.currency.code != sessionCurrency.code) input.currency.code,
    if (sessionCurrency.code != 'EUR') sessionCurrency.code,
  };
  return [
    for (final c in kCostCurrencies)
      if (codes.contains(c.code)) c,
  ];
}

/// Som van de afgeleide uurtarieven in [sessionCurrency]. Regels in een
/// vreemde valuta gaan eerst door de koersen in [rates] (#2438) — zonder
/// koers tellen ze niet mee; dat is zichtbaar via [unconvertedRateCount].
int sumAttendeeRatesMinor(
  List<AttendeeInput> inputs,
  CostAssumptions assumptions,
  CostCurrency sessionCurrency, [
  Map<String, ExchangeRate> rates = const {},
]) {
  var total = 0;
  for (final input in inputs) {
    final derived = hourlyRateMinorFor(input, assumptions);
    if (derived == null) continue;
    total +=
        convertAmountMinor(derived, input.currency, sessionCurrency, rates) ??
        0;
  }
  return total;
}

/// Hoeveel regels niet meetellen omdat hun koers ontbreekt — de sessie toont
/// dat als 'koers ontbreekt' in plaats van stil te doen alsof die
/// aanwezigen gratis waren.
int unconvertedRateCount(
  List<AttendeeInput> inputs,
  CostCurrency sessionCurrency,
  Map<String, ExchangeRate> rates,
) {
  var count = 0;
  for (final input in inputs) {
    if (input.currency.code == sessionCurrency.code) continue;
    if (convertAmountMinor(
          input.amountMinor,
          input.currency,
          sessionCurrency,
          rates,
        ) ==
        null) {
      count++;
    }
  }
  return count;
}
