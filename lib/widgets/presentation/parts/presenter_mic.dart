// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Microfoon-doorvoer (#2158): de schakelaar, de knop en de afbraak-garantie.
//
// Alles hier is top-level (hetzelfde patroon als [_handleZoomKey] en
// [_helpOverlayRows]): de klasse-plafondratchet telt elk extension-lid mee bij
// _FullscreenPresenterState, en deze logica hoeft geen lid te zijn — de state
// gaat als parameter mee.
part of '../fullscreen_presenter.dart';

/// Of de doorvoer nu loopt — stuurt het knop-icoon en de "live"-kleur.
bool _micMonitorRunning(_FullscreenPresenterState state) =>
    state._micMonitor?.running ?? false;

/// Mic-invoer rechtstreeks op de audio-uitvoer aan/uit. De monitor wordt pas
/// gebouwd bij de eerste aan-zet: zo verschijnt de OS-machtigingsprompt op het
/// moment dat de presentator hem bewust gebruikt, en nooit daarvoor.
/// [_FullscreenPresenterState._micBusy] dekt de tijd dat de prompt of de opbouw
/// kan duren — een tweede klik of toetsaanslag in die tijd is geen tweede start.
Future<void> _toggleMicMonitor(_FullscreenPresenterState state) async {
  if (state._micBusy) return;
  final monitor = state._micMonitor ??=
      state.widget.micMonitor ?? WebrtcMicMonitor();
  if (monitor.running) {
    await monitor.stop();
    if (state.mounted) state._rebuild(() {});
    return;
  }
  state._micBusy = true;
  try {
    await monitor.start();
    if (state.mounted) state._rebuild(() {});
  } on MicMonitorException catch (e) {
    logWarning('FullscreenPresenter: microfoon-doorvoer starten faalde', e);
    if (state.mounted) _showMicStartFailed(state.context);
  } finally {
    state._micBusy = false;
  }
}

/// De melding bij een mislukte start: wat er mis is én waar de presentator kan
/// kijken (machtiging, invoerapparaat) — de binding kan de OS-reden niet
/// betrouwbaar onderscheiden, dus één eerlijke melding.
void _showMicStartFailed(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.d(
          'De microfoon kon niet worden aangeschakeld. Controleer de machtiging en het invoerapparaat.',
        ),
      ),
    ),
  );
}

/// De knop mag nooit de enige afbraakweg zijn: elke exit (Esc, de sluitknop,
/// een toets van het beamervenster, dispose) moet de mic vrijgeven, zodat de
/// mic-indicator van het OS uit gaat zodra de presentatie eindigt.
void _stopMicMonitor(_FullscreenPresenterState state) =>
    unawaited(state._micMonitor?.stop());

/// De cockpit-knop voor de doorvoer. Top-level, want de klasse-plafondratchet
/// telt elk extension-lid mee bij _FullscreenPresenterState.
Widget _micButton(_FullscreenPresenterState state, AppLocalizations l10n) {
  final active = _micMonitorRunning(state);
  return Tooltip(
    message: l10n.d('Microfoon-doorvoer (V)'),
    child: _NavButton(
      icon: active ? Icons.mic : Icons.mic_none_outlined,
      onTap: () => _toggleMicMonitor(state),
      active: active,
    ),
  );
}
