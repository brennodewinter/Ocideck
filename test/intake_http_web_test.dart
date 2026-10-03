// De webhelft van het inzendverkeer (`intake_http_web.dart`): het web praat nog niet met een
// inzendserver, en zegt dat in plaats van het te proberen. Het bestand heeft niets van `dart:html`
// nodig, dus het draait ook hier.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/intake/intake_http.dart';
import 'package:ocideck/services/form/intake/intake_http_web.dart' as web;

void main() {
  test('weigert elk verzoek: alleen op de computer', () async {
    final http = web.createIntakeHttp();
    expect(http, isA<web.WebRefusingIntakeHttp>());
    await expectLater(
      http.send(
        method: 'GET',
        url: Uri.parse('https://intake.example.org/v1/info'),
        maxResponseBytes: 1024,
        timeout: const Duration(seconds: 1),
      ),
      throwsA(
        isA<IntakeHttpException>().having(
          (e) => e.failure,
          'failure',
          IntakeHttpFailure.desktopOnly,
        ),
      ),
    );
  });
}
