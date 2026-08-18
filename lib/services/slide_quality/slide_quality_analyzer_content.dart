// Part of the slide_quality_analyzer library — see
// ../slide_quality_analyzer.dart. Split out for navigability (de losse
// inhoudscontroles: speelbare vraag, bevindingssecties, grafiek-alt-tekst en
// sprongen die nergens uitkomen); alle imports staan in het hoofdbestand.
// Verhuisd toen het hoofdbestand tegen het plafond van 1000 regels liep —
// dezelfde library, dezelfde top-level functies, geen gedragswijziging.
part of '../slide_quality_analyzer.dart';

/// Waarschuw voor vraagslides die tijdens het presenteren niet speelbaar
/// zijn (geen geldige vraagspecificatie), vóórdat de presentator er live
/// tegenaan loopt.
void _checkQuestionAnswerable(
  Slide slide,
  int index,
  List<SlideQualityIssue> issues,
) {
  if (slide.type != SlideType.question) return;
  final spec = QuestionSpec.parse(slide.customMarkdown);
  if (!spec.hasValidAnswerCount) {
    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.questionAnswerCountHigh,
        category: SlideQualityCategory.content,
        severity: MarkdownValidationSeverity.error,
        field: 'customMarkdown',
        args: {
          'count': '${spec.sourceAnswerCount}',
          'maximum': '${spec.answerCountLimit}',
        },
      ),
    );
    return;
  }
  if (spec.isPresentable) return;
  issues.add(
    SlideQualityIssue(
      slideIndex: index,
      kind: SlideQualityIssueKind.questionNotAnswerable,
      category: SlideQualityCategory.content,
      severity: MarkdownValidationSeverity.warning,
      field: 'customMarkdown',
    ),
  );
}

/// Waarschuw voor een `## …`-sectie in de kopkaart van een bevinding waarvan de
/// naam geen canonieke sectie is (en ook geen herkende korte vorm — zie
/// [FindingSpec.canonicalSectionAnchor]).
///
/// De kopkaart rendert alleen de vier vaste secties; een handgeschreven of
/// geïmporteerde `## Notes` / `## References` staat wél in de `.md` maar verdwijnt
/// uit de weergave, de presentatie én de export. Op schijf gaat er niets
/// verloren — het bestand blijft de bron — maar een uitgeleverd pentestrapport
/// zou de sectie stil missen. Een waarschuwing en geen fout: het bestand is niet
/// kapot, en de auteur hoeft alleen de kop te hernoemen naar een standaardsectie.
/// Alleen op de kop-dia (rol `header`): een detail-/bewijs-dia draagt geen
/// kopkaart en mag vrije `##`-koppen bevatten. Gevonden bij de keuring van #1198.
void _checkFindingSections(
  Slide slide,
  int index,
  List<SlideQualityIssue> issues,
) {
  if (slide.type != SlideType.finding) return;
  if (slide.findingRole != FindingRole.header) return;
  final spec = FindingSpec.parse(slide.customMarkdown);
  for (final title in spec.unknownSectionTitles) {
    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.findingUnknownSection,
        category: SlideQualityCategory.content,
        severity: MarkdownValidationSeverity.warning,
        field: 'customMarkdown',
        args: {'section': title},
      ),
    );
  }
}

void _checkChartAltText(
  Slide slide,
  int index,
  List<SlideQualityIssue> issues,
) {
  final spec = ChartSpec.parse(slide.customMarkdown);
  if (spec.title.trim().isNotEmpty) return;
  if (spec.hasInlineData && spec.series.any((s) => s.name.trim().isNotEmpty)) {
    return;
  }
  if (spec.source != null && spec.source!.trim().isNotEmpty) return;

  issues.add(
    SlideQualityIssue(
      slideIndex: index,
      kind: SlideQualityIssueKind.chartMissingDescription,
      category: SlideQualityCategory.altText,
      severity: MarkdownValidationSeverity.informational,
      field: 'customMarkdown',
    ),
  );
}

/// Sprongen die nergens meer uitkomen: een keuze-menublok of een sprong-uit met
/// een anker dat geen enkele dia (meer) draagt.
///
/// De presentator valt bij een onbekend anker stil terug op de gewone volgorde
/// (`_jumpToAnchor` doet dan niets). Dat is het juiste gedrag — beter dan
/// stranden — maar het maakt de fout onzichtbaar tot iemand op het podium op een
/// knop drukt die niets doet. Vandaar hier een melding, bij het maken.
void _checkDanglingJumps(List<Slide> slides, List<SlideQualityIssue> issues) {
  final anchors = {
    for (final s in slides)
      if (s.anchor.isNotEmpty) s.anchor,
  };
  for (var i = 0; i < slides.length; i++) {
    final slide = slides[i];
    if (slide.skipped) continue;
    void report(String target, String label, String field) {
      if (target.isEmpty || anchors.contains(target)) return;
      issues.add(
        SlideQualityIssue(
          slideIndex: i,
          kind: SlideQualityIssueKind.danglingJump,
          category: SlideQualityCategory.content,
          severity: MarkdownValidationSeverity.warning,
          field: field,
          args: {'label': label.isEmpty ? target : label},
        ),
      );
    }

    if (slide.type == SlideType.menu) {
      for (final block in menuBlocksFor(slide.bullets)) {
        report(block.targetAnchor, block.label, 'bullets');
      }
    }
    report(slide.nextAnchor, slide.nextAnchor, 'title');
  }
}
