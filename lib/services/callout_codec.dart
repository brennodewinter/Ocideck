// The codec for the `ocideck_callouts` front-matter block (IMAGE_CALLOUTS.md §2).
//
// Two things are stored, and only two: the visible `(A)` reference in the bullet
// (ordinary text, handled by the editor) and the canonical data in front matter
// (handled here). Nothing derived is persisted (§2.3).
//
// Owning the key removes the byte-for-byte preservation that `mergeFrontMatter`
// gives to unknown keys (§2.5). This codec therefore implements a **nested merge
// contract**: the parser keeps raw lines alongside its typed view, and the
// serialiser rewrites only the entries it actually edited — every other line
// survives exactly: unknown entry keys, malformed known entries, comments, blank
// lines, original order, quoting and duplicate keys.

import '../models/image_callout.dart';
import 'front_matter_merge.dart';

/// The front-matter key under which callouts are stored.
const String kCalloutsFrontMatterKey = 'ocideck_callouts';

/// Parsed view of one slide's callout block, plus the raw lines it came from.
///
/// The [rawLines] are kept so the writer can perform the nested merge: only
/// entries that were deliberately edited are rewritten; everything else stays
/// byte-for-byte. An anchor that the parser could not parse at all keeps its
/// raw lines and has a null [typed] view — it is preserved and reported by the
/// checker, not rendered.
class CalloutSlideBlock {
  /// The slide anchor this block is keyed by.
  final String anchor;

  /// The typed view, or null if the block could not be parsed (malformed,
  /// unknown geometry, etc.). Raw lines are always kept.
  final CalloutSlideData? typed;

  /// The raw lines of this anchor's block (the indented lines under the anchor
  /// key), in original order, for lossless rewriting.
  final List<String> rawLines;

  CalloutSlideBlock({
    required this.anchor,
    required this.typed,
    required this.rawLines,
  });
}

/// The typed data extracted from one slide's callout block.
class CalloutSlideData {
  final CalloutPresentation presentation;
  final BulletRevealMode reveal;
  final List<ImageCallout> callouts;

  /// Raw lines keyed by entry letter, for the nested merge. Each entry's raw
  /// line is kept so the writer can rewrite only edited entries.
  final Map<String, String> rawEntryLines;

  /// The order of entries as they appeared in the file, including duplicates and
  /// unknown keys. Preserved for lossless rewriting.
  final List<String> entryOrder;

  CalloutSlideData({
    required this.presentation,
    required this.reveal,
    required this.callouts,
    required this.rawEntryLines,
    required this.entryOrder,
  });
}

/// The result of parsing the entire `ocideck_callouts` front-matter block.
class CalloutBlockParseResult {
  /// All slide blocks, in the order they appeared in the file.
  final List<CalloutSlideBlock> blocks;

  /// Raw lines of the entire block (everything under `ocideck_callouts:`),
  /// for lossless rewriting when no typed data is edited.
  final List<String> rawLines;

  /// Whether the block was present at all.
  final bool present;

  CalloutBlockParseResult({
    required this.blocks,
    required this.rawLines,
    required this.present,
  });

  static CalloutBlockParseResult empty() =>
      CalloutBlockParseResult(blocks: [], rawLines: [], present: false);
}

/// Parse the `ocideck_callouts` block from front-matter source lines.
///
/// [sourceLines] are the full front-matter lines (as stored by
/// `Deck.frontMatterSource`). This function finds the `ocideck_callouts:` key,
/// consumes its indented continuation lines, and returns the typed view plus
/// raw lines for lossless rewriting.
///
/// Lines before and after the block are not consumed — the caller passes the
/// full source and gets back the block's parse result.
CalloutBlockParseResult parseCalloutBlock(List<String> sourceLines) {
  // Find the `ocideck_callouts:` key at column 0.
  int? keyIndex;
  for (var i = 0; i < sourceLines.length; i++) {
    final line = sourceLines[i];
    // A line that starts with `ocideck_callouts:` is already at column 0 —
    // an indented line would start with whitespace, not the key.
    if (!line.startsWith('$kCalloutsFrontMatterKey:')) continue;
    keyIndex = i;
    break;
  }
  if (keyIndex == null) return CalloutBlockParseResult.empty();

  // Collect all continuation lines (indented or list items at col 0).
  final blockLines = <String>[];
  for (var i = keyIndex + 1; i < sourceLines.length; i++) {
    final line = sourceLines[i];
    if (isFrontMatterContinuation(line)) {
      blockLines.add(line);
      continue;
    }
    break;
  }

  // Now parse the two-level grammar from blockLines:
  // Level 1: `<anchor>:` (indented 2 spaces typically)
  // Level 2: `mode: pin`, `reveal: steps`, `A: point 0.4 0.2 | desc`
  final blocks = <CalloutSlideBlock>[];
  String? currentAnchor;
  final currentRaw = <String>[];

  void flush() {
    if (currentAnchor != null) {
      blocks.add(
        CalloutSlideBlock(
          anchor: currentAnchor,
          typed: null, // filled below
          rawLines: List.of(currentRaw),
        ),
      );
    }
  }

  for (final line in blockLines) {
    final anchorMatch = _reAnchorKey.firstMatch(line);
    if (anchorMatch != null) {
      flush();
      currentRaw.clear();
      currentAnchor = anchorMatch.group(1)!;
      currentRaw.add(line);
      continue;
    }
    if (currentAnchor != null) {
      currentRaw.add(line);
    }
  }
  flush();

  // Now parse each block's entry lines into typed data.
  final typedBlocks = <CalloutSlideBlock>[];
  for (final blk in blocks) {
    final entryLines = blk.rawLines.skip(1).toList();
    final data = _parseSlideData(entryLines);
    typedBlocks.add(
      CalloutSlideBlock(
        anchor: blk.anchor,
        typed: data,
        rawLines: blk.rawLines,
      ),
    );
  }

  return CalloutBlockParseResult(
    blocks: typedBlocks,
    rawLines: blockLines,
    present: true,
  );
}

/// Regex for an anchor key line: `  <anchor>:` (indented, key at col 2+).
final _reAnchorKey = RegExp(r'^[ \t]+([A-Za-z0-9_-]+):[ \t]*$');

/// Parse the entry lines under one anchor into typed data.
CalloutSlideData? _parseSlideData(List<String> entryLines) {
  var presentation = CalloutPresentation.pin;
  var reveal = BulletRevealMode.all;
  final callouts = <ImageCallout>[];
  final rawEntryLines = <String, String>{};
  final entryOrder = <String>[];

  for (final line in entryLines) {
    final trimmed = line.trimLeft();
    // mode: pin|region|arrow
    if (trimmed.startsWith('mode:')) {
      final val = trimmed.substring(5).trim();
      presentation = switch (val) {
        'pin' => CalloutPresentation.pin,
        'region' => CalloutPresentation.region,
        'arrow' => CalloutPresentation.arrow,
        _ => presentation, // unknown mode: keep default, checker reports
      };
      continue;
    }
    // reveal: all|steps
    if (trimmed.startsWith('reveal:')) {
      final val = trimmed.substring(7).trim();
      reveal = switch (val) {
        'all' => BulletRevealMode.all,
        'steps' => BulletRevealMode.steps,
        _ => reveal, // unknown reveal: keep default, checker reports
      };
      continue;
    }
    // Entry: `A: point 0.4 0.2 | description`
    final entryMatch = _reEntryKey.firstMatch(trimmed);
    if (entryMatch != null) {
      final ref = entryMatch.group(1)!;
      final value = (entryMatch.group(2) ?? '').trim();
      entryOrder.add(ref);
      rawEntryLines[ref] = line;
      final callout = _parseCalloutEntry(ref, value);
      if (callout != null) callouts.add(callout);
      continue;
    }
    // Unknown line (comment, blank, future token, malformed entry): keep in
    // entryOrder as raw passthrough. We track every line so the writer knows
    // what to preserve byte-voor-byte (§2.5).
    entryOrder.add('\x00RAW:$line');
  }

  return CalloutSlideData(
    presentation: presentation,
    reveal: reveal,
    callouts: callouts,
    rawEntryLines: rawEntryLines,
    entryOrder: entryOrder,
  );
}

/// Regex for an entry key: `A:` (single uppercase letter).
final _reEntryKey = RegExp(r'^([A-Z]):[ \t]*(.*)$');

/// Parse one entry value: `point 0.402 0.251 | description` or
/// `region 0.5 0.2 0.18 0.22 | description` or
/// `point 0.6 0.4; point 0.7 0.3 | description`.
ImageCallout? _parseCalloutEntry(String ref, String value) {
  // Split geometry from description at the first ` | `.
  final pipeIdx = value.indexOf(' | ');
  final geoPart = pipeIdx >= 0 ? value.substring(0, pipeIdx) : value;
  final desc = pipeIdx >= 0 ? value.substring(pipeIdx + 3) : '';
  // The description is a plain scalar — strip surrounding quotes if present,
  // otherwise keep as-is. No YAML scalar parsing here: the codec is a
  // standalone module, and the description is author text, not YAML.
  final description = _stripScalarQuotes(desc.trim());

  // Split multiple targets at `; `.
  final geoTokens = geoPart
      .split('; ')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (geoTokens.isEmpty) return null;

  final targets = <CalloutTarget>[];
  for (final token in geoTokens) {
    final target = _parseGeometry(token);
    if (target != null) targets.add(target);
  }
  if (targets.isEmpty) return null;

  return ImageCallout(
    reference: ref,
    targets: targets,
    description: description,
  );
}

/// Parse one geometry token: `point 0.402 0.251` or `region 0.5 0.2 0.18 0.22`.
/// Returns null for malformed geometry — the checker reports it, the renderer
/// refuses to draw it, and the raw line is preserved.
CalloutTarget? _parseGeometry(String token) {
  final parts = token.split(RegExp(r'\s+'));
  if (parts.isEmpty) return null;

  switch (parts[0]) {
    case 'point':
      if (parts.length != 3) return null;
      final x = double.tryParse(parts[1]);
      final y = double.tryParse(parts[2]);
      if (x == null || y == null) return null;
      return CalloutPoint(x, y);
    case 'region':
      if (parts.length != 5) return null;
      final x = double.tryParse(parts[1]);
      final y = double.tryParse(parts[2]);
      final w = double.tryParse(parts[3]);
      final h = double.tryParse(parts[4]);
      if (x == null || y == null || w == null || h == null) return null;
      return CalloutRegion(x, y, w, h);
    default:
      // Unknown geometry token (future version): return null, checker reports.
      return null;
  }
}

/// Strip surrounding single or double quotes from a YAML-style scalar, but
/// leave quotes that are part of the text alone. Only strips matching pairs
/// that wrap the entire string.
String _stripScalarQuotes(String s) {
  if (s.length >= 2) {
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      return s.substring(1, s.length - 1);
    }
  }
  return s;
}

/// Serialise the callout block for a deck, performing the nested merge.
///
/// This is the lossless writer (§2.5). It takes the deck's slides (with their
/// typed callout data) and the original raw block lines, and produces the
/// canonical block lines — rewriting only entries that were deliberately edited,
/// preserving everything else byte-for-byte.
///
/// Returns null if no slide has callouts (the block is omitted entirely).
List<String>? serializeCalloutBlock({
  required List<
    ({
      String anchor,
      List<ImageCallout> callouts,
      CalloutPresentation presentation,
      BulletRevealMode reveal,
    })
  >
  slidesWithCallouts,
  required CalloutBlockParseResult? original,
}) {
  if (slidesWithCallouts.every((s) => s.callouts.isEmpty)) return null;

  final out = <String>['$kCalloutsFrontMatterKey:'];

  // Build a map of original blocks by anchor for the nested merge.
  final origByAnchor = <String, CalloutSlideBlock>{};
  if (original != null) {
    for (final blk in original.blocks) {
      origByAnchor[blk.anchor] = blk;
    }
  }

  for (final slide in slidesWithCallouts) {
    if (slide.callouts.isEmpty) continue;
    out.add('  ${slide.anchor}:');

    final orig = origByAnchor[slide.anchor];
    final origData = orig?.typed;

    // mode and reveal: only write if non-default. These are always canonical
    // (the codec owns them); they go before the entries, matching §2.2 grammar.
    if (slide.presentation != CalloutPresentation.pin) {
      out.add('    mode: ${slide.presentation.name}');
    }
    if (slide.reveal != BulletRevealMode.all) {
      out.add('    reveal: ${slide.reveal.name}');
    }

    // Entries: walk the original order and rewrite in place. For each original
    // entry, if it's still in the typed model and unchanged, keep the raw line
    // (preserving quoting/formatting). If edited, emit canonical. If no longer
    // in the typed model (orphan, duplicate), preserve verbatim. Comments,
    // blanks and unknown tokens are always preserved verbatim. New entries
    // (not in the original) are appended at the end.
    final typedByRef = <String, ImageCallout>{
      for (final c in slide.callouts) c.reference: c,
    };
    final written = <String>{};

    if (origData != null) {
      for (final key in origData.entryOrder) {
        if (key.startsWith('\x00RAW:')) {
          // Comment, blank, malformed entry, future token: preserve verbatim.
          out.add(key.substring(5));
        } else {
          final callout = typedByRef[key];
          if (callout != null) {
            written.add(key);
            final origRaw = origData.rawEntryLines[key];
            if (origRaw != null && _entryMatches(origRaw, callout)) {
              out.add(origRaw);
            } else {
              out.add('    $key: ${callout.toBlockValue()}');
            }
          } else {
            // Entry existed in file but not in typed model: preserve verbatim.
            final raw = origData.rawEntryLines[key];
            if (raw != null) out.add(raw);
          }
        }
      }
    }

    // New entries (in typed model but not in original): append at end.
    for (final callout in slide.callouts) {
      if (!written.contains(callout.reference)) {
        out.add('    ${callout.reference}: ${callout.toBlockValue()}');
      }
    }
  }

  // Preserve original anchor blocks that are no longer in the typed model
  // (orphans — §2.4: kept, reported, removed only by explicit cleanup).
  if (original != null) {
    final writtenAnchors = slidesWithCallouts
        .where((s) => s.callouts.isNotEmpty)
        .map((s) => s.anchor)
        .toSet();
    for (final blk in original.blocks) {
      if (!writtenAnchors.contains(blk.anchor)) {
        // Preserve the entire raw block verbatim.
        for (final line in blk.rawLines) {
          out.add(line);
        }
      }
    }
  }

  return out;
}

/// Check whether an original raw entry line matches the typed callout value.
/// If they match, the writer keeps the raw line (preserving quoting/formatting).
bool _entryMatches(String rawLine, ImageCallout callout) {
  final trimmed = rawLine.trimLeft();
  final entryMatch = _reEntryKey.firstMatch(trimmed);
  if (entryMatch == null) return false;
  final value = (entryMatch.group(2) ?? '').trim();
  // Compare the parsed meaning, not the raw text — the raw might have different
  // decimal precision or quoting that normalises to the same value.
  final parsed = _parseCalloutEntry(callout.reference, value);
  if (parsed == null) return false;
  return parsed == callout;
}
