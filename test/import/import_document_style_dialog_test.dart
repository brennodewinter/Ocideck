// De stijldialoog van de documentimport (#2119) op zichzelf: wat hij toont
// bij een gegeven bronstijl, los van een echt bestand.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/import/models/source_document_style.dart';
import 'package:ocideck/widgets/dialogs/import_document_style_dialog.dart';

import 'helpers/docx_styled_fixture.dart' show fixtureLogoPng;

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<Future<ImportDocumentStyleChoice>> open(
    WidgetTester tester,
    SourceDocumentStyle style, {
    String? existing,
    bool sessionOnly = false,
  }) async {
    late Future<ImportDocumentStyleChoice> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => result = ImportDocumentStyleDialog.ask(
                context,
                style: style,
                suggestedStyleName: 'Stijl van Test',
                existingStyleName: existing,
                logoIsSessionOnly: sessionOnly,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return Future<Future<ImportDocumentStyleChoice>>.value(result);
  }

  testWidgets('kopkleuren per niveau worden één regel, in het meervoud', (
    tester,
  ) async {
    final result = await open(
      tester,
      const SourceDocumentStyle(
        headingFontFamily: 'Aptos',
        losses: [
          DocumentStyleLoss(
            DocumentStyleLossKind.perLevelHeadingColor,
            detail: '2:#1E78B5',
          ),
          DocumentStyleLoss(
            DocumentStyleLossKind.perLevelHeadingColor,
            detail: '5:#00343B',
          ),
          DocumentStyleLoss(DocumentStyleLossKind.titlePageImage),
        ],
      ),
    );
    expect(
      find.textContaining('Kopniveaus 2, 5 hebben elk een eigen kleur'),
      findsOneWidget,
    );
    expect(find.textContaining('#1E78B5, #00343B'), findsOneWidget);
    expect(find.textContaining('titelblad'), findsOneWidget);
    // Twee regels in totaal, niet drie.
    expect(find.textContaining('• '), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('import-document-style-text-only')));
    await tester.pumpAndSettle();
    expect((await result).disposition, ImportDocumentStyleDisposition.textOnly);
  });

  testWidgets('het naamveld staat boven de secties en is meteen zichtbaar', (
    tester,
  ) async {
    final result = await open(
      tester,
      SourceDocumentStyle(
        bodyFontFamily: 'Aptos Light',
        logoCandidates: [
          DocumentLogoCandidate(
            bytes: fixtureLogoPng(),
            ext: 'png',
            sha256: 'x',
            edge: DocumentLogoEdge.top,
            side: DocumentLogoSide.left,
            centred: true,
            widthMm: 30,
            origin: DocumentLogoOrigin.header,
          ),
        ],
        losses: const [DocumentStyleLoss(DocumentStyleLossKind.centredLogo)],
      ),
      sessionOnly: true,
    );
    final name = tester.getTopLeft(
      find.byKey(const Key('import-document-style-name')),
    );
    final logo = tester.getTopLeft(
      find.byKey(const Key('import-document-style-logo')),
    );
    expect(name.dy, lessThan(logo.dy));
    expect(find.textContaining('gecentreerd bovenaan'), findsOneWidget);
    expect(find.textContaining('30 mm'), findsOneWidget);
    expect(find.textContaining('alleen deze sessie'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('import-document-style-name')),
      'Mijn stijl',
    );
    await tester.tap(find.byKey(const Key('import-document-style-new')));
    await tester.pumpAndSettle();
    final choice = await result;
    expect(choice.disposition, ImportDocumentStyleDisposition.newStyle);
    expect(choice.styleName, 'Mijn stijl');
    expect(choice.includeLogo, isTrue);
  });

  testWidgets('met een bestaand profiel is hergebruik de hoofdknop', (
    tester,
  ) async {
    final result = await open(
      tester,
      const SourceDocumentStyle(bodyFontFamily: 'Cambria'),
      existing: 'Huisstijl',
    );
    expect(
      find.textContaining('bestaat al als de stijl Huisstijl'),
      findsOneWidget,
    );
    expect(find.textContaining('EB Garamond'), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-document-style-existing')));
    await tester.pumpAndSettle();
    expect(
      (await result).disposition,
      ImportDocumentStyleDisposition.useExisting,
    );
  });
}
