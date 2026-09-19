// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
part of '../fullscreen_presenter.dart';

typedef _TimedSnapshot = ({
  int index,
  double progress,
  int countdown,
  _TimedSessionPhase phase,
  bool audienceChanged,
});

String _timedFormatName(
  AppLocalizations l10n,
  PresentationTimingConfig timing,
) => timing.isIgnite ? l10n.d('Ignite') : l10n.d('PechaKucha');

String _timedReadyLabel(
  AppLocalizations l10n,
  PresentationTimingConfig timing,
) => timing.isIgnite
    ? l10n.d('Ignite klaar om te starten')
    : l10n.d('PechaKucha klaar om te starten');

String _timedFinishedLabel(
  AppLocalizations l10n,
  PresentationTimingConfig timing,
) =>
    timing.isIgnite ? l10n.d('Ignite afgerond') : l10n.d('PechaKucha afgerond');

/// Owns the monotone clock and its small amount of session-only state.
///
/// This deliberately is not an extension on [_FullscreenPresenterState]: the
/// presenter consumes snapshots, while timing remains independently testable.
class _TimedPresentationSession {
  _TimedPresentationSession({
    required this.config,
    required int slideCount,
    required this.onChanged,
  }) : controller = TimedPresentationController(
         config: config,
         slideCount: slideCount,
       );

  final PresentationTimingConfig config;
  final TimedPresentationController controller;
  final ValueChanged<_TimedSnapshot> onChanged;

  _TimedSessionPhase phase = _TimedSessionPhase.ready;
  Timer? _ticker;
  Timer? _countdownTimer;
  int countdown = 3;
  int index = 0;
  double progress = 0;

  Duration get elapsed => controller.elapsed;

  int get secondsRemaining {
    final micros = controller.remainingInSlide.inMicroseconds;
    return micros <= 0 ? 0 : (micros / Duration.microsecondsPerSecond).ceil();
  }

  void prepare() {
    _ticker?.cancel();
    _countdownTimer?.cancel();
    controller.reset();
    phase = _TimedSessionPhase.ready;
    countdown = 3;
    index = 0;
    progress = 0;
    _emit(audienceChanged: true);
  }

  void startCountdown() {
    if (!config.enabled ||
        phase == _TimedSessionPhase.countdown ||
        phase == _TimedSessionPhase.running) {
      return;
    }
    _countdownTimer?.cancel();
    phase = _TimedSessionPhase.countdown;
    countdown = 3;
    index = 0;
    progress = 0;
    _emit(audienceChanged: true);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown > 1) {
        countdown--;
        _emit(audienceChanged: true);
        return;
      }
      timer.cancel();
      controller.start();
      countdown = 0;
      phase = _TimedSessionPhase.running;
      _emit(audienceChanged: true);
      _startTicker();
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  void _tick() {
    if (phase != _TimedSessionPhase.running) return;
    if (controller.isComplete) {
      _ticker?.cancel();
      progress = 1;
      phase = _TimedSessionPhase.finished;
      _emit(audienceChanged: true);
      return;
    }
    final nextIndex = controller.currentSlideIndex;
    final durationUs = config.slideDuration.inMicroseconds;
    final spentUs = durationUs <= 0
        ? 0
        : controller.elapsed.inMicroseconds % durationUs;
    final nextProgress = durationUs <= 0
        ? 0.0
        : (spentUs / durationUs).clamp(0.0, 1.0);
    final changed = nextIndex != index;
    index = nextIndex;
    progress = nextProgress;
    _emit(audienceChanged: changed);
  }

  void togglePause() {
    switch (phase) {
      case _TimedSessionPhase.ready:
      case _TimedSessionPhase.finished:
        startCountdown();
        return;
      case _TimedSessionPhase.countdown:
        return;
      case _TimedSessionPhase.running:
        pauseIfRunning();
        return;
      case _TimedSessionPhase.paused:
        controller.resume();
        phase = _TimedSessionPhase.running;
        _emit(audienceChanged: true);
        return;
    }
  }

  void pauseIfRunning() {
    if (phase != _TimedSessionPhase.running) return;
    controller.pause();
    phase = _TimedSessionPhase.paused;
    _emit(audienceChanged: true);
  }

  void _emit({required bool audienceChanged}) => onChanged((
    index: index,
    progress: progress,
    countdown: countdown,
    phase: phase,
    audienceChanged: audienceChanged,
  ));

  void dispose() {
    _ticker?.cancel();
    _countdownTimer?.cancel();
  }
}

bool _timedManualAdvanceBlocked(_FullscreenPresenterState state) =>
    state.widget.presentationTiming.enabled &&
    !state.widget.presentationTiming.manualAdvance;

void _applyTimedSnapshot(
  _FullscreenPresenterState state,
  _TimedSnapshot snapshot,
) {
  if (!state.mounted) return;
  final next = snapshot.index.clamp(0, state.widget.slides.length - 1);
  final changed = next != state._index;
  state._rebuild(() {
    state._index = next;
    state._progress = snapshot.progress;
    if (changed) {
      state._richTextPage = 0;
      state._menuCategory = 0;
      state._stepIndex = 0;
    }
  });
  if (changed) {
    state._timelineSync.reset();
    state._loadUserNoteIntoController();
    state._precacheNeighbours();
    state._onSlideShown();
    state._announceSlide();
  }
  if (snapshot.audienceChanged) state._syncAudience(force: true);
}

Widget _timedClockBar(_FullscreenPresenterState state) =>
    _TimedClockBar(state: state);

class _TimedClockBar extends StatelessWidget {
  const _TimedClockBar({required this.state});

  final _FullscreenPresenterState state;

  String _clock(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = state._timedSession;
    final paused = session.phase == _TimedSessionPhase.paused;
    final timing = state.widget.presentationTiming;
    final total = timing.durationForSlides(
      timing.requiredSlides ?? state.widget.slides.length,
    );
    final secondsRemaining = session.secondsRemaining;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: paused
            ? AppTheme.amber600.withValues(alpha: 0.14)
            : PresenterPalette.bg2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: paused ? AppTheme.amber600 : PresenterPalette.surface2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                paused ? Icons.pause_circle_outline : Icons.timelapse,
                color: paused ? AppTheme.amber600 : PresenterPalette.laserGreen,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  paused
                      ? l10n.d('GEPAUZEERD')
                      : '${l10n.d('Automatisch')} · '
                            '${l10n.d('handmatig doorgaan uit')}',
                  maxLines: 2,
                  style: TextStyle(
                    color: paused ? AppTheme.amber600 : _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: paused ? 0.8 : 0,
                  ),
                ),
              ),
              IconButton(
                tooltip: paused ? l10n.d('Hervatten') : l10n.d('Pauzeren'),
                onPressed: session.togglePause,
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                color: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: state._metric(
                  l10n.d('Deze slide'),
                  '$secondsRemaining ${l10n.d('sec')}',
                  color: secondsRemaining <= 5
                      ? AppTheme.amber600
                      : Colors.white,
                  size: 28,
                ),
              ),
              state._metric(
                l10n.d('Totaal'),
                '${_clock(session.elapsed)} / ${_clock(total)}',
                color: Colors.white70,
                align: CrossAxisAlignment.end,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: session.progress,
              minHeight: 4,
              backgroundColor: Colors.white12,
              color: secondsRemaining <= 5
                  ? AppTheme.amber600
                  : PresenterPalette.laserGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimedPresentationOverlay extends StatelessWidget {
  const _TimedPresentationOverlay({required this.state});

  final _FullscreenPresenterState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = state._timedSession;
    final timing = state.widget.presentationTiming;
    final countdown = session.phase == _TimedSessionPhase.countdown;
    final finished = session.phase == _TimedSessionPhase.finished;
    final total = timing.durationForSlides(
      timing.requiredSlides ?? state.widget.slides.length,
    );
    final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Semantics(
      container: true,
      liveRegion: countdown,
      label: countdown
          ? '${session.countdown}'
          : finished
          ? _timedFinishedLabel(l10n, timing)
          : _timedReadyLabel(l10n, timing),
      child: ColoredBox(
        color: PresenterPalette.bgDeepest,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.15),
              radius: 0.9,
              colors: [PresenterPalette.bg2, PresenterPalette.bgDeepest],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: countdown
                      ? Text(
                          '${session.countdown}',
                          key: ValueKey(session.countdown),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 112,
                            height: 1,
                            fontWeight: FontWeight.w300,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        )
                      : _TimedReadyCard(
                          timing: timing,
                          finished: finished,
                          slideCount:
                              timing.requiredSlides ??
                              state.widget.slides.length,
                          slideSeconds: timing.slideDuration.inSeconds,
                          total: '${total.inMinutes}:$seconds',
                          onPressed: finished
                              ? () => state._exit(completed: true)
                              : session.startCountdown,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimedReadyCard extends StatelessWidget {
  const _TimedReadyCard({
    required this.timing,
    required this.finished,
    required this.slideCount,
    required this.slideSeconds,
    required this.total,
    required this.onPressed,
  });

  final PresentationTimingConfig timing;
  final bool finished;
  final int slideCount;
  final int slideSeconds;
  final String total;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: ValueKey(finished),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          finished ? Icons.check_circle_outline : Icons.auto_awesome_motion,
          color: PresenterPalette.laserGreen,
          size: 48,
        ),
        const SizedBox(height: 20),
        Text(
          finished
              ? _timedFinishedLabel(l10n, timing)
              : _timedFormatName(l10n, timing),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '$slideCount ${l10n.d('dia\'s')}  ·  '
          '$slideSeconds ${l10n.d('seconden per dia')}  ·  $total',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: PresenterPalette.textMuted,
            fontSize: 16,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 30),
        FilledButton.icon(
          autofocus: true,
          onPressed: onPressed,
          icon: Icon(finished ? Icons.close : Icons.play_arrow_rounded),
          label: Text(finished ? l10n.d('Sluiten') : l10n.d('Start aftellen')),
          style: FilledButton.styleFrom(
            minimumSize: const Size(190, 52),
            backgroundColor: PresenterPalette.laserGreen,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (!finished) ...[
          const SizedBox(height: 18),
          Text(
            l10n.d('Spatie pauzeert · Escape stopt de presentatie'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PresenterPalette.textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}
