import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/document_signature.dart';
import 'package:ocideck/widgets/document_signature_view.dart';
import 'package:ocideck/widgets/signature_draw_dialog.dart';

import 'support/pump_until.dart';

// A 1×1 transparent PNG — a valid embedded signature image for the render path.
const _pngDataUri =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1'
    'HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('decodeEmbeddedSignatureImage', () {
    test('decodes a base64 data URI and rejects everything else', () {
      expect(decodeEmbeddedSignatureImage(_pngDataUri), isNotNull);
      expect(decodeEmbeddedSignatureImage(''), isNull);
      expect(decodeEmbeddedSignatureImage('images/sig.png'), isNull);
      expect(decodeEmbeddedSignatureImage('data:image/png,notbase64'), isNull);
      expect(decodeEmbeddedSignatureImage('data:image/png;base64,@@@'), isNull);
    });
  });

  testWidgets('DocumentSignatureView renders the drawn image over the typed '
      'name', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const DocumentSignatureView(
          signature: DocumentSignature(
            name: 'Jane Doe',
            typedSignature: 'J. Doe',
            imagePath: _pngDataUri,
          ),
        ),
      ),
    );
    await tester.pump();
    // The image is shown; the typed mark is not used as the signature.
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('J. Doe'), findsNothing);
    // The signer name still appears as metadata under the line.
    expect(find.text('Jane Doe'), findsOneWidget);
  });

  testWidgets('DocumentSignatureView falls back to the typed mark without an '
      'image', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const DocumentSignatureView(
          signature: DocumentSignature(
            name: 'Jane Doe',
            typedSignature: 'J. Doe',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('J. Doe'), findsOneWidget);
  });

  testWidgets('drawing on the pad returns a PNG data URI', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? result;
    var opened = false;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              opened = true;
              result = await SignatureDrawDialog.show(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(SignatureDrawDialog), findsOneWidget);

    // Draw a stroke across the pad.
    await tester.drag(
      find.byKey(const Key('signature-canvas')),
      const Offset(160, 20),
    );
    await tester.pump();

    // Rasteren gebruikt echte (geen nep-async) beeldcodering, dus dat moet in
    // echte tijd draaien. Hier stond een vaste wachttijd van 80 ms, en dat getal
    // klopte niet: gemeten duurt dit rasteren **67–165 ms op een stille machine
    // en 116–212 ms onder belasting** (22-07-2026, 18 kernen). De test overleefde
    // alleen doordat de `pumpAndSettle` erna toevallig nog wat echte tijd
    // doorlaat — een onbedoeld neveneffect, geen wachttijd waar iemand op
    // gerekend had. Viel dat verkeerd uit, dan was `result` nog null, ging het
    // rasteren gewoon door ná de test en riep het `Navigator.pop` aan op een
    // afgebroken boom: vandaar de "FocusManager was used after being disposed"
    // in de nasleep.
    //
    // Hier stond even een eigen lus (commit 3bec656a, gelijktijdig gevonden).
    // Die deed hetzelfde en deed het goed; dit is dezelfde oplossing als
    // gedeelde hulp, zodat de vijf andere plekken met dezelfde constructie er
    // ook op konden — en met een foutmelding die zegt wát er niet gebeurde in
    // plaats van alleen "Expected: not null".
    await tester.tap(find.text('Klaar'));
    await pumpUntil(
      tester,
      () => result != null,
      reason: 'de handtekeningdialoog gaf geen data-URI terug',
    );

    expect(opened, isTrue);
    expect(result, isNotNull);
    expect(result, startsWith('data:image/png;base64,'));
    expect(decodeEmbeddedSignatureImage(result!), isNotNull);
  });

  testWidgets('closing the pad without drawing returns null', (tester) async {
    String? result;
    var returned = false;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await SignatureDrawDialog.show(context);
              returned = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Klaar'));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(result, isNull);
  });
}
