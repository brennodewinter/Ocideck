import '../models/presentation_timing.dart';

final Stopwatch _presentationClock = Stopwatch()..start();

typedef MonotonicNow = Duration Function();

/// Driftvrije toestand voor automatisch getimede presentaties.
///
/// De controller plant bewust geen keten van timers. Iedere lezing leidt de
/// dia af uit één monotone tijdlijn; een late UI-tick verschuift daardoor geen
/// enkele volgende dia.
class TimedPresentationController {
  TimedPresentationController({
    required this.config,
    required this.slideCount,
    MonotonicNow? monotonicNow,
  }) : assert(slideCount >= 0),
       _now = monotonicNow ?? (() => _presentationClock.elapsed);

  final PresentationTimingConfig config;
  final int slideCount;
  final MonotonicNow _now;

  Duration _accumulated = Duration.zero;
  Duration? _runningSince;
  bool _started = false;

  bool get hasStarted => _started;
  bool get isPaused => _started && _runningSince == null && !isComplete;
  bool get isRunning => _runningSince != null && !isComplete;

  Duration get elapsed {
    final runningSince = _runningSince;
    final raw = runningSince == null
        ? _accumulated
        : _accumulated + _nonNegative(_now() - runningSince);
    final total = totalDuration;
    if (config.stopAfterLastSlide && raw > total) return total;
    return raw;
  }

  int get effectiveSlideCount {
    final maximum = config.maxSlides;
    return maximum == null || slideCount <= maximum ? slideCount : maximum;
  }

  Duration get totalDuration => config.slideDuration * effectiveSlideCount;

  bool get isComplete =>
      _started &&
      config.stopAfterLastSlide &&
      (effectiveSlideCount == 0 || elapsed >= totalDuration);

  int get currentSlideIndex {
    if (effectiveSlideCount == 0 || config.slideDuration <= Duration.zero) {
      return 0;
    }
    final derived =
        elapsed.inMicroseconds ~/ config.slideDuration.inMicroseconds;
    return derived.clamp(0, effectiveSlideCount - 1);
  }

  Duration get remainingInSlide {
    if (!_started || isComplete || config.slideDuration <= Duration.zero) {
      return Duration.zero;
    }
    final spent = Duration(
      microseconds:
          elapsed.inMicroseconds % config.slideDuration.inMicroseconds,
    );
    return config.slideDuration - spent;
  }

  void start() {
    _accumulated = Duration.zero;
    _runningSince = _now();
    _started = true;
  }

  void pause() {
    final runningSince = _runningSince;
    if (runningSince == null || isComplete) return;
    _accumulated += _nonNegative(_now() - runningSince);
    _runningSince = null;
  }

  void resume() {
    if (!_started || _runningSince != null || isComplete) return;
    _runningSince = _now();
  }

  void reset() {
    _accumulated = Duration.zero;
    _runningSince = null;
    _started = false;
  }
}

Duration _nonNegative(Duration value) =>
    value.isNegative ? Duration.zero : value;
