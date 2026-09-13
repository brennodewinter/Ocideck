import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/reader/pdf_evidence_viewer.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Widget host(Widget child) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  testWidgets('toont PDF-bewijs als lokale alleen-lezen werkruimte', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PdfEvidenceViewer(
          bytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
          fileName: 'ondertekend-bewijs.pdf',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ondertekend-bewijs.pdf'), findsOneWidget);
    expect(find.textContaining('OciDeck controleert'), findsOneWidget);
    expect(find.byTooltip('Uitzoomen'), findsOneWidget);
    expect(find.byTooltip('Inzoomen'), findsOneWidget);
    expect(find.byTooltip('Sluiten'), findsOneWidget);
  });

  testWidgets('open gebruikt de hoofd-navigator en sluiten keert terug', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => PdfEvidenceViewer.open(
              context,
              bytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
              fileName: 'route-bewijs.pdf',
            ),
            child: const Text('Start'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('route-bewijs.pdf'), findsOneWidget);

    await tester.tap(find.byTooltip('Sluiten'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Start'), findsOneWidget);
  });
}
