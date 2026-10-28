import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../../utils/log.dart';

/// Meldt in het logbestand wanneer de UI-isolate vastzat (#2618).
///
/// Een periodieke timer hoort elke [tick] te vuren. Kwam hij ruim later
/// ([threshold] bovenop de [tick]), dan was de isolate al die tijd bezig met
/// iets anders — en kon de gebruiker niet typen, klikken of scrollen. De regel
/// noemt de duur en de werklabels die in dat venster zijn gezet
/// ([noteWork]); dat is precies wat een melding als "loopt vast" mist.
///
/// De timer draait op dezelfde isolate, dus hij meldt een vastloper pas als
/// die voorbij is. Een vastloper die nooit voorbijgaat, laat de sessiemarkering
/// van het logbestand liggen; die meldt zich bij de volgende start.
class UiStallWatch {
  UiStallWatch({
    this.tick = const Duration(milliseconds: 250),
    this.threshold = const Duration(milliseconds: 500),
    int Function()? clockMs,
    AppLifecycleState? Function()? lifecycle,
  }) : _now = clockMs ?? (() => logClockMs),
       _lifecycle =
           lifecycle ?? (() => SchedulerBinding.instance.lifecycleState);

  final Duration tick;
  final Duration threshold;
  final int Function() _now;
  final AppLifecycleState? Function() _lifecycle;

  Timer? _timer;
  int _lastTickMs = 0;
  AppLifecycleState? _lastState;

  void start() {
    if (_timer != null) return;
    _lastTickMs = _now();
    _lastState = _lifecycle();
    _timer = Timer.periodic(tick, (_) => check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Eén meting: hoe lang was het sinds de vorige?
  void check() {
    final now = _now();
    final since = _lastTickMs;
    _lastTickMs = now;
    final state = _lifecycle();
    final stateChanged = state != _lastState;
    _lastState = state;
    final gap = now - since;
    if (gap - tick.inMilliseconds < threshold.inMilliseconds) return;
    // Een verborgen of geminimaliseerd venster krijgt van het OS minder
    // timertijd (App Nap op macOS); dat is geen vastloper. Wisselde de toestand
    // in dit venster, dan is de gemeten tijd evenmin te vertrouwen.
    if (stateChanged || !_isActive(state)) return;
    final work = workSince(since);
    logWarning(
      'UI-isolate $gap ms onbereikbaar'
      '${work.isEmpty ? '' : ' — werk: ${work.join(', ')}'}'
      '${gap > 30000 ? ' (of de computer sliep)' : ''}',
    );
  }

  static bool _isActive(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;
}
