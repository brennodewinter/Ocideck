import '../models/exchange_rate.dart';
import '../models/presentation_cost.dart';
import '../models/rehearsal.dart';
import 'timed_presentation_controller.dart' show MonotonicNow;

final Stopwatch _costClock = Stopwatch()..start();

/// Wat de startschermen (#2436, #2438) bij elkaar leveren om een
/// [PresentationCostSession] te bouwen. Sessiegegevens — gaan nooit richting
/// schijf, export of het publieksscherm.
class CostSessionSeed {
  /// Samengeteld uurtarief van de aanwezigen in kleinste eenheden van de
  /// sessievaluta; `0` bij het vaste groepstarief.
  final int hourlyRateMinor;

  /// De sessie-vaste EUR-koers van de sessievaluta, of `null` bij EUR /
  /// ontbrekende koers.
  final ExchangeRate? eurRate;

  /// Aanwezigen-regels die door een ontbrekende koers buiten het totaal
  /// vielen — het eindoverzicht benoemt ze.
  final int unconvertedAttendees;

  const CostSessionSeed({
    this.hourlyRateMinor = 0,
    this.eurRate,
    this.unconvertedAttendees = 0,
  });
}

/// De lopende kostenberekening van één presentatiesessie (#2435).
///
/// Sessie-only: niets hiervan wordt op schijf bewaard, in export opgenomen of
/// gelogd. De klok is [MonotonicNow] — niet de wandklok — zodat een
/// NTP-sprong het lopende bedrag niet meeneemt.
///
/// Grenzen (zek vastgelegd, zie issue #2435):
/// - **Start**: de teller loopt vanaf [PresentationCostSession.new], dat is
///   ná het invulscherm (#2436) en vóór de eerste dia — de invoer zelf telt
///   dus niet mee als presenteertijd.
/// - **Diawissels en teruggaan**: geen effect; de teller meet sessietijd.
/// - **Pauze** (autoplay-pauze in de presenter): de teller loopt door — de
///   aanwezigen zitten er nog.
/// - **Reset** (toets R): de sessie begint opnieuw bij nul, zoals de
///   oefenklok.
/// - **Voortijdig stoppen**: het eindbedrag is de tijd tot aan het stoppen.
class PresentationCostSession {
  PresentationCostSession({
    required this.currency,
    required this.hourlyRateMinor,
    this.eurRate,
    this.unconvertedAttendees = 0,
    MonotonicNow? now,
  }) : _now = now ?? (() => _costClock.elapsed) {
    _startedAt = _now();
  }

  /// De valuta waarin [hourlyRateMinor] en alle bedragen uitgedrukt zijn.
  final CostCurrency currency;

  /// Som van alle uurtarieven in kleinste eenheden per uur — de
  /// berekeningsbasis van het eindoverzicht ("zoveel per uur × zoveel tijd").
  final int hourlyRateMinor;

  /// De bij de sessiestart vastgelegde koers van [currency] naar EUR (#2438)
  /// — één koersmoment per sessie, zodat lopend bedrag en eindoverzicht
  /// controleerbaar blijven. `null` wanneer de valuta EUR is of toen er geen
  /// koers bekend was; de UI markeert dat als 'koers ontbreekt'.
  final ExchangeRate? eurRate;

  /// Hoeveel aanwezigen-regels niet meetellen omdat hun koers ontbrak —
  /// het eindoverzicht benoemt dat in plaats van stil te doen alsof die
  /// aanwezigen gratis waren.
  final int unconvertedAttendees;

  final MonotonicNow _now;
  late Duration _startedAt;

  /// Verstreken presenteertijd op de monotone klok.
  Duration get elapsed => _now() - _startedAt;

  /// Lopend sessietotaal in kleinste eenheden.
  int get currentCostMinor => costMinorForElapsed(hourlyRateMinor, elapsed);

  /// Kosten voor deelperiode [duration] — voor de uitsplitsing per dia in
  /// het eindoverzicht (tijd per dia × uurtarief).
  int costMinorFor(Duration duration) =>
      costMinorForElapsed(hourlyRateMinor, duration);

  /// [minor] omgerekend naar EUR, of `null` bij een EUR-sessie (overbodig)
  /// of een ontbrekende koers. Dezelfde rekenregel als bij aanwezigen.
  int? eurMinorOf(int minor) {
    if (currency.code == 'EUR') return null;
    return convertAmountMinor(minor, currency, kCostCurrencies.first, {
      ?eurRate?.code: ?eurRate,
    });
  }

  /// Het sessietotaal plus per-dia-kosten, gedeeld met het eindoverzicht.
  CostRun finish() {
    return CostRun(
      hourlyRateMinor: hourlyRateMinor,
      currency: currency,
      elapsed: elapsed,
      eurRate: eurRate,
      unconvertedAttendees: unconvertedAttendees,
    );
  }

  /// Volgnummer van deze run; telt op bij elke [reset]. Het publieksvenster
  /// gebruikt hem om een vertraagd 'costTick' van een oude run te herkennen
  /// — anders zou dat de teller zichtbaar terugzetten (#2437).
  int get runId => _runId;
  int _runId = 0;

  /// Zet de teller terug naar nul; het tarief en de valuta blijven.
  void reset() {
    _startedAt = _now();
    _runId++;
  }
}

/// De eindstand van een kostensessie voor het overzicht (#2437 vult de
/// per-dia-uitsplitsing uit dezelfde getallen).
class CostRun {
  /// Som van de uurtarieven in kleinste eenheden per uur.
  final int hourlyRateMinor;
  final CostCurrency currency;
  final Duration elapsed;

  /// De sessie-vaste koers naar EUR (#2438) — alleen relevant wanneer
  /// [currency] niet EUR is; `null` markeert 'koers ontbreekt'.
  final ExchangeRate? eurRate;

  /// Aantal aanwezigen-regels dat door een ontbrekende koers buiten het
  /// totaal viel.
  final int unconvertedAttendees;

  const CostRun({
    required this.hourlyRateMinor,
    required this.currency,
    required this.elapsed,
    this.eurRate,
    this.unconvertedAttendees = 0,
  });

  /// Totale kosten van de run in kleinste eenheden.
  int get totalMinor => costMinorForElapsed(hourlyRateMinor, elapsed);

  /// [minor] als EUR-equivalent, `null` bij EUR-sessie of ontbrekende koers.
  int? eurMinorOf(int minor) {
    if (currency.code == 'EUR') return null;
    return convertAmountMinor(minor, currency, kCostCurrencies.first, {
      ?eurRate?.code: ?eurRate,
    });
  }

  /// Kosten van één dia op basis van haar gemeten tijd.
  int forSlide(SlideTiming t) => costMinorForElapsed(hourlyRateMinor, t.spent);
}
