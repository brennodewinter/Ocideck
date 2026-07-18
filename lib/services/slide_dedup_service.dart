import 'dart:collection';
import 'dart:convert';

import '../models/slide.dart';
import '../utils/log.dart';
import 'duplicate_service.dart';
import 'markdown_service.dart';

/// Which slide field a [SlideFieldDiff] describes. The widget layer maps these
/// to localized labels; this service stays Flutter- and l10n-free.
enum SlideField {
  type,
  title,
  subtitle,
  bullets,
  bullets2,
  columnTitle1,
  columnTitle2,
  listStyle,
  quote,
  quoteAuthor,
  body, // customMarkdown: free markdown / code / chart / cockpit / question / scaffold
  codeLanguage,
  image,
  imageCaption,
  image2,
  imageCaption2,
  video,
  audio,
  table,
  notes,
}

/// One field whose value differs between two slides. [before]/[after] are the
/// plain-text renderings of that field on each slide (empty = the field is
/// unset on that side).
class SlideFieldDiff {
  final SlideField field;
  final String before;
  final String after;
  const SlideFieldDiff(this.field, this.before, this.after);
}

/// A run of occurrences that share byte-identical slide *content* (same
/// [signature]), kept in discovery order. [primary] is the first occurrence —
/// the single card the picker shows; the rest are the duplicates it hides.
class SlideGroup<T> {
  final String signature;

  /// Every occurrence with this signature, in discovery order (length ≥ 1).
  final List<T> occurrences;

  const SlideGroup(this.signature, this.occurrences);

  T get primary => occurrences.first;

  /// How many places this exact slide was found (1 = unique).
  int get copies => occurrences.length;

  bool get hasCopies => occurrences.length > 1;

  /// The occurrences other than [primary] — the ones a de-duplicated list hides.
  Iterable<T> get duplicates => occurrences.skip(1);
}

/// Outcome of de-duplicating a list of slide occurrences: the collapsed
/// [groups] plus, per group, the indices of other groups whose slide *looks
/// alike* (same title, or same type with high text similarity) but is not
/// identical. [similar] is aligned to [groups] — `similar[i]` holds the group
/// indices related to `groups[i]`, so the UI can offer a "show differences"
/// action. [truncated] is true when a `maxGroups` cap hid further distinct
/// slides.
class SlideDedupResult<T> {
  final List<SlideGroup<T>> groups;
  final List<List<int>> similar;
  final bool truncated;
  const SlideDedupResult(this.groups, this.similar, {this.truncated = false});
}

/// De-duplicates slides gathered from several decks and finds near-duplicates.
///
/// Identity is content-based: a slide's [Slide.id] is a fresh UUID per parse,
/// so the same slide loaded from two files carries different ids. Instead the
/// signature is the markdown [MarkdownService] would write for the slide (with
/// no theme, so styling never splits an otherwise-identical pair) — it captures
/// every rendered field (including speaker notes, which travel with the slide)
/// but not the id, so two slides that would save identically collapse into one
/// [SlideGroup]. Slides that differ only in their notes therefore stay separate
/// and surface as look-alikes rather than being silently merged.
///
/// "Looks alike" (for the differences view) means the same non-empty title, or
/// the same [SlideType] with a Sørensen–Dice text similarity at or above
/// [similarityThreshold].
class SlideDedupService {
  SlideDedupService({MarkdownService? markdown, this.similarityThreshold = 0.8})
    : _md = markdown ?? MarkdownService();

  final MarkdownService _md;

  /// Minimum Dice coefficient (0..1) for two same-type slides to count as
  /// looking alike. 0.8 links clear edits of one slide without pulling in
  /// merely-related ones.
  final double similarityThreshold;

  /// Above this same-type bucket size we skip the O(n²) fuzzy pass and rely on
  /// same-title links only, so a huge scan never degrades to a quadratic sweep
  /// over thousands of slides.
  static const _fuzzyBucketCap = 80;

  // Identity-keyed caches: the same [Slide] instances recur across rebuilds
  // (they live in the scanned decks), so serialising/tokenising once keeps the
  // per-keystroke re-dedup cheap. Rescanning yields new instances; the few dead
  // entries are negligible.
  final Map<Slide, String> _sigCache = HashMap.identity();
  final Map<Slide, Map<String, int>> _gramCache = HashMap.identity();

  /// Content signature of [slide] — equal iff two slides render identically.
  String signatureOf(Slide slide) => _sigCache.putIfAbsent(slide, () {
    try {
      return DuplicateService.contentHash(
        utf8.encode(_md.generateSlide(slide, themeProfile: null)),
      );
    } catch (e, s) {
      // A malformed embedded spec (chart/cockpit/question) can trip the
      // serialiser; fall back to a coarse text key so the slide still dedups.
      logError('SlideDedupService.signatureOf: serialise slide for hash', e, s);
      return DuplicateService.contentHash(
        utf8.encode('${slide.type.name}\u0000${similarityText(slide)}'),
      );
    }
  });

  /// Collapse [items] onto their slides' content, preserving first-seen order,
  /// and link groups whose slides look alike. [slideOf] extracts the [Slide]
  /// from each item so callers keep their own occurrence type (a search hit, a
  /// per-deck entry, …).
  ///
  /// [maxGroups] caps the number of *distinct* slides returned: further
  /// distinct slides are dropped and [SlideDedupResult.truncated] is set, but
  /// copies of already-seen slides keep merging into their group. Leave it null
  /// to keep every distinct slide.
  SlideDedupResult<T> dedupe<T>(
    List<T> items,
    Slide Function(T) slideOf, {
    int? maxGroups,
  }) {
    final byKey = <String, List<T>>{};
    final order = <String>[];
    var truncated = false;
    for (final item in items) {
      final key = signatureOf(slideOf(item));
      final bucket = byKey[key];
      if (bucket != null) {
        bucket.add(item);
      } else if (maxGroups == null || order.length < maxGroups) {
        byKey[key] = [item];
        order.add(key);
      } else {
        truncated = true;
      }
    }
    final groups = [for (final k in order) SlideGroup(k, byKey[k]!)];
    return SlideDedupResult(
      groups,
      _similarLinks(groups, slideOf),
      truncated: truncated,
    );
  }

  List<List<int>> _similarLinks<T>(
    List<SlideGroup<T>> groups,
    Slide Function(T) slideOf,
  ) {
    final n = groups.length;
    // Sets keep pair-adds O(1) even for a large clique of same-title slides.
    final links = List.generate(n, (_) => <int>{});
    if (n < 2) return [for (var i = 0; i < n; i++) <int>[]];
    final slides = [for (final g in groups) slideOf(g.primary)];

    void link(int i, int j) {
      if (i == j) return;
      links[i].add(j);
      links[j].add(i);
    }

    // Same normalized, non-empty title → every such group is mutually alike.
    // A huge same-title bucket links to its first member only (star), so this
    // never becomes a quadratic sweep.
    final byTitle = <String, List<int>>{};
    for (var i = 0; i < n; i++) {
      final t = _normalize(slides[i].title);
      if (t.isEmpty) continue;
      (byTitle[t] ??= []).add(i);
    }
    for (final idxs in byTitle.values) {
      if (idxs.length > _fuzzyBucketCap) {
        for (var a = 1; a < idxs.length; a++) {
          link(idxs.first, idxs[a]);
        }
      } else {
        for (var a = 0; a < idxs.length; a++) {
          for (var b = a + 1; b < idxs.length; b++) {
            link(idxs[a], idxs[b]);
          }
        }
      }
    }

    // Same type + high text similarity, bounded per type bucket.
    final byType = <SlideType, List<int>>{};
    for (var i = 0; i < n; i++) {
      (byType[slides[i].type] ??= []).add(i);
    }
    for (final idxs in byType.values) {
      if (idxs.length < 2 || idxs.length > _fuzzyBucketCap) continue;
      for (var a = 0; a < idxs.length; a++) {
        for (var b = a + 1; b < idxs.length; b++) {
          final i = idxs[a], j = idxs[b];
          if (links[i].contains(j)) continue; // already alike by title
          final ga = _grams(slides[i]), gb = _grams(slides[j]);
          if (ga.isEmpty || gb.isEmpty) continue;
          if (_dice(ga, gb) >= similarityThreshold) link(i, j);
        }
      }
    }

    return [for (final l in links) l.toList()..sort()];
  }

  /// The fields that differ between [a] and [b], in [SlideField] order. Only
  /// fields whose plain-text value differs are returned.
  List<SlideFieldDiff> diff(Slide a, Slide b) {
    final va = _fieldValues(a), vb = _fieldValues(b);
    final out = <SlideFieldDiff>[];
    for (final field in SlideField.values) {
      final x = va[field] ?? '', y = vb[field] ?? '';
      if (x != y) out.add(SlideFieldDiff(field, x, y));
    }
    return out;
  }

  /// How alike [a] and [b] read, 0..1 (Sørensen–Dice over their visible text).
  /// Slides of different types never match. The dedup pass uses this internally;
  /// it is public so a cross-version comparison can pair up an *edited* slide
  /// with the one it came from (§9.5).
  double similarity(Slide a, Slide b) {
    if (a.type != b.type) return 0;
    return _dice(_grams(a), _grams(b));
  }

  /// The visible textual content of [slide], used for similarity scoring
  /// (paths and notes are deliberately excluded — they are not what a reader
  /// sees on the slide).
  String similarityText(Slide slide) => [
    slide.title,
    slide.subtitle,
    ...slide.bullets,
    ...slide.bullets2,
    slide.columnTitle1,
    slide.columnTitle2,
    slide.quote,
    slide.quoteAuthor,
    slide.customMarkdown,
    slide.imageCaption,
    slide.imageCaption2,
    for (final row in slide.tableRows) row.join(' '),
  ].where((s) => s.isNotEmpty).join('\n');

  Map<SlideField, String> _fieldValues(Slide s) => {
    SlideField.type: s.type.label,
    SlideField.title: s.title,
    SlideField.subtitle: s.subtitle,
    SlideField.bullets: s.bullets.join('\n'),
    SlideField.bullets2: s.bullets2.join('\n'),
    SlideField.columnTitle1: s.columnTitle1,
    SlideField.columnTitle2: s.columnTitle2,
    SlideField.listStyle: s.listStyle.name,
    SlideField.quote: s.quote,
    SlideField.quoteAuthor: s.quoteAuthor,
    SlideField.body: s.customMarkdown,
    SlideField.codeLanguage: s.codeLanguage,
    SlideField.image: s.imagePath,
    SlideField.imageCaption: s.imageCaption,
    SlideField.image2: s.imagePath2,
    SlideField.imageCaption2: s.imageCaption2,
    SlideField.video: s.videoPath,
    SlideField.audio: s.audioPath,
    SlideField.table: s.tableRows.map((r) => r.join(' | ')).join('\n'),
    SlideField.notes: s.notes,
  };

  Map<String, int> _grams(Slide s) =>
      _gramCache.putIfAbsent(s, () => _bigrams(similarityText(s)));

  static String _normalize(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Character-bigram multiset of [text] (whitespace collapsed), the basis for
  /// the Sørensen–Dice coefficient.
  static Map<String, int> _bigrams(String text) {
    final s = _normalize(text);
    final grams = <String, int>{};
    for (var i = 0; i + 1 < s.length; i++) {
      final g = s.substring(i, i + 2);
      grams[g] = (grams[g] ?? 0) + 1;
    }
    return grams;
  }

  /// Sørensen–Dice coefficient over two bigram multisets (0..1).
  static double _dice(Map<String, int> a, Map<String, int> b) {
    var total = 0, overlap = 0;
    for (final v in a.values) {
      total += v;
    }
    for (final entry in b.entries) {
      total += entry.value;
      final inA = a[entry.key];
      if (inA != null) overlap += inA < entry.value ? inA : entry.value;
    }
    if (total == 0) return 0;
    return 2 * overlap / total;
  }
}
