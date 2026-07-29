part of 'openkat_report_composer.dart';

class _OpenKatReportBlockRenderer extends _OpenKatRenderer {
  const _OpenKatReportBlockRenderer(super.composer);

  List<Slide> legacyManagement(
    OpenKatReportRequest request,
    OpenKatReportBlock block, {
    required List<OpenKatOrganization> organizations,
    required bool comparablePortfolio,
    required Set<String> comparableOrganizations,
  }) {
    final portfolio = facts.aggregatePortfolio(organizations);
    final hasComparison = portfolio.previous != null;
    return [
      if (organizations.length > 1)
        composer._organizationAttentionSlide(portfolio),
      if (hasComparison && comparablePortfolio)
        composer._keyMessageSlide(portfolio),
      composer._portfolioSummarySlide(portfolio, compare: comparablePortfolio),
      composer._trendSlide(portfolio, compare: comparablePortfolio),
      composer._portfolioSurfaceSlide(portfolio),
      if (organizations.length > 1) composer._severityMatrixSlide(portfolio),
      composer._topIssuesSlide(portfolio, compare: comparablePortfolio),
      ?composer._recommendationsSlide(portfolio),
      composer._longestOpenSlide(portfolio),
      ?composer._controlsSlide(portfolio),
      for (final organization in organizations)
        ...composer._organisationSlides(
          organization,
          compare: comparableOrganizations.contains(organization.code),
        ),
    ];
  }

  /// Behoudt het bestaande managementrapport, maar laat het declaratieve plan
  /// als enige route bepalen welk deel wordt opgebouwd.
  List<Slide>? declarativeManagement(
    OpenKatReportRequest request,
    OpenKatReportBlock block, {
    required List<OpenKatOrganization> organizations,
    required bool comparablePortfolio,
    required Set<String> comparableOrganizations,
  }) {
    final portfolio = facts.aggregatePortfolio(organizations);
    final hasComparison = portfolio.previous != null;
    final slides = switch (block.kind) {
      OpenKatReportBlockKind.organizationComparison => [
        if (organizations.length > 1)
          composer._organizationAttentionSlide(portfolio),
      ],
      OpenKatReportBlockKind.portfolioSummary => [
        if (hasComparison && comparablePortfolio)
          composer._keyMessageSlide(portfolio),
        composer._portfolioSummarySlide(
          portfolio,
          compare: comparablePortfolio,
        ),
        composer._trendSlide(portfolio, compare: comparablePortfolio),
        composer._portfolioSurfaceSlide(portfolio),
      ],
      OpenKatReportBlockKind.portfolioTrend => const <Slide>[],
      OpenKatReportBlockKind.severityConcentration => [
        if (organizations.length > 1) composer._severityMatrixSlide(portfolio),
      ],
      OpenKatReportBlockKind.findingTypePrevalence => [
        composer._topIssuesSlide(portfolio, compare: comparablePortfolio),
      ],
      OpenKatReportBlockKind.recommendations => [
        if (composer._recommendationsSlide(portfolio) case final slide?)
          slide
        else
          _slide(
            id: _blockId(request, block, 'empty'),
            type: SlideType.bullets,
            title: _text(
              'Geen bronaanbevelingen in de gekozen metingen',
              'No source recommendations in the selected measurements',
            ),
            bullets: [
              _text(
                'OpenKAT leverde voor deze selectie geen aanbevelingstekst aan.',
                'OpenKAT supplied no recommendation text for this selection.',
              ),
            ],
            notes: _blockNotes(request, block, 'empty'),
          ),
        composer._longestOpenSlide(portfolio),
      ],
      OpenKatReportBlockKind.findingAge => const <Slide>[],
      OpenKatReportBlockKind.controlCoverage => [
        ?composer._controlsSlide(portfolio),
      ],
      OpenKatReportBlockKind.systemHotspots => [
        for (final organization in organizations)
          ...composer._organisationSlides(
            organization,
            compare: comparableOrganizations.contains(organization.code),
          ),
      ],
      OpenKatReportBlockKind.measurementAvailability => null,
      _ => null,
    };
    return slides == null ? null : _canonicalManagementSlides(slides);
  }

  List<Slide> _canonicalManagementSlides(Iterable<Slide> slides) => [
    for (final slide in slides)
      OpenKatSlideProvenance.markGeneratedOrigin(
        slide.copyWith(
          notes: slide.notes.replaceAllMapped(_managementViewMarker, (match) {
            final view = match.group(1)!;
            return '<!-- ocideck_openkat_view: '
                '${OpenKatReportComposer.canonicalManagementViewId(view)} -->';
          }),
        ),
      ),
  ];

  static final RegExp _managementViewMarker = RegExp(
    r'<!--\s*ocideck_openkat_view:\s*([^\s>]+)\s*-->',
  );

  Slide reportTitle(
    OpenKatReportRequest request,
    String title,
    List<OpenKatOrganization> organizations,
  ) {
    final orgNames = organizations.map((org) => _literal(org.name)).join(', ');
    return _slide(
      id: _id('openkat-${request.scenarioId}-title'),
      type: SlideType.title,
      title: _literal(title),
      subtitle: '${_text('Organisaties', 'Organizations')}: $orgNames',
      notes:
          '<!-- ocideck_openkat_view: report.${request.scenarioId}.title -->',
    );
  }

  List<Slide> portfolioSummary(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final organizations = facts.selectedOrganizations(request);
    final portfolio = facts.aggregatePortfolio(organizations);
    final current = portfolio.current;
    final comparable = facts
        .selections(request)
        .every(
          (selection) =>
              selection.previous != null &&
              facts.hasComparableCoverage(selection),
        );
    final previous = comparable ? portfolio.previous : null;
    return [
      _scorecardSlide(
        id: _blockId(request, block, 'summary'),
        title: _text('Kerncijfers', 'Key figures'),
        entries: [
          for (final band in openKatSeverityOrder)
            _severityEntry(
              band,
              current.severityCounts,
              previous?.severityCounts,
            ),
          ScorecardEntry(
            label: _text('Getroffen systemen', 'Affected systems'),
            value: current.affectedSystems.toDouble(),
            previous: previous?.affectedSystems.toDouble(),
            polarity: ScorecardPolarity.neutral,
          ),
        ],
        view: _blockView(request, block, 'summary'),
      ),
      _slide(
        id: _blockId(request, block, 'scope'),
        type: SlideType.bullets,
        title: _text('Wat er in beeld is', 'Observed scope'),
        bullets: [
          '${current.totalSystems} ${_text('systemen in de gekozen metingen', 'systems in the selected measurements')}',
          '${current.hostnames} ${_text('hostnamen', 'hostnames')}, '
              '${current.ipv4} IPv4, ${current.ipv6} IPv6',
          '${current.totalFindings} ${_text('waargenomen findings van', 'observed findings across')} '
              '${current.uniqueFindingTypes} ${_text('typen', 'types')}',
        ],
        notes: _blockNotes(request, block, 'scope'),
      ),
    ];
  }

  List<Slide> organizationComparison(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final ranked = facts.organizationRanking(request);
    final lowest = ranked.toList()
      ..sort((a, b) {
        var result = a.critical.compareTo(b.critical);
        if (result != 0) return result;
        result = a.high.compareTo(b.high);
        if (result != 0) return result;
        result = a.affectedSystems.compareTo(b.affectedSystems);
        if (result != 0) return result;
        return a.name.compareTo(b.name);
      });
    final missing = facts
        .selections(request)
        .where((selection) => selection.current == null)
        .map((selection) => selection.organization)
        .toList();
    List<List<String>> rows(Iterable<OpenKatOrganizationRanking> values) => [
      [
        _text('Organisatie', 'Organization'),
        _text('Critical', 'Critical'),
        _text('High', 'High'),
        _text('Getroffen systemen', 'Affected systems'),
        _text('Totaal waargenomen', 'Total observed'),
        _text('Meetdatum', 'Measurement date'),
      ],
      for (final item in values)
        [
          _literal(item.name),
          '${item.critical}',
          '${item.high}',
          '${item.affectedSystems}',
          '${item.totalFindings}',
          _iso(item.measuredAt),
        ],
    ];
    final most = _bounded(ranked, request, block);
    final least = _bounded(lowest, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'most'),
        type: SlideType.table,
        title: _text(
          'Meeste waargenomen critical/high findings',
          'Most observed critical/high findings',
        ),
        subtitle: _text(
          'Gesorteerd op critical, high, getroffen systemen en organisatienaam.',
          'Sorted by critical, high, affected systems, and organization name.',
        ),
        tableRows: [
          ...rows(most.values),
          if (most.omitted)
            _omittedRow(columns: 6, english: _english, shown: most.limit),
        ],
        viewLimit: _tableViewLimit(block, most),
        notes: _blockNotes(request, block, 'most'),
      ),
      _slide(
        id: _blockId(request, block, 'least'),
        type: SlideType.table,
        title: _text(
          'Minste waargenomen critical/high findings',
          'Fewest observed critical/high findings',
        ),
        subtitle: _text(
          'Weinig waargenomen findings betekent niet automatisch weinig kwetsbaarheid. Meetdekking en actualiteit bepalen wat in beeld kon komen.',
          'Few observed findings do not automatically mean low vulnerability. Measurement coverage and recency determine what could be observed.',
        ),
        tableRows: [
          ...rows(least.values),
          if (least.omitted)
            _omittedRow(columns: 6, english: _english, shown: least.limit),
        ],
        viewLimit: _tableViewLimit(block, least),
        notes: _blockNotes(request, block, 'least'),
      ),
      if (missing.isNotEmpty)
        _slide(
          id: _blockId(request, block, 'missing'),
          type: SlideType.bullets,
          title: _text(
            'Niet gerangschikt: meting ontbreekt',
            'Not ranked: measurement missing',
          ),
          bullets: [
            for (final organization in missing) _literal(organization.name),
          ],
          notes: _blockNotes(request, block, 'missing'),
        ),
    ];
  }

  List<Slide> severityConcentration(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final organizations = facts.selectedOrganizations(request);
    final perOrganization = <String, Map<String, int>>{
      for (final organization in organizations)
        if (organization.current != null)
          organization.name: openKatSeverityCounts(
            organization.current!.findings,
          ),
    };
    final hotspots = facts
        .systemHotspots(request)
        .where(
          (item) =>
              (item.severityCounts['critical'] ?? 0) > 0 ||
              (item.severityCounts['high'] ?? 0) > 0,
        )
        .toList();
    final types = facts.findingTypePrevalence(request).where((item) {
      final severity = openKatSeverityBand(item.highestSeverity);
      return severity == 'critical' || severity == 'high';
    }).toList();
    final boundedOrganizations = _bounded(
      perOrganization.entries,
      request,
      block,
    );
    final boundedHotspots = _bounded(hotspots, request, block);
    final boundedTypes = _bounded(types, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'organizations'),
        type: SlideType.chart,
        title: _text(
          'Critical/high per organisatie',
          'Critical/high by organization',
        ),
        subtitle: boundedOrganizations.omitted
            ? _text(
                'Meer organisaties weggelaten na de ingestelde limiet van ${boundedOrganizations.limit}.',
                'More organizations omitted after the configured limit of ${boundedOrganizations.limit}.',
              )
            : '',
        customMarkdown: ChartSpec(
          type: ChartType.bar,
          title: _text(
            'Waargenomen aantallen, zonder weging',
            'Observed counts, without weighting',
          ),
          x: [
            for (final entry in boundedOrganizations.values)
              _literal(entry.key),
          ],
          series: [
            for (final band in const ['critical', 'high'])
              ChartSeries(
                name: _severityLabel(band),
                data: [
                  for (final entry in boundedOrganizations.values)
                    (entry.value[band] ?? 0).toDouble(),
                ],
              ),
          ],
        ).toBlock(),
        notes: _blockNotes(request, block, 'organizations'),
      ),
      _slide(
        id: _blockId(request, block, 'systems'),
        type: SlideType.table,
        title: _text(
          'Systemen met de meeste critical/high findings',
          'Systems with the most critical/high findings',
        ),
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Systeem', 'System'),
            _text('Critical', 'Critical'),
            _text('High', 'High'),
          ],
          for (final item in boundedHotspots.values)
            [
              _inline(item.organizationCode),
              _inline(
                item.unknownSystem
                    ? _text('Onbekend systeem', 'Unknown system')
                    : item.systemId,
              ),
              '${item.severityCounts['critical'] ?? 0}',
              '${item.severityCounts['high'] ?? 0}',
            ],
          if (boundedHotspots.omitted)
            _omittedRow(
              columns: 4,
              english: _english,
              shown: boundedHotspots.limit,
            ),
        ],
        viewLimit: _tableViewLimit(block, boundedHotspots),
        notes: _blockNotes(request, block, 'systems'),
      ),
      _slide(
        id: _blockId(request, block, 'finding-types'),
        type: SlideType.table,
        title: _text(
          'Findingtypen achter de concentratie',
          'Finding types behind the concentration',
        ),
        tableRows: [
          [
            _text('Findingtype', 'Finding type'),
            _text('Ernst', 'Severity'),
            _text('Organisaties', 'Organizations'),
            _text('Systemen', 'Systems'),
            _text('Waarnemingen', 'Observations'),
          ],
          for (final item in boundedTypes.values)
            [
              _inline(item.findingTypeName ?? item.findingTypeId),
              _severityLabel(openKatSeverityBand(item.highestSeverity)),
              '${item.affectedOrganizations}',
              '${item.affectedSystems}',
              '${item.occurrenceCount}',
            ],
          if (boundedTypes.omitted)
            _omittedRow(
              columns: 5,
              english: _english,
              shown: boundedTypes.limit,
            ),
        ],
        viewLimit: _tableViewLimit(block, boundedTypes),
        notes: _blockNotes(request, block, 'finding-types'),
      ),
    ];
  }

  List<Slide> portfolioTrend(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final limit = _constructionLimit(request, block);
    final timelineProbe = facts.portfolioTimeline(
      request,
      maxResults: limit + 1,
    );
    final timelineOmitted = timelineProbe.length > limit;
    final timeline = timelineOmitted
        ? timelineProbe.sublist(timelineProbe.length - limit)
        : timelineProbe;
    final hasCarryForward = timeline.any(
      (point) => point.carriedForwardOrganizations > 0,
    );
    final comparisonSelections = facts.comparisonSelections(request);
    final comparisonProven =
        comparisonSelections.isNotEmpty &&
        comparisonSelections.every(facts.hasComparableCoverage);
    final comparisonWarning = _text(
      'Vergelijkbare meetdekking is niet aangetoond; lees dit niet als trend van verbetering of verslechtering.',
      'Comparable measurement coverage is not demonstrated; do not read this as an improvement or deterioration trend.',
    );
    final carryForwardWarning = _text(
      'Eén of meer punten gebruiken de laatst bekende organisatiemeting.',
      'One or more points carry forward the latest organization measurement.',
    );
    final subtitle = [
      if (!comparisonProven) comparisonWarning,
      if (hasCarryForward) carryForwardWarning,
      if (timelineOmitted)
        _text(
          'Eerdere meetmomenten zijn weggelaten na de ingestelde limiet van $limit.',
          'Earlier measurement points were omitted after the configured limit of $limit.',
        ),
    ].join(' ');
    return [
      _slide(
        id: _blockId(request, block, 'severity'),
        type: SlideType.chart,
        title: _text('Portfolioverloop', 'Portfolio trend'),
        subtitle: subtitle,
        customMarkdown: ChartSpec(
          type: ChartType.line,
          title: comparisonProven
              ? _text(
                  'Waargenomen findings per meetmoment',
                  'Observed findings by measurement point',
                )
              : comparisonWarning,
          x: [for (final point in timeline) _iso(point.date)],
          series: [
            for (final band in openKatSeverityOrder)
              ChartSeries(
                name: _severityLabel(band),
                data: [
                  for (final point in timeline)
                    (point.severityCounts[band] ?? 0).toDouble(),
                ],
              ),
          ],
        ).toBlock(),
        notes: _blockNotes(request, block, 'severity'),
      ),
      _slide(
        id: _blockId(request, block, 'coverage'),
        type: SlideType.table,
        title: _text(
          'Bijdrage en carried-forward metingen',
          'Contributors and carried-forward measurements',
        ),
        tableRows: [
          [
            _text('Meetmoment', 'Measurement point'),
            _text('Bijdragende organisaties', 'Contributing organizations'),
            _text('Carried forward', 'Carried forward'),
          ],
          for (final point in timeline)
            [
              _iso(point.date),
              '${point.contributingOrganizations}',
              '${point.carriedForwardOrganizations}',
            ],
          if (timelineOmitted)
            _omittedRow(columns: 3, english: _english, shown: limit),
        ],
        viewLimit: timelineOmitted
            ? null
            : DisplayWindowSpec(limit: block.preconditions.viewLimit),
        notes: _blockNotes(request, block, 'coverage'),
      ),
    ];
  }

  List<Slide> findingTypePrevalence(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final issues = facts.findingTypePrevalence(request);
    final bounded = _bounded(issues, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'ranking'),
        type: SlideType.table,
        title: _text(
          'Findingtypen bij de meeste organisaties',
          'Finding types affecting the most organizations',
        ),
        tableRows: [
          [
            _text('Findingtype', 'Finding type'),
            _text('Hoogste ernst', 'Highest severity'),
            _text('Organisaties', 'Organizations'),
            _text('Systemen', 'Systems'),
            _text('Waarnemingen', 'Observations'),
          ],
          for (final issue in bounded.values)
            [
              _inline(issue.findingTypeName ?? issue.findingTypeId),
              _severityLabel(openKatSeverityBand(issue.highestSeverity)),
              '${issue.affectedOrganizations}',
              '${issue.affectedSystems}',
              '${issue.occurrenceCount}',
            ],
          if (issues.isEmpty) _emptyResultRow(columns: 5),
          if (bounded.omitted)
            _omittedRow(columns: 5, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'ranking'),
      ),
    ];
  }

  List<Slide> measurementAvailability(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final usages = _bounded(facts.measurementUsages(request), request, block);
    return [
      _slide(
        id: _blockId(request, block, 'measurements'),
        type: SlideType.table,
        title: _text('Gebruikte meetmomenten', 'Measurements used'),
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Periode', 'Period'),
            _text('Peildatum', 'Cut-off'),
            _text('Meting', 'Measurement'),
            _text('Ouderdom (dagen)', 'Age (days)'),
          ],
          for (final usage in usages.values)
            [
              _inline(usage.organizationCode),
              usage.role == OpenKatMeasurementRole.current
                  ? _text('Huidig', 'Current')
                  : _text('Vorig', 'Previous'),
              _iso(usage.requestedAsOf),
              usage.measuredAt == null ? '-' : _iso(usage.measuredAt!),
              usage.age == null ? '-' : '${usage.age!.inDays}',
            ],
          if (usages.omitted)
            _omittedRow(columns: 5, english: _english, shown: usages.limit),
        ],
        viewLimit: _tableViewLimit(block, usages),
        notes: _blockNotes(request, block, 'measurements'),
      ),
    ];
  }

  List<Slide> measurementAccountability(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final traces = facts.sourceTraces(request);
    final traceByKey = {
      for (final trace in traces)
        '${trace.organizationCode}|${trace.role.name}|${trace.reportDate.toIso8601String()}':
            trace,
    };
    final hashes = [
      for (final trace in traces)
        '${trace.organizationCode} ${trace.role.name}: ${trace.sourceHash}',
    ];
    final usages = _bounded(facts.measurementUsages(request), request, block);
    return [
      _slide(
        id: _blockId(request, block, 'sources'),
        type: SlideType.table,
        title: _text('Meetverantwoording', 'Measurement accountability'),
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Periode', 'Period'),
            _text('Gevraagd', 'Requested'),
            _text('Gebruikt', 'Used'),
            _text('Bronbestand', 'Source file'),
            _text('Adapter', 'Adapter'),
          ],
          for (final usage in usages.values)
            [
              _inline(usage.organizationCode),
              usage.role == OpenKatMeasurementRole.current
                  ? _text('Huidig', 'Current')
                  : _text('Vorig', 'Previous'),
              _iso(usage.requestedAsOf),
              usage.measuredAt == null ? '-' : _iso(usage.measuredAt!),
              if (usage.measuredAt == null)
                '-'
              else
                _inline(
                  traceByKey['${usage.organizationCode}|${usage.role.name}|${usage.measuredAt!.toIso8601String()}']
                          ?.sourceFile ??
                      '-',
                ),
              if (usage.measuredAt == null)
                '-'
              else
                _inline(
                  traceByKey['${usage.organizationCode}|${usage.role.name}|${usage.measuredAt!.toIso8601String()}']
                          ?.schema ??
                      '-',
                ),
            ],
          if (usages.omitted)
            _omittedRow(columns: 6, english: _english, shown: usages.limit),
        ],
        viewLimit: _tableViewLimit(block, usages),
        notes: _blockNotes(
          request,
          block,
          'sources',
          extra:
              '<!-- ${_text('Bronhashes', 'Source hashes')}\n'
              '${hashes.map(_literal).join('\n')}\n-->',
        ),
      ),
    ];
  }

  List<Slide> findingLifecycle(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final budget = _constructionLimit(request, block);
    final lifecycle = facts.findingLifecycle(request, maxResults: budget + 1);
    final bounded = _bounded(lifecycle, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'changes'),
        type: SlideType.table,
        title: _text(
          'Nieuwe en niet meer waargenomen findings',
          'New and no longer observed findings',
        ),
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Finding', 'Finding'),
            _text('Systeem', 'System'),
            _text('Waarneming', 'Observation'),
            _text('Vergelijkbare dekking', 'Comparable coverage'),
          ],
          for (final item in bounded.values)
            [
              _inline(item.organizationCode),
              _inline(
                item.finding.findingTypeName ?? item.finding.findingTypeId,
              ),
              _inline(item.finding.systemId ?? '-'),
              _observationLabel(item.observation, english: _english),
              item.comparableCoverage
                  ? _text('Ja', 'Yes')
                  : _text('Niet aangetoond', 'Not demonstrated'),
            ],
          if (lifecycle.isEmpty) _emptyResultRow(columns: 5),
          if (bounded.omitted)
            _omittedRow(columns: 5, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'changes'),
      ),
    ];
  }

  List<Slide> findingAge(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final findings =
        <
          ({String organization, OpenKatFinding finding, DateTime reportDate})
        >[];
    for (final selection in facts.selections(request)) {
      final snapshot = selection.current;
      if (snapshot == null) continue;
      for (final finding in snapshot.findings) {
        if (finding.openedAt == null) continue;
        findings.add((
          organization: selection.organization.code,
          finding: finding,
          reportDate: snapshot.reportDate,
        ));
      }
    }
    findings.sort((a, b) {
      var result = a.finding.openedAt!.compareTo(b.finding.openedAt!);
      if (result != 0) return result;
      result = a.organization.compareTo(b.organization);
      if (result != 0) return result;
      result = (a.finding.systemId ?? '').compareTo(b.finding.systemId ?? '');
      if (result != 0) return result;
      return a.finding.id.compareTo(b.finding.id);
    });
    int age(
      ({String organization, OpenKatFinding finding, DateTime reportDate}) item,
    ) {
      final days = item.reportDate.difference(item.finding.openedAt!).inDays;
      return days < 0 ? 0 : days;
    }

    final bounded = _bounded(findings, request, block);

    return [
      _slide(
        id: _blockId(request, block, 'ranking'),
        type: SlideType.table,
        title: _text(
          'Langst waargenomen findings',
          'Longest-observed findings',
        ),
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Systeem', 'System'),
            _text('Findingtype', 'Finding type'),
            _text('Ernst', 'Severity'),
            _text('Eerste waarneming', 'First observation'),
            _text('Dagen op meetdatum', 'Days at measurement date'),
          ],
          for (final item in bounded.values)
            [
              _inline(item.organization),
              _inline(item.finding.systemId ?? '-'),
              _inline(
                item.finding.findingTypeName ?? item.finding.findingTypeId,
              ),
              _severityLabel(openKatSeverityBand(item.finding.severity)),
              _iso(item.finding.openedAt!),
              '${age(item)}',
            ],
          if (findings.isEmpty) _emptyResultRow(columns: 6),
          if (bounded.omitted)
            _omittedRow(columns: 6, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'ranking'),
      ),
    ];
  }

  List<Slide> systemHotspots(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final hotspots = facts.systemHotspots(request);
    final bounded = _bounded(hotspots, request, block);
    return [
      _slide(
        id: _blockId(request, block, 'ranking'),
        type: SlideType.table,
        title: _text(
          'Systemen met de meeste waargenomen findings',
          'Systems with the most observed findings',
        ),
        subtitle: hotspots.any((item) => item.unknownSystem)
            ? _text(
                'Findings zonder betrouwbare systeemkoppeling staan apart onder Onbekend systeem.',
                'Findings without a reliable system link are listed separately under Unknown system.',
              )
            : '',
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Systeem', 'System'),
            _text('Hostname/IP', 'Hostname/IP'),
            _text('Critical', 'Critical'),
            _text('High', 'High'),
            _text('Medium', 'Medium'),
            _text('Low', 'Low'),
            _text('Overig', 'Other'),
            _text('Totaal', 'Total'),
          ],
          for (final item in bounded.values)
            [
              _inline(item.organizationCode),
              _inline(
                item.unknownSystem
                    ? _text('Onbekend systeem', 'Unknown system')
                    : item.systemId,
              ),
              _inline(item.hostname ?? item.ip ?? '-'),
              '${item.severityCounts['critical'] ?? 0}',
              '${item.severityCounts['high'] ?? 0}',
              '${item.severityCounts['medium'] ?? 0}',
              '${item.severityCounts['low'] ?? 0}',
              '${item.severityCounts['other'] ?? 0}',
              '${item.total}',
            ],
          if (hotspots.isEmpty) _emptyResultRow(columns: 9),
          if (bounded.omitted)
            _omittedRow(columns: 9, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'ranking'),
      ),
    ];
  }

  List<Slide> systemChanges(
    OpenKatReportRequest request,
    OpenKatReportBlock block,
  ) {
    final changes = facts.systemChangeItems(request);
    final bounded = _bounded(changes, request, block);
    String label(OpenKatSystemChangeKind kind) => switch (kind) {
      OpenKatSystemChangeKind.moreObserved => _text(
        'Meer waargenomen',
        'More observed',
      ),
      OpenKatSystemChangeKind.fewerObserved => _text(
        'Minder waargenomen',
        'Fewer observed',
      ),
      OpenKatSystemChangeKind.mixed => _text('Gemengde verandering', 'Mixed'),
    };
    return [
      _slide(
        id: _blockId(request, block, 'changes'),
        type: SlideType.table,
        title: _text('Systeemveranderingen', 'System changes'),
        tableRows: [
          [
            _text('Organisatie', 'Organization'),
            _text('Systeem', 'System'),
            _text('Verandering', 'Change'),
            'Δ critical',
            'Δ high',
            'Δ medium',
            'Δ low',
            _text('Δ overig', 'Δ other'),
          ],
          for (final item in bounded.values)
            [
              _inline(item.organizationCode),
              _inline(item.systemId),
              label(item.kind),
              '${item.severityDeltas['critical']}',
              '${item.severityDeltas['high']}',
              '${item.severityDeltas['medium']}',
              '${item.severityDeltas['low']}',
              '${item.severityDeltas['other']}',
            ],
          if (changes.isEmpty) _emptyResultRow(columns: 8),
          if (bounded.omitted)
            _omittedRow(columns: 8, english: _english, shown: bounded.limit),
        ],
        viewLimit: _tableViewLimit(block, bounded),
        notes: _blockNotes(request, block, 'changes'),
      ),
    ];
  }
}
