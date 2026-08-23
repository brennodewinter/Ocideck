// The workspace call rail (`docs/design/NATIVE_CALLS.md` §1, §3). One
// backend-agnostic panel: it renders whatever the active [MeetingSession] holds —
// participant tiles and capability-driven controls — and never learns which
// backend produced it. A Jitsi or (later) MatrixRTC session looks identical here.
//
// F1 has no in-app join flow (that arrives with the first adapter in F3), so with
// no active session the panel shows a plain placeholder; a widget test drives the
// active-call layout with a fake session. Video frames are not rendered yet — a
// tile is a labelled placeholder until `flutter_webrtc` lands and maps a real
// track onto the tile.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../meetings/meeting_event.dart';
import '../../meetings/meeting_participant.dart';
import '../../meetings/meeting_provider.dart';
import '../../state/meeting_session_provider.dart';
import '../../theme/app_theme.dart';

/// The call rail for the workspace row: a divider plus the panel while the module
/// is revealed, otherwise nothing. Kept out of the shell so
/// `app_shell_main_layout.dart` stays under its size ceiling — the shell spreads
/// the result into its row (mirrors `collabChatRail`).
List<Widget> callRail(WidgetRef ref) {
  if (!ref.watch(videoCallsRevealProvider)) return const [];
  return const [
    VerticalDivider(width: 1),
    SizedBox(width: 320, child: CallPanel()),
  ];
}

/// The call panel. Renders the active [MeetingSession] (participants + controls),
/// or a placeholder when no call is running.
class CallPanel extends ConsumerWidget {
  const CallPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(meetingSessionProvider);
    return Container(
      color: AppTheme.paper,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Videovergadering'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: session == null
                ? _CallPlaceholder(l10n: l10n)
                : _ActiveCall(session: session),
          ),
        ],
      ),
    );
  }
}

class _CallPlaceholder extends StatelessWidget {
  const _CallPlaceholder({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        l10n.d(
          'Nog geen actieve vergadering. Het aansluiten op een vergaderdienst wordt in een volgende versie toegevoegd.',
        ),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: AppTheme.slate500),
      ),
    );
  }
}

class _ActiveCall extends ConsumerWidget {
  const _ActiveCall({required this.session});

  final MeetingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild on every session event, reading a fresh snapshot each time — the
    // session object is stable across a call, so watching the provider alone
    // would miss joins/mutes/role changes.
    return StreamBuilder<MeetingEvent>(
      stream: session.events,
      builder: (context, _) {
        final participants = session.participants;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView.separated(
                itemCount: participants.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _ParticipantTile(participants[i]),
              ),
            ),
            const SizedBox(height: 8),
            _CallControls(session: session),
          ],
        );
      },
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile(this.participant);

  final MeetingParticipant participant;

  @override
  Widget build(BuildContext context) {
    final border = participant.isDominantSpeaker
        ? AppTheme.accentFg
        : AppTheme.iceBlue;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            participant.isScreenShare
                ? Icons.screen_share_outlined
                : Icons.person_outline,
            size: 18,
            color: AppTheme.slate600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              participant.displayName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (participant.micMuted)
            Icon(Icons.mic_off_outlined, size: 16, color: AppTheme.slate500),
          if (participant.camOff)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.videocam_off_outlined,
                size: 16,
                color: AppTheme.slate500,
              ),
            ),
        ],
      ),
    );
  }
}

class _CallControls extends ConsumerWidget {
  const _CallControls({required this.session});

  final MeetingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final caps = session.capabilities;
    MeetingParticipant? local;
    for (final p in session.participants) {
      if (p.isLocal) {
        local = p;
        break;
      }
    }
    final muted = local?.micMuted ?? true;
    final camOff = local?.camOff ?? true;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (caps.audio)
          IconButton(
            tooltip: muted ? l10n.d('Dempen opheffen') : l10n.d('Dempen'),
            icon: Icon(muted ? Icons.mic_off_outlined : Icons.mic_outlined),
            onPressed: () => session.setMicrophone(enabled: muted),
          ),
        if (caps.video)
          IconButton(
            tooltip: camOff ? l10n.d('Camera aan') : l10n.d('Camera uit'),
            icon: Icon(
              camOff ? Icons.videocam_off_outlined : Icons.videocam_outlined,
            ),
            onPressed: () => session.setCamera(enabled: camOff),
          ),
        if (caps.screenShare)
          IconButton(
            tooltip: l10n.d('Scherm delen'),
            icon: const Icon(Icons.screen_share_outlined),
            onPressed: session.startScreenShare,
          ),
        IconButton(
          tooltip: l10n.d('Vergadering verlaten'),
          icon: Icon(Icons.call_end_outlined, color: AppTheme.dangerFg),
          onPressed: () => ref.read(meetingSessionProvider.notifier).leave(),
        ),
      ],
    );
  }
}
