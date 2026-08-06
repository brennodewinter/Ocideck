// De deconstructie-invariant-poort (DOCUMENT_MODE.md §11.5, eis 3): geen
// niet-lege bronsectie mag tot een LEEG getypeerd veld leiden. Dit is een
// privacyvereiste, geen netheidswens — een dia die door `documentToDeck` uit
// echte broninhoud ontstaat maar met lege `customMarkdown` én lege `tableRows`
// eindigt, ontsnapt aan de OciWacht-scan (die per getypeerd veld werkt). Precies
// de stille kop-geleide-drop die de oude, op `_inferSlideType` leunende parser
// maakte.
//
// Deze poort neemt een set representatieve documenten (kop-geleid, gemengd
// prosa+tabel, chart, mermaid) door `documentToDeck` en bewijst dat een
// toekomstige regressie die drop niet stil kan herintroduceren.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_deck_bridge.dart';

void main() {
  /// Alle gescande tekst van één dia: `customMarkdown` plus elke cel van
  /// `tableRows` — exact de velden die de invariant beschermt.
  String scannedFields(Slide slide) =>
      '${slide.customMarkdown}${slide.tableRows.expand((r) => r).join()}';

  /// Documenten met inhoud: elk moet zónder verlies deconstrueren.
  const documents = <String, String>{
    'kop-geleid': '# Titel\n\nProsa onder de titel met TOKEN_A.\n',
    'geneste koppen':
        '# Een\n\nprosa TOKEN_B\n\n## Twee\n\nprosa TOKEN_C\n\n### Drie\n\nprosa TOKEN_D\n',
    'gemengd prosa + tabel':
        '## Overzicht\n\ntoelichting TOKEN_E\n\n| Naam | BSN |\n| --- | --- |\n| TOKEN_F | 123 |\n',
    'chart-sectie':
        '# Cijfers\n\ninleiding TOKEN_G\n\n```chart\nTOKEN_H\n```\n',
    'mermaid-sectie':
        '# Stroom\n\nuitleg TOKEN_I\n\n```mermaid\nflowchart TD\n  A --> B\n```\n',
    'tabel-only': '| A | B |\n| --- | --- |\n| TOKEN_J | TOKEN_K |\n',
    'prosa-only zonder kop': 'gewoon een alinea met TOKEN_L, geen kop\n',
  };

  group('deconstructie-invariant', () {
    for (final entry in documents.entries) {
      test('geen lege getypeerde dia — ${entry.key}', () {
        final deck = DocumentDeckBridge.documentToDeck(entry.value);
        for (final slide in deck.slides) {
          expect(
            scannedFields(slide).trim(),
            isNotEmpty,
            reason:
                'een dia (${slide.type.name}) uit "${entry.key}" heeft géén '
                'gescand veld gevuld — dat is de stille drop die de poort verbiedt',
          );
        }
      });

      test('elk broninhoud-token belandt in een gescand veld — ${entry.key}', () {
        final deck = DocumentDeckBridge.documentToDeck(entry.value);
        final haystack = deck.slides.map(scannedFields).join('\n');
        final tokens = RegExp(
          r'TOKEN_[A-Z]',
        ).allMatches(entry.value).map((m) => m.group(0)!);
        for (final token in tokens) {
          expect(
            haystack.contains(token),
            isTrue,
            reason:
                '$token uit "${entry.key}" mag in geen enkel dia-veld ontbreken',
          );
        }
      });
    }

    test('een leeg document is de enige toegestane lege dia', () {
      final deck = DocumentDeckBridge.documentToDeck('');
      expect(deck.slides, hasLength(1));
      expect(deck.slides.single.customMarkdown, isEmpty);
      expect(deck.slides.single.tableRows, isEmpty);
    });
  });
}
