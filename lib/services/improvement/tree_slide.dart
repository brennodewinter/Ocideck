// Bridge between a `tree` slide and golden-thread ids (PROCESS_IMPROVEMENT §3.3/§5).
library;

import '../../models/slide.dart';
import 'tree_spec.dart';

/// Matches authored ids like `**X-03**` or `**Y-01**` inline in bullet text.
final RegExp improvementIdPattern = RegExp(r'\*\*([YX]-\d+)\*\*');

/// All Y-/X-ids found in [bullets], in encounter order (duplicates kept once).
List<String> improvementIdsInBullets(List<String> bullets) {
  final seen = <String>{};
  final out = <String>[];
  for (final b in bullets) {
    for (final m in improvementIdPattern.allMatches(bulletText(b))) {
      final id = m.group(1)!;
      if (seen.add(id)) out.add(id);
    }
  }
  return out;
}

/// Next free id of [kind] (`X` or `Y`) given ids already present.
String nextImprovementId(String kind, Iterable<String> existing) {
  final prefix = kind.toUpperCase() == 'Y' ? 'Y' : 'X';
  var max = 0;
  final re = RegExp('^$prefix-(\\d+)\$');
  for (final id in existing) {
    final m = re.firstMatch(id);
    if (m != null) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n > max) max = n;
    }
  }
  return '$prefix-${(max + 1).toString().padLeft(2, '0')}';
}

TreeLayout treeLayoutOf(Slide slide) {
  if (slide.improvementLayout.isNotEmpty) {
    return treeLayoutFromToken(slide.improvementLayout);
  }
  return treeTemplateById(slide.improvementTemplateId)?.defaultLayout ??
      TreeLayout.tree;
}

List<String> treeStarterBullets(String templateId) => List<String>.from(
  treeTemplateById(templateId)?.starterBullets ??
      bundledTreeTemplates.first.starterBullets,
);
