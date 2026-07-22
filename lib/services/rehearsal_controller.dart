import '../models/rehearsal.dart';

/// Meet verstreken tijd, resterende tijd t.o.v. een doeltijd, en de tijd per
/// slide tijdens het presenteren/oefenen.
///
/// Bewust *alleen een klok*: het registreert wandkloktijd en rekent geen
/// pacing-advies uit ("ga sneller/langzamer"). Alles is sessie-only; er wordt
/// niets gepersisteerd.
///
/// De klokbron is injecteerbaar ([now]) zodat de timing in tests deterministisch
/// is — productie gebruikt [DateTime.now].
class RehearsalController {
  RehearsalController({DateTime Function()? now, Duration? target})
    : _now = now ?? DateTime.now,
      _target = (target != null && target > Duration.zero) ? target : null {
    final t = _now();
    _runStart = t;
    _slideEntered = t;
  }

  final DateTime Function() _now;

  Duration? _target;
  late DateTime _runStart;
  late DateTime _slideEntered;
  String? _currentId;

  /// Opgetelde tijd per slide-id over de hele run.
  final Map<String, Duration> _spent = {};

  /// Eerste positie waarop een slide werd gezien (voor stabiele volgorde).
  final Map<String, int> _firstIndex = {};

  /// Volgorde van eerste verschijning, voor een leesbare samenvatting.
  final List<String> _order = [];

  /// Elke beantwoorde vraagpoging, in antwoordvolgorde.
  final List<QuestionAttempt> _questionAttempts = [];

  /// De vraagronde die nu loopt: wanneer ze begon en op welke slide. Null
  /// zolang er geen vraag open staat.
  DateTime? _questionStart;
  String? _questionSlideId;
  int _questionIndex = 0;

  /// Huidige doeltijd, of null als er geen aftelling loopt.
  Duration? get target => _target;

  /// Zet de doeltijd. Een waarde van nul of minder zet de aftelling uit.
  set target(Duration? value) =>
      _target = (value != null && value > Duration.zero) ? value : null;

  /// Verstreken tijd sinds de (her)start van de run.
  Duration get elapsed => _now().difference(_runStart);

  /// Resterende tijd t.o.v. de doeltijd; null zonder doeltijd. Kan negatief
  /// worden wanneer je over de tijd gaat.
  Duration? get remaining {
    final t = _target;
    return t == null ? null : t - elapsed;
  }

  /// Tijd op de huidige slide sinds binnenkomst.
  Duration get currentSlideElapsed => _now().difference(_slideEntered);

  /// Heeft de run genoeg gegevens om een zinvolle samenvatting te tonen?
  /// Voorkomt een dialoog bij het meteen weer sluiten van de presentatie.
  bool get hasMeaningfulData => _order.isNotEmpty && elapsed.inSeconds >= 10;

  /// Registreer dat slide [id] op positie [index] nu zichtbaar is.
  ///
  /// Idempotent: alleen een échte wissel sluit de vorige slide af. Wordt elke
  /// build aangeroepen, dus moet goedkoop blijven.
  void observe(String id, int index) {
    if (_currentId == id) return;
    final t = _now();
    final prev = _currentId;
    if (prev != null) {
      _spent[prev] =
          (_spent[prev] ?? Duration.zero) + t.difference(_slideEntered);
    }
    _currentId = id;
    _slideEntered = t;
    if (!_firstIndex.containsKey(id)) {
      _firstIndex[id] = index;
      _order.add(id);
    }
  }

  /// Registreer dat er een verse vraagronde begint op slide [id] (positie
  /// [index]). Een lopende, onbeantwoorde ronde vervalt daarmee: wie de vraag
  /// verlaat zonder te antwoorden, heeft haar niet beantwoord.
  void startQuestion(String id, int index) {
    _questionSlideId = id;
    _questionIndex = index;
    _questionStart = _now();
  }

  /// Registreer dat de lopende vraagronde beantwoord is. Zonder lopende ronde
  /// gebeurt er niets, zodat een tweede oordeel over dezelfde poging (fout →
  /// vergrendeld, bijvoorbeeld) niet dubbel geteld wordt.
  void finishQuestion({required bool correct}) {
    final start = _questionStart;
    final id = _questionSlideId;
    if (start == null || id == null) return;
    _questionStart = null;
    _questionAttempts.add(
      QuestionAttempt(
        slideId: id,
        index: _questionIndex,
        spent: _now().difference(start),
        correct: correct,
      ),
    );
  }

  /// Reset de hele run (verstreken tijd, per-slide-tijden én vraagpogingen).
  /// De doeltijd blijft staan. De eerstvolgende [observe] registreert de
  /// huidige slide opnieuw.
  void reset() {
    final t = _now();
    _runStart = t;
    _slideEntered = t;
    _spent.clear();
    _firstIndex.clear();
    _order.clear();
    _currentId = null;
    _questionAttempts.clear();
    _questionStart = null;
    _questionSlideId = null;
  }

  /// Sluit de lopende slide af en geef de samenvatting van deze run terug.
  /// Niet-destructief: je kunt erna gewoon doorpresenteren.
  RehearsalRun finish() {
    final t = _now();
    final spent = Map<String, Duration>.from(_spent);
    final cur = _currentId;
    if (cur != null) {
      spent[cur] = (spent[cur] ?? Duration.zero) + t.difference(_slideEntered);
    }
    final perSlide = [
      for (final id in _order)
        SlideTiming(
          slideId: id,
          index: _firstIndex[id] ?? 0,
          spent: spent[id] ?? Duration.zero,
        ),
    ];
    return RehearsalRun(
      total: t.difference(_runStart),
      target: _target,
      perSlide: perSlide,
      questionAttempts: List.unmodifiable(_questionAttempts),
    );
  }
}
