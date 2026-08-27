// Guards the direction the collaboration tests do not cover: **every field on
// `Slide` is accounted for in the syncable surface.**
//
// Two parity tests already exist, and they both look the same way —
// `test/deck_op_test.dart` asserts every `SlideField` has a case, and
// `test/collab_codec_test.dart` asserts the codec maps every `SlideField`.
// Both answer "is everything *in* the enum handled?". Neither answers "is every
// syncable field *in* the enum?", so adding a field to `Slide` lowered no gate
// at all. That is exactly how `imageZoom` slipped through (#1803): it was added
// two weeks after the op model landed, its own neighbours `imageSize` and the
// four focal fields were covered, and nothing noticed. A changed panel zoom
// silently never reached the other client.
//
// So this gate reads `Slide`'s field declarations and requires each to be in
// one of three places:
//
//   1. `SlideField` — it syncs on edit. The normal answer.
//   2. [deliberatelyNotSynced] — a written decision, with the reason next to it.
//   3. [unsyncedBaseline] — known debt. A RATCHET: it may shrink, never grow.
//
// The baseline exists because the gate must be able to land before the debt is
// paid off, and because silent debt is the thing that caused this bug. A field
// nobody has classified fails the gate, which forces the choice to be made once,
// in writing, by whoever adds the field — when they still know the answer.

import 'dart:io';

/// Fields deliberately outside the syncable surface, each with the reason.
///
/// "Deliberate" means there is written evidence in the code for it, not that it
/// seems unimportant. Anything else belongs in [unsyncedBaseline] until someone
/// decides.
const Map<String, String> deliberatelyNotSynced = {
  'id':
      'Slide identity. The op model keys *by* id (`SetSlideField.slideId`), so '
      'it can never itself be an edit — changing it would rename the slide out '
      'from under every op in flight.',
  'mediaRedacted':
      'Transient projection state, not authored content — `slideToJson` calls '
      'it out as such. It is recomputed from the privacy disposition on each '
      'side; syncing it would ship one participant\'s projection to another.',
  'contentRedacted': 'Transient projection state, as `mediaRedacted`.',
  'renderPage':
      'Transient render state (which rich-text page is on screen), not content. '
      '`slideToJson` calls it out as such.',
  'tableRows':
      'A known v1 boundary, named in the doc comment of collab_deck_diff.dart: '
      'the diff "leaves everything outside that surface (table rows, '
      'annotations, the seal) alone, exactly as the op model does". Table '
      'content is carried whole on insert and snapshot, but a cell edit does '
      'not sync. Documented limitation, not an oversight.',
};

/// Known debt: on `Slide`, not in `SlideField`, and nobody has decided whether
/// that is right. **A ratchet — this set may shrink, never grow.**
///
/// These fields are carried by `slideToJson` but not by `SlideField`, so a
/// *new* slide arrives complete and an *edit* to the field does not. That is
/// the `imageZoom` shape. The seven fields that were missing from the
/// collaboration layer entirely (`anchor`, `nextAnchor`, `ganttScale`,
/// `ganttSections`, `menuLayout`, `tableColumnAlignments`,
/// `tableNumberColumns`) were added to both `slideToJson` and `SlideField` in
/// #1807, fixing the broken "Every field is carried" invariant.
const Set<String> unsyncedBaseline = {
  // Carried whole, not carried on edit.
  'aiAssistedFields',
  'bulletMarkerOverride',
  'findingRole',
  'improvementLayout',
  'privacy',
  'quality',
  'timelineAnimationMs',
  'timelineCurrentIndex',
  'timelineLayout',
  'timelineReveal',
  'viewLimit',
};

/// The `final` field names declared directly on `class Slide`.
List<String> slideFieldNames(String source) {
  final start = source.indexOf('\nclass Slide {');
  if (start < 0) throw StateError('class Slide not found in slide.dart');
  final end = source.indexOf('\n}\n', start);
  final body = source.substring(start, end < 0 ? source.length : end);
  return RegExp(
    r'^  final\s+[\w<>,\s?]+?\s+(\w+);',
    multiLine: true,
  ).allMatches(body).map((m) => m.group(1)!).toList();
}

/// The entries of `enum SlideField`.
List<String> slideFieldEnumNames(String source) {
  final start = source.indexOf('enum SlideField {');
  if (start < 0) throw StateError('enum SlideField not found in deck_op.dart');
  final end = source.indexOf('\n}', start);
  final body = source.substring(start, end < 0 ? source.length : end);
  return RegExp(
    r'^  (\w+),',
    multiLine: true,
  ).allMatches(body).map((m) => m.group(1)!).toList();
}

/// The parity problems between [fields] (everything declared on `Slide`) and
/// [synced] (the `SlideField` entries). Empty means the surfaces agree.
///
/// Pure, so a test can plant a violation instead of editing the real model — a
/// gate that has never been seen to fail is not known to guard anything.
List<String> parityProblems({
  required List<String> fields,
  required Set<String> synced,
  Map<String, String> deliberate = deliberatelyNotSynced,
  Set<String> baseline = unsyncedBaseline,
}) {
  final problems = <String>[];

  // 1. Every field is classified.
  final unclassified = fields
      .where(
        (f) =>
            !synced.contains(f) &&
            !deliberate.containsKey(f) &&
            !baseline.contains(f),
      )
      .toList();
  if (unclassified.isNotEmpty) {
    problems.add(
      'Not classified (${unclassified.length}): ${unclassified.join(', ')}\n'
      '  A new field on Slide must be one of three things, and only you know\n'
      '  which — decide it now rather than leaving it to be discovered by two\n'
      '  people whose decks quietly disagree:\n'
      '    * add it to `SlideField` (+ slideFieldValue, applyOp, the codec\n'
      '      kind map and a case in test/deck_op_test.dart) so edits sync; or\n'
      '    * add it to `deliberatelyNotSynced` in this file, with the reason; or\n'
      '    * add it to `unsyncedBaseline` — only if you are knowingly leaving\n'
      '      debt, and say so in the pull request.',
    );
  }

  // 2. The baseline is a ratchet: it may shrink, never grow.
  final paidOff = baseline.where(synced.contains).toList()..sort();
  if (paidOff.isNotEmpty) {
    problems.add(
      'Now synced, so remove from `unsyncedBaseline` (${paidOff.length}): '
      '${paidOff.join(', ')}\n'
      '  The ratchet only counts if it is tightened when the debt is paid.',
    );
  }

  final gone =
      baseline
          .followedBy(deliberate.keys)
          .where((f) => !fields.contains(f))
          .toList()
        ..sort();
  if (gone.isNotEmpty) {
    problems.add(
      'No longer a field on Slide, so remove the entry (${gone.length}): '
      '${gone.join(', ')}',
    );
  }

  // 3. The enum may not name something Slide does not have.
  final phantom = synced.where((f) => !fields.contains(f)).toList()..sort();
  if (phantom.isNotEmpty) {
    problems.add(
      'In SlideField but not a field on Slide (${phantom.length}): '
      '${phantom.join(', ')}',
    );
  }

  return problems;
}

void main() {
  final fields = slideFieldNames(
    File('lib/models/slide.dart').readAsStringSync(),
  );
  final synced = slideFieldEnumNames(
    File('lib/collab/deck_op.dart').readAsStringSync(),
  ).toSet();
  final problems = parityProblems(fields: fields, synced: synced);

  if (problems.isEmpty) {
    stdout.writeln(
      'check-collab-field-parity: OK '
      '(${fields.length} Slide fields — ${synced.length} synced, '
      '${deliberatelyNotSynced.length} deliberately not, '
      '${unsyncedBaseline.length} known debt).',
    );
    return;
  }

  stderr.writeln(
    'check-collab-field-parity: the syncable surface and Slide disagree.',
  );
  for (final p in problems) {
    stderr
      ..writeln('')
      ..writeln(p);
  }
  exit(1);
}
