import '../../models/markdown_validation.dart';
import '../../models/slide.dart';
import '../../models/slide_quality.dart';
import '../split_run.dart';

/// De lengte-gedreven dichtheidsmeldingen: ze komen uit hoe lang de bullets
/// zijn, niet uit hoevéél er op één dia staan. 'Splits slide' verdeelt de
/// bullets over pagina's — het maakt ze niet korter — dus keert elk van deze
/// meldingen op elke deelpagina van dezelfde gesplitste lijst terug.
///
/// Bewust alleen de niet-kritieke soorten. De kritieke tegenhangers
/// ([SlideQualityIssueKind.textDensityCritical],
/// [SlideQualityIssueKind.bulletWordCountCritical]) en de aantal-gedreven
/// meldingen ([SlideQualityIssueKind.bulletCountHigh] en `…Critical`) zijn eigen
/// soorten en vallen hier vanzelf buiten: die lost verder splitsen wél op, dus
/// een reeks die ze nog draagt is niet klaar en de gebruiker hoort ze per pagina
/// te zien.
const Set<SlideQualityIssueKind> kLengthDrivenRunDensityKinds = {
  SlideQualityIssueKind.textDensityWarning,
  SlideQualityIssueKind.bulletWordCountHigh,
  SlideQualityIssueKind.bulletAverageLengthHigh,
  SlideQualityIssueKind.bulletMultiSentence,
  SlideQualityIssueKind.bulletNestingDeep,
};

/// Vat de lengte-gedreven dichtheidsmeldingen die over de pagina's van één
/// split-run heen herhalen samen tot één melding per soort per reeks (#1289).
///
/// 'Splits slide' lost de dichtheid-per-aantal op, maar niet de lengte-per-
/// bullet: een lijst van lange volzinnen die je over vijf pagina's verdeelt,
/// meldt op elke pagina opnieuw 'veel woorden', 'lange bullets' en 'meerzins'.
/// De gebruiker die de aanbeveling opvolgde kreeg zo een veelvoud aan meldingen
/// terug — straf op gehoorzaamheid. De meldingen zijn niet onjuist, maar het is
/// één probleem (de bullets zijn lang), niet vijf, en het hoort één keer geteld
/// te worden. De samenvatting draagt in `args['runPages']` op hoeveel pagina's
/// hij staat, zodat de tekst dat eerlijk kan zeggen.
///
/// Puur presentatie: dit draait op de weg naar het paneel, niet in de analyzer
/// die de fix-motor voedt. Die blijft elke pagina apart zien, zodat 'los
/// automatisch op wat kan' onverstoord de grondwaarheid houdt en per pagina kan
/// blijven ingrijpen.
///
/// Samenvatten gebeurt alleen bij een echte split-run: een keten van
/// [Slide.continuesSplit]-pagina's van hetzelfde type ([splitRunRange]). Los
/// geschreven bullet-dia's die toevallig op elkaar volgen vormen geen run en
/// blijven onaangeraakt. Eén losse treffer (bijvoorbeeld de volste pagina die
/// zijn buren meetrekt) wordt niet samengevat — pas vanaf twee pagina's is het
/// een reeks-eigenschap in plaats van een pagina-eigenschap.
List<SlideQualityIssue> collapseSplitRunDensity(
  List<Slide> slides,
  List<SlideQualityIssue> issues,
) {
  final runStartOf = _multiPageRunStarts(slides);
  if (runStartOf.isEmpty) return issues;

  // Groepeer de samenvatbare meldingen per (reeks-start, soort), in de volgorde
  // waarin ze in de lijst staan — zo blijft de eerste treffer het anker.
  final groups = <(int, SlideQualityIssueKind), List<int>>{};
  for (var idx = 0; idx < issues.length; idx++) {
    final issue = issues[idx];
    if (issue.isDeckWide) continue;
    if (!kLengthDrivenRunDensityKinds.contains(issue.kind)) continue;
    final runStart = runStartOf[issue.slideIndex];
    if (runStart == null) continue;
    groups.putIfAbsent((runStart, issue.kind), () => <int>[]).add(idx);
  }

  // Alleen groepen van twee of meer pagina's worden samengevat. Onthoud welke
  // indexen verdwijnen en op welke plek (de eerste treffer) de samenvatting komt.
  final removed = <int>{};
  final summaryAt = <int, SlideQualityIssue>{};
  for (final entry in groups.entries) {
    final memberIdxs = entry.value;
    if (memberIdxs.length < 2) continue;
    removed.addAll(memberIdxs);
    final anchor = issues[memberIdxs.first];
    summaryAt[memberIdxs.first] = SlideQualityIssue(
      slideIndex: anchor.slideIndex,
      kind: anchor.kind,
      category: anchor.category,
      severity: _maxSeverity([for (final m in memberIdxs) issues[m].severity]),
      field: anchor.field,
      span: anchor.span,
      args: {...anchor.args, 'runPages': '${memberIdxs.length}'},
    );
  }
  if (summaryAt.isEmpty) return issues;

  // Herbouw in de oorspronkelijke volgorde: de samenvatting neemt de plek van de
  // eerste treffer in, de overige treffers van die groep vallen weg.
  final result = <SlideQualityIssue>[];
  for (var idx = 0; idx < issues.length; idx++) {
    final summary = summaryAt[idx];
    if (summary != null) {
      result.add(summary);
    } else if (!removed.contains(idx)) {
      result.add(issues[idx]);
    }
  }
  return result;
}

/// Voor elke pagina die in een split-run van meerdere pagina's zit: de index van
/// de eerste pagina van die reeks. Pagina's buiten een meerpagina-run staan er
/// niet in. De reeks-start is de sleutel waarop meldingen van dezelfde run
/// samenkomen, ook als ze op verschillende pagina's staan.
Map<int, int> _multiPageRunStarts(List<Slide> slides) {
  final starts = <int, int>{};
  var i = 0;
  while (i < slides.length) {
    final (start, end) = splitRunRange(slides, i);
    if (end > start) {
      for (var k = start; k <= end; k++) {
        starts[k] = start;
      }
      i = end + 1;
    } else {
      i++;
    }
  }
  return starts;
}

MarkdownValidationSeverity _maxSeverity(List<MarkdownValidationSeverity> all) {
  // De volgorde in de enum loopt van zwaar naar licht (error, warning,
  // informational), dus de kleinste index is de zwaarste melding.
  var worst = all.first;
  for (final severity in all) {
    if (severity.index < worst.index) worst = severity;
  }
  return worst;
}
