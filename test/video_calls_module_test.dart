import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/state/meeting_session_provider.dart';
import 'package:ocideck/state/module_registry.dart';
import 'package:ocideck/widgets/dialogs/settings/video_calls_module_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meetings/fakes/fake_meeting_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('de module staat standaard uit en bewaart de keuze', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(videoCallsModuleProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(videoCallsEnabledProvider), isFalse);

    await container.read(videoCallsModuleProvider.notifier).setEnabled(true);
    expect(container.read(videoCallsEnabledProvider), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(videoCallsModuleEnabledKey), isTrue);
    expect(moduleRegistry.map((e) => e.id), contains(ModuleId.videoCalls));
  });

  test(
    'reveal volgt de schakelaar, en blijft aan tijdens een actieve call',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(videoCallsModuleProvider);
      await Future<void>.delayed(Duration.zero);

      // Uit en geen call: verborgen.
      expect(container.read(videoCallsRevealProvider), isFalse);

      // Schakelaar aan: zichtbaar.
      await container.read(videoCallsModuleProvider.notifier).setEnabled(true);
      expect(container.read(videoCallsRevealProvider), isTrue);

      // Schakelaar weer uit, maar een call loopt: niet stranden — nog zichtbaar.
      await container.read(videoCallsModuleProvider.notifier).setEnabled(false);
      expect(container.read(videoCallsRevealProvider), isFalse);
      const provider = FakeMeetingProvider();
      final match = provider.match(Uri.parse('https://fake.local/r'))!;
      final session = await provider.join(
        MeetingJoinRequest(link: match, displayName: 'Me'),
      );
      container.read(meetingSessionProvider.notifier).adopt(session);
      expect(container.read(videoCallsRevealProvider), isTrue);

      // Call verlaten: weer verborgen.
      await container.read(meetingSessionProvider.notifier).leave();
      expect(container.read(videoCallsRevealProvider), isFalse);
    },
  );

  testWidgets('de modulekaart schakelt de module aan', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: VideoCallsModuleCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Videovergaderingen'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });
}
