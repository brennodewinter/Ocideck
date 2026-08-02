import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_participant.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/state/meeting_session_provider.dart';
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
  testWidgets('shows a placeholder when no call is active', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container));
    await tester.pump();

    expect(find.textContaining('Nog geen actieve vergadering'), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
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
}
