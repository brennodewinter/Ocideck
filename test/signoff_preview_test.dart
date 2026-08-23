import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/document_signature.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host({DocumentSignature? signature, String sealedAt = ''}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(
            slide: Slide.create(SlideType.signOff),
            themeProfile: const ThemeProfile(),
            deckSignature: signature,
            sealedAt: sealedAt,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('signOff renders the signature and a sealed status', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        signature: const DocumentSignature(
          name: 'Jan Jansen',
          role: 'Onderzoeker',
          certification: 'OSCP',
          statement: 'Naar waarheid opgesteld.',
          typedSignature: 'J. Jansen',
        ),
        sealedAt: '2026-07-11T10:00:00.000Z',
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Jan Jansen · Onderzoeker'), findsOneWidget);
    expect(find.text('OSCP'), findsOneWidget);
    expect(find.text('J. Jansen'), findsOneWidget);
    // The sealed date (not the full ISO timestamp) is shown.
    expect(find.textContaining('2026-07-11'), findsOneWidget);
    expect(find.textContaining('T10:00'), findsNothing);
  });

  testWidgets('an unsigned, unsealed signOff shows placeholders', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Locale-independent structural check: it still renders a heading + status.
    expect(find.byType(Icon), findsWidgets);
  });
}
