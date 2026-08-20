// De fail-closed garantie voor het PDF-exportpad (DOCUMENT_MODE.md §11.5, eis 2).
//
// De compiler bewaakt dát de body via een `AudienceDeck` reist, niet dát er
// werkelijk geredigeerd wordt. Voor de `.md`- en HTML-uitvoer meet
// `document_export_privacy_test.dart` dat laatste op de geprojecteerde tekst.
// Voor een PDF is die meting niet genoeg: de tekst gaat daarna nog door een
// zetter heen, en de vraag is of het geleverde *bestand* het gegeven draagt.
// Deze test opent daarom de PDF zelf.
//
// De controletest hoort er onlosmakelijk bij. Een test die alleen "het BSN staat
// er niet in" beweert, staat ook groen als het hulpje niets kán lezen — dan meet
// hij niets. Daarom bewijst de eerste test dat het volledige profiel het nummer
// wél in het bestand zet.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/pdf/document_pdf_export.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';

import 'pdf_text_probe.dart';

void main() {
  // Een elfproef-conform BSN mét het contextwoord ernaast — precies de vorm die
  // `privacy_projection_test.dart` als `certain` bewijst. In de prosa én in een
  // tabelcel, zodat beide takken van de bridge langs de scan komen.
  const bsn = '728398242';
  const body =
      '## Bevinding\n'
      '\n'
      'toelichting met BSN $bsn hier\n'
      '\n'
      '| Naam | BSN |\n'
      '| --- | --- |\n'
      '| Jan Jansen | $bsn |\n';

  const labels = DocumentPdfLabels(
    tocTitle: 'Inhoud',
    footnotesTitle: 'Noten',
    mathLabel: 'formule',
    mermaidLabel: 'diagram',
    chartLabel: 'grafiek',
  );

  Future<String> pdfTextFor(PrivacyExportProfile profile) async {
    final bundle = await buildDocumentExportBundle(
      body,
      projectPath: null,
      profile: profile,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
    );
    final result = await buildDocumentExportPdf(bundle, labels: labels);
    return pdfVisibleText(result.bytes);
  }

  test('het volledige profiel zet het nummer wél in de PDF', () async {
    // De controle: zonder deze test bewijst de volgende niets.
    expect(await pdfTextFor(PrivacyExportProfile.full), contains(bsn));
  });

  test('het geredigeerde profiel laat geen BSN in de PDF achter', () async {
    final text = await pdfTextFor(PrivacyExportProfile.redacted);
    expect(text, isNot(contains(bsn)));
    // Ook niet in de tabelcel, die langs een andere tak van de bridge gaat.
    expect(text, contains('Jan Jansen'));
  });

  test('de melding over ontbrekende tekens blijft leeg bij gewone tekst', () async {
    final bundle = await buildDocumentExportBundle(
      '# Verslag\n\nGewone Nederlandse tekst met accenten: café, Zürich.\n',
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
    );
    final result = await buildDocumentExportPdf(bundle, labels: labels);
    expect(result.isComplete, isTrue);
    expect(result.unsupportedCharacters, isEmpty);
  });

  test('tekens die nergens in staan worden geteld, niet stil verzwegen', () async {
    // Zonder terugvalfont reikt de zetter tot Latin-1. Japans valt daarbuiten en
    // verdwijnt uit de tekstlaag; dat hoort de schil te kunnen melden.
    final bundle = await buildDocumentExportBundle(
      '# Verslag\n\n日本語 in de tekst.\n',
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
    );
    final result = await buildDocumentExportPdf(bundle, labels: labels);
    expect(result.isComplete, isFalse);
    expect(
      result.unsupportedCharacters.map(String.fromCharCode).join(),
      contains('日'),
    );
  });
}
