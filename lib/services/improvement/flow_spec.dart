// Flow / VSM engine data (PROCESS_IMPROVEMENT.md §3.4 / §11). Pure Dart.
// Template *data* lives in assets/improvement/templates/ (see catalog).
library;

import '../../l10n/app_localizations.dart';
import 'improvement_template_catalog.dart';

enum FlowLayout { flow, swimlane, vsm }

FlowLayout flowLayoutFromToken(String token) {
  switch (token.trim().toLowerCase()) {
    case 'swimlane':
      return FlowLayout.swimlane;
    case 'vsm':
      return FlowLayout.vsm;
    default:
      return FlowLayout.flow;
  }
}

String flowLayoutToken(FlowLayout layout) => switch (layout) {
  FlowLayout.flow => 'flow',
  FlowLayout.swimlane => 'swimlane',
  FlowLayout.vsm => 'vsm',
};

const String kDefaultFlowTemplateId = 'process-map';

List<FlowTemplate> get bundledFlowTemplates =>
    ImprovementTemplateCatalog.instance.flowTemplates;

FlowTemplate? flowTemplateById(String id) =>
    ImprovementTemplateCatalog.instance.flowById(id);

class FlowTemplate {
  const FlowTemplate({
    required this.id,
    required this.defaultLayout,
    required this.phase,
    required this.labelNl,
    required this.labelEn,
    required this.guidanceNl,
    required this.guidanceEn,
    required this.starterBullets,
  });

  final String id;
  final FlowLayout defaultLayout;
  final String phase;
  final String labelNl;
  final String labelEn;
  final String guidanceNl;
  final String guidanceEn;
  final List<String> starterBullets;

  String label(String lang) => AppLocalizations.sourceFor(lang, labelNl);
  String guidance(String lang) => AppLocalizations.sourceFor(lang, guidanceNl);
}

/// One parsed flow step. Durations are minutes (derived at parse time).
class FlowStep {
  const FlowStep({
    required this.title,
    required this.kind,
    this.processMinutes = 0,
    this.leadMinutes = 0,
    this.wip = 0,
    this.fte = 0,
    this.fpy = 0,
    this.lane = '',
  });

  final String title;
  final String kind;
  final double processMinutes;
  final double leadMinutes;
  final double wip;
  final double fte;
  final double fpy;
  final String lane;

  bool get isInventory => kind == 'inventory' || kind == 'wait';
  bool get isProcess => !isInventory;
}

/// Derived roll-ups — never persisted.
class FlowRollup {
  const FlowRollup({
    required this.totalProcessMinutes,
    required this.totalLeadMinutes,
    required this.pce,
    required this.bottleneckTitle,
    required this.littlesLawWarning,
  });

  final double totalProcessMinutes;
  final double totalLeadMinutes;

  /// Process cycle efficiency = PT/LT, or 0 when LT is 0.
  final double pce;
  final String bottleneckTitle;

  /// Non-empty when WIP and flow time contradict Little's Law roughly.
  final String littlesLawWarning;
}
