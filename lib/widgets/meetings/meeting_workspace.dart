// Het gespreksvenster: wie er meedoen, en wat je kunt doen (§6.4).
//
// **Elke knop komt uit [MeetingCapabilities] en uit niets anders** (T12).
// Er staat hier geen knop die "meestal wel werkt": kan de adapter het niet, dan
// is de knop er niet — geen grijze knop die suggereert dat het aan de gebruiker
// ligt. Een organisator die halverwege het delen van het scherm intrekt, laat
// die knop dus verdwijnen zónder dat het gesprek eindigt; dat is live toestand,
// geen eigenschap van de sessie.
//
// **`Verlaten` staat er altijd** (§17). Het staat los van de rechten, want
// weggaan is geen gunst van de aanbieder, en het moet in elke fase met het
// toetsenbord te bereiken zijn.
//
// **Wat een vergaderdienst óók doet, staat er bij.** Opname en het uitschrijven
// van het gesprek krijgen een blijvende banier zolang ze lopen (§15) — niet een
// melding die wegtrekt, want het feit blijft gelden zolang de opname loopt.
//
// **Dit venster is niet waar de vergadering "woont".** Het is te sluiten zonder
// weg te gaan: de presentatie is het werk, het gesprek loopt in de omlijsting
// door, en het lampje in de tabbalk brengt je hier terug.
//
// Wat er nog niet in zit, hardop: beeld. Deelnemers staan als tegel met naam en
// toestand, niet als videostroom — het renderen van beeld hangt aan de
// clientlaag en de brug die er nog niet zijn (§10). Dat is de reden dat dit
// venster geen `Deck`/`Speaker`/`Grid`-keuze biedt: die keuze gaat over waar
// beeld terechtkomt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../meetings/meeting_models.dart';
import '../../meetings/meeting_state.dart';
import '../../state/meeting_session_provider.dart';
import '../../theme/app_theme.dart';
import 'meeting_failure_text.dart';

/// Het gespreksvenster als dialoog.
class MeetingWorkspaceDialog extends ConsumerWidget {
  const MeetingWorkspaceDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const MeetingWorkspaceDialog(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(meetingSessionProvider);
    return AlertDialog(
      title: Text(l10n.d('Onlinevergadering')),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PhaseLine(state: state),
            if (state.isRecordingActive || state.isTranscriptionActive) ...[
              const SizedBox(height: 10),
              _RecordingBanner(
                recording: state.isRecordingActive,
                transcribing: state.isTranscriptionActive,
              ),
            ],
            if (state.explicitConsentRequired) ...[
              const SizedBox(height: 10),
              const _ConsentRequest(),
            ],
            const SizedBox(height: 12),
            Flexible(child: _Roster(state: state)),
            const SizedBox(height: 12),
            _Controls(state: state),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Venster sluiten')),
        ),
        if (state.phase == MeetingPhase.ended ||
            state.phase == MeetingPhase.failed)
          FilledButton(
            onPressed: () {
              ref.read(meetingSessionProvider.notifier).reset();
              Navigator.of(context).pop();
            },
            child: Text(l10n.d('Afsluiten')),
          )
        else
          FilledButton(
            // Altijd bereikbaar, ongeacht de rechten (§17).
            onPressed: () => ref.read(meetingSessionProvider.notifier).leave(),
            child: Text(l10n.d('Verlaten')),
          ),
      ],
    );
  }
}

/// Waar het gesprek nu staat, in één regel — en bij een mislukking de uitleg.
class _PhaseLine extends StatelessWidget {
  const _PhaseLine({required this.state});

  final MeetingState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = meetingPhaseLabelOf(state.phase);
    final failure = state.failure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Semantics(
            liveRegion: true,
            child: Text(
              meetingPhaseLabel(l10n, label),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        if (failure != null) ...[
          const SizedBox(height: 4),
          Text(
            meetingFailureText(l10n, failure.kind),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          // De code hoort bij de diagnose, niet bij de uitleg: hij helpt bij
          // het uitzoeken en zegt de gebruiker zelf niets.
          if (failure.code != null)
            Text(
              l10n
                  .d('Technische code: {code}')
                  .replaceAll('{code}', failure.code!),
              style: TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
        ],
      ],
    );
  }
}

/// De blijvende melding dat er opgenomen of uitgeschreven wordt (§15).
///
/// Blijvend en niet wegtrekkend: het feit geldt zolang de opname loopt, en een
/// melding die na drie seconden verdwijnt laat iemand die net terugkomt in de
/// veronderstelling dat er niets loopt.
class _RecordingBanner extends StatelessWidget {
  const _RecordingBanner({required this.recording, required this.transcribing});

  final bool recording;
  final bool transcribing;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final text = recording && transcribing
        ? l10n.d('Deze vergadering wordt opgenomen en uitgeschreven.')
        : recording
        ? l10n.d('Deze vergadering wordt opgenomen.')
        : l10n.d('Deze vergadering wordt uitgeschreven.');
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              Icons.fiber_manual_record,
              size: 14,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// De dienst vraagt uitdrukkelijk toestemming voordat er verder meegedaan mag
/// worden (§15).
///
/// Weigeren is een volwaardig antwoord en staat er daarom als gelijkwaardige
/// keuze bij, niet als klein linkje: wie niet wil dat er opgenomen wordt, hoort
/// weg te kunnen zonder eerst ja te zeggen.
class _ConsentRequest extends ConsumerWidget {
  const _ConsentRequest();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notifier = ref.read(meetingSessionProvider.notifier);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.iceBlue),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'De vergadering vraagt uw uitdrukkelijke toestemming om mee te blijven doen.',
            ),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              FilledButton(
                onPressed: () => notifier.submitRecordingConsent(true),
                child: Text(l10n.d('Toestemming geven')),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => notifier.leave(),
                child: Text(l10n.d('Weigeren en verlaten')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wie er meedoen. Alleen zichtbaar wanneer de adapter de lijst geeft — zonder
/// dat recht is er geen lijst, en dan doet de schil ook niet alsof.
class _Roster extends StatelessWidget {
  const _Roster({required this.state});

  final MeetingState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!state.capabilities.canSeeRoster) {
      return Text(
        l10n.d('Deze vergadering geeft geen deelnemerslijst.'),
        style: TextStyle(fontSize: 12, color: AppTheme.slate500),
      );
    }
    if (state.participants.isEmpty) {
      return Text(
        l10n.d('Nog geen deelnemers.'),
        style: TextStyle(fontSize: 12, color: AppTheme.slate500),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n
              .d('Deelnemers ({aantal})')
              .replaceAll('{aantal}', '${state.participantCount}'),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final participant in state.participants)
                _ParticipantTile(
                  participant: participant,
                  isSpeaking: state.dominantSpeakerId == participant.id,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Eén deelnemer. De naam is platte tekst en al gesnoeid in het domein — hier
/// wordt hij niet opnieuw opgemaakt of als link behandeld.
class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.participant, required this.isSpeaking});

  final MeetingParticipant participant;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            participant.isMuted ? Icons.mic_off : Icons.mic,
            size: 14,
            color: AppTheme.slate500,
          ),
          const SizedBox(width: 6),
          if (participant.hasVideo) ...[
            Icon(Icons.videocam, size: 14, color: AppTheme.slate500),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              participant.displayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSpeaking ? FontWeight.w700 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _roleLabel(l10n, participant.role),
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          ),
        ],
      ),
    );
  }
}

/// De rolnaam in aanbieder-neutrale woorden. Het eigen label van de aanbieder
/// blijft in de diagnose en komt hier niet op het scherm: het is per dienst
/// anders en zegt de gebruiker weinig.
String _roleLabel(AppLocalizations l10n, MeetingRole role) => switch (role) {
  MeetingRole.guest => l10n.d('gast'),
  MeetingRole.attendee => l10n.d('deelnemer'),
  MeetingRole.presenter => l10n.d('presentator'),
  MeetingRole.moderator => l10n.d('moderator'),
  MeetingRole.organiser => l10n.d('organisator'),
  MeetingRole.unknown => l10n.d('rol onbekend'),
};

/// De knoppenbalk — precies de knoppen die de adapter toestaat.
class _Controls extends ConsumerWidget {
  const _Controls({required this.state});

  final MeetingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notifier = ref.read(meetingSessionProvider.notifier);
    final caps = state.capabilities;
    // Buiten een lopend gesprek valt er niets te bedienen; de knoppen zouden
    // dan alleen een gesprek suggereren dat er niet is.
    final live =
        state.phase == MeetingPhase.connected ||
        state.phase == MeetingPhase.reconnecting;
    if (!live) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (caps.allows(MeetingControl.microphone))
          _ControlChip(
            icon: state.isMuted ? Icons.mic_off : Icons.mic,
            label: state.isMuted
                ? l10n.d('Microfoon aanzetten')
                : l10n.d('Microfoon dempen'),
            onPressed: () => notifier.setMicrophone(state.isMuted),
          ),
        if (caps.allows(MeetingControl.camera))
          _ControlChip(
            icon: state.isCameraEnabled
                ? Icons.videocam
                : Icons.videocam_off_outlined,
            label: state.isCameraEnabled
                ? l10n.d('Camera uitzetten')
                : l10n.d('Camera aanzetten'),
            onPressed: () => notifier.setCamera(!state.isCameraEnabled),
          ),
        if (caps.allows(MeetingControl.screenShare))
          _ControlChip(
            icon: state.isScreenSharing
                ? Icons.stop_screen_share_outlined
                : Icons.screen_share_outlined,
            label: state.isScreenSharing
                ? l10n.d('Delen stoppen')
                : l10n.d('Presentatie delen'),
            onPressed: () => notifier.setScreenShare(!state.isScreenSharing),
          ),
      ],
    );
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    label: Text(label, style: const TextStyle(fontSize: 12)),
  );
}
