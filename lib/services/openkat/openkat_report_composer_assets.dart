part of 'openkat_report_composer.dart';

class _OpenKatReportAssetRenderer extends _OpenKatRenderer {
  const _OpenKatReportAssetRenderer(super.composer);

  List<Slide> assetInventory(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final rows =
        <
          ({
            String organization,
            DateTime date,
            OpenKatSystem system,
            bool findings,
          })
        >[];
    for (final selection in facts.selections(request)) {
      final snapshot = selection.current;
      if (snapshot == null) continue;
      final affected = snapshot.findings
          .map((finding) => finding.systemId)
          .whereType<String>()
          .toSet();
      for (final system in snapshot.systems) {
        rows.add((
          organization: selection.organization.code,
          date: snapshot.reportDate,
          system: system,
          findings: affected.contains(system.id),
        ));
      }
    }
    rows.sort((a, b) {
      var result = a.organization.compareTo(b.organization);
      if (result != 0) return result;
      return a.system.id.compareTo(b.system.id);
    });
    final bounded = _bounded(rows, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'inventory'),
        type: SlideType.table,
        title: _text(
          'Systemen in de gekozen metingen',
          'Systems in the selected measurements',
        ),
        subtitle: _text(
          'Geen gekoppelde finding is geen bewijs dat een asset veilig is.',
          'No linked finding is not evidence that an asset is safe.',
        ),
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Systeem', 'System'),
            _text('Hostname', 'Hostname'),
            'IP',
            _text('Gekoppelde findings', 'Linked findings'),
            _text('Meetdatum', 'Measurement date'),
          ],
          for (final item in bounded.values)
            [
              _inline(item.organization),
              _inline(item.system.id),
              _inline(item.system.hostname ?? '-'),
              _inline(item.system.ip ?? '-'),
              item.findings ? _text('Ja', 'Yes') : _text('Geen', 'None'),
              _iso(item.date),
            ],
          if (rows.isEmpty) _emptyResultRow(columns: 6),
          if (bounded.omitted)
            _omittedRow(columns: 6, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'inventory'),
        privacy: PrivacyDisposition.redact,
      ),
    ];
  }

  List<Slide> monitoringCoverage(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final counts = <String, Map<String, int>>{};
    for (final selection in facts.selections(request)) {
      final snapshot = selection.current;
      if (snapshot == null) continue;
      final organizationCounts = {
        'monitored': 0,
        'notMonitored': 0,
        'unknown': 0,
      };
      for (final system in snapshot.systems) {
        final key = switch (system.monitoringStatus) {
          OpenKatMonitoringStatus.monitored => 'monitored',
          OpenKatMonitoringStatus.notMonitored => 'notMonitored',
          null => 'unknown',
        };
        organizationCounts[key] = organizationCounts[key]! + 1;
      }
      counts[selection.organization.code] = organizationCounts;
    }
    final bounded = _bounded(counts.entries, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'coverage'),
        type: SlideType.table,
        title: _text('Monitoringdekking', 'Monitoring coverage'),
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Gemonitord', 'Monitored'),
            _text('Expliciet niet gemonitord', 'Explicitly not monitored'),
            _text('Status onbekend', 'Status unknown'),
          ],
          for (final entry in bounded.values)
            [
              _inline(entry.key),
              '${entry.value['monitored']}',
              '${entry.value['notMonitored']}',
              '${entry.value['unknown']}',
            ],
          if (counts.isEmpty) _emptyResultRow(columns: 4),
          if (bounded.omitted)
            _omittedRow(columns: 4, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'coverage'),
      ),
    ];
  }

  List<Slide> monitoringChanges(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final changes = facts.monitoringMutations(
      request,
      maxResults: _constructionLimit(request, block) + 1,
    );
    final bounded = _bounded(changes, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'changes'),
        type: SlideType.table,
        title: _text('Monitoringmutaties', 'Monitoring changes'),
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Asset', 'Asset'),
            _text('Verandering', 'Change'),
          ],
          for (final change in bounded.values)
            [
              _inline(change.organizationCode),
              _inline(change.system.id),
              change.kind == OpenKatMonitoringMutationKind.added
                  ? _text('Toegevoegd aan monitoring', 'Added to monitoring')
                  : _text('Niet meer in monitoring', 'No longer in monitoring'),
            ],
          if (changes.isEmpty) _emptyResultRow(columns: 3),
          if (bounded.omitted)
            _omittedRow(columns: 3, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'changes'),
      ),
    ];
  }

  List<Slide> organizationOverview(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final selection = facts.selections(request).first;
    final snapshot = selection.current!;
    final aggregate = facts.aggregateSnapshot(snapshot);
    return [
      _scorecardSlide(
        id: _blockId(request, block, 'summary'),
        title:
            '${_literal(selection.organization.name)} — '
            '${_text('huidige meting', 'current measurement')}',
        entries: [
          ScorecardEntry(
            label: _text('Gemeten systemen', 'Measured systems'),
            value: aggregate.totalSystems.toDouble(),
            polarity: ScorecardPolarity.neutral,
          ),
          ScorecardEntry(
            label: _text('Waargenomen findings', 'Observed findings'),
            value: aggregate.totalFindings.toDouble(),
            polarity: ScorecardPolarity.neutral,
          ),
          for (final band in openKatSeverityOrder)
            ScorecardEntry(
              label: _severityLabel(band),
              value: (aggregate.severityCounts[band] ?? 0).toDouble(),
              polarity: ScorecardPolarity.neutral,
            ),
        ],
        view: _blockView(request, block, 'summary'),
      ),
      _slide(
        id: _blockId(request, block, 'measurement'),
        type: SlideType.bullets,
        title: _text('Gebruikte meting', 'Measurement used'),
        bullets: [
          '${_text('Werkelijke meetdatum', 'Actual measurement date')}: '
              '${_iso(snapshot.reportDate)}',
          '${_text('Bronbestand', 'Source file')}: '
              '${_literal(snapshot.sourceFile)}',
        ],
        notes: _blockNotes(request, block, 'measurement'),
      ),
    ];
  }
}
