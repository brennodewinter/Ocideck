// Tree engine data shapes for Procesverbetering (PROCESS_IMPROVEMENT.md §3.3).
// Pure Dart — depth is leading tabs on Slide.bullets; layout is template/data.
// Template *data* lives in assets/improvement/templates/ (see catalog).
library;

import '../../l10n/app_localizations.dart';
import 'improvement_template_catalog.dart';

/// How a tree lays out on the slide.
enum TreeLayout {
  /// Nested indented hierarchy.
  tree,

  /// Ishikawa / fishbone — top-level bullets are category bones.
  fishbone,
}

TreeLayout treeLayoutFromToken(String token) {
  switch (token.trim().toLowerCase()) {
    case 'fishbone':
      return TreeLayout.fishbone;
    default:
      return TreeLayout.tree;
  }
}

String treeLayoutToken(TreeLayout layout) => switch (layout) {
  TreeLayout.tree => 'tree',
  TreeLayout.fishbone => 'fishbone',
};

const String kDefaultTreeTemplateId = 'five-whys';

List<TreeTemplate> get bundledTreeTemplates =>
    ImprovementTemplateCatalog.instance.treeTemplates;

TreeTemplate? treeTemplateById(String id) =>
    ImprovementTemplateCatalog.instance.treeById(id);

class TreeTemplate {
  const TreeTemplate({
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
  final TreeLayout defaultLayout;
  final String phase;
  final String labelNl;
  final String labelEn;
  final String guidanceNl;
  final String guidanceEn;
  final List<String> starterBullets;

  String label(String lang) => AppLocalizations.sourceFor(lang, labelNl);
  String guidance(String lang) => AppLocalizations.sourceFor(lang, guidanceNl);
}
