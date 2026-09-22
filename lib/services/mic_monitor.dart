// De naad voor live microfoon-doorvoer tijdens het presenteren (#2158): de
// presentator zet hem aan en de microfoon-invoer wordt rechtstreeks op de
// audio-uitvoer weergegeven — laptop plus speakers/beamer zijn dan een kleine
// versterker voor de stem.
//
// Zelfde vorm als de meetings-media-naad (`lib/meetings/meeting_media_core.dart`):
// de interface en elke toetsbare beslissing wonen hier; de enige echte binding
// (`mic_monitor_webrtc.dart`) blijft bewust dun en wordt live geverifieerd, niet
// door een unit-test — een microfoon vangen vereist een apparaat.
//
// Privacy is hier eenvoudig omdat de belofte eenvoudig is: doorvoer, geen
// opname, geen opslag, geen netwerk. De enige toestemming is de OS-prompt op
// het moment dat de presentator de knop aanzet — en die komt er bewust pas dan,
// niet bij het openen van de presentatie.

/// Live microfoon-doorvoer: het standaard invoerapparaat vangen en op het
/// standaard uitvoerapparaat renderen.
abstract interface class MicMonitor {
  /// Of de doorvoer op dit moment loopt.
  bool get running;

  /// Start de doorvoer. Gooit [MicMonitorException] als de microfoon niet
  /// geopend kan worden; een mislukte start laat de monitor volledig gestopt
  /// achter (geen half-open stream).
  Future<void> start();

  /// Stop de doorvoer en geef de microfoon vrij. Idempotent: stoppen op een
  /// gestopte monitor is een no-op, en een stop midden in een lopende [start]
  /// breekt die start alsnog netjes af.
  Future<void> stop();
}

/// De microfoon kon niet geopend worden voor doorvoer. De OS-reden (geen
/// apparaat, geweigerde machtiging, ontbrekende mediastack) is niet betrouwbaar
/// te onderscheiden over de platformen heen, dus doen we niet alsof: de
/// presenter vertaalt dit naar één melding die zegt wat er mis is én waar de
/// gebruiker kan kijken.
class MicMonitorException implements Exception {
  MicMonitorException(this.cause);

  final Object? cause;

  @override
  String toString() => 'MicMonitorException($cause)';
}
