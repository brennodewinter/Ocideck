// Widget test for the "test XMPP connection" dialog (F2). The connection call is
// injected, so this drives the whole UI — enter server/JID/password, press test,
// read the result — without ever opening a socket. Locale is pinned to Dutch so
// the assertions match the source strings regardless of translation state.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/xmpp_settings.dart';
import 'package:ocideck/widgets/dialogs/xmpp_test_connection_dialog.dart';
import 'package:ocideck/xmpp/xmpp_connection.dart';

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

Future<void> fillAndTest(WidgetTester tester) async {
  await tester.enterText(
    find.byType(TextField).at(0),
    'wss://xmpp.example/xmpp-websocket',
  );
  await tester.enterText(find.byType(TextField).at(1), 'a@example');
  await tester.enterText(find.byType(TextField).at(2), 'pencil');
  await tester.tap(find.text('Verbinding testen'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reports success with the negotiated mechanism', (tester) async {
    XmppSettings? seenSettings;
    String? seenPassword;
    await pumpDialog(tester, (settings, password) async {
      seenSettings = settings;
      seenPassword = password;
      return const XmppAuthResult.success('SCRAM-SHA-256');
    });
    await fillAndTest(tester);

    // The typed fields reach the connection call verbatim (nothing mangled).
    expect(seenSettings?.serverUrl, 'wss://xmpp.example/xmpp-websocket');
    expect(seenSettings?.jid, 'a@example');
    expect(seenPassword, 'pencil');
    // The success line names the mechanism (locale-independent protocol name).
    expect(find.textContaining('SCRAM-SHA-256'), findsOneWidget);
  });

  testWidgets('maps a failure code to a translated message', (tester) async {
    await pumpDialog(
      tester,
      (settings, password) async =>
          const XmppAuthResult.failed(XmppAuthFailure.badCredentials),
    );
    await fillAndTest(tester);
    expect(find.textContaining('wachtwoord'), findsWidgets);
  });

  testWidgets('the injected call is what runs — no real socket', (tester) async {
    var called = false;
    await pumpDialog(tester, (settings, password) async {
      called = true;
      return const XmppAuthResult.success('ANONYMOUS');
    });
    await fillAndTest(tester);
    expect(called, isTrue);
  });
}
