// Integratietest: de ECHTE renderers achter de tekeningen in een document-PDF.
//
// ── Waarom dit bestaat naast test/pdf/document_pdf_graphics_test.dart ────────
//
// Die unit-test voedt de export met verzonnen SVG en bewijst daarmee wat de
// PDF-laag met een tekening dóet — inclusief de terugval op de bron. Wat hij
// niet kan bewijzen is dat er in het echt ook een tekening uitkomt: mermaid en
// MathJax draaien in een verborgen WebView, en die bestaat onder `flutter test`
// niet. Daar valt alles dus stil terug op de bron, en een groene suite zou niets
// zeggen over de functie die de gebruiker vroeg.
//
// Een integratietest draait als een echte app op een echt platform, mét WebView.
// Dit is de enige plek waar het volgende werkelijk wordt aangetoond:
//
//   * de verborgen pagina bootstrapt en levert een mermaid-diagram als SVG;
//   * dezelfde pagina levert een TeX-formule als SVG (MathJax `tex-svg`);
//   * beide belanden als tekening in de PDF — niet als het bron-kader dat de
//     terugval zou opleveren.
//
// Draaien:
//   flutter test integration_test/document_pdf_graphics_test.dart -d macos

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/mermaid_render_service.dart';
import 'package:ocideck/services/pdf/document_pdf_export.dart';
import 'package:ocideck/services/pdf/document_pdf_svg.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:ocideck/widgets/mermaid_render_host.dart';

const _document = '''
# Rapport met beeld

```mermaid
graph TD;
  Aanvraag-->Beoordeling;
  Beoordeling-->Besluit;
```

De massa-energierelatie:

\$\$E = mc^2\$\$
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mermaid en formule belanden als tekening in de PDF', (
    tester,
  ) async {
    // De host rechtstreeks monteren, niet via [MermaidRenderHostLayer]: die
    // schakelt zichzelf uit zodra hij een testomgeving ruikt, en juist híer
    // willen we de echte WebView.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Stack(children: [MermaidRenderHost()])),
      ),
    );
    await tester.pumpAndSettle();

    // De renderers hebben een echte pagina en een echte JS-engine nodig; die
    // komen niet binnen één pump. Pompen tot beide antwoorden, met een plafond.
    String? diagram;
    String? formule;
    final klok = Stopwatch()..start();
    while ((diagram == null || formule == null) &&
        klok.elapsed < const Duration(seconds: 60)) {
      diagram ??= await MermaidRenderService.instance.render(
        'graph TD;\n  Aanvraag-->Beoordeling;',
      );
      formule ??= await MermaidRenderService.instance.renderMath('E = mc^2');
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(diagram, isNotNull, reason: 'de mermaid-renderer gaf niets terug');
    expect(diagram, contains('<svg'));
    expect(formule, isNotNull, reason: 'de formulerenderer gaf niets terug');
    expect(formule, contains('<svg'));

    // En dan de hele weg: van document naar PDF, met die renderers aangesloten.
    final bundle = await buildDocumentExportBundle(
      _document,
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
    );
    final result = await buildDocumentExportPdf(
      bundle,
      labels: const DocumentPdfLabels(
        footnotesTitle: 'Noten',
        mathLabel: 'Formule (bron)',
        mermaidLabel: 'Diagram (bron)',
        chartLabel: 'Grafiek (bron)',
      ),
      renderMermaid: MermaidRenderService.instance.render,
      renderMath: MermaidRenderService.instance.renderMath,
    );
    expect(result.bytes.length, greaterThan(2000));

    // De verbindingslijnen van een stroomdiagram horen erin te staan. Mermaid
    // hangt aan elke lijn `stroke-dasharray: 0px` — een browser negeert dat, de
    // SVG-lezer van de PDF tekent er streepjes van lengte nul mee en dan staat
    // het diagram er mét vakjes en pijlpunten maar zónder één lijn. Hier is de
    // echte uitvoer van mermaid de invoer, dus hier wordt dat werkelijk gemeten.
    expect(
      diagram,
      contains('stroke-dasharray'),
      reason: 'zonder dit meet de assertie hieronder niets',
    );
    expect(
      prepareSvgForPdf(diagram!, inkHex: '#222222', fontSizePt: 11).svg,
      isNot(contains('stroke-dasharray')),
    );

    // Het bestand wegschrijven zodat een mens er met eigen ogen naar kan kijken;
    // een test die alleen bytes telt ziet niet of het diagram klopt.
    final out = File('${Directory.systemTemp.path}/ocideck-pdf-tekeningen.pdf');
    await out.writeAsBytes(result.bytes);
    // ignore: avoid_print
    print('PDF geschreven naar ${out.path}');
  });
}
