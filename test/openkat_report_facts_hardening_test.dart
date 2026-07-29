import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/services/openkat/openkat_report_facts.dart';

OpenKatFinding _finding(String id) => OpenKatFinding(
  id: id,
  findingTypeId: 'KAT-$id',
  severity: 'high',
  stableIdentity: true,
);

OpenKatSnapshot _snapshot({
  required int day,
  List<OpenKatFinding> findings = const [],
  List<OpenKatSystem> systems = const [],
}) => OpenKatSnapshot(
  reportDate: DateTime.utc(2026, 7, day),
  sourceFile: '2026-07-$day.json',
  sourceHash: 'sha256:$day',
  findings: findings,
  systems: systems,
);

OpenKatOrganization _organization(List<OpenKatSnapshot> snapshots) =>
    OpenKatOrganization(code: 'alpha', name: 'Alpha', snapshots: snapshots);

OpenKatReportRequest _request() => OpenKatReportRequest(
  scenarioId: 'hardening',
  scope: const OpenKatReportScope.portfolio(),
  currentAsOf: DateTime.utc(2026, 7, 14),
  previousAsOf: DateTime.utc(2026, 7, 7),
);

OpenKatSystem _system(
  String id,
  OpenKatMonitoringStatus? status, {
  bool stableIdentity = true,
}) => OpenKatSystem(
  id: id,
  stableIdentity: stableIdentity,
  monitoringStatus: status,
);

class _CountingList<T> extends ListBase<T> {
  final List<T> _values;
  int reads = 0;

  _CountingList(Iterable<T> values) : _values = List.of(values);

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('Alleen-lezen testlijst');

  @override
  T operator [](int index) {
    reads++;
    return _values[index];
  }

  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('Alleen-lezen testlijst');
}

void main() {
  test(
    'expliciete voorganger mag geldige huidige organisatie niet verwijderen',
    () {
      final current = _snapshot(day: 13);
      final facts = OpenKatReportFacts([
        _organization([current]),
      ]);

      final selected = facts.selectedOrganizations(_request());

      expect(selected, hasLength(1));
      expect(selected.single.snapshots, [same(current)]);
    },
  );

  group('monitoringmutaties vereisen volledig overgangsbewijs', () {
    test('meldt alleen een echte overgang van dezelfde stabiele asset', () {
      final facts = OpenKatReportFacts([
        _organization([
          _snapshot(
            day: 6,
            systems: [
              _system('added.example', OpenKatMonitoringStatus.notMonitored),
              _system('removed.example', OpenKatMonitoringStatus.monitored),
              _system('unchanged.example', OpenKatMonitoringStatus.monitored),
              _system('unknown-before.example', null),
              _system(
                'unknown-after.example',
                OpenKatMonitoringStatus.monitored,
              ),
              _system(
                'unstable.example',
                OpenKatMonitoringStatus.notMonitored,
                stableIdentity: false,
              ),
              _system('disappeared.example', OpenKatMonitoringStatus.monitored),
            ],
          ),
          _snapshot(
            day: 13,
            systems: [
              _system('added.example', OpenKatMonitoringStatus.monitored),
              _system('removed.example', OpenKatMonitoringStatus.notMonitored),
              _system('unchanged.example', OpenKatMonitoringStatus.monitored),
              _system(
                'unknown-before.example',
                OpenKatMonitoringStatus.monitored,
              ),
              _system('unknown-after.example', null),
              _system('unstable.example', OpenKatMonitoringStatus.monitored),
              _system('appeared.example', OpenKatMonitoringStatus.monitored),
            ],
          ),
        ]),
      ]);

      expect(
        {
          for (final mutation in facts.monitoringMutations(_request()))
            mutation.system.id: mutation.kind,
        },
        {
          'added.example': OpenKatMonitoringMutationKind.added,
          'removed.example': OpenKatMonitoringMutationKind.removed,
        },
      );
    });

    test('stopt met lezen zodra maxResults is bereikt', () {
      final previous = [
        for (var index = 0; index < 100; index++)
          _system('asset-$index.example', OpenKatMonitoringStatus.notMonitored),
      ];
      final current = _CountingList([
        for (var index = 0; index < 100; index++)
          _system('asset-$index.example', OpenKatMonitoringStatus.monitored),
      ]);
      final facts = OpenKatReportFacts([
        _organization([
          _snapshot(day: 6, systems: previous),
          _snapshot(day: 13, systems: current),
        ]),
      ]);

      expect(
        facts.monitoringMutations(_request(), maxResults: 5),
        hasLength(5),
      );
      expect(current.reads, 5);
    });
  });

  group('findinglevenscyclus schaalt lineair en begrensd', () {
    test(
      'controleert het historische werkbudget zonder volledige ID-index',
      () {
        final facts = OpenKatReportFacts([
          _organization([
            _snapshot(
              day: 1,
              findings: [_finding('history-a'), _finding('history-b')],
            ),
            _snapshot(day: 6),
            _snapshot(day: 13, findings: [_finding('current')]),
          ]),
        ]);

        expect(facts.exceedsHistoricalFindingWorkLimit(_request(), 1), isTrue);
        expect(facts.exceedsHistoricalFindingWorkLimit(_request(), 2), isFalse);
      },
    );

    test('indexeert oudere finding-ID’s precies eenmaal', () {
      final older = _CountingList([
        for (var index = 0; index < 2000; index++) _finding('older-$index'),
      ]);
      final facts = OpenKatReportFacts([
        _organization([
          _snapshot(day: 1, findings: older),
          _snapshot(day: 6),
          _snapshot(
            day: 13,
            findings: [
              for (var index = 0; index < 2000; index++)
                _finding('current-$index'),
            ],
          ),
        ]),
      ]);

      expect(facts.findingLifecycle(_request()), hasLength(2000));
      expect(
        older.reads,
        older.length,
        reason:
            'het aantal huidige findings mag geen nieuwe historische scan '
            'veroorzaken',
      );
    });

    test('materialiseert en leest hoogstens maxResults treffers', () {
      final current = _CountingList([
        for (var index = 0; index < 100; index++) _finding('current-$index'),
      ]);
      final facts = OpenKatReportFacts([
        _organization([
          _snapshot(day: 6),
          _snapshot(day: 13, findings: current),
        ]),
      ]);

      expect(facts.findingLifecycle(_request(), maxResults: 3), hasLength(3));
      expect(current.reads, 3);
    });
  });

  test('CVE-selectie stopt met lezen zodra maxResults is bereikt', () {
    final current = _CountingList([
      for (var index = 0; index < 100; index++)
        OpenKatFinding(
          id: 'finding-$index',
          findingTypeId: 'KAT-$index',
          cveIds: const ['CVE-2026-1234'],
        ),
    ]);
    final facts = OpenKatReportFacts([
      _organization([_snapshot(day: 13, findings: current)]),
    ]);

    expect(
      facts.cveExposure(_request(), 'cve-2026-1234', maxResults: 4),
      hasLength(4),
    );
    expect(current.reads, 4);
  });

  test('maxResults nul stopt vóór het lezen van snapshots', () {
    final snapshots = _CountingList([_snapshot(day: 6), _snapshot(day: 13)]);
    final facts = OpenKatReportFacts([_organization(snapshots)]);

    expect(facts.findingLifecycle(_request(), maxResults: 0), isEmpty);
    expect(
      facts.cveExposure(_request(), 'CVE-2026-1234', maxResults: 0),
      isEmpty,
    );
    expect(facts.monitoringMutations(_request(), maxResults: 0), isEmpty);
    expect(snapshots.reads, 0);
  });

  test('negatieve maxResults wordt geweigerd', () {
    final facts = OpenKatReportFacts(const []);

    expect(
      () => facts.findingLifecycle(_request(), maxResults: -1),
      throwsArgumentError,
    );
    expect(
      () => facts.cveExposure(_request(), 'CVE-2026-1234', maxResults: -1),
      throwsArgumentError,
    );
    expect(
      () => facts.monitoringMutations(_request(), maxResults: -1),
      throwsArgumentError,
    );
  });
}
