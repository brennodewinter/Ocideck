// Widget test for MeetingPreflightDialog (#2533). Resolver and preflight are
// injected — no socket, no SharedPreferences. Drives the full flow: link in →
// local verdict → provider question (only when hinted) → explicit preflight
// consent → typed result. Asserts the honest boundaries: no join button, no
// network before the preflight click.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/meetings/meeting_link_resolver.dart';
import 'package:ocideck/meetings/meeting_participant.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/meetings/meeting_provider_profile.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_meeting_provider.dart';
import 'package:ocideck/widgets/dialogs/meeting_preflight_dialog.dart';

Future<void> _pump(
  WidgetTester tester, {
  MeetingLinkResolver? resolver,
  MeetingPreflightFn? preflight,
  MeetingProfileSaveFn? saveProfile,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('nl'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: MeetingPreflightDialog(
            resolver: resolver,
            preflight: preflight,
            saveProfile: saveProfile,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MeetingLinkResolver _resolver({
  List<MeetingProviderProfile> profiles = const [],
}) => MeetingLinkResolver(
  providers: [JitsiMeetingProvider()],
  profiles: profiles,
);

MeetingPreflight _ok() => const MeetingPreflight(
  support: MeetingSupport.nativeClient,
  capabilities: MeetingCapabilities(
    audio: true,
    video: true,
    chat: true,
    roster: true,
  ),
  e2ee: MeetingE2eeStatus.off,
  identityLabel: 'ocideck-00000001',
  egressOrigins: [
    'https://meet.jit.si',
    'wss://meet.example',
    'xmpp:muc.meet.jitsi',
  ],
);

Future<void> _typeLink(WidgetTester tester, String link) async {
  await tester.enterText(find.byType(TextField), link);
  await tester.tap(find.widgetWithText(FilledButton, 'Controleer'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('recognised link offers preflight, which shows the facts', (
    tester,
  ) async {
    var preflightCalls = 0;
    await _pump(
      tester,
      resolver: _resolver(),
      preflight: (m) async {
        preflightCalls++;
        return _ok();
      },
    );
    await _typeLink(tester, 'https://meet.jit.si/standup');
    expect(
      find.textContaining('Herkend als Jitsi-vergadering'),
      findsOneWidget,
    );
    expect(preflightCalls, 0); // nog geen netwerk — consent komt eerst

    await tester.tap(find.widgetWithText(FilledButton, 'Preflight uitvoeren'));
    await tester.pumpAndSettle();
    expect(preflightCalls, 1);
    expect(find.textContaining('Server bereikt'), findsOneWidget);
    expect(find.textContaining('ocideck-00000001'), findsOneWidget);
    expect(find.textContaining('niet end-to-end'), findsOneWidget);
    // Eerlijke afwezigheid: er is geen deelname-knop.
    expect(find.text('Deelnemen'), findsNothing);
  });

  testWidgets('invalid link shows the reason, never a provider question', (
    tester,
  ) async {
    await _pump(tester, resolver: _resolver());
    await _typeLink(tester, 'javascript:alert(1)');
    expect(find.textContaining('http(s)'), findsWidgets);
    expect(find.text('Jitsi'), findsNothing);
  });

  testWidgets('a hint asks the provider question; approval preflights', (
    tester,
  ) async {
    MeetingProviderProfile? saved;
    await _pump(
      tester,
      resolver: _resolver(),
      preflight: (m) async => _ok(),
      saveProfile: (p) async => saved = p,
    );
    await _typeLink(tester, 'https://video.example.org/standup');
    expect(find.textContaining('Welke vergaderdienst'), findsOneWidget);

    // Onthoud + intern netwerk aanvinken, dan Jitsi kiezen.
    await tester.tap(find.textContaining('Onthoud deze server'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('eigen (interne) netwerk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jitsi'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.origin.host, 'video.example.org');
    expect(saved!.trustedInternal, isTrue);
    expect(
      find.widgetWithText(FilledButton, 'Preflight uitvoeren'),
      findsOneWidget,
    );
  });

  testWidgets('stripped credential is disclosed to the user', (tester) async {
    await _pump(tester, resolver: _resolver());
    await _typeLink(tester, 'https://meet.jit.si/r?jwt=SECRET');
    expect(find.textContaining('inlogtoken'), findsOneWidget);
  });

  testWidgets('a failed preflight shows the typed reason', (tester) async {
    await _pump(
      tester,
      resolver: _resolver(),
      preflight: (m) async => const MeetingPreflight(
        support: MeetingSupport.nativeClient,
        capabilities: MeetingCapabilities(),
        e2ee: MeetingE2eeStatus.off,
        failureReason: MeetingFailureReason.accountRequired,
      ),
    );
    await _typeLink(tester, 'https://meet.jit.si/team');
    await tester.tap(find.widgetWithText(FilledButton, 'Preflight uitvoeren'));
    await tester.pumpAndSettle();
    expect(find.textContaining('account'), findsWidgets);
  });
}
