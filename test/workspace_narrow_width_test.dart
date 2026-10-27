// Regression test for #2603: the workspace must not overflow when the
// preview/editor section gets squeezed, and joining a meeting is a button,
// not a permanent side rail.
//
// The width math in `_MainLayout` used to ignore the fixed-width right rails
// (call 321px, chat 301px): with the video-calls module on, the editor dropped
// below its 420px minimum and its toolbar, help chips and the status bar
// overflowed (RenderFlex errors). The rail also showed permanently whenever
// the module was on — including with no call — which read as an unwanted
// extra tab during presentation work.
//
// Sizing note: `binding.setSurfaceSize` only fakes the layout constraints —
// `MediaQuery` keeps reporting 800x600, so the math under test would see a
// different width than the row gets. `tester.view.physicalSize` changes both.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/meeting_session_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/meeting_preflight_dialog.dart';
import 'package:ocideck/widgets/panels/call_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meetings/fakes/fake_meeting_provider.dart';

Deck _sampleDeck() => Deck(
  title: 'Testrapport',
  slides: [
    Slide.create(SlideType.title).copyWith(title: 'Testrapport'),
    Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Bevindingen', bullets: const ['Een', 'Twee']),
  ],
);

void _resize(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 800);
}

Future<ProviderContainer> _pumpWorkspace(
  WidgetTester tester, {
  required double width,
}) async {
  _resize(tester, width);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AppShell)),
  );
  container.read(tabsProvider).current!.deckNotifier.loadDeck(_sampleDeck());
  await tester.pumpAndSettle();
  return container;
}

Future<void> _adoptFakeCall(ProviderContainer container) async {
  const provider = FakeMeetingProvider();
  final match = provider.match(Uri.parse('https://fake.local/r'))!;
  final session = await provider.join(
    MeetingJoinRequest(link: match, displayName: 'Me'),
  );
  container.read(meetingSessionProvider.notifier).adopt(session);
}

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'videoCallsModuleEnabled': true,
    });
  });

  testWidgets(
    'module on without a call shows no rail, but a join button that opens the flow',
    (tester) async {
      await _pumpWorkspace(tester, width: 1200);

      // No permanent pane: the rail only exists while a call does.
      expect(find.byType(CallPanel), findsNothing);

      // The join entry is a button; it opens the same preflight/join flow.
      final joinButton = find.widgetWithIcon(
        IconButton,
        Icons.video_camera_front_outlined,
      );
      expect(joinButton, findsOneWidget);
      await tester.tap(joinButton);
      await tester.pumpAndSettle();
      expect(find.byType(MeetingPreflightDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a live call keeps its rail at every workspace width', (
    tester,
  ) async {
    final container = await _pumpWorkspace(tester, width: 1100);
    await _adoptFakeCall(container);
    for (final width in [1100.0, 900.0, 700.0, 640.0]) {
      _resize(tester, width);
      await tester.pumpAndSettle();
      expect(
        find.byType(CallPanel),
        findsOneWidget,
        reason: 'a call is never invisible (width $width)',
      );
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
    await container.read(meetingSessionProvider.notifier).leave();
  });

  testWidgets('narrow workspace with module on overflows nowhere', (
    tester,
  ) async {
    final container = await _pumpWorkspace(tester, width: 900);
    await _adoptFakeCall(container);
    for (final width in [900.0, 800.0, 700.0, 640.0]) {
      _resize(tester, width);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('without the module there is no rail and no join button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    await _pumpWorkspace(tester, width: 900);
    expect(find.byType(CallPanel), findsNothing);
    expect(
      find.widgetWithIcon(IconButton, Icons.video_camera_front_outlined),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
