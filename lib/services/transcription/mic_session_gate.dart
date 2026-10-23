// Eén microfoon tegelijk (#2516).
//
// De presentatie-doorvoer (#2158) en een opname mogen niet allebei een
// verborgen sessie openen: twee grepen op dezelfde invoer zingen rond via
// de luidsprekers. Deze poort geeft de microfoon aan precies één houder.
// De ander krijgt een weigering met uitleg, geen tweede stream.
enum MicHolder { monitor, recording }

class MicSessionGate {
  MicSessionGate();

  /// De poort die de app deelt. Tests van de opnamebron krijgen een eigen
  /// instantie, zodat ze de presentator niet vasthouden.
  static final instance = MicSessionGate();

  MicHolder? _holder;

  MicHolder? get holder => _holder;

  /// True als [who] de microfoon nu heeft. Een tweede aanvraag van
  /// dezelfde houder slaagt ook — start-tijdens-start mag niet op slot.
  bool tryAcquire(MicHolder who) {
    if (_holder == null || _holder == who) {
      _holder = who;
      return true;
    }
    return false;
  }

  void release(MicHolder who) {
    if (_holder == who) _holder = null;
  }
}

/// Diagnose die de dialoog herkent. Geen zichtbare zin: de UI vertaalt
/// de situatie zelf.
const micHeldByMonitorMessage = 'microfoon-doorvoer bezet de invoer';
