import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/widgets/dialogs/settings/webdav_form.dart';
import 'package:ocideck/widgets/dialogs/settings/webdav_panel.dart';

/// Het WebDAV-paneel, los van het instellingenvenster. Zie
/// settings_s3_panel_test.dart voor waarom dat losstaan de winst is (#631).
void main() {
  late WebdavForm form;
  var changes = 0;

  setUp(() {
    form = WebdavForm();
    changes = 0;
  });
  tearDown(() => form.dispose());

  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebdavPanel(
              form: form,
              confirmCertificate:
                  ({
                    required origin,
                    required host,
                    required allowPrivate,
                  }) async => null,
              onChanged: () => changes++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders without the settings dialog around it', (tester) async {
    await show(tester);
    expect(find.text('WEBDAV-BRON'), findsOneWidget);
    expect(find.text('Server-URL'), findsOneWidget);
    // Nextcloud is de standaard, en alleen dáár heet het een app-wachtwoord.
    expect(find.text('App-wachtwoord'), findsOneWidget);
  });

  testWidgets('another server kind renames the password and shows the root '
      'rule', (tester) async {
    await show(tester);
    await tester.tap(find.byType(DropdownButtonFormField<WebdavServerKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Andere WebDAV-server').last);
    await tester.pumpAndSettle();

    expect(form.kind, WebdavServerKind.generic);
    expect(find.text('Wachtwoord'), findsOneWidget);
    expect(find.text('App-wachtwoord'), findsNothing);
    expect(
      find.text('Het pad in de server-URL is de WebDAV-wortel.'),
      findsOneWidget,
    );
    expect(changes, greaterThan(0));
  });

  testWidgets('a pasted DAV URL is offered for splitting, not silently kept', (
    tester,
  ) async {
    await show(tester);
    await tester.enterText(
      find.byType(TextField).first,
      'https://cloud.test/remote.php/dav/files/bram/Presentaties',
    );
    await tester.pumpAndSettle();
    expect(find.text('Overnemen'), findsOneWidget);

    await tester.tap(find.text('Overnemen'));
    await tester.pumpAndSettle();

    // De submap die in de geplakte URL zat ging hiervóór stil verloren.
    expect(form.url.text, 'https://cloud.test');
    expect(form.user.text, 'bram');
    expect(form.root.text, '/Presentaties');
    expect(find.text('Overnemen'), findsNothing);
  });

  testWidgets('an unconfigured server is refused before any network call', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Verbinding testen'));
    await tester.pumpAndSettle();

    expect(find.text('Vul server-URL en gebruikersnaam in'), findsOneWidget);
    expect(form.testOk, false);
  });
}
