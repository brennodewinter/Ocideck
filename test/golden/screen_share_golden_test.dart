@Tags(['golden'])
library;

// De schermdeel-kiezer en het "welke bron is live"-beeld (#2537) — de layout
// is wat er kan breken (een venstertitel loopt, een miniatuur drukt de lijst
// weg), en dat ziet een waardentest niet. Eén PNG per thema, Ahem-font zoals
// alle goldens.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/meetings/meeting_media_core.dart'
    show MeetingScreenSource;
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/state/meeting_session_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dialogs/screen_share_picker.dart';
import 'package:ocideck/widgets/panels/call_panel.dart';

import '../meetings/fakes/fake_meeting_provider.dart';

const _surfaceKey = ValueKey('screen-share-golden-surface');

/// Een echte 1×1 png — de miniatuur-route in de kiezer moet wel renderen,
/// niet alleen de icoon-terugval.
final _thumbBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

const _sources = [
  MeetingScreenSource(id: 'screen:0', label: 'Het hele scherm'),
  MeetingScreenSource(
    id: 'window:7',
    label: 'OciDeck — kwartaalpresentatie.md',
    isWindow: true,
  ),
];

Future<void> _match(
  WidgetTester tester, {
  required String name,
  required bool dark,
  required Widget child,
}) async {
  const size = Size(960, 760);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => AppTheme.isDark = false);
  AppTheme.isDark = dark;

  final baseTheme = AppTheme.fromProfile(
    dark ? AppAppearanceProfile.dark : AppAppearanceProfile.basic,
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('nl'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(fontFamily: 'Ahem'),
      ),
      home: MediaQuery(
        data: const MediaQueryData(size: size, disableAnimations: true),
        child: Scaffold(
          body: RepaintBoundary(
            key: _surfaceKey,
            child: ColoredBox(
              color: baseTheme.colorScheme.surfaceContainerLow,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await expectLater(
    find.byKey(_surfaceKey),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  testWidgets('de bronkiezer in licht en donker', (tester) async {
    for (final dark in [false, true]) {
      final sources = [
        _sources[0],
        MeetingScreenSource(
          id: _sources[1].id,
          label: _sources[1].label,
          isWindow: true,
          thumbnail: _thumbBytes,
        ),
      ];
      await _match(
        tester,
        name: 'screen_share_picker_${dark ? 'dark' : 'light'}',
        dark: dark,
        child: SizedBox(
          width: 520,
          child: ScreenSharePickerDialog(sources: sources),
        ),
      );
    }
  });

  testWidgets('het callpaneel tijdens een lopende share', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const provider = FakeMeetingProvider();
    final match = provider.match(Uri.parse('https://fake.local/r'))!;
    final session =
        await provider.join(
              MeetingJoinRequest(link: match, displayName: 'Brenno'),
            )
            as FakeMeetingSession;
    await session.startScreenShare(
      sourceId: 'screen:0',
      sourceLabel: 'Het hele scherm',
    );
    container.read(meetingSessionProvider.notifier).adopt(session);
    for (final dark in [false, true]) {
      await _match(
        tester,
        name: 'call_panel_sharing_${dark ? 'dark' : 'light'}',
        dark: dark,
        child: UncontrolledProviderScope(
          container: container,
          child: const SizedBox(width: 320, height: 400, child: CallPanel()),
        ),
      );
    }
  });
}
