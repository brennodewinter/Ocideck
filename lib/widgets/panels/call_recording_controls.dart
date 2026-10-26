// Opnamebediening in het callpaneel (#2528). De knop staat er alleen als
// de adapter een whole-call-audiobron meldt én de gebruiker de deelnemers
// heeft geïnformeerd. Zonder die bron toont het paneel de reden, geen
// startknop. Het lampje van de provider is een eigen regel: het start
// niets en het is niet de opname van OciDeck.
//
// De live-route (#2530) is dezelfde als bij de microfoon: de opt-in bewijst
// de streaming-capability van de gekozen server zelf, zijn vinkje ís de
// sessieconsent. Zonder vinkje blijft de voorlopige tekst lokaal — audio
// gaat nooit stil weg.
//
// De fase leeft in [callRecordingProvider], niet in deze widget. Het
// paneel kan verdwijnen bij een presentatiewissel; de strook erboven
// blijft de Stop tonen zolang de fase `bezig` is.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../meetings/call_recording.dart';
import '../../meetings/meeting_event.dart';
import '../../meetings/meeting_provider.dart';
import '../../services/transcription/transcription_engine.dart';
import '../../state/call_recording_provider.dart';
import '../../theme/app_theme.dart';
import '../dialogs/live_server_opt_in.dart';

class CallRecordingSection extends ConsumerStatefulWidget {
  const CallRecordingSection({
    super.key,
    required this.session,
    this.probeRunner,
  });

  final MeetingSession session;

  /// Testhaak voor de live-serverproef — productie bouwt de echte.
  final LiveProbeRunner? probeRunner;

  @override
  ConsumerState<CallRecordingSection> createState() =>
      _CallRecordingSectionState();
}

class _CallRecordingSectionState extends ConsumerState<CallRecordingSection> {
  /// De keuze van de live-opt-in — de Start-knop maakt er de
  /// `ServerConsent.liveSession` van (zelfde patroon als de mic-dialoog).
  LiveOptInState _live = const LiveOptInState();

  void _start() {
    ref
        .read(callRecordingProvider.notifier)
        .start(
          liveConsent: _live.chosen
              ? ServerConsent.liveSession(_live.host)
              : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final recorded = ref.watch(callRecordingProvider);
    final connected =
        session.connectionState == MeetingConnectionState.connected;
    final stored = recorded.phase;
    final phase =
        stored == CallRecordingPhase.bezig ||
            stored == CallRecordingPhase.stoppen ||
            stored == CallRecordingPhase.fout
        ? stored
        : restingCallRecordingPhase(
            connected: connected,
            audio: session.capabilities.callAudio,
            noticeAcknowledged: recorded.noticeAcknowledged,
          );
    final offer = offerCallRecording(
      connected: connected,
      audio: session.capabilities.callAudio,
      noticeAcknowledged: recorded.noticeAcknowledged,
      providerIndicatesRecording: recorded.providerIndicatesRecording,
      phase: phase,
    );
    if (!offer.showSection) return const SizedBox.shrink();
    final l10n = context.l10n;
    final notifier = ref.read(callRecordingProvider.notifier);
    final message = _message(l10n, offer.message);
    return Semantics(
      container: true,
      liveRegion:
          recorded.phase == CallRecordingPhase.bezig ||
          recorded.phase == CallRecordingPhase.fout,
      label: message,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.d('Opnemen en transcriberen'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (message.isNotEmpty)
                Text(
                  message,
                  style: TextStyle(fontSize: 11, color: AppTheme.slate600),
                ),
              if (recorded.providerIndicatesRecording)
                Text(
                  l10n.d(
                    'De vergadering meldt zelf een opname. Dat is niet de opname van OciDeck.',
                  ),
                  style: TextStyle(fontSize: 11, color: AppTheme.slate600),
                ),
              if (offer.showNotice)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: recorded.noticeAcknowledged,
                  onChanged: (value) => notifier.setNotice(value ?? false),
                  title: Text(
                    l10n.d('Deelnemers zijn geïnformeerd'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    l10n.d(
                      'Zeg de deelnemers dat OciDeck opneemt. OciDeck vraagt hun toestemming niet zelf.',
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              if (phase == CallRecordingPhase.klaar ||
                  phase == CallRecordingPhase.toestemmingNodig)
                LiveServerOptIn(
                  sourcesLabel: l10n.d('de vergadering'),
                  onChanged: (s) => _live = s,
                  probeRunner: widget.probeRunner,
                ),
              if (offer.showStart)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _start,
                    child: Text(l10n.d('Start opname')),
                  ),
                ),
              if (recorded.phase == CallRecordingPhase.bezig)
                Text(
                  '${l10n.d('Ontvangen brokken:')} ${recorded.capturedChunks}',
                  style: TextStyle(fontSize: 11, color: AppTheme.slate600),
                ),
              if (offer.showStop) const _StopButton(),
              if (offer.showRetry)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: notifier.retry,
                    child: Text(l10n.d('Opnieuw proberen')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Blijft in de bannerkolom staan, ook als het callpaneel er even niet is.
class CallRecordingBanner extends ConsumerWidget {
  const CallRecordingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recorded = ref.watch(callRecordingProvider);
    final show =
        recorded.phase == CallRecordingPhase.bezig ||
        recorded.phase == CallRecordingPhase.stoppen;
    if (!show) return const SizedBox.shrink();
    final l10n = context.l10n;
    final text = recorded.phase == CallRecordingPhase.stoppen
        ? l10n.d('Opname stopt…')
        : l10n.d('OciDeck neemt deze vergadering op.');
    return Semantics(
      liveRegion: true,
      label: text,
      child: Material(
        color: AppTheme.dangerFg.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              Icon(
                Icons.fiber_manual_record,
                size: 14,
                color: AppTheme.dangerFg,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
              const _StopButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StopButton extends ConsumerWidget {
  const _StopButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.d('Opname stoppen'),
      child: ExcludeSemantics(
        child: OutlinedButton(
          onPressed: () => ref.read(callRecordingProvider.notifier).stop(),
          child: Text(l10n.d('Stoppen')),
        ),
      ),
    );
  }
}

String _message(AppLocalizations l10n, CallRecordingMessage message) {
  return switch (message) {
    CallRecordingMessage.none => '',
    CallRecordingMessage.noPerSourceTap => l10n.d(
      'Deze vergadering levert geen aparte audiobron. Een opname van de hele call is niet beschikbaar.',
    ),
    CallRecordingMessage.remoteMissing => l10n.d(
      'Alleen de microfoon is geen opname van de hele call.',
    ),
    CallRecordingMessage.providerForbids => l10n.d(
      'Deze vergadering staat opnemen niet toe. Opname blijft uit.',
    ),
    CallRecordingMessage.consentNeeded => '',
    CallRecordingMessage.ready => l10n.d('Klaar om op te nemen.'),
    CallRecordingMessage.recording => l10n.d(
      'OciDeck neemt deze vergadering op.',
    ),
    CallRecordingMessage.stopping => l10n.d('Opname stopt…'),
    CallRecordingMessage.failed => l10n.d(
      'De opname is mislukt. Je zit nog in de vergadering. Start opnieuw als je wilt opnemen.',
    ),
  };
}
