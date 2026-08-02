// Widget test for the media preflight tile (F3.4a). The media core is injected, so
// this drives the whole UI without loading a real WebRTC stack.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/meetings/meeting_media_core.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/media_preflight_tile.dart';

class FakeMediaCore implements MeetingMediaCore {
  FakeMediaCore(this._stackOk);
  final bool _stackOk;
  var disposed = false;

  @override
  MeetingE2eeStatus get mediaE2ee => MeetingE2eeStatus.off;

  @override
  Future<bool> selfTest() async => _stackOk;

  @override
  Future<void> dispose() async => disposed = true;
}

Future<void> pumpTile(WidgetTester tester, MediaCoreFactory factory) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('nl'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: Scaffold(body: MediaPreflightTile(createMediaCore: factory)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('discloses the media-E2EE status up front', (tester) async {
    await pumpTile(tester, () => FakeMediaCore(true));
    expect(find.textContaining('E2EE'), findsOneWidget);
  });

  testWidgets('a working media stack reports success and disposes the core', (
    tester,
  ) async {
    final fake = FakeMediaCore(true);
    await pumpTile(tester, () => fake);
    await tester.tap(find.text('Media-stack testen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('werkt'), findsOneWidget);
    expect(fake.disposed, isTrue);
  });

  testWidgets('a missing media stack reports the failure', (tester) async {
    await pumpTile(tester, () => FakeMediaCore(false));
    await tester.tap(find.text('Media-stack testen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('kon niet laden'), findsOneWidget);
  });
}
