// Afsluiten van de app moet een lopende call netjes verlaten (#2536) — en een
// leave die blijft hangen mag het afsluiten niet ophouden.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/state/meeting_session_provider.dart';
import 'package:ocideck/widgets/shell/meeting_lifecycle.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_meeting_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, WidgetRef)> shell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef ref;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return (container, ref);
  }

  testWidgets('quit verlaat een lopende call en ruimt de provider op', (
    tester,
  ) async {
    final (container, ref) = await shell(tester);
    final session = FakeMeetingSession(
      MeetingJoinRequest(
        link: MeetingLinkMatch(
          providerId: 'fake',
          invitation: Uri.parse('https://fake.local/kamer'),
        ),
        displayName: 'gast',
      ),
    );
    container.read(meetingSessionProvider.notifier).adopt(session);

    await leaveMeetingBeforeQuit(ref);

    expect(session.left, isTrue);
    expect(container.read(meetingSessionProvider), isNull);
  });

  testWidgets('quit zonder call doet niets', (tester) async {
    final (_, ref) = await shell(tester);
    await leaveMeetingBeforeQuit(ref);
  });

  testWidgets('een leave die blijft hangen houdt het afsluiten niet op', (
    tester,
  ) async {
    final (container, ref) = await shell(tester);
    container
        .read(meetingSessionProvider.notifier)
        .adopt(_HangingLeaveSession());

    // runAsync: de vijfseconden-timeout moet op een echte klok lopen; onder de
    // fake klok van testWidgets zou deze await op de timer wachten die nooit
    // gepompt wordt.
    await tester.runAsync(() => leaveMeetingBeforeQuit(ref));
    expect(container.read(meetingSessionProvider), isNull);
  });
}

/// Een sessie waarvan `leave()` nooit terugkeert — de dood-netwerk-kant die de
/// vijfseconden-begrenzing van `leaveMeetingBeforeQuit` moet opvangen.
class _HangingLeaveSession extends FakeMeetingSession {
  _HangingLeaveSession()
    : super(
        MeetingJoinRequest(
          link: MeetingLinkMatch(
            providerId: 'fake',
            invitation: Uri.parse('https://fake.local/kamer'),
          ),
          displayName: 'gast',
        ),
      );

  @override
  Future<void> leave() => Completer<void>().future;
}
