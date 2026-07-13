import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/document_signature.dart';
import 'package:ocideck/widgets/document_signature_view.dart';
import 'package:ocideck/widgets/signature_draw_dialog.dart';

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

    // Rasterising uses real (not fake-async) image encoding, so let it run.
    await tester.runAsync(() async {
      await tester.tap(find.text('Klaar'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();

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
