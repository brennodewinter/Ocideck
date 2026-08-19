// Een documentexport mag een lange sectie niet herhalen (#1589).
//
// `expandRichTextForRender` klapt sinds #1409 ook `freeMarkdown` uit, en elke
// kopie draagt de **héle** body — alleen `Slide.renderPage` verschilt. Dat is
// een lijst om te *tekenen*, nooit om weg te schrijven; `MarkdownService` zegt
// dat zelf en filtert erop. Het documentexportpad liep er dwars doorheen:
// `buildExportBundle` klapte onvoorwaardelijk uit vóór de projectie, en
// `deckToDocumentMarkdown` schreef alle kopieën achter elkaar weg.
//
// Twee assertions, met opzet allebei:
// - de uitkomst (elke alinea precies één keer) is wat de gebruiker merkt;
// - de naad (`renderPage == 0` op élke dia in de bundel) is waaróm, en die
//   bewaakt tegelijk dat de scan en het redactiemanifest niet meer over N
//   identieke kopieën lopen. Alleen de uitkomst toetsen zou een filter achteraf
//   in `deckToDocumentMarkdown` groen laten, terwijl het manifest dan nog steeds
//   entries krijgt op dia-indexen die in het geëxporteerde document niet bestaan.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';

void main() {
  // Eén kop met genoeg doorlopende tekst eronder om over meerdere
  // renderpagina's te lopen. Elke alinea is uniek en herkenbaar, zodat een
  // herhaling te tellen is in plaats van te vermoeden.
  final alineas = [
    for (var i = 1; i <= 60; i++)
      'Alinea $i: de bevinding werd tijdens het onderzoek vastgesteld en is '
          'hier feitelijk beschreven zodat de lezer haar kan navolgen.',
  ];
  final body = '# Hoofdstuk\n\n${alineas.join('\n\n')}\n';

  Future<ExportBundle> bundelVoor() => buildDocumentExportBundle(
    body,
    projectPath: null,
    profile: PrivacyExportProfile.full,
    ownIdentity: OwnIdentity.empty,
    regions: defaultPrivacyRegions,
    disabledRules: const {},
    markdownService: MarkdownService(),
  );

  test('elke alinea komt precies één keer in de geprojecteerde body', () async {
    final out = projectedDocumentBody(await bundelVoor());

    for (final alinea in alineas) {
      expect(
        RegExp(RegExp.escape(alinea)).allMatches(out).length,
        1,
        reason: 'deze alinea is herhaald in de export: $alinea',
      );
    }
  });

  test('geen enkele dia in de bundel is een render-kopie', () async {
    final bundle = await bundelVoor();

    expect(
      bundle.audience.deck.slides.every((s) => s.renderPage == 0),
      isTrue,
      reason:
          'de bundel draagt render-kopieën; die horen niet over de '
          'projectiegrens, want scan en redactiemanifest lopen er dan ook over',
    );
  });
}
