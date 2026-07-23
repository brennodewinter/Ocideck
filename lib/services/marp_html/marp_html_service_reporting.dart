// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// De rapportagedia's in de HTML-export. Zes slidetypes bewaren hun inhoud als
// een gewone Markdown-tabel — `scorecard`, `assets`, `discoveries`,
// `checklist`, `scope-matrix` en `findings-summary` — en vielen in de export
// daarom terug op precies dat: een tabel. In de app heeft elk van de zes een
// eigen weergave, en juist bij de MIAUW-types ís die weergave de inhoud. Een
// dekkingsbalk zegt iets wat de rijen eronder niet zeggen, en een kolom vol
// "Tested" zonder kleur leest als een lijst in plaats van als een uitspraak.
//
// De export is het bestand dat een klant het vaakst krijgt. Dat die zes daar
// hun vorm verloren, was het grootste gat tussen wat de auteur goedkeurde en
// wat de ontvanger las.
//
// De scorecard, het aanvalsoppervlak en de ontdekkingen staan hier; de drie
// MIAUW-types in `marp_html_service_reporting_miauw.dart`, de opmaak in
// `marp_html_service_reporting_css.dart`.
part of '../marp_html_service.dart';

/// De vaste kleuren die een oordeel dragen in plaats van stijl, als hex.
///
/// Dezelfde waarden als de `const` tokens in `AppTheme`, hier herhaald omdat
/// deze service bewust geen Flutter-UI importeert. Ze volgen het thema niet, en
/// dat is opzet: groen voor vooruitgang en rood voor werk moeten in elke
/// huisstijl hetzelfde betekenen — dezelfde uitzondering die de preview, de
/// scorecard en de heatmap maken.
const _repGood = '#15803D'; // green 700
const _repBad = '#B91C1C'; // red 700
const _repWarn = '#B45309'; // amber 700
const _repMuted = '#64748B'; // slate 500

/// De `_class`-tokens van de zes rapportagetypes. Ze komen uit `slideTypeMeta`
/// (`marpClass`), maar staan hier als letterlijke tekst: de export werkt op
/// markdown en kent het slidetype niet.
const _reportingClasses = <String>{
  'scorecard',
  'assets',
  'discoveries',
  'checklist',
  'scope-matrix',
  'findings-summary',
};

final _repClassComment = RegExp(r'<!--\s*_class:\s*([^>]+?)\s*-->');
final _repHeading = RegExp(r'^#\s+(.*)$');
final _repChecklistScope = RegExp(
  r'<!--\s*ocideck_checklist_scope:\s*([^>]*?)\s*-->',
);

/// Wat er uit een rapportagedia te lezen valt.
typedef _ReportingSlide = ({
  String cssClass,
  String title,
  List<List<String>> rows,
  String checklistScope,
});

/// Leest [slideMarkdown] als rapportagedia, of geeft null wanneer het er geen
/// is. Alleen de kop en de tabel worden gelezen — dat is precies wat de
/// serialiser voor deze zes types schrijft.
_ReportingSlide? _readReportingSlide(String slideMarkdown) {
  final cssClass = _repClassComment
      .firstMatch(slideMarkdown)
      ?.group(1)
      ?.split(RegExp(r'\s+'))
      .firstWhere(_reportingClasses.contains, orElse: () => '');
  if (cssClass == null || cssClass.isEmpty) return null;

  var title = '';
  final tableLines = <String>[];
  for (final line in slideMarkdown.split('\n')) {
    if (title.isEmpty) {
      final heading = _repHeading.firstMatch(line.trim());
      if (heading != null) {
        title = heading.group(1)!.trim();
        continue;
      }
    }
    if (isMarkdownTableLine(line)) tableLines.add(line);
  }
  return (
    cssClass: cssClass,
    title: title,
    rows: decodeMarkdownTableRows(tableLines),
    checklistScope:
        _repChecklistScope.firstMatch(slideMarkdown)?.group(1)?.trim() ?? '',
  );
}

/// Percentagetekst voor een breedte in een inline `style`, afgekapt op 0..100.
///
/// Altijd via deze functie, zodat een NaN of een oneindige breuk — een deling
/// door een totaal van nul — nooit als attribuutwaarde in het document belandt.
String _repPct(double fraction) {
  if (fraction.isNaN || fraction.isInfinite) return '0.0';
  final clamped = fraction < 0 ? 0.0 : (fraction > 1 ? 1.0 : fraction);
  return (clamped * 100).toStringAsFixed(1);
}

/// Een gevulde balk: [fraction] van de breedte in [color].
String _repBar(double fraction, String color) =>
    '<div class="rep-bar"><i style="width:${_repPct(fraction)}%;'
    'background:$color"></i></div>';

/// De kop van een rapportagedia, of niets wanneer er geen is.
String _repTitle(String title) =>
    title.isEmpty ? '' : '<p class="rep-title">${_esc(title)}</p>';

/// Een tabelkop-cel.
String _repHead(String label) => '<th>${_esc(label)}</th>';

// ── Scorecard ───────────────────────────────────────────────────────────────

/// De scorecard: een handvol kerncijfers, elk met de verandering sinds het
/// vorige rapport eronder.
///
/// Dezelfde opbouw als de preview — kaart, accentrand, label, cijfer,
/// verandering, "was …" — maar in kaarten die met de breedte meebuigen in
/// plaats van in een vaste rasterindeling. De richting staat als pijl én als
/// getekend voorteken, zodat een afdruk in grijstinten hem nog draagt.
String _repScorecard(_ReportingSlide slide, ThemeProfile? theme) {
  const l10n = AppLocalizations(Locale('nl'));
  final spec = ScorecardSpec.fromSlide(slide.title, slide.rows);
  final entries = spec.entries.where((e) => !e.isBlank).toList();
  final b = StringBuffer('<div class="rep rep-scorecard">')
    ..write(_repTitle(spec.title))
    ..write('<div class="sc-grid">');
  for (final entry in entries) {
    final direction = entry.direction;
    final delta = entry.delta;
    b
      ..write('<div class="sc-card"><div class="sc-rule"></div>')
      ..write('<div class="sc-body">');
    if (entry.label.isNotEmpty) {
      b.write('<p class="sc-label">${_esc(entry.label)}</p>');
    }
    b.write(
      '<p class="sc-value">'
      '${_esc(entry.value == null ? '—' : formatScorecardNumber(entry.value!))}'
      '${entry.unit.isEmpty ? '' : '<span class="sc-unit">${_esc(entry.unit)}</span>'}'
      '</p>',
    );
    if (direction != null && delta != null) {
      final tone = switch (entry.sentiment) {
        ScorecardSentiment.good => _repGood,
        ScorecardSentiment.bad => _repBad,
        ScorecardSentiment.neutral => _repMuted,
      };
      final arrow = switch (direction) {
        ScorecardDirection.up => '▲',
        ScorecardDirection.down => '▼',
        ScorecardDirection.flat => '–',
      };
      final text = direction == ScorecardDirection.flat
          ? l10n.d('ongewijzigd')
          : formatScorecardDelta(delta);
      b.write(
        '<p class="sc-change" style="color:$tone;background:${tone}22">'
        '$arrow ${_esc(text)}</p>',
      );
    }
    if (entry.previous != null) {
      b.write(
        '<p class="sc-prev">${_esc(l10n.d('was'))} '
        '${_esc(formatScorecardNumber(entry.previous!))}'
        '${entry.unit.isEmpty ? '' : ' ${_esc(entry.unit)}'}</p>',
      );
    }
    b.write('</div></div>');
  }
  b.write('</div></div>');
  return b.toString();
}

// ── Aanvalsoppervlak ────────────────────────────────────────────────────────

/// Het aanvalsoppervlak: per soort object een balk op één gedeelde schaal, met
/// het deel dat werk kost als rode kop erin, en de vier tellingen in kolommen.
///
/// De schaal is gedeeld met de grootste groep op de dia, precies zoals in de
/// preview: per rij schalen zou een categorie van drie even breed tekenen als
/// een van driehonderd, en dan zegt het plaatje het omgekeerde van de getallen.
String _repAssets(_ReportingSlide slide, ThemeProfile? theme) {
  const l10n = AppLocalizations(Locale('nl'));
  final spec = AssetOverviewSpec.fromSlide(slide.title, slide.rows);
  final groups = spec.groups.where((g) => !g.isBlank).toList();
  final accent = theme?.accentColor ?? '#003399';
  final largest = spec.largestGroup;
  final b = StringBuffer('<div class="rep rep-assets">')
    ..write(_repTitle(spec.title));
  if (groups.isEmpty) return (b..write('</div>')).toString();

  String num(int value, String tone) =>
      '<td class="rep-num" style="color:$tone">$value</td>';
  String tone(int value, String loud) => value > 0 ? loud : _repMuted;

  b
    ..write('<table class="rep-table"><thead><tr>')
    ..write('<th></th><th></th>')
    ..write(_repHead(l10n.d('gevonden')))
    ..write(_repHead(l10n.d('werk')))
    ..write(_repHead(l10n.d('nieuw')))
    ..write(_repHead(l10n.d('geen eigenaar')))
    ..write('</tr></thead><tbody>');
  for (final group in groups) {
    final share = largest <= 0 ? 0.0 : group.total / largest;
    b
      ..write('<tr><th scope="row">${_esc(group.name)}</th>')
      ..write('<td class="rep-barcell">')
      ..write(
        '<div class="rep-bar" style="width:${_repPct(share)}%">'
        '<i style="width:${_repPct(group.atRiskFraction)}%;'
        'background:$_repBad"></i></div>',
      )
      ..write('</td>')
      ..write(num(group.total, 'inherit'))
      ..write(num(group.atRisk, tone(group.atRisk, _repBad)))
      ..write(num(group.newlyFound, tone(group.newlyFound, accent)))
      ..write(num(group.unowned, tone(group.unowned, _repBad)))
      ..write('</tr>');
  }
  b
    ..write('</tbody><tfoot><tr>')
    ..write('<th scope="row">${_esc(l10n.d('objecten in beeld'))}</th>')
    ..write('<td></td>')
    ..write(num(spec.totalAssets, 'inherit'))
    ..write(num(spec.totalAtRisk, tone(spec.totalAtRisk, _repBad)))
    ..write(num(spec.totalNew, tone(spec.totalNew, accent)))
    ..write(num(spec.totalUnowned, tone(spec.totalUnowned, _repBad)))
    ..write('</tr></tfoot></table></div>');
  return b.toString();
}

// ── Ontdekkingen ────────────────────────────────────────────────────────────

/// Een blootstelling in de eenheid die een lezer hoort — dezelfde regel als in
/// de preview: onder twee maanden dagen, daarboven maanden.
String _repExposure(int days) {
  const l10n = AppLocalizations(Locale('nl'));
  final scaled = scaleDaysUnnoticed(days);
  final unit = scaled.inMonths
      ? (scaled.value == 1 ? l10n.d('maand') : l10n.d('maanden'))
      : (scaled.value == 1 ? l10n.d('dag') : l10n.d('dagen'));
  return '${scaled.value} $unit';
}

/// De ontdekkingen: wat deze scan vond dat niemand wist te bestaan, met de
/// langste blootstelling als kop en per rij een balk op die gedeelde schaal.
String _repDiscoveries(_ReportingSlide slide, ThemeProfile? theme) {
  const l10n = AppLocalizations(Locale('nl'));
  final spec = DiscoveriesSpec.fromSlide(slide.title, slide.rows);
  final found = spec.discoveries.where((d) => !d.isBlank).toList();
  final accent = theme?.accentColor ?? '#003399';
  final b = StringBuffer('<div class="rep rep-discoveries">')
    ..write(_repTitle(spec.title));
  if (found.isEmpty) return (b..write('</div>')).toString();

  final longest = spec.longestUnnoticed;
  if (longest != null) {
    b.write(
      '<p class="dc-headline"><strong>${_esc(_repExposure(longest))}</strong>'
      '<span>${_esc(l10n.d('langst onopgemerkt bereikbaar'))}</span></p>',
    );
  }
  b
    ..write('<table class="rep-table"><thead><tr>')
    ..write('<th></th><th></th>')
    ..write(_repHead(l10n.d('onopgemerkt')))
    ..write(_repHead(l10n.d('eigenaar')))
    ..write('</tr></thead><tbody>');
  for (final discovery in found) {
    final days = discovery.daysUnnoticed;
    b
      ..write('<tr><th scope="row">${_esc(discovery.name)}')
      ..write(
        discovery.kind.isEmpty
            ? ''
            : '<span class="dc-kind">${_esc(discovery.kind)}</span>',
      )
      ..write('</th><td class="rep-barcell">')
      // Een onbekende blootstelling tekent HELEMAAL geen balk, ook geen lege
      // baan: "we weten het niet" en "meteen gevonden" zijn verschillende
      // uitspraken, en een baan van nul leest als de tweede.
      ..write(days == null ? '' : _repBar(spec.barFraction(discovery), accent))
      ..write('</td>')
      ..write(
        '<td class="rep-num${days == null ? ' rep-unknown' : ''}">'
        '${_esc(days == null ? l10n.d('onbekend') : _repExposure(days))}</td>',
      )
      ..write(
        discovery.hasOwner
            ? '<td>${_esc(discovery.owner)}</td>'
            : '<td class="dc-unowned" style="color:$_repBad">'
                  '${_esc(l10n.d('geen eigenaar'))}</td>',
      )
      ..write('</tr>');
  }
  final parts = [
    '${spec.count} '
        '${spec.count == 1 ? l10n.d('ontdekking') : l10n.d('ontdekkingen')}',
    if (spec.unownedCount > 0)
      '${spec.unownedCount} ${l10n.d('geen eigenaar')}',
  ];
  b
    ..write('</tbody></table>')
    ..write('<p class="rep-totals">${_esc(parts.join('  ·  '))}</p>')
    ..write('</div>');
  return b.toString();
}
