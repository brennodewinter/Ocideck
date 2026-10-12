/// What category of dangerous, *executable* content was spotted in an imported
/// deck. A presentation file is meant to be pure data; anything that could run
/// code (in a browser when the deck is later exported to HTML, or in any other
/// viewer) has no business being there. The UI maps these to localized labels.
enum MarkdownThreat {
  /// `<script>`, inline `on…=` event handlers, `javascript:`/`vbscript:` URLs,
  /// or the `<foreignObject>` SVG scripting vector.
  scriptExecution,

  /// `<iframe>`, `<object>`, `<embed>`, `<applet>` — pulls in / runs foreign
  /// content.
  embeddedContent,

  /// `data:text/html` payloads, `<meta http-equiv>` redirects, `<base>` tag
  /// hijacks — URLs/tags that can smuggle executable content or rewrite links.
  unsafeUrl,
}

/// A single hit from [MarkdownSafetyScanner.scan].
class MarkdownSafetyFinding {
  final MarkdownThreat kind;

  /// 1-based line number in the source markdown where the match starts.
  final int line;

  /// The offending fragment, whitespace-collapsed and truncated, shown verbatim
  /// to the user so they can see exactly what tripped the alarm.
  final String evidence;

  const MarkdownSafetyFinding({
    required this.kind,
    required this.line,
    required this.evidence,
  });
}

class _Rule {
  final MarkdownThreat kind;
  final RegExp pattern;
  const _Rule(this.kind, this.pattern);
}

/// Fail-closed gate run on EVERY imported/opened `.md` before it is accepted.
///
/// A deck the app itself produced is plain data and never trips these rules; a
/// foreign deck carrying anything executable is refused at the door. This is a
/// front-line layer on top of the existing export-time defences (DOMPurify +
/// CSP in the HTML export, `sanitizeMermaidSvg` at render time): the safest
/// thing is to never let executable content in at all.
class MarkdownSafetyScanner {
  MarkdownSafetyScanner._();

  static final List<_Rule> _rules = [
    // ── Script execution ────────────────────────────────────────────────────
    _Rule(
      MarkdownThreat.scriptExecution,
      RegExp(r'<\s*script\b', caseSensitive: false),
    ),
    _Rule(
      MarkdownThreat.scriptExecution,
      RegExp(r'<\s*foreignObject\b', caseSensitive: false),
    ),
    // An inline event handler attribute inside a tag: `<img … onerror=…>`.
    _Rule(
      MarkdownThreat.scriptExecution,
      RegExp(r'<[a-z][^>\n]*[\s/]on[a-z]+\s*=', caseSensitive: false),
    ),
    // `javascript:` / `vbscript:` in a markdown link target or an attribute…
    _Rule(
      MarkdownThreat.scriptExecution,
      RegExp(
        r'''(?:\]\(\s*|=\s*["']?\s*)(?:javascript|vbscript)\s*:''',
        caseSensitive: false,
      ),
    ),
    // …or as an autolink `<javascript:…>`.
    _Rule(
      MarkdownThreat.scriptExecution,
      RegExp(r'<\s*(?:javascript|vbscript)\s*:', caseSensitive: false),
    ),

    // ── Embedded / foreign content ──────────────────────────────────────────
    _Rule(
      MarkdownThreat.embeddedContent,
      RegExp(r'<\s*(?:iframe|object|embed|applet)\b', caseSensitive: false),
    ),

    // ── Unsafe URLs / tags ──────────────────────────────────────────────────
    _Rule(
      MarkdownThreat.unsafeUrl,
      RegExp(
        r'''(?:\]\(\s*|=\s*["']?\s*)data\s*:\s*text/html''',
        caseSensitive: false,
      ),
    ),
    _Rule(
      MarkdownThreat.unsafeUrl,
      RegExp(r'<\s*data\s*:\s*text/html', caseSensitive: false),
    ),
    _Rule(
      MarkdownThreat.unsafeUrl,
      RegExp(r'<\s*meta\b[^>\n]*http-equiv', caseSensitive: false),
    ),
    _Rule(
      MarkdownThreat.unsafeUrl,
      RegExp(r'<\s*base\b', caseSensitive: false),
    ),
  ];

  /// Return every executable-content hit in [markdown], sorted by line. An empty
  /// list means the deck is data-only and safe to open.
  ///
  /// The text is scanned as-is and again after decoding numeric HTML entities
  /// and stripping invisible characters, so entity- and zero-width-encoded
  /// evasions are caught too.
  static List<MarkdownSafetyFinding> scan(String markdown) {
    if (markdown.isEmpty) return const [];
    final findings = <MarkdownSafetyFinding>[];
    final seen = <String>{};

    void run(String text) {
      final newlinePositions = _newlinePositions(text);
      final tagEnds = _tagEnds(text);
      for (final rule in _rules) {
        for (final m in rule.pattern.allMatches(text)) {
          // OciDeck serialises YouTube/Vimeo video slides as
          // `<iframe class="ocideck-embed" … src="https://…/embed/…">`. That is
          // the app's own, host-restricted output, so re-opening a deck the app
          // just saved must not fail the gate. Any *other* danger inside the
          // same tag (an `on…=` handler, a `javascript:` src) is still caught by
          // its own rule or rejected by the whitelist, so this exception is safe.
          if (rule.kind == MarkdownThreat.embeddedContent &&
              _isSafeOcideckEmbed(text, m.start, tagEnds)) {
            continue;
          }
          final line = _lineAt(m.start, newlinePositions);
          final evidence = _snippet(text, m.start, newlinePositions);
          // Dedup on (kind, line, evidence) so the raw and normalized passes
          // don't double-report the same spot.
          if (seen.add('${rule.kind.name}|$line|$evidence')) {
            findings.add(
              MarkdownSafetyFinding(
                kind: rule.kind,
                line: line,
                evidence: evidence,
              ),
            );
          }
        }
      }
    }

    run(markdown);
    // Entity decoding and invisible-char stripping never add/remove newlines, so
    // line numbers stay aligned with the original text.
    final normalized = _stripInvisible(_decodeNumericEntities(markdown));
    if (normalized != markdown) run(normalized);

    findings.sort((a, b) => a.line.compareTo(b.line));
    return findings;
  }

  /// Convenience: true when [markdown] carries no executable content.
  static bool isSafe(String markdown) => scan(markdown).isEmpty;

  /// The embed hosts [VideoSource.embedUri] can produce. Kept in sync with
  /// `video_source.dart`; a mismatch only means an embed is (safely) refused.
  static final RegExp _safeEmbedSrc = RegExp(
    r'''src\s*=\s*"https://(?:www\.youtube-nocookie\.com/embed/|player\.vimeo\.com/video/)''',
    caseSensitive: false,
  );

  /// True when the `<iframe>` starting at [tagStart] is OciDeck's own
  /// `class="ocideck-embed"` video embed pointing at an allowed host. Only the
  /// tag itself (up to the first `>`) is inspected.
  static bool _isSafeOcideckEmbed(
    String text,
    int tagStart,
    Map<int, int> tagEnds,
  ) {
    final end = tagEnds[tagStart];
    if (end == null) return false;
    // shortcut: 8192-byte tag cap, increase only if generated embeds require larger tags.
    if (end - tagStart > 8192) return false;
    final tag = text.substring(tagStart, end);
    if (!RegExp(r'<\s*iframe\b', caseSensitive: false).hasMatch(tag)) {
      return false; // object/embed/applet are never whitelisted
    }
    if (!tag.contains('class="ocideck-embed"')) return false;
    if (RegExp(r'[\s/]on[a-z]+\s*=', caseSensitive: false).hasMatch(tag)) {
      return false;
    }
    return _safeEmbedSrc.hasMatch(tag);
  }

  static List<int> _positionsOf(String text, int codeUnit) {
    final positions = <int>[];
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == codeUnit) positions.add(i);
    }
    return positions;
  }

  static List<int> _newlinePositions(String text) => _positionsOf(text, 0x0A);

  static Map<int, int> _tagEnds(String text) {
    final ends = <int, int>{};
    int? start;
    int? quote;
    var malformed = false;
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (start == null) {
        if (code == 0x3C) start = i;
        continue;
      }
      if (quote != null) {
        if (code == quote) {
          quote = null;
        } else if (code == 0x3E) {
          malformed = true;
        }
      } else if (code == 0x22 || code == 0x27) {
        quote = code;
      } else if (code == 0x3E) {
        if (!malformed) ends[start] = i;
        start = null;
        quote = null;
        malformed = false;
      }
    }
    return ends;
  }

  static int? _nextPosition(List<int> positions, int index) {
    var low = 0;
    var high = positions.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (positions[middle] < index) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low < positions.length ? positions[low] : null;
  }

  static int _lineAt(int index, List<int> newlinePositions) {
    var low = 0;
    var high = newlinePositions.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (newlinePositions[middle] < index) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low + 1;
  }

  static String _snippet(String text, int start, List<int> newlinePositions) {
    var end = start + 80;
    if (end > text.length) end = text.length;
    final nl = _nextPosition(newlinePositions, start);
    if (nl != null && nl < end) end = nl;
    var s = text.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
    final truncated = end < text.length && (nl == null || nl > end);
    if (truncated) s = '$s…';
    return s;
  }

  static final RegExp _numEntity = RegExp(r'&#(x?)([0-9a-fA-F]+);');

  static String _decodeNumericEntities(String s) {
    if (!s.contains('&#')) return s;
    return s.replaceAllMapped(_numEntity, (m) {
      final hex = m.group(1)!.isNotEmpty;
      final code = int.tryParse(m.group(2)!, radix: hex ? 16 : 10);
      if (code == null || code < 0 || code > 0x10FFFF) return m.group(0)!;
      // Keep source line boundaries aligned between the raw and normalized pass.
      if (code == 0x0A || code == 0x0D) return m.group(0)!;
      try {
        return String.fromCharCode(code);
      } on ArgumentError {
        // [code] is already range-checked above; this is purely defensive
        // against any remaining unrepresentable scalar.
        return m.group(0)!;
      }
    });
  }

  // NUL plus zero-width chars (U+200B..U+200D, U+FEFF) used to split tokens
  // like `java<ZWSP>script:`.
  static final RegExp _invisible = RegExp('[\u0000\u200B\u200C\u200D\uFEFF]');

  static String _stripInvisible(String s) => s.replaceAll(_invisible, '');
}
