// De web-waarschuwing bij document-export (DOCUMENT_MODE.md §11.4).
//
// Op web vertrekt een .md- of .tex-export als één losse download — de browser
// neemt geen map mee. Een document dat naar afbeeldingen of grafiekdata in
// losse bestanden verwijst, leverde daarmee een export met dode paden zonder
// dat iemand het zag. Deze test bewaakt twee dingen: dat de detectie precies
// de verwijzingen vindt die niet meereizen (en de zelfvoorzienende laat
// staan), en dat de bevestigingsdialoog de gebruiker de keuze geeft —
// waarschuwen, niet blokkeren.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/widgets/dialogs/document_export_dialog.dart';

void main() {
  group('documentMarkdownHasExternalAssetRefs', () {
    test(
      'relatieve afbeeldingspaden reizen niet mee in een losse download',
      () {
        expect(
          documentMarkdownHasExternalAssetRefs(
            '# Titel\n\n![grafiek](images/omzet.png)\n',
          ),
          isTrue,
        );
        // Ook een pad zonder images/-prefix telt: het staat naast het document.
        expect(
          documentMarkdownHasExternalAssetRefs('![x](foto.jpg)\n'),
          isTrue,
        );
      },
    );

    test('mem:- en absolute paden reizen evenmin mee', () {
      expect(
        documentMarkdownHasExternalAssetRefs('![x](mem:abc-123)\n'),
        isTrue,
      );
      expect(
        documentMarkdownHasExternalAssetRefs(
          '![x](/home/user/plaatjes/foto.png)\n',
        ),
        isTrue,
      );
    });

    test('URL\'s en data-URI\'s zijn zelfvoorzienend of al extern', () {
      expect(
        documentMarkdownHasExternalAssetRefs(
          '![x](https://voorbeeld.nl/x.png)\n'
          '![y](data:image/png;base64,aGk=)\n',
        ),
        isFalse,
      );
    });

    test('een afbeelding met titel achter het pad telt ook', () {
      expect(
        documentMarkdownHasExternalAssetRefs(
          '![x](images/a.png "onderschrift")\n',
        ),
        isTrue,
      );
    });

    test('HTML-mediaverwijzingen tellen', () {
      expect(
        documentMarkdownHasExternalAssetRefs(
          '<img src="images/logo.png" alt="logo">\n',
        ),
        isTrue,
      );
      expect(
        documentMarkdownHasExternalAssetRefs(
          '<video src="mem:clip-1"></video>\n',
        ),
        isTrue,
      );
      expect(
        documentMarkdownHasExternalAssetRefs(
          '<img src="https://cdn.example/x.png">\n',
        ),
        isFalse,
      );
    });

    test('een chart-blok met source: verwijst naar een los databestand', () {
      const metSource =
          '```chart\n'
          '{"type": "bar", "source": "data/omzet.json"}\n'
          '```\n';
      expect(documentMarkdownHasExternalAssetRefs(metSource), isTrue);

      // Inline data staat in het blok zelf en reist gewoon mee.
      const inline =
          '```chart\n'
          '{"type": "bar", "x": ["a"], "series": [{"name": "s", "y": [1]}]}\n'
          '```\n';
      expect(documentMarkdownHasExternalAssetRefs(inline), isFalse);
    });

    test('platte tekst zonder verwijzingen valt stil uit', () {
      expect(
        documentMarkdownHasExternalAssetRefs(
          '# Titel\n\nGewone tekst met [een link](https://example.nl).\n',
        ),
        isFalse,
      );
    });
  });

  group('confirmDocumentExportWebAssetLoss', () {
    Future<bool?> toonEnBeantwoord(WidgetTester tester, String knop) async {
      bool? antwoord = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  antwoord = await confirmDocumentExportWebAssetLoss(ctx);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(knop));
      await tester.pumpAndSettle();
      return antwoord;
    }

    testWidgets(
      'toont de waarschuwing met de weg om alles in één bestand te leveren',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => confirmDocumentExportWebAssetLoss(ctx),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(
          find.text('Afbeeldingen en grafiekdata gaan niet mee'),
          findsOneWidget,
        );
        // De melding noemt de consequentie én de uitweg — een melding zonder
        // "wat nu" laat de gebruiker net zo verstoken als geen melding.
        expect(find.textContaining('HTML, PDF of DOCX'), findsOneWidget);
        expect(find.text('Annuleren'), findsOneWidget);
        expect(find.text('Doorgaan'), findsOneWidget);
      },
    );

    testWidgets('Doorgaan geeft true, Annuleren geeft false', (tester) async {
      expect(await toonEnBeantwoord(tester, 'Doorgaan'), isTrue);
      expect(await toonEnBeantwoord(tester, 'Annuleren'), isFalse);
    });
  });
}
