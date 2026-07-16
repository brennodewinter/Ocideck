import 'dart:math' as math;

import '../models/slide.dart';

/// Splitting an over-full bullet list into balanced, group-aware pages — the
/// logic behind the "Split slide" density fix. These are pure functions over a
/// list of bullet strings and a per-page capacity; the capacity itself comes
/// from `bulletFitCounts`/`bulletPageCap` in `slide_layout_metrics.dart`, which
/// measure how many bullets fit at natural size.

/// The comfortable number of bullets on one page: the smaller of what fits at
/// natural size ([fit], from `bulletFitCounts`) and the readability [limit],
/// never below one.
int bulletPageCap(int fit, int limit) {
  final cap = fit < limit ? fit : limit;
  return cap < 1 ? 1 : cap;
}

/// How many pages [bullets] need so none exceeds [cap], keeping whole groups
/// (a heading plus its bullets) on one page where they fit — so the balanced
/// spread that follows lands its breaks on group boundaries. A group larger than
/// [cap] is cut across pages. Always at least two, so splitting a slide that
/// already fits still divides it in two on request.
int pageCountToFit(List<String> bullets, int cap) {
  final c = cap < 1 ? 1 : cap;
  final len = bullets.length;
  var pages = 1;
  var fill = 0; // items al op de huidige pagina
  var i = 0;
  while (i < len) {
    // De groep die bij [i] begint: de (optionele) kop plus alle bullets tot de
    // volgende kop.
    var end = i + 1;
    while (end < len && !isGroupHeading(bullets[end])) {
      end++;
    }
    final size = end - i;
    if (size > c) {
      // Groep groter dan een pagina: sluit een gevulde pagina af en verdeel de
      // groep over zoveel pagina's als nodig.
      if (fill > 0) pages++;
      pages += (size - 1) ~/ c;
      fill = size - ((size - 1) ~/ c) * c;
    } else if (fill + size <= c) {
      fill += size; // past nog bij de vorige groep(en) op deze pagina
    } else {
      pages++; // begin een nieuwe pagina voor deze groep
      fill = size;
    }
    i = end;
  }
  return pages < 2 ? 2 : pages;
}

/// Split [bullets] into as many balanced pages as needed so no page exceeds the
/// per-page optimum [cap] — the answer to "Splits slide" on an overfull list.
/// Page breaks snap to group headings so a heading always leads its page.
List<List<String>> paginateBulletsToFit(List<String> bullets, int cap) =>
    spreadBulletsOverPages(bullets, pageCountToFit(bullets, cap), cap);

/// Split [left] and [right] over the same number of pages so a two-column slide
/// falls into aligned halves, each column within its own optimum ([capL]/[capR]).
/// Returns one `(left, right)` record per page; a column shorter than the other
/// simply runs out of items on the later pages.
List<(List<String>, List<String>)> paginateTwoColumnsToFit(
  List<String> left,
  int capL,
  List<String> right,
  int capR,
) {
  final nPages = math.max(
    pageCountToFit(left, capL),
    pageCountToFit(right, capR),
  );
  final lp = spreadBulletsOverPages(left, nPages, capL);
  final rp = spreadBulletsOverPages(right, nPages, capR);
  return [for (var i = 0; i < nPages; i++) (lp[i], rp[i])];
}

/// Split [bullets] into exactly [nPages] consecutive pages, balanced in size,
/// with page breaks snapped to group headings so a heading always leads its page
/// (never stranded at the foot of the previous one). Each page holds at most
/// [cap] items whenever `nPages ≥ ceil(len / cap)`; pages stay non-empty while
/// items remain, and any surplus pages at the end are empty (used when one
/// column of a two-column split is shorter than the other). A single group
/// larger than [cap] is cut across pages — there is no boundary that fits it.
List<List<String>> spreadBulletsOverPages(
  List<String> bullets,
  int nPages,
  int cap,
) {
  final len = bullets.length;
  if (nPages <= 1) return [List<String>.of(bullets)];
  final c = cap < 1 ? 1 : cap;
  final pages = <List<String>>[];
  var start = 0;
  for (var p = 0; p < nPages; p++) {
    final pagesLeft = nPages - p; // deze pagina meegerekend
    if (start >= len) {
      pages.add(const <String>[]);
      continue;
    }
    if (pagesLeft == 1) {
      pages.add(bullets.sublist(start));
      start = len;
      continue;
    }
    final remaining = len - start;
    // Gelijkmatige paginagrootte, naar boven afgerond zodat de eerste pagina's
    // niet leger zijn dan de laatste.
    var at = start + (remaining + pagesLeft - 1) ~/ pagesLeft;
    // Grenzen: deze pagina ≤ cap, en de rest past nog over de overige pagina's
    // (elk ≥ 1). Elk punt hierbinnen behoudt de "geen volle pagina"-garantie.
    final lo = math.max(start + 1, len - (pagesLeft - 1) * c);
    final hi = math.min(math.min(start + c, len - (pagesLeft - 1)), len);
    if (hi < lo) {
      at = start + 1; // te weinig items voor de resterende pagina's: één hier
    } else {
      at = at.clamp(lo, hi);
      at = _snapPageToGroupHeading(bullets, at, lo, hi);
    }
    pages.add(bullets.sublist(start, at));
    start = at;
  }
  return pages;
}

/// Nudge a page boundary [at] onto the nearest group heading within `[lo, hi]`
/// so the heading leads the next page instead of ending the current one. Ties
/// favour the earlier boundary; with no heading in range the boundary is kept.
int _snapPageToGroupHeading(List<String> bullets, int at, int lo, int hi) {
  var best = at;
  var bestDist = 1 << 30;
  for (var i = lo; i <= hi; i++) {
    if (i < bullets.length && isGroupHeading(bullets[i])) {
      final dist = (i - at).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
  }
  return best;
}
