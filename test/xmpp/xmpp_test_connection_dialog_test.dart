// Widget test for the "test XMPP connection" dialog (F2/F3). The connection call
// is injected, so this drives the whole UI — enter server/JID/password/room, press
// test, read the result — without ever opening a socket. Locale is pinned to Dutch
// so the assertions match the source strings regardless of translation state.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/xmpp_settings.dart';
import 'package:ocideck/widgets/dialogs/xmpp_test_connection_dialog.dart';
import 'package:ocideck/xmpp/xmpp_muc.dart';
import 'package:ocideck/xmpp/xmpp_session.dart';

Future<void> pumpDialog(WidgetTester tester, XmppConnectTest connect) async {
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
      home: Scaffold(body: XmppTestConnectionDialog(connect: connect)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> fillAndTest(WidgetTester tester, {String? room}) async {
  await tester.enterText(
    find.byType(TextField).at(0),
    'wss://xmpp.example/xmpp-websocket',
  );
  await tester.enterText(find.byType(TextField).at(1), 'a@example');
  await tester.enterText(find.byType(TextField).at(2), 'pencil');
  if (room != null) {
    await tester.enterText(find.byType(TextField).at(3), room);
  }
  await tester.tap(find.text('Verbinding testen'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reports success with the negotiated mechanism', (tester) async {
    XmppSettings? seenSettings;
    String? seenPassword;
    String? seenRoom;
    await pumpDialog(tester, (settings, password, room) async {
      seenSettings = settings;
      seenPassword = password;
      seenRoom = room;
      return const XmppTestOutcome(
        result: XmppSessionResult.ok(
          mechanism: 'SCRAM-SHA-256',
          boundJid: 'a@example/ocideck-1',
        ),
      );
    });
    await fillAndTest(tester);

    // The typed fields reach the connection call verbatim (nothing mangled).
    expect(seenSettings?.serverUrl, 'wss://xmpp.example/xmpp-websocket');
    expect(seenSettings?.jid, 'a@example');
    expect(seenPassword, 'pencil');
    expect(seenRoom, ''); // no room entered
    // The success line names the mechanism (locale-independent protocol name)
    // and the bound full JID.
    expect(find.textContaining('SCRAM-SHA-256'), findsOneWidget);
    expect(find.textContaining('a@example/ocideck-1'), findsOneWidget);
  });

  testWidgets('maps a session failure code to a translated message', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      (settings, password, room) async => const XmppTestOutcome(
        result: XmppSessionResult.failed(XmppSessionFailure.badCredentials),
      ),
    );
    await fillAndTest(tester);
    expect(find.textContaining('wachtwoord'), findsWidgets);
  });

  testWidgets('lists the room occupants when a room is joined', (tester) async {
    String? seenRoom;
    await pumpDialog(tester, (settings, password, room) async {
      seenRoom = room;
      return const XmppTestOutcome(
        result: XmppSessionResult.ok(
          mechanism: 'SCRAM-SHA-256',
          boundJid: 'a@example/ocideck-1',
        ),
        occupants: ['alice', 'a'],
      );
    });
    await fillAndTest(tester, room: 'room@conf.example');

    expect(seenRoom, 'room@conf.example');
    expect(find.textContaining('alice'), findsOneWidget);
  });

  testWidgets('maps a join failure to a translated message', (tester) async {
    await pumpDialog(
      tester,
      (settings, password, room) async => const XmppTestOutcome(
        result: XmppSessionResult.ok(
          mechanism: 'SCRAM-SHA-256',
          boundJid: 'a@example/ocideck-1',
        ),
        joinFailure: MucJoinFailure.nickConflict,
      ),
    );
    await fillAndTest(tester, room: 'room@conf.example');
    expect(find.textContaining('bijnaam'), findsWidgets);
  });

  testWidgets('the injected call is what runs — no real socket', (
    tester,
  ) async {
    var called = false;
    await pumpDialog(tester, (settings, password, room) async {
      called = true;
      return const XmppTestOutcome(
        result: XmppSessionResult.ok(
          mechanism: 'ANONYMOUS',
          boundJid: 'anon@example/x',
        ),
      );
    });
    await fillAndTest(tester);
    expect(called, isTrue);
  });
}
