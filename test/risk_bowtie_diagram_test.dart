// Tests voor de grafische bowtie-projectie (#2496): deterministische
// Mermaid uit dezelfde tabel, gedeelde knopen voor gedeelde maatregelen,
// status als tekst én stijl, en de render-export die het diagram voor de
// tabel zet zonder de bron aan te raken.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/ocideck_marked_table.dart';
import 'package:ocideck/services/risk_bowtie_diagram.dart';

const _dossier = '''
<!-- ocideck:bowtie v1 id=bt1 rev=1 cols=path,side,role,element,measure,status,owner -->
| Pad | Zijde | Rol | Element | Maatregel | Status | Eigenaar |
|---|---|---|---|---|---|---|
| P-1 | links | threat | Corrosie | | | |
| P-1 | links | barrier-preventive | Coating inspecteren | M-001 | werkt | J.J. |
| P-1 | links | escalation | Inspectiecapaciteit te kort | | voorgesteld | |
| P-1 | top | top-event | Breuk in leiding | | | |
| P-1 | rechts | barrier-mitigating | Noodafsluiter | M-002 | gepland | |
| P-1 | rechts | consequence | Overstrooming | | | |
| P-2 | links | threat | Externe graafschade | | | |
| P-2 | links | barrier-preventive | Coating inspecteren | M-001 | werkt | J.J. |
| P-2 | top | top-event | Breuk in leiding | | | |
| P-2 | rechts | barrier-mitigating | Noodafsluiter | M-002 | gepland | |
| P-2 | rechts | consequence | Bodemverontreiniging | | | |
''';

void main() {
  test('de projectie is deterministisch en deelt knopen', () {
    final table = scanOciMarkedTables(_dossier).tables.first;
    final a = ociBowtieMermaid(table)!;
    expect(ociBowtieMermaid(table), a);
    expect(a, startsWith('flowchart LR'));
    // De gedeelde maatregel M-001 is één knoop, geen twee.
    expect('m_m_001["'.allMatches(a).length, 1);
    // En het padverhaal staat er als keten.
    expect(a, contains('t_corrosie --> m_m_001'));
    expect(a, contains('m_m_001 --> top_breuk_in_leiding'));
    expect(a, contains('top_breuk_in_leiding --> m_m_002'));
    // Escalatiefactor: gestippeld op de barrière die hij aantast —
    // de preventieve, niet de mitigerende die later in de rij komt.
    expect(a, contains('-.-> m_m_001'));
    // Status als tekst én stijl — gepland is geen bewezen dekking.
    expect(a, contains('○ gepland'));
    expect(a, contains('✓ werkt'));
    expect(a, contains(':::barrierDraft'));
    expect(a, contains(':::barrierOk'));
  });

  test('een open pad krijgt geen verzonnen verbinding', () {
    final open = _dossier.replaceAll(
      '| P-1 | rechts | barrier-mitigating | Noodafsluiter | M-002 | gepland | |\n',
      '',
    );
    final table = scanOciMarkedTables(open).tables.first;
    final a = ociBowtieMermaid(table)!;
    // P-1 zonder mitigerende barrière: top → gevolg direct, zichtbaar open.
    expect(a, contains('top_breuk_in_leiding --> c_overstrooming'));
  });

  test('speciale tekens in labels breken de grammatica niet', () {
    final tricky = _dossier.replaceAll(
      'Corrosie',
      'Scheur (druk) "boven" [x]; a<b',
    );
    final table = scanOciMarkedTables(tricky).tables.first;
    final a = ociBowtieMermaid(table)!;
    expect(a, isNot(contains('"boven"')));
    expect(a, contains('#quot;'));
  });

  test('de render-export zet het diagram vóór de bron-tabel', () {
    final out = markdownWithBowtieDiagrams(_dossier);
    final mermaid = out.indexOf('```mermaid');
    final tableRow = out.indexOf('| P-1 | links | threat');
    expect(mermaid, greaterThan(-1));
    expect(mermaid, lessThan(tableRow));
    // De brontekst zelf blijft onaangeroerd.
    expect(out, contains('<!-- ocideck:bowtie'));
    expect(markdownWithBowtieDiagrams('geen bowtie'), 'geen bowtie');
  });

  test('schermlezer-alternatief noemt de paden', () {
    final table = scanOciMarkedTables(_dossier).tables.first;
    final label = ociBowtieSemanticsLabel(table);
    expect(label, contains('P-1'));
    expect(label, contains('Corrosie'));
    expect(label, contains('Overstrooming'));
  });
}
