import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/s3_settings.dart';
import 'package:ocideck/widgets/dialogs/settings/s3_form.dart';
import 'package:ocideck/widgets/dialogs/settings/s3_panel.dart';

/// Het S3-paneel, los van het instellingenvenster.
///
/// Dát het zonder venster te tekenen is, is de winst van #631: het paneel had
/// eerst toegang tot élk veld van de zesentwintig andere parts — inclusief de
/// inloggegevens van WebDAV, git en de AI-backend — en was alleen te toetsen
/// door de hele dialoog te openen.
void main() {
  late S3Form form;
  var changes = 0;

  setUp(() {
    form = S3Form();
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
            child: S3Panel(
              form: form,
              // De certificaatbevestiging is een dialoog van het venster; het
              // paneel kent er alleen de weg naartoe.
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
    expect(find.text('S3-BUCKET'), findsOneWidget);
    expect(find.text('Endpoint'), findsOneWidget);
    expect(find.text('Secret access key'), findsOneWidget);
  });

  testWidgets('typing lands in the form the dialog owns', (tester) async {
    await show(tester);
    await tester.enterText(find.byType(TextField).first, 'https://minio.test');
    expect(form.endpoint.text, 'https://minio.test');
  });

  testWidgets('changing the addressing style voids the previous result', (
    tester,
  ) async {
    // De vorige uitslag ging over een andere URL-vorm. Blijft het vinkje staan,
    // dan meldt het paneel "verbinding gelukt" over een verbinding die het niet
    // geprobeerd heeft.
    form
      ..testOk = true
      ..testMessage = null;
    await show(tester);
    expect(find.text('Verbinding gelukt'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<S3AddressingStyle>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bucket in het pad (MinIO en andere)').last);
    await tester.pumpAndSettle();

    expect(form.addressingStyle, S3AddressingStyle.path);
    expect(form.testOk, isNull);
    expect(find.text('Verbinding gelukt'), findsNothing);
    // Het venster erbuiten toont dezelfde uitslag achter de verbindingsnaam en
    // moet dus meekrijgen dat hij verviel.
    expect(changes, greaterThan(0));
  });

  testWidgets('an unconfigured bucket is refused before any network call', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Verbinding testen'));
    await tester.pumpAndSettle();

    expect(
      find.text('Vul endpoint, bucket en access key ID in'),
      findsOneWidget,
    );
    expect(form.testOk, false);
  });
}
