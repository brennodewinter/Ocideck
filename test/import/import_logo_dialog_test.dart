import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/import/logo_detection.dart';
import 'package:ocideck/services/import/models/source_image.dart';
import 'package:ocideck/widgets/dialogs/import_logo_dialog.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  final png = Uint8List.fromList(
    image.encodePng(image.Image(width: 8, height: 4)),
  );
  late ImportLogoCandidate candidate;

  setUp(() {
    candidate = ImportLogoCandidate(
      image: SourceImage(
        bytes: png,
        ext: 'png',
        placement: const SourceImagePlacement(
          left: .8,
          top: .88,
          width: .12,
          height: .08,
        ),
      ),
      slideIndexes: const [0, 2],
      edge: ImportLogoEdge.bottom,
    );
  });

  Future<void> showDialogUnderTest(
    WidgetTester tester,
    void Function(ImportLogoChoice choice) capture, {
    bool canAddAsStyle = true,
    String? knownStyleName,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                capture(
                  await ImportLogoDialog.ask(
                    context,
                    candidate: candidate,
                    suggestedStyleName: 'Stijl van Voorbeeld',
                    canAddAsStyle: canAddAsStyle,
                    knownStyleName: knownStyleName,
                  ),
                );
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
  }

  testWidgets('nee laat de afbeelding een gewone dia-afbeelding', (
    tester,
  ) async {
    ImportLogoChoice? captured;
    await showDialogUnderTest(tester, (choice) => captured = choice);
    expect(find.textContaining('2 dia’s onderaan'), findsOneWidget);

    await tester.tap(find.text('Als afbeelding behouden'));
    await tester.pumpAndSettle();

    expect(captured?.isLogo, isFalse);
    expect(captured?.addAsStyle, isFalse);
  });

  testWidgets('negeren geeft een aparte uitkomst zonder stijlvraag', (
    tester,
  ) async {
    ImportLogoChoice? captured;
    await showDialogUnderTest(tester, (choice) => captured = choice);

    await tester.tap(find.text('Logo niet importeren'));
    await tester.pumpAndSettle();

    expect(captured?.disposition, ImportLogoDisposition.ignore);
    expect(captured?.isIgnored, isTrue);
    expect(captured?.isLogo, isFalse);
    expect(captured?.addAsStyle, isFalse);
    expect(captured?.styleName, isEmpty);
    expect(find.text('Ook als stijl toevoegen?'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('bekende stijl toont extra bewijs en kan worden genegeerd', (
    tester,
  ) async {
    ImportLogoChoice? captured;
    await showDialogUnderTest(
      tester,
      (choice) => captured = choice,
      knownStyleName: 'Gemeentehuis',
    );

    expect(find.text('Logo gevonden'), findsOneWidget);
    expect(
      find.text('Dit logo komt ook voor in de stijl Gemeentehuis.'),
      findsOneWidget,
    );
    expect(find.text('Logo niet importeren'), findsOneWidget);
    await tester.tap(find.text('Logo niet importeren'));
    await tester.pumpAndSettle();

    expect(captured?.disposition, ImportLogoDisposition.ignore);
    expect(find.text('Ook als stijl toevoegen?'), findsNothing);
  });

  testWidgets('bekende stijl wordt bij ja direct als logo gebruikt', (
    tester,
  ) async {
    ImportLogoChoice? captured;
    await showDialogUnderTest(
      tester,
      (choice) => captured = choice,
      knownStyleName: 'Gemeentehuis',
    );

    await tester.tap(find.text('Ja, als logo gebruiken'));
    await tester.pumpAndSettle();

    expect(captured?.disposition, ImportLogoDisposition.useAsLogo);
    expect(captured?.addAsStyle, isFalse);
    expect(find.text('Ook als stijl toevoegen?'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('ja kan het logo alleen voor dit deck gebruiken', (tester) async {
    ImportLogoChoice? captured;
    await showDialogUnderTest(tester, (choice) => captured = choice);
    await tester.tap(find.text('Ja, als logo gebruiken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alleen in deze presentatie'));
    await tester.pumpAndSettle();

    expect(captured?.isLogo, isTrue);
    expect(captured?.addAsStyle, isFalse);
    expect(captured?.styleName, isEmpty);
  });

  testWidgets('ja met naam levert een herbruikbare stijlkeuze', (tester) async {
    ImportLogoChoice? captured;
    await showDialogUnderTest(tester, (choice) => captured = choice);
    await tester.tap(find.text('Ja, als logo gebruiken'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Gemeentehuis  ');
    await tester.tap(find.text('Stijl toevoegen'));
    await tester.pumpAndSettle();

    expect(captured?.isLogo, isTrue);
    expect(captured?.addAsStyle, isTrue);
    expect(captured?.styleName, 'Gemeentehuis');
  });

  testWidgets('zonder duurzame opslag blijft het logo bij dit deck', (
    tester,
  ) async {
    ImportLogoChoice? captured;
    await showDialogUnderTest(
      tester,
      (choice) => captured = choice,
      canAddAsStyle: false,
    );
    expect(find.text('Alleen in deze presentatie'), findsOneWidget);

    await tester.tap(find.text('Ja, als logo gebruiken'));
    await tester.pumpAndSettle();

    expect(captured?.isLogo, isTrue);
    expect(captured?.addAsStyle, isFalse);
    expect(find.text('Ook als stijl toevoegen?'), findsNothing);
  });
}
