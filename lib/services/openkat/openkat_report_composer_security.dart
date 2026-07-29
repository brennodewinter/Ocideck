part of 'openkat_report_composer.dart';

class _OpenKatReportSecurityRenderer extends _OpenKatRenderer {
  const _OpenKatReportSecurityRenderer(super.composer);

  List<Slide> cveExposure(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final cve = request.cveId!.trim().toUpperCase();
    final exposure = facts.cveExposure(
      request,
      cve,
      maxResults: _constructionLimit(request, block) + 1,
    );
    final bounded = _bounded(exposure, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'exposure'),
        type: SlideType.table,
        title: _text('Blootstelling aan $cve', 'Exposure to $cve'),
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Finding', 'Finding'),
            _text('Systeem', 'System'),
            _text('Ernst', 'Severity'),
          ],
          for (final item in bounded.values)
            [
              _inline(item.organizationCode),
              _inline(
                item.finding.findingTypeName ?? item.finding.findingTypeId,
              ),
              _inline(item.finding.systemId ?? '-'),
              _severityLabel(openKatSeverityBand(item.finding.severity)),
            ],
          if (bounded.omitted)
            _omittedRow(columns: 4, english: _english, shown: bounded.limit),
          if (exposure.isEmpty) _emptyResultRow(columns: 4),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'exposure'),
      ),
    ];
  }

  List<Slide> cveLandscape(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final cves = facts.cveLandscape(request);
    final bounded = _bounded(cves, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'ranking'),
        type: SlideType.table,
        title: _text(
          'CVE’s bij de meeste organisaties',
          'CVEs affecting the most organizations',
        ),
        tableRows: [
          [
            'CVE',
            _text('Organisaties', 'Organizations'),
            _text('Unieke systemen', 'Unique systems'),
            _text('Unieke waarnemingen', 'Unique observations'),
            _text('Critical', 'Critical'),
            _text('High', 'High'),
            _text('Medium', 'Medium'),
            _text('Low', 'Low'),
          ],
          for (final item in bounded.values)
            [
              item.cveId,
              '${item.organizationCount}',
              '${item.systemCount}',
              '${item.observationCount}',
              '${item.severityCounts['critical'] ?? 0}',
              '${item.severityCounts['high'] ?? 0}',
              '${item.severityCounts['medium'] ?? 0}',
              '${item.severityCounts['low'] ?? 0}',
            ],
          if (cves.isEmpty) _emptyResultRow(columns: 8),
          if (bounded.omitted)
            _omittedRow(columns: 8, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'ranking'),
      ),
    ];
  }

  List<Slide> cveChanges(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final changes = facts.cveChangeItems(request);
    final bounded = _bounded(changes, request, block);
    String label(OpenKatCveObservation observation) => switch (observation) {
      OpenKatCveObservation.newlyObserved => _text(
        'Nieuw waargenomen',
        'Newly observed',
      ),
      OpenKatCveObservation.reobserved => _text(
        'Opnieuw waargenomen',
        'Observed again',
      ),
      OpenKatCveObservation.noLongerObserved => _text(
        'Niet meer waargenomen',
        'No longer observed',
      ),
    };
    return [
      _slide(
        id: _blockId(request, block, 'changes'),
        type: SlideType.table,
        title: _text('CVE-veranderingen', 'CVE changes'),
        tableRows: [
          [
            'CVE',
            _text('Waarneming', 'Observation'),
            _text('Organisaties', 'Organizations'),
            _text('Systemen', 'Systems'),
          ],
          for (final item in bounded.values)
            [
              item.cveId,
              label(item.observation),
              _inline((item.organizationCodes.toList()..sort()).join(', ')),
              _inline((item.systemIds.toList()..sort()).join(', ')),
            ],
          if (changes.isEmpty) _emptyResultRow(columns: 4),
          if (bounded.omitted)
            _omittedRow(columns: 4, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'changes'),
      ),
    ];
  }

  List<Slide> controlCoverage(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final rows =
        <({String organization, String id, OpenKatControlScore score})>[];
    for (final selection in facts.selections(request)) {
      final snapshot = selection.current;
      if (snapshot == null) continue;
      for (final entry in snapshot.controls.entries) {
        rows.add((
          organization: selection.organization.code,
          id: entry.key,
          score: entry.value,
        ));
      }
    }
    rows.sort((a, b) {
      final aRatio = a.score.ratio;
      final bRatio = b.score.ratio;
      if (aRatio == null && bRatio != null) return 1;
      if (aRatio != null && bRatio == null) return -1;
      var result = (aRatio ?? 0).compareTo(bRatio ?? 0);
      if (result != 0) return result;
      result = a.organization.compareTo(b.organization);
      if (result != 0) return result;
      return a.id.compareTo(b.id);
    });
    final bounded = _bounded(rows, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'coverage'),
        type: SlideType.table,
        title: _text('Controldekking', 'Control coverage'),
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Control', 'Control'),
            _text('Voldoet', 'Compliant'),
            _text('Totaal', 'Total'),
            _text('Percentage', 'Percentage'),
          ],
          for (final item in bounded.values)
            [
              _inline(item.organization),
              _controlLabel(item.score.name),
              item.score.compliant == null ? '-' : '${item.score.compliant}',
              item.score.total == null ? '-' : '${item.score.total}',
              item.score.ratio == null ? '-' : _percent(item.score.ratio!),
            ],
          if (rows.isEmpty) _emptyResultRow(columns: 5),
          if (bounded.omitted)
            _omittedRow(columns: 5, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'coverage'),
      ),
    ];
  }

  List<Slide> controlChanges(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final changes = facts.controlChanges(request).toList()
      ..sort((a, b) {
        var result = a.delta.compareTo(b.delta);
        if (result != 0) return result;
        result = a.organizationCode.compareTo(b.organizationCode);
        if (result != 0) return result;
        return a.controlId.compareTo(b.controlId);
      });
    final bounded = _bounded(changes, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'changes'),
        type: SlideType.table,
        title: _text('Controlveranderingen', 'Control changes'),
        subtitle: _text(
          'Ratio’s worden alleen vergeleken bij aantoonbaar vergelijkbare meetdekking.',
          'Ratios are compared only when measurement coverage is demonstrably comparable.',
        ),
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Control', 'Control'),
            _text('Vorig', 'Previous'),
            _text('Huidig', 'Current'),
            _text('Absolute verandering', 'Absolute change'),
          ],
          for (final item in bounded.values)
            [
              _inline(item.organizationCode),
              _controlLabel(item.controlId),
              '${item.previousCompliant}/${item.previousTotal} '
                  '(${_percent(item.previousRatio)})',
              '${item.currentCompliant}/${item.currentTotal} '
                  '(${_percent(item.currentRatio)})',
              '${(item.delta * 100).toStringAsFixed(1)} pp',
            ],
          if (changes.isEmpty) _emptyResultRow(columns: 5),
          if (bounded.omitted)
            _omittedRow(columns: 5, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'changes'),
      ),
    ];
  }

  List<Slide> recommendations(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final limit = _constructionLimit(request, block);
    final recommendations = facts.recommendationItems(
      request,
      maxResults: limit + 1,
      maxGroups: block.preconditions.constructionBudget,
    );
    final bounded = _bounded(recommendations, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'ranking'),
        type: SlideType.table,
        title: _text(
          'Aanbevelingen uit OpenKAT',
          'Recommendations from OpenKAT',
        ),
        subtitle: _text(
          'OciDeck groepeert letterlijke bronaanbevelingen en voegt geen eigen prioriteit toe.',
          'OciDeck groups literal source recommendations and adds no priority of its own.',
        ),
        tableRows: [
          [
            _text('Findingtype', 'Finding type'),
            _text('OpenKAT adviseert', 'OpenKAT recommends'),
            _text('Organisaties', 'Organizations'),
            _text('Systemen', 'Systems'),
            _text('Hoogste ernst', 'Highest severity'),
          ],
          for (final item in bounded.values)
            [
              _inline(item.findingTypeName),
              _inline(sanitizeImportedText(item.recommendation)),
              '${item.organizationCount}',
              '${item.systemCount}',
              _severityLabel(item.highestSeverity),
            ],
          if (recommendations.isEmpty) _emptyResultRow(columns: 5),
          if (bounded.omitted)
            _omittedRow(columns: 5, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'ranking'),
      ),
    ];
  }
}
