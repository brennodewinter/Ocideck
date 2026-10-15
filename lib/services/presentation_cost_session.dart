import '../models/presentation_cost.dart';
import '../models/rehearsal.dart';
import 'timed_presentation_controller.dart' show MonotonicNow;

final Stopwatch _costClock = Stopwatch()..start();

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
    MonotonicNow? now,
  }) : _now = now ?? (() => _costClock.elapsed) {
    _startedAt = _now();
  }

  /// De valuta waarin [hourlyRateMinor] en alle bedragen uitgedrukt zijn.
  final CostCurrency currency;

  /// Som van alle uurtarieven in kleinste eenheden per uur — de
  /// berekeningsbasis van het eindoverzicht ("zoveel per uur × zoveel tijd").
  final int hourlyRateMinor;

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

  /// Het sessietotaal plus per-dia-kosten, gedeeld met het eindoverzicht.
  CostRun finish() {
    return CostRun(
      hourlyRateMinor: hourlyRateMinor,
      currency: currency,
      elapsed: elapsed,
    );
  }

  /// Zet de teller terug naar nul; het tarief en de valuta blijven.
  void reset() {
    _startedAt = _now();
  }
}

/// De eindstand van een kostensessie voor het overzicht (#2437 vult de
/// per-dia-uitsplitsing uit dezelfde getallen).
class CostRun {
  /// Som van de uurtarieven in kleinste eenheden per uur.
  final int hourlyRateMinor;
  final CostCurrency currency;
  final Duration elapsed;

  const CostRun({
    required this.hourlyRateMinor,
    required this.currency,
    required this.elapsed,
  });

  /// Totale kosten van de run in kleinste eenheden.
  int get totalMinor => costMinorForElapsed(hourlyRateMinor, elapsed);

  /// Kosten van één dia op basis van haar gemeten tijd.
  int forSlide(SlideTiming t) => costMinorForElapsed(hourlyRateMinor, t.spent);
}
