// Canvas engine data shapes for Procesverbetering (PROCESS_IMPROVEMENT.md §3.2).
// Pure Dart — regions are ordinary ## headings on disk; layout is template data.
// Template *data* lives in assets/improvement/templates/ (see catalog).
library;

import '../../l10n/app_localizations.dart';
import 'improvement_template_catalog.dart';

/// How a canvas lays its regions on the slide.
enum CanvasLayout {
  /// Fixed named boxes (A3, charter).
  regions,

  /// Four quadrants with axis labels (Impact/Effort, SWOT, PICK).
  quadrant,

  /// Columns of cards (Kanban / board).
  board,
}

/// One named region on a canvas template.
class CanvasRegion {
  const CanvasRegion({
    required this.key,
    required this.labelNl,
    required this.labelEn,
  });

  final String key;
  final String labelNl;
  final String labelEn;

  String label(String lang) => AppLocalizations.sourceFor(lang, labelNl);
}

/// A filled region: the heading that was on disk plus its body text.
class CanvasRegionContent {
  const CanvasRegionContent({
    required this.key,
    required this.heading,
    required this.body,
  });

  final String key;
  final String heading;
  final String body;
}

/// Bundled canvas templates from [ImprovementTemplateCatalog].
List<CanvasTemplate> get bundledCanvasTemplates =>
    ImprovementTemplateCatalog.instance.canvasTemplates;

/// The default canvas a fresh slide starts from — A3 is the one-page poster
/// most authors expect first.
const String kDefaultCanvasTemplateId = 'a3';

CanvasTemplate? canvasTemplateById(String id) =>
    ImprovementTemplateCatalog.instance.canvasById(id);

/// Starter Markdown for [id]: English `##` headings (file contract) and empty
/// bodies. Unknown ids yield a single empty region heading.
String canvasTemplateStarterMarkdown(String id) {
  final template = canvasTemplateById(id);
  if (template == null) return '## Region\n\n';
  return [
    for (final region in template.regions) '## ${region.labelEn}\n\n',
  ].join();
}

class CanvasTemplate {
  const CanvasTemplate({
    required this.id,
    required this.layout,
    required this.phase,
    required this.labelNl,
    required this.labelEn,
    required this.guidanceNl,
    required this.guidanceEn,
    required this.regions,
    this.axisXLowNl = '',
    this.axisXHighNl = '',
    this.axisYLowNl = '',
    this.axisYHighNl = '',
    this.axisXLowEn = '',
    this.axisXHighEn = '',
    this.axisYLowEn = '',
    this.axisYHighEn = '',
  });

  final String id;
  final CanvasLayout layout;
  final String phase;
  final String labelNl;
  final String labelEn;
  final String guidanceNl;
  final String guidanceEn;
  final List<CanvasRegion> regions;
  final String axisXLowNl;
  final String axisXHighNl;
  final String axisYLowNl;
  final String axisYHighNl;
  final String axisXLowEn;
  final String axisXHighEn;
  final String axisYLowEn;
  final String axisYHighEn;

  String label(String lang) => AppLocalizations.sourceFor(lang, labelNl);
  String guidance(String lang) => AppLocalizations.sourceFor(lang, guidanceNl);

  String axisXLow(String lang) => AppLocalizations.sourceFor(lang, axisXLowNl);
  String axisXHigh(String lang) =>
      AppLocalizations.sourceFor(lang, axisXHighNl);
  String axisYLow(String lang) => AppLocalizations.sourceFor(lang, axisYLowNl);
  String axisYHigh(String lang) =>
      AppLocalizations.sourceFor(lang, axisYHighNl);
}
