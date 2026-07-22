// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// De drie MIAUW-rapportagetypes in de HTML-export: de checklist (§3.2), de
// scope-matrix (§2.2/§4.4) en het bevindingenoverzicht (§4.3.4/§11). Zie
// `marp_html_service_reporting.dart` voor het waarom en de gedeelde helpers.
part of '../marp_html_service.dart';

/// De statuskleur van een checklistregel. Dezelfde `const` waarden als de
/// `AppTheme.checklist*`-tokens die de preview gebruikt, zodat een afwijking in
/// de export dezelfde kleur heeft als op het scherm.
String _repChecklistColor(ChecklistStatus status) => switch (status) {
  ChecklistStatus.tested => _repGood,
  ChecklistStatus.anomaly => _repBad,
  ChecklistStatus.notTestable => _repWarn,
  ChecklistStatus.notTested => _repMuted,
};

/// De statuskleur van een scope-matrixregel (`AppTheme.scope*`).
String _repScopeColor(ScopeStatus status) => switch (status) {
  ScopeStatus.tested => _repGood,
  ScopeStatus.deviation => _repWarn,
  ScopeStatus.unreachable => _repBad,
  ScopeStatus.notTested => _repMuted,
};

/// Een getinte statuspil, zoals de preview hem tekent.
String _repChip(String label, String color) =>
    '<span class="rep-chip" style="color:$color;background:${color}20">'
    '${_esc(label)}</span>';

/// De voortgangsbalk met "x/y" ernaast, gedeeld door de checklist en de
/// scope-matrix — bij beide is de teller afgeleid, nooit opgeslagen.
/// Een `div` en geen `p`: de balk erin is zelf een `div`, en een `p` sluit de
/// browser dán al — de teller viel daardoor onder de balk in plaats van ernaast.
String _repProgress(int done, int total, String label, String accent) =>
    '<div class="rep-progress">'
    '${_repBar(total == 0 ? 0 : done / total, accent)}'
    '<span>$done/$total ${_esc(label)}</span></div>';

// ── Checklist ───────────────────────────────────────────────────────────────

/// De checklist: het standaardlabel, het scope-object, de afgeleide voortgang
/// en de toetsen met hun drietoestand als gekleurde pil.
String _repChecklist(_ReportingSlide slide, ThemeProfile? theme) {
  const l10n = AppLocalizations(Locale('nl'));
  final spec = ChecklistSpec.fromSlide(slide.title, slide.rows);
  final accent = theme?.accentColor ?? '#003399';
  final b = StringBuffer('<div class="rep rep-checklist">')
    ..write(_repTitle(spec.standardLabel));
  if (slide.checklistScope.isNotEmpty) {
    b.write(
      '<p class="rep-sub">${_esc(l10n.d('Scope-object'))}: '
      '${_esc(slide.checklistScope)}</p>',
    );
  }
  b.write(
    _repProgress(spec.testedCount, spec.total, l10n.d('getoetst'), accent),
  );
  if (spec.rows.isEmpty) return (b..write('</div>')).toString();

  b
    ..write('<table class="rep-table"><thead><tr>')
    ..write(_repHead(l10n.d('ID')))
    ..write(_repHead(l10n.d('Test')))
    ..write(_repHead(l10n.d('Status')))
    ..write(_repHead(l10n.d('Bevinding')))
    ..write('</tr></thead><tbody>');
  for (final row in spec.rows) {
    b
      ..write('<tr><th scope="row">${_esc(row.id)}</th>')
      ..write('<td>${_esc(row.test)}</td>')
      ..write(
        '<td>${_repChip(l10n.d(row.status.dutchLabel), _repChecklistColor(row.status))}</td>',
      )
      ..write(
        row.findingId.isEmpty
            ? '<td class="rep-unknown">—</td>'
            : '<td style="color:$accent">${_esc(row.findingId)}</td>',
      )
      ..write('</tr>');
  }
  b.write('</tbody></table></div>');
  return b.toString();
}

// ── Scope-matrix ────────────────────────────────────────────────────────────

/// De scope-matrix: de dekking als balk, dan per object het type, de daaraan
/// gebonden standaard en hoe ver het getoetst is.
String _repScopeMatrix(_ReportingSlide slide, ThemeProfile? theme) {
  const l10n = AppLocalizations(Locale('nl'));
  final spec = ScopeMatrixSpec.fromSlide(slide.title, slide.rows);
  final accent = theme?.accentColor ?? '#003399';
  final b = StringBuffer('<div class="rep rep-scope">')
    ..write(_repTitle(spec.title))
    ..write(
      _repProgress(spec.testedCount, spec.total, l10n.d('gedekt'), accent),
    );
  if (spec.rows.isEmpty) return (b..write('</div>')).toString();

  b
    ..write('<table class="rep-table"><thead><tr>')
    ..write(_repHead(l10n.d('Object')))
    ..write(_repHead(l10n.d('Type')))
    ..write(_repHead(l10n.d('Standaard')))
    ..write(_repHead(l10n.d('Status')))
    ..write('</tr></thead><tbody>');
  for (final row in spec.rows) {
    b
      ..write('<tr><th scope="row">${_esc(row.object)}</th>')
      ..write('<td>${_esc(l10n.d(row.type.dutchLabel))}</td>')
      ..write('<td>${row.standard.isEmpty ? '—' : _esc(row.standard)}</td>')
      ..write(
        '<td>${_repChip(l10n.d(row.status.dutchLabel), _repScopeColor(row.status))}</td>',
      )
      ..write('</tr>');
  }
  b.write('</tbody></table></div>');
  return b.toString();
}

// ── Bevindingenoverzicht ────────────────────────────────────────────────────

/// De ernstkleur van een band, uit het thema wanneer dat er is — dezelfde
/// afspraak als `FindingSeverityPalette`.
String _repSeverityColor(Cvss4Severity band, ThemeProfile? theme) =>
    switch (band) {
      Cvss4Severity.critical => theme?.severityCriticalColor ?? '#B91C1C',
      Cvss4Severity.high => theme?.severityHighColor ?? '#EA580C',
      Cvss4Severity.medium => theme?.severityMediumColor ?? '#D97706',
      Cvss4Severity.low => theme?.severityLowColor ?? '#15803D',
      Cvss4Severity.none => theme?.severityNoneColor ?? '#475569',
    };

/// Het bevindingenoverzicht: het totaal, wat er na hertest is opgelost, en per
/// ernstband een staaf met de telling — de managementopname van het rapport.
///
/// De staven zijn CSS-hoogtes en geen SVG: ze moeten meebuigen met de breedte
/// van het venster waarin de ontvanger het document opent, en de telling staat
/// er los onder zodat het overzicht ook zonder kleur te lezen is.
String _repFindingsSummary(_ReportingSlide slide, ThemeProfile? theme) {
  const l10n = AppLocalizations(Locale('nl'));
  final spec = FindingsSummarySpec.fromSlide(slide.title, slide.rows);
  final tallest = FindingsSummarySpec.order
      .map(spec.countOf)
      .fold(0, (a, b) => a > b ? a : b);
  final b = StringBuffer('<div class="rep rep-findings">')
    ..write(_repTitle(spec.title))
    ..write('<p class="rep-sub">${_esc(l10n.d('Totaal'))}: ${spec.total}</p>')
    ..write(
      '<p class="rep-sub fs-resolved" style="color:$_repGood">'
      '${_esc(l10n.d('Opgelost na hertest'))}: ${spec.resolved}</p>',
    )
    ..write('<div class="fs-chart">');
  for (final band in FindingsSummarySpec.order) {
    final count = spec.countOf(band);
    final height = tallest <= 0 ? 0.0 : count / tallest;
    b
      ..write('<div class="fs-col">')
      ..write(
        '<div class="fs-bar"><i style="height:${_repPct(height)}%;'
        'background:${_repSeverityColor(band, theme)}"></i></div>',
      )
      ..write('<p class="fs-count">$count</p>')
      ..write(
        '<p class="fs-band">'
        '${_esc(l10n.d(findingsSeverityDutchLabel(band)))}</p>',
      )
      ..write('</div>');
  }
  b.write('</div></div>');
  return b.toString();
}
