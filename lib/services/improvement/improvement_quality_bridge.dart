// Golden-thread lint: Y-/X-ids defined on tree slides must be referenced elsewhere.
library;

import '../../models/deck.dart';
import '../../models/markdown_validation.dart';
import '../../models/slide.dart';
import '../../models/slide_quality.dart';
import 'tree_slide.dart';

/// Collects all **Y-nn** / **X-nn** ids in [text], in encounter order.
Iterable<String> improvementIdsInText(String text) sync* {
  for (final m in improvementIdPattern.allMatches(text)) {
    yield m.group(1)!;
  }
}

void _scanText(String text, void Function(String id) onId) {
  for (final id in improvementIdsInText(text)) {
    onId(id);
  }
}

void _scanSlide(Slide slide, void Function(String id) onId) {
  for (final bullet in slide.bullets) {
    _scanText(bulletText(bullet), onId);
  }
  _scanText(slide.customMarkdown, onId);
  for (final row in slide.tableRows) {
    for (final cell in row) {
      _scanText(cell, onId);
    }
  }
}

/// Scans [deck] for orphan and unused golden-thread ids.
List<SlideQualityIssue> improvementIssuesFrom(Deck deck) {
  final defined = <String>{};
  final referenced = <String, int>{};

  for (var i = 0; i < deck.slides.length; i++) {
    final slide = deck.slides[i];
    if (slide.type == SlideType.tree) {
      for (final id in improvementIdsInBullets(slide.bullets)) {
        defined.add(id);
      }
    }
    _scanSlide(slide, (id) {
      referenced[id] = i;
    });
  }

  final issues = <SlideQualityIssue>[];

  for (final entry in referenced.entries) {
    final id = entry.key;
    if (defined.contains(id)) continue;
    issues.add(
      SlideQualityIssue(
        slideIndex: entry.value,
        kind: SlideQualityIssueKind.improvementOrphanId,
        category: SlideQualityCategory.improvement,
        severity: MarkdownValidationSeverity.warning,
        args: {'id': id},
      ),
    );
  }

  for (final id in defined) {
    var referencedOutsideTree = false;
    for (final slide in deck.slides) {
      if (slide.type == SlideType.tree) continue;
      var found = false;
      _scanSlide(slide, (foundId) {
        if (foundId == id) found = true;
      });
      if (found) {
        referencedOutsideTree = true;
        break;
      }
    }
    if (referencedOutsideTree) continue;

    final treeIndex = deck.slides.indexWhere(
      (s) =>
          s.type == SlideType.tree &&
          improvementIdsInBullets(s.bullets).contains(id),
    );
    issues.add(
      SlideQualityIssue(
        slideIndex: treeIndex >= 0 ? treeIndex : 0,
        kind: SlideQualityIssueKind.improvementUnusedId,
        category: SlideQualityCategory.improvement,
        severity: MarkdownValidationSeverity.informational,
        args: {'id': id},
      ),
    );
  }

  return issues;
}
