import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_media_core.dart'
    show MeetingScreenSource;
import 'package:ocideck/meetings/meeting_participant.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/state/meeting_session_provider.dart';
import 'package:ocideck/widgets/dialogs/meeting_preflight_dialog.dart';
import 'package:ocideck/widgets/panels/call_panel.dart';

import 'fakes/fake_meeting_provider.dart';

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(
    home: Scaffold(body: SizedBox(width: 320, child: CallPanel())),
  ),
);

Future<FakeMeetingSession> _join(ProviderContainer container) async {
  const provider = FakeMeetingProvider();
  final match = provider.match(Uri.parse('https://fake.local/r'))!;
  final session = await provider.join(
    MeetingJoinRequest(link: match, displayName: 'Me'),
  );
  container.read(meetingSessionProvider.notifier).adopt(session);
  return session as FakeMeetingSession;
}

void main() {
  testWidgets('no call shows the real join route, not a placeholder promise', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container));
    await tester.pump();

    expect(find.textContaining('Nog geen actieve vergadering'), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);

    // The entry point is real: the button opens the link-check/preflight/join
    // dialog (#2536).
    await tester.tap(find.text('Deelnemen aan een vergadering…'));
    await tester.pumpAndSettle();
    expect(find.byType(MeetingPreflightDialog), findsOneWidget);
  });

  testWidgets('a reconnecting call shows its connection state', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = await _join(container);
    await tester.pumpWidget(_host(container));
    await tester.pump();

    session.setConnectionState(MeetingConnectionState.reconnecting);
    await tester.pump();
    await tester.pump();

    expect(find.text('Opnieuw verbinden…'), findsOneWidget);

    session.setConnectionState(MeetingConnectionState.connected);
    await tester.pump();
    await tester.pump();
    expect(find.text('Opnieuw verbinden…'), findsNothing);
  });

  testWidgets('a non-terminal error stays visible next to a live call', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = await _join(container);
    await tester.pumpWidget(_host(container));
    await tester.pump();

    session.pushError('Je microfoon of camera viel weg.');
    await tester.pump();
    await tester.pump();
    expect(find.text('Je microfoon of camera viel weg.'), findsOneWidget);

    // A roster event right after must not hide the error — it accumulates,
    // it is not "the latest event wins".
    session.addRemoteParticipant(
      const MeetingParticipant(
        id: 'r1',
        displayName: 'Ada',
        role: MeetingRole.attendee,
      ),
    );
    await tester.pump();
    expect(find.text('Je microfoon of camera viel weg.'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('a terminal end shows the ended state; Sluiten dismisses it', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = await _join(container);
    await tester.pumpWidget(_host(container));
    await tester.pump();

    // The session dies on its own (remote terminate / media dead): a terminal
    // error plus a failed state, NOT a notifier leave.
    session.pushError('De verbinding is verbroken.', terminal: true);
    session.setConnectionState(MeetingConnectionState.failed);
    await tester.pump();
    await tester.pump();

    expect(find.text('De verbinding is verbroken.'), findsOneWidget);
    // The call controls are gone — you cannot mute a dead call.
    expect(find.byIcon(Icons.mic_off_outlined), findsNothing);

    await tester.tap(find.text('Sluiten'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Nog geen actieve vergadering'), findsOneWidget);
    expect(session.left, isTrue);
  });

  testWidgets('a session ended cleanly without error says the meeting ended', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = await _join(container);
    await tester.pumpWidget(_host(container));
    await tester.pump();

    // Remote terminate: the session tears itself down to `disconnected` while
    // the provider still holds it — the end must be VISIBLE until dismissed.
    await session.leave();
    await tester.pump();
    await tester.pump();

    expect(find.text('De vergadering is beëindigd.'), findsOneWidget);
    await tester.tap(find.text('Sluiten'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Nog geen actieve vergadering'), findsOneWidget);
  });

  test('adopting a session while one is live leaves the old call', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const provider = FakeMeetingProvider();
    final match = provider.match(Uri.parse('https://fake.local/r'))!;
    final first = await provider.join(
      MeetingJoinRequest(link: match, displayName: 'Een'),
    );
    final second = await provider.join(
      MeetingJoinRequest(link: match, displayName: 'Twee'),
    );

    final notifier = container.read(meetingSessionProvider.notifier);
    notifier.adopt(first);
    expect(container.read(meetingSessionProvider), same(first));

    notifier.adopt(second);
    expect(container.read(meetingSessionProvider), same(second));
    await Future<void>.delayed(Duration.zero);
    expect((first as FakeMeetingSession).left, isTrue);
    expect((second as FakeMeetingSession).left, isFalse);
  });

  testWidgets('controls follow live capabilities', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = await _join(container);
    await tester.pumpWidget(_host(container));
    await tester.pump();
    expect(find.byType(IconButton), findsNWidgets(4)); // mic cam share leave

    // The host revokes audio + screen share mid-call: the controls go with it.
    session.setCapabilities(
      const MeetingCapabilities(video: true, chat: true, roster: true),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(IconButton), findsNWidgets(2)); // camera + leave
  });

  testWidgets('renders tiles and capability-driven controls, backend-agnostic', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = await _join(container);
    await tester.pumpWidget(_host(container));
    await tester.pump();

    // The local participant tile.
    expect(find.text('Me'), findsOneWidget);
    // Controls from the fake's full capabilities: mic, camera, screen + leave.
    expect(find.byType(IconButton), findsNWidgets(4));

    // A remote joins — its tile appears after the event flows through.
    session.addRemoteParticipant(
      const MeetingParticipant(
        id: 'r1',
        displayName: 'Ada',
        role: MeetingRole.attendee,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('leaving clears the call back to the placeholder', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _join(container);
    await tester.pumpWidget(_host(container));
    await tester.pump();
    expect(find.text('Me'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.call_end_outlined));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Nog geen actieve vergadering'), findsOneWidget);
  });

  testWidgets('a dominant, screen-sharing participant renders its state', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = await _join(container);
    await tester.pumpWidget(_host(container));
    await tester.pump();

    session.addRemoteParticipant(
      const MeetingParticipant(
        id: 'r2',
        displayName: 'Bo',
        role: MeetingRole.presenter,
        isDominantSpeaker: true,
        isScreenShare: true,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Bo'), findsOneWidget);
  });

  testWidgets('media controls invoke the session and reflect the new state', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _join(container);
    await tester.pumpWidget(_host(container));
    await tester.pump();

    // Local starts muted + camera off (the join defaults). Each control lives in
    // an IconButton, so widgetWithIcon(IconButton, ...) hits the control, not the
    // matching tile indicator.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.mic_off_outlined));
    await tester.pump();
    await tester.pump();
    expect(find.widgetWithIcon(IconButton, Icons.mic_outlined), findsOneWidget);

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.videocam_off_outlined),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.widgetWithIcon(IconButton, Icons.videocam_outlined),
      findsOneWidget,
    );

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.screen_share_outlined),
    );
    await tester.pump();
    await tester.pump();
  });

  testWidgets('screen share: picker → gedeelde bron → stop-knop', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = await _join(container);
    session.screenSourcesToOffer = const [
      MeetingScreenSource(id: 'screen:0', label: 'Scherm 1'),
      MeetingScreenSource(id: 'window:3', label: 'Editor', isWindow: true),
    ];
    await tester.pumpWidget(_host(container));
    await tester.pump();

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.screen_share_outlined),
    );
    await tester.pump();
    await tester.pump();

    // De bronlijst komt als kiezer — scherm én venster met hun soort.
    expect(find.text('Kies wat je deelt'), findsOneWidget);
    expect(find.text('Scherm 1'), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Venster'), findsOneWidget);

    await tester.tap(find.text('Editor'));
    await tester.pump();
    await tester.pump();

    // De juiste source-id en label gingen naar de sessie; het paneel toont
    // wat er live gedeeld wordt en de knop wordt "stoppen".
    expect(session.lastShareSourceId, 'window:3');
    expect(find.textContaining('Je deelt'), findsOneWidget);
    expect(find.textContaining('Editor'), findsOneWidget);
    expect(
      find.widgetWithIcon(IconButton, Icons.stop_screen_share_outlined),
      findsOneWidget,
    );

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.stop_screen_share_outlined),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.widgetWithIcon(IconButton, Icons.screen_share_outlined),
      findsOneWidget,
    );
  });

  testWidgets('zonder eigen bronlijst deelt de knop meteen', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = await _join(container);
    // Lege lijst = browser/OS-kiezer: geen eigen dialoog, direct delen.
    await tester.pumpWidget(_host(container));
    await tester.pump();

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.screen_share_outlined),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Kies wat je deelt'), findsNothing);
    expect(session.lastShareSourceId, isNull);
    expect(
      find.widgetWithIcon(IconButton, Icons.stop_screen_share_outlined),
      findsOneWidget,
    );
  });

  testWidgets('annuleren in de kiezer start niets', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = await _join(container);
    session.screenSourcesToOffer = const [
      MeetingScreenSource(id: 'screen:0', label: 'Scherm 1'),
    ];
    await tester.pumpWidget(_host(container));
    await tester.pump();

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.screen_share_outlined),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Annuleren'));
    await tester.pump();
    await tester.pump();

    expect(session.lastShareSourceId, isNull);
    expect(
      find.widgetWithIcon(IconButton, Icons.screen_share_outlined),
      findsOneWidget,
    );
  });
}
