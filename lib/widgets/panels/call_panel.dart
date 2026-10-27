// The workspace call rail (`docs/design/NATIVE_CALLS.md` §1, §3). One
// backend-agnostic panel: it renders whatever the active [MeetingSession] holds —
// participant tiles and capability-driven controls — and never learns which
// backend produced it. A Jitsi or (later) MatrixRTC session looks identical here.
//
// With no active session the panel offers the real join route (#2536): the
// link-check/preflight/join dialog whose *Deelnemen* button adopts the session
// into `meetingSessionProvider` (root-scoped, survives a deck-tab switch). A
// participant with a video track renders it through `session.videoSurfaceFor`
// as a Flutter texture (#2535); a participant without one keeps the labelled
// placeholder — never a fake frame. The connection lifecycle is shown too:
// (re)connecting as a status line, a terminal end as an ended-state the user
// dismisses — a call never silently keeps running or silently disappears.

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../meetings/meeting_event.dart';
import '../../meetings/meeting_media_core.dart'
    show MeetingAudioOutput, MeetingScreenSource, MeetingVideoSurface;
import '../../meetings/meeting_participant.dart';
import '../../meetings/meeting_provider.dart';
import '../../state/call_recording_provider.dart';
import '../../state/meeting_session_provider.dart';
import '../../theme/app_theme.dart';
import '../dialogs/meeting_preflight_dialog.dart';
import '../dialogs/screen_share_picker.dart';
import 'call_recording_controls.dart';

/// Breedte die de callrail in de workspacerij inneemt (320 paneel + 1
/// divider), of 0 wanneer er geen sessie is. De layout trekt dit van de
/// beschikbare breedte af vóórdat hij sliderail en editor verdeelt — zonder
/// die aftrek kreeg de editor bij een actieve call in een smaller venster
/// minder dan zijn minimum en liep zijn inhoud over (#2603).
double callRailWidth(WidgetRef ref) =>
    ref.watch(meetingSessionProvider) != null ? 321 : 0;

/// The call rail for the workspace row: a divider plus the panel while a
/// call exists (live or just ended — a call is never invisible), otherwise
/// nothing. Kept out of the shell so `app_shell_main_layout.dart` stays
/// under its size ceiling — the shell spreads the result into its row
/// (mirrors `collabChatRail`). De join-ingang zit hier níet meer: zonder
/// call bestaat de rail niet, en de appbalkknop opent dezelfde
/// preflight/join-flow (#2603) — de module vreet geen vaste 320px meer
/// voor een functie die je maar af en toe gebruikt.
List<Widget> callRail(WidgetRef ref) {
  if (callRailWidth(ref) == 0) return const [];
  return const [
    VerticalDivider(width: 1),
    SizedBox(width: 320, child: CallPanel()),
  ];
}

/// De vergadering-ingang als appbalkknop — de rail hierboven verschijnt
/// pas zodra er daadwerkelijk een sessie loopt (#2603). Zelfde reveal-
/// regel als voorheen: module aan óf een call live, zodat een actieve
/// vergadering nooit onbereikbaar is. De knop opent dezelfde
/// preflight/join-flow als de rail voorheen deed.
class MeetingJoinButton extends ConsumerWidget {
  const MeetingJoinButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(videoCallsRevealProvider)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: context.l10n.d('Deelnemen aan een vergadering…'),
      icon: const Icon(Icons.video_camera_front_outlined, size: 18),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const MeetingPreflightDialog(),
      ),
    );
  }
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

/// Geen actieve call: niet alleen een mededeling maar de echte ingang — de
/// knop opent de linkcontrole/preflight/join-flow (#2536).
class _CallPlaceholder extends StatelessWidget {
  const _CallPlaceholder({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.d('Nog geen actieve vergadering.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.d('Plak een Jitsi-vergaderlink om deel te nemen.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            icon: const Icon(Icons.video_camera_front_outlined, size: 16),
            label: Text(l10n.d('Deelnemen aan een vergadering…')),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const MeetingPreflightDialog(),
            ),
          ),
        ],
      ),
    );
  }
}

/// De actieve call. Stateful met een eigen event-subscriptie (niet
/// StreamBuilder): een [MeetingErrorEvent] moet BLIJVEN staan tot de sessie het
/// oplost of eindigt — laatste-event-rendering zou een fout verbergen zodra er
/// óók maar één roster-update overheen komt (#2536).
class _ActiveCall extends ConsumerStatefulWidget {
  const _ActiveCall({required this.session});

  final MeetingSession session;

  @override
  ConsumerState<_ActiveCall> createState() => _ActiveCallState();
}

class _ActiveCallState extends ConsumerState<_ActiveCall> {
  StreamSubscription<MeetingEvent>? _sub;
  MeetingErrorEvent? _error;

  MeetingSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _sub = session.events.listen(_onEvent);
    // bind wijzigt een provider. Dat mag niet ín initState; na dit frame
    // is de boom klaar en hangt de opnamefase aan deze sessie.
    WidgetsBinding.instance.addPostFrameCallback((_) => bindRecording());
  }

  void bindRecording() {
    if (!mounted) return;
    ref.read(callRecordingProvider.notifier).bind(session);
  }

  void _onEvent(MeetingEvent event) {
    if (event is MeetingErrorEvent) _error = event;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _ActiveCall oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Een verse adopt() levert een andere sessie in dezelfde widgetplek —
    // zonder hersubscribe luistert deze state naar de dode sessie.
    if (!identical(oldWidget.session, widget.session)) {
      unawaited(_sub?.cancel());
      _error = null;
      _sub = widget.session.events.listen(_onEvent);
      WidgetsBinding.instance.addPostFrameCallback((_) => bindRecording());
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = session.connectionState;
    final ended =
        state == MeetingConnectionState.disconnected ||
        state == MeetingConnectionState.failed;
    final participants = session.participants;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!ended &&
            (state == MeetingConnectionState.connecting ||
                state == MeetingConnectionState.reconnecting))
          _ConnectionStatusLine(l10n: l10n, state: state),
        if (ended)
          Expanded(
            child: _EndedCall(l10n: l10n, error: _error),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: participants.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) =>
                  _ParticipantTile(participants[i], session: session),
            ),
          ),
        if (!ended && _error != null) _ErrorLine(message: _error!.message),
        if (!ended) ...[
          const SizedBox(height: 6),
          _MediaStatusLine(session: session),
        ],
        if (!ended) CallRecordingSection(session: session),
        const SizedBox(height: 8),
        ended ? const _DismissEndedCall() : _CallControls(session: session),
      ],
    );
  }
}

/// De verbindingsstand als statusregel — liveRegion zodat een schermlezer een
/// wissel (bijv. opnieuw verbinden na een hik) aankondigt zonder focus.
class _ConnectionStatusLine extends StatelessWidget {
  const _ConnectionStatusLine({required this.l10n, required this.state});

  final AppLocalizations l10n;
  final MeetingConnectionState state;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.slate500,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state == MeetingConnectionState.connecting
                    ? l10n.d('Verbinden…')
                    : l10n.d('Opnieuw verbinden…'),
                style: TextStyle(fontSize: 11, color: AppTheme.slate600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// De eindstand van een call: de remote hing op, de media stierf of de
/// verbinding viel — zichtbaar tot de gebruiker hem wegklikt (#2536). De
/// sessie is intern al afgebroken (leave() is idempotent); Sluiten ruimt de
/// provider op en keert terug naar de placeholder.
class _EndedCall extends StatelessWidget {
  const _EndedCall({required this.l10n, required this.error});

  final AppLocalizations l10n;
  final MeetingErrorEvent? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.call_end_outlined, size: 18, color: AppTheme.dangerFg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                error?.message ?? l10n.d('De vergadering is beëindigd.'),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Een niet-terminale fout (bijv. een weggevallen microfoon): blijft staan tot
/// de sessie eindigt — stille fouten zijn hier een ontwerpfout.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppTheme.amber600),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11, color: AppTheme.slate600),
            ),
          ),
        ],
      ),
    );
  }
}

/// De enige actie op een beëindigde call: wegklikken. De notifier-leave is
/// idempotent — de sessie zelf is al afgebroken.
class _DismissEndedCall extends ConsumerWidget {
  const _DismissEndedCall();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: FilledButton.tonalIcon(
        icon: const Icon(Icons.call_end_outlined, size: 16),
        label: Text(context.l10n.d('Sluiten')),
        onPressed: () => ref.read(meetingSessionProvider.notifier).leave(),
      ),
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
    final sharing = local?.isScreenShare ?? false;
    final shareLabel = session.screenShareLabel;
    return Column(
      children: [
        // Welke bron live wordt verzonden (#2537) — geen naam bekend (de
        // browser koos zelf) dan alleen "je deelt".
        if (sharing)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              shareLabel == null
                  ? l10n.d('Je deelt je scherm.')
                  : '${l10n.d('Je deelt')} $shareLabel',
              style: TextStyle(fontSize: 11, color: AppTheme.slate600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Row(
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
                  camOff
                      ? Icons.videocam_off_outlined
                      : Icons.videocam_outlined,
                ),
                onPressed: () => session.setCamera(enabled: camOff),
              ),
            if (caps.screenShare)
              IconButton(
                tooltip: sharing
                    ? l10n.d('Delen stoppen')
                    : l10n.d('Scherm delen'),
                icon: Icon(
                  sharing
                      ? Icons.stop_screen_share_outlined
                      : Icons.screen_share_outlined,
                ),
                onPressed: sharing
                    ? session.stopScreenShare
                    : () => _pickShareSource(context),
              ),
            _AudioOutputMenu(session: session),
            IconButton(
              tooltip: l10n.d('Vergadering verlaten'),
              icon: Icon(Icons.call_end_outlined, color: AppTheme.dangerFg),
              onPressed: () =>
                  ref.read(meetingSessionProvider.notifier).leave(),
            ),
          ],
        ),
      ],
    );
  }

  /// Deel-route (#2537): een eigen bronlijst als het platform die heeft
  /// (desktop → kiezer met miniaturen), anders kiest de browser of het OS
  /// zelf in `getDisplayMedia`. Annuleren of weigeren doet niets — de sessie
  /// meldt een mislukte share zelf als MeetingErrorEvent.
  Future<void> _pickShareSource(BuildContext context) async {
    final sources = await session.screenShareSources();
    if (!context.mounted) return;
    if (sources.isEmpty) {
      await session.startScreenShare();
      return;
    }
    final source = await showDialog<MeetingScreenSource>(
      context: context,
      builder: (_) => ScreenSharePickerDialog(sources: sources),
    );
    if (source != null) {
      await session.startScreenShare(
        sourceId: source.id,
        sourceLabel: source.label,
      );
    }
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
