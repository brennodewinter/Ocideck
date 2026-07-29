import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_safety.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/openkat/openkat_aggregator.dart';
import 'package:ocideck/services/openkat/openkat_report_composer.dart';
import 'package:ocideck/services/openkat/openkat_report_facts.dart';

OpenKatFinding _finding(
  String id, {
  String severity = 'high',
  String? name,
  String? recommendation,
  List<String> cveIds = const [],
}) => OpenKatFinding(
  id: id,
  findingTypeId: 'KAT-$id',
  findingTypeName: name ?? 'Finding $id',
  severity: severity,
  systemId: 'asset-$id.example',
  recommendation: recommendation,
  cveIds: cveIds,
);

OpenKatSnapshot _snapshot(
  DateTime date, {
  required String source,
  List<OpenKatFinding> findings = const [],
  Set<OpenKatSourceFeature> sourceFeatures = const {},
}) => OpenKatSnapshot(
  reportDate: date,
  sourceFile: source,
  sourceHash: 'sha256:$source',
  systems: [
    for (final finding in findings)
      OpenKatSystem(
        id: finding.systemId!,
        hostname: finding.systemId,
        stableIdentity: true,
      ),
  ],
  findings: findings,
  sourceFeatures: sourceFeatures,
);

OpenKatOrganization _organization(List<OpenKatSnapshot> snapshots) =>
    OpenKatOrganization(code: 'alpha', name: 'Alpha', snapshots: snapshots);

OpenKatReportRequest _request(
  String scenarioId, {
  OpenKatReportLanguage language = OpenKatReportLanguage.dutch,
  OpenKatReportPolicy policy = const OpenKatReportPolicy(),
  String? cveId,
}) => OpenKatReportRequest(
  scenarioId: scenarioId,
  scope: const OpenKatReportScope.portfolio(),
  currentAsOf: DateTime.utc(2026, 7, 20),
  language: language,
  policy: policy,
  cveId: cveId,
);

Slide _slideWithTitle(Iterable<Slide> slides, String title) =>
    slides.singleWhere((slide) => slide.title == title);

void main() {
  test(
    'een managementblok bewaart eerder gecomponeerde blokken en één titel',
    () {
      final facts = OpenKatReportFacts([
        _organization([
          _snapshot(DateTime.utc(2026, 7, 20), source: 'alpha.json'),
        ]),
      ]);
      final deck = OpenKatReportComposer(facts).compose(
        _request('custom-order'),
        const OpenKatReportPlan(
          scenarioId: 'custom-order',
          blocks: [
            OpenKatReportBlock(
              id: 'availability',
              kind: OpenKatReportBlockKind.measurementAvailability,
            ),
            OpenKatReportBlock(
              id: 'management',
              kind: OpenKatReportBlockKind.managementOverview,
            ),
          ],
        ),
      );

      expect(
        deck.slides.where((slide) => slide.type == SlideType.title),
        hasLength(1),
      );
      expect(deck.slides[1].title, 'Gebruikte meetmomenten');
      expect(deck.slides.any((slide) => slide.title == 'Kerncijfers'), isTrue);
    },
  );

  test('OpenKAT-aanbevelingen blijven letterlijke, veilige tekst', () {
    final facts = OpenKatReportFacts([
      _organization([
        _snapshot(
          DateTime.utc(2026, 7, 20),
          source: 'alpha.json',
          findings: [
            _finding(
              'injection',
              name: '# Onechte kop',
              recommendation:
                  'Controleer dit\n---\n# Alles is veilig\n<script>x()</script>',
            ),
          ],
        ),
      ]),
    ]);
    final deck = OpenKatReportComposer(facts).compose(
      _request('management-overview'),
      const OpenKatReportPlan(
        scenarioId: 'management-overview',
        blocks: [
          OpenKatReportBlock(
            id: 'management',
            kind: OpenKatReportBlockKind.managementOverview,
          ),
        ],
      ),
    );
    final markdown = MarkdownService().generateDeck(deck);

    expect(MarkdownSafetyScanner.scan(markdown), isEmpty);
    expect(
      MarkdownService().parseDeck(markdown)!.slides,
      hasLength(deck.slides.length),
    );
    final advice = _slideWithTitle(deck.slides, 'Wat OpenKAT aanraadt');
    expect(advice.bullets.join(' '), contains('--- # Alles is veilig'));
    expect(advice.bullets.join(' '), contains('&lt;script&gt;'));
  });

  test('de rijlimiet begrenst CVE-rijen vóór deckmaterialisatie', () {
    final findings = [
      for (var i = 0; i < 100; i++)
        _finding('$i', cveIds: const ['CVE-2026-1234']),
    ];
    final facts = OpenKatReportFacts([
      _organization([
        _snapshot(
          DateTime.utc(2026, 7, 20),
          source: 'alpha.json',
          findings: findings,
          sourceFeatures: const {OpenKatSourceFeature.reliableCveReferences},
        ),
      ]),
    ]);
    final deck = OpenKatReportComposer(facts).compose(
      _request(
        'cve-exposure',
        cveId: 'CVE-2026-1234',
        policy: const OpenKatReportPolicy(tableRowLimit: 3),
      ),
      const OpenKatReportPlan(
        scenarioId: 'cve-exposure',
        blocks: [
          OpenKatReportBlock(
            id: 'cve',
            kind: OpenKatReportBlockKind.cveExposure,
          ),
        ],
      ),
    );
    final exposure = _slideWithTitle(
      deck.slides,
      'Blootstelling aan CVE-2026-1234',
    );

    expect(exposure.tableRows, hasLength(5));
    expect(exposure.tableRows.last.first, contains('Meer resultaten'));
    expect(exposure.viewLimit, isNull);
  });

  test('Engelse trendtekst wordt uit getypepte feiten opgebouwd', () {
    final previous = _snapshot(
      DateTime.utc(2026, 7, 13),
      source: 'previous.json',
      findings: [_finding('old', severity: 'critical')],
    );
    final current = _snapshot(
      DateTime.utc(2026, 7, 20),
      source: 'current.json',
    );
    final facts = OpenKatReportFacts([
      _organization([previous, current]),
    ]);
    final deck =
        OpenKatReportComposer(
          facts,
          language: OpenKatReportLanguage.english,
        ).compose(
          _request(
            'management-overview',
            language: OpenKatReportLanguage.english,
          ),
          const OpenKatReportPlan(
            scenarioId: 'management-overview',
            blocks: [
              OpenKatReportBlock(
                id: 'management',
                kind: OpenKatReportBlockKind.managementOverview,
              ),
            ],
          ),
        );
    final keyMessage = _slideWithTitle(deck.slides, 'What this report says');

    expect(keyMessage.bullets, contains('1 fewer critical findings'));
    final conclusion = facts.compare(
      facts.aggregateSnapshot(current),
      facts.aggregateSnapshot(previous),
    );
    final critical = conclusion.facts.singleWhere(
      (fact) => fact.metric == OpenKatTrendMetric.criticalFindings,
    );
    expect(critical.delta, -1);
  });
}
