import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/document_signature.dart';
import 'package:ocideck/widgets/document_signature_view.dart';

/// Behaviour tests for the reusable signature block: an empty signature renders
/// nothing, a typed signature shows the statement/name/role/certification/date,
/// and an embedded `data:` image is drawn while any other path (or a malformed
/// data URI) falls back to the typed name.
void main() {
  // A minimal, valid 1×1 transparent PNG as a base64 data URI.
  const dataUri =
      'data:image/png;base64,'
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

  Future<void> pump(
    WidgetTester tester,
    DocumentSignature sig, {
    bool compact = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentSignatureView(signature: sig, compact: compact),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an empty signature renders nothing', (tester) async {
    await pump(tester, const DocumentSignature());

    expect(find.byType(Text), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a typed signature renders all its fields', (tester) async {
    await pump(
      tester,
      const DocumentSignature(
        name: 'Jan Jansen',
        role: 'CISO',
        certification: 'OSCP',
        date: '2026-07-10',
        statement: 'Ik verklaar naar waarheid te hebben gerapporteerd.',
        typedSignature: 'J. Jansen',
      ),
    );

    expect(
      find.text('Ik verklaar naar waarheid te hebben gerapporteerd.'),
      findsOneWidget,
    );
    expect(find.text('J. Jansen'), findsOneWidget); // the typed mark
    expect(find.text('Jan Jansen · CISO'), findsOneWidget);
    expect(find.text('OSCP'), findsOneWidget);
    expect(find.text('2026-07-10'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('an embedded data-URI image is drawn instead of the typed name', (
    tester,
  ) async {
    await pump(tester, const DocumentSignature(name: 'X', imagePath: dataUri));

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a non-data image path falls back to the typed name', (
    tester,
  ) async {
    await pump(
      tester,
      const DocumentSignature(
        name: 'Naam',
        typedSignature: 'Handtekening',
        imagePath: 'signature.png',
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.text('Handtekening'), findsOneWidget);
  });

  testWidgets('a malformed data URI is ignored and falls back', (tester) async {
    await pump(
      tester,
      const DocumentSignature(
        name: 'Naam',
        typedSignature: 'Terugval',
        imagePath: 'data:image/png;base64,%%not-base64%%',
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.text('Terugval'), findsOneWidget);
  });

  testWidgets('compact layout still renders the content', (tester) async {
    await pump(
      tester,
      const DocumentSignature(name: 'Compact', role: 'Rol'),
      compact: true,
    );

    expect(find.text('Compact · Rol'), findsOneWidget);
  });
}
