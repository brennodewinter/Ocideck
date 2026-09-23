// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Microfoon-doorvoer (#2158, #2167): de schakelaar, de knoppen en de
// afbraak-garantie.
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
///
/// Elke kant van de wissel meldt zich met een toast: wie met V schakelt terwijl
/// de cockpit verborgen is (enkel scherm), moet toch zien dat het gelukt is.
Future<void> _toggleMicMonitor(_FullscreenPresenterState state) async {
  if (state._micBusy) return;
  final monitor = state._micMonitor ??=
      state.widget.micMonitor ?? WebrtcMicMonitor();
  if (monitor.running) {
    await monitor.stop();
    if (state.mounted) {
      state._rebuild(() {});
      // De toast is voor waar geen knop in beeld blijft: met de cockpit open
      // is de kleurwissel van de knop zelf al de bevestiging.
      if (!state._presenterView) {
        _showMicToast(
          state.context,
          state.context.l10n.d('Microfoon-doorvoer uit'),
        );
      }
    }
    return;
  }
  state._micBusy = true;
  try {
    await monitor.start();
    if (state.mounted) {
      state._rebuild(() {});
      if (!state._presenterView) {
        _showMicToast(
          state.context,
          state.context.l10n.d('Microfoon-doorvoer aan'),
        );
      }
    }
  } on MicMonitorException catch (e) {
    logWarning('FullscreenPresenter: microfoon-doorvoer starten faalde', e);
    if (state.mounted) _showMicStartFailed(state.context);
  } finally {
    state._micBusy = false;
  }
}

/// Korte bevestiging van een staatswissel — ook op de publieksweergave, waar
/// geen knop in beeld blijft staan.
void _showMicToast(BuildContext context, String message) {
  // Twee wissels vlak na elkaar mogen niet in de snackbar-wachtrij komen:
  // vervang de vorige, anders toont hij "aan" terwijl hij alweer uit staat.
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// De foutdialoog bij een mislukte start (#2167): wat er mis is én de route
/// eruit. De binding kan de OS-reden (geweigerde machtiging, geen apparaat,
/// ontbrekende mediastack) niet betrouwbaar onderscheiden, dus de tekst dekt
/// beide en de knop opent — waar het OS dat kent — het paneel waar de
/// presentator het herstelt. Een eenmaal geweigerde machtiging prompt macOS
/// niet opnieuw; zonder die knop zit de presentator vast.
void _showMicStartFailed(BuildContext context) {
  final l10n = context.l10n;
  final canOpenSettings = !kIsWeb && (Platform.isMacOS || Platform.isWindows);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.d('De microfoon kon niet worden aangeschakeld')),
      content: Text(
        l10n.d(
          'Geef OciDeck toegang tot de microfoon in de systeeminstellingen, en controleer dat er een invoerapparaat is aangesloten.',
        ),
      ),
      actions: [
        if (canOpenSettings)
          TextButton(
            onPressed: () => _openMicSystemSettings(),
            child: Text(l10n.d('Open systeeminstellingen')),
          ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.d('Sluiten')),
        ),
      ],
    ),
  );
}

/// Opent het privacy-paneel van het OS waar de microfoonmachtiging leeft. De
/// deep-links zijn vaste strings, geen invoer — en het gaat via `launchUrl`
/// (het platform krijgt de URI direct, zoals bij de licentielink), niet via
/// een subproces dat NetGuard niet kan zien.
Future<void> _openMicSystemSettings() async {
  final uri = Uri.parse(
    Platform.isMacOS
        ? 'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone'
        : 'ms-settings:privacy-microphone',
  );
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    logWarning('FullscreenPresenter: systeeminstellingen openen faalde', e);
  }
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

/// De overlay voor de publieks-Stack: een open microfoon hoort ook zonder
/// hover of cockpit in één blik zichtbaar te zijn — voor de presentator én de
/// zaal. Rechtsboven naast het tabel-potlood (right:20); onderaan zitten de
/// hover-balk en de status-toasts in de weg. Lijst-vorm, zodat de Stack hem
/// met `...` opneemt en het `if` uit de klasse blijft (plafondratchet).
List<Widget> _micBadgeIfRunning(_FullscreenPresenterState state) =>
    _micMonitorRunning(state)
    ? [Positioned(top: 20, right: 76, child: _micLiveBadge(state))]
    : const [];

/// Het blijvende "live"-badge op de publieksweergave (#2167). Alleen zichtbaar
/// zolang de doorvoer loopt — de hover-balk met de knop verdwijnt na drie
/// seconden, maar een open microfoon moet in één blik zichtbaar blijven, ook
/// voor de zaal. Klikken stopt de doorvoer, zoals de E-toets-toggle.
Widget _micLiveBadge(_FullscreenPresenterState state) {
  return Tooltip(
    message: state.context.l10n.d('Microfoon-doorvoer aan (V)'),
    child: Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _toggleMicMonitor(state),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.danger500.withValues(alpha: 0.92),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.85),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.danger500.withValues(alpha: 0.5),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.mic, size: 22, color: Colors.white),
        ),
      ),
    ),
  );
}
