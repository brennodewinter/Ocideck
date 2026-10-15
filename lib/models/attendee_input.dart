import 'package:flutter/foundation.dart';

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

/// Som van de afgeleide uurtarieven die al in [sessionCurrency] staan.
/// Regels in een vreemde valuta tellen hier niet mee — die worden eerst
/// omgerekend (#2438) voordat ze in het sessietotaal landen.
int sumAttendeeRatesMinor(
  List<AttendeeInput> inputs,
  CostAssumptions assumptions,
  CostCurrency sessionCurrency,
) {
  var total = 0;
  for (final input in inputs) {
    if (input.currency.code != sessionCurrency.code) continue;
    total += hourlyRateMinorFor(input, assumptions) ?? 0;
  }
  return total;
}
