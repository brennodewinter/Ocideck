// The workspace call rail (`docs/design/NATIVE_CALLS.md` §1, §3). One
// backend-agnostic panel: it renders whatever the active [MeetingSession] holds —
// participant tiles and capability-driven controls — and never learns which
// backend produced it. A Jitsi or (later) MatrixRTC session looks identical here.
//
// With no active session the panel shows a plain placeholder; a live session
// (#2534, adopted into `meetingSessionProvider` by the preflight dialog) fills
// the tiles and controls for real. A participant with a video track renders
// it through `session.videoSurfaceFor` as a Flutter texture (#2535); a
// participant without one keeps the labelled placeholder — never a fake
// frame.

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../meetings/meeting_event.dart';
import '../../meetings/meeting_media_core.dart'
    show MeetingAudioOutput, MeetingVideoSurface;
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
                itemBuilder: (_, i) =>
                    _ParticipantTile(participants[i], session: session),
              ),
            ),
            const SizedBox(height: 6),
            _MediaStatusLine(session: session),
            const SizedBox(height: 8),
            _CallControls(session: session),
          ],
        );
      },
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile(this.participant, {required this.session});

  final MeetingParticipant participant;
  final MeetingSession session;

  @override
  Widget build(BuildContext context) {
    final border = participant.isDominantSpeaker
        ? AppTheme.accentFg
        : AppTheme.iceBlue;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.slate50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Een video-track rendert als texture; geen track → geen vlak,
          // nooit een nepframe. Key op track-id: bij een track-wissel of
          // -einde bouwt de state zijn surface opnieuw op.
          if (participant.video != null)
            _VideoTile(
              key: ValueKey(participant.video!.id),
              session: session,
              participant: participant,
            ),
          Padding(
            padding: const EdgeInsets.all(8),
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (participant.micMuted)
                  Icon(
                    Icons.mic_off_outlined,
                    size: 16,
                    color: AppTheme.slate500,
                  ),
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
          ),
        ],
      ),
    );
  }
}

/// Eén videovlak: haalt een [MeetingVideoSurface] op bij de sessie en rendert
/// de texture; toont een neutraal vlak tot het beeld er is of als attach
/// null geeft (track al weg, platform zonder video).
class _VideoTile extends StatefulWidget {
  const _VideoTile({
    super.key,
    required this.session,
    required this.participant,
  });

  final MeetingSession session;
  final MeetingParticipant participant;

  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  MeetingVideoSurface? _surface;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  Future<void> _attach() async {
    final surface = await widget.session.videoSurfaceFor(widget.participant.id);
    if (!mounted) {
      // Weg voordat de surface er was — wel opruimen, anders lekt de
      // renderer.
      await surface?.dispose();
      return;
    }
    setState(() => _surface = surface);
  }

  @override
  void dispose() {
    unawaited(_surface?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = _surface;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: surface == null
            ? Icon(Icons.person_outline, color: AppTheme.slate500)
            : Texture(textureId: surface.textureId),
      ),
    );
  }
}

/// De eerlijke media-facts onder de tegels: wat we aan E2EE kunnen verifiëren
/// en waar de media heen gaat — beide rechtstreeks uit de sessie (#2535).
/// Nooit meer claimen dan de medialaag meldt.
class _MediaStatusLine extends StatelessWidget {
  const _MediaStatusLine({required this.session});

  final MeetingSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final e2eeText = switch (session.mediaE2ee) {
      MeetingE2eeStatus.on => l10n.d('Media is end-to-end versleuteld.'),
      MeetingE2eeStatus.off => l10n.d('Media is niet end-to-end versleuteld.'),
      MeetingE2eeStatus.unknown => l10n.d(
        'End-to-end-versleuteling van media onbekend.',
      ),
    };
    final egress = session.mediaEgressOrigins;
    final text = egress.isEmpty
        ? e2eeText
        : '$e2eeText ${l10n.d('Media gaat naar')} ${egress.join(', ')}.';
    return Text(text, style: TextStyle(fontSize: 11, color: AppTheme.slate500));
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
        _AudioOutputMenu(session: session),
        IconButton(
          tooltip: l10n.d('Vergadering verlaten'),
          icon: Icon(Icons.call_end_outlined, color: AppTheme.dangerFg),
          onPressed: () => ref.read(meetingSessionProvider.notifier).leave(),
        ),
      ],
    );
  }
}

/// Waar de call-audio heen gaat. Alleen zichtbaar met meer dan één
/// bestemming (#2535) — een enkel device of geen media betekent niets kiezen.
class _AudioOutputMenu extends StatelessWidget {
  const _AudioOutputMenu({required this.session});

  final MeetingSession session;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MeetingAudioOutput>>(
      future: session.audioOutputs(),
      builder: (context, snap) {
        final outputs = snap.data ?? const <MeetingAudioOutput>[];
        if (outputs.length < 2) return const SizedBox.shrink();
        return PopupMenuButton<String>(
          tooltip: context.l10n.d('Audio-uitvoer kiezen'),
          icon: const Icon(Icons.volume_up_outlined),
          onSelected: session.selectAudioOutput,
          itemBuilder: (_) => [
            for (final output in outputs)
              PopupMenuItem(value: output.id, child: Text(output.label)),
          ],
        );
      },
    );
  }
}
