// Builds a starter deck for a process-improvement project (PROCESS_IMPROVEMENT Phase 7).
library;

import '../../models/deck.dart';
import '../../models/improvement_y01.dart';
import '../../models/slide.dart';
import 'canvas_spec.dart';
import 'matrix_spec.dart';
import 'tree_spec.dart';

/// Supported values for [Deck.improvementFramework].
const kImprovementFrameworks = ['dmaic', 'dmadv', 'kaizen', 'a3', '8d'];

bool isValidImprovementFramework(String value) =>
    value.isEmpty || kImprovementFrameworks.contains(value);

/// Section headings per framework (Dutch source strings — localise at UI if needed).
List<String> improvementPhaseSections(String framework) {
  switch (framework) {
    case 'dmadv':
      return const ['Define', 'Measure', 'Analyze', 'Design', 'Verify'];
    case 'kaizen':
      return const ['Plan', 'Do', 'Check'];
    case 'a3':
      return const ['Probleem', 'Analyse', 'Actie'];
    case '8d':
      return const ['D1–D2', 'D3–D4', 'D5–D6', 'D7–D8'];
    case 'dmaic':
    default:
      return const ['Define', 'Measure', 'Analyze', 'Improve', 'Control'];
  }
}

List<String> _ctqStarterBullets(String y01Description) {
  final need = y01Description.trim().isEmpty
      ? 'Customer need'
      : y01Description.trim();
  return ['$need — **Y-01**', '\tCTQ 1', '\tCTQ 2'];
}

/// Slides for a new improvement project: title, phase sections, charter, CTQ tree,
/// SIPOC matrix, and empty section markers for the remaining phases.
List<Slide> buildImprovementProjectSlides({
  required String projectTitle,
  required String framework,
  required String y01Description,
}) {
  final phases = improvementPhaseSections(framework);
  final slides = <Slide>[
    Slide.create(SlideType.title).copyWith(title: projectTitle),
  ];

  if (phases.isNotEmpty) {
    slides.add(Slide.create(SlideType.section).copyWith(title: phases.first));
  }

  slides.addAll([
    Slide.create(SlideType.canvas).copyWith(
      title: 'Projectcharter',
      improvementTemplateId: 'charter',
      customMarkdown: canvasTemplateStarterMarkdown('charter'),
    ),
    Slide.create(SlideType.tree).copyWith(
      title: 'CTQ-boom',
      improvementTemplateId: 'ctq-tree',
      improvementLayout: treeLayoutToken(
        treeTemplateById('ctq-tree')!.defaultLayout,
      ),
      bullets: _ctqStarterBullets(y01Description),
    ),
    Slide.create(SlideType.matrix).copyWith(
      title: 'SIPOC',
      improvementTemplateId: 'sipoc',
      tableRows: improvementTemplateStarterRows('sipoc', dataRows: 2),
    ),
  ]);

  for (final phase in phases.skip(1)) {
    slides.add(Slide.create(SlideType.section).copyWith(title: phase));
  }

  return slides;
}

/// Full deck including front-matter fields for framework and primary Y metric.
Deck buildImprovementProjectDeck({
  required String projectTitle,
  required String framework,
  required ImprovementY01Metric y01,
}) {
  final fw = isValidImprovementFramework(framework) ? framework : 'dmaic';
  return Deck(
    title: projectTitle,
    improvementFramework: fw,
    improvementY01Metric: y01,
    slides: buildImprovementProjectSlides(
      projectTitle: projectTitle,
      framework: fw,
      y01Description: y01.name,
    ),
  );
}
