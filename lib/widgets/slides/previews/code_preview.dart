// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Een 'broncode-sheet': de code op een donker editor-vlak, met
/// syntaxkleuring wanneer een taal bekend is. De tekst blijft platte tekst maar
/// wordt monospace en gekleurd weergegeven. Past zich met een FittedBox aan de
/// slide aan zodat lange fragmenten netjes verkleinen i.p.v. af te kappen.
class _CodePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _CodePreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  /// Meetresultaten per (tekst, stijl): de meting draait in de LayoutBuilder
  /// en dus bij elke layout-pass; TextPainter.layout over een heel codeblok
  /// kost al snel milliseconden per frame bij resizen of scrollen.
  static final _measureCache = LruCache<String, Size>(64);

  /// Natural (unwrapped) size of [text] in [style]: width is the longest line,
  /// height the full block. Used to scale code to the available space.
  static Size _measureMono(String text, TextStyle style) {
    final key = '${style.fontSize}|${style.fontFamily}|$text';
    final cached = _measureCache[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(text: text.isEmpty ? ' ' : text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return _measureCache[key] = painter.size;
  }

  @override
  Widget build(BuildContext context) {
    _ensureHighlightLanguages();
    final pad = w * 0.05;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final topPad = safe.top > 0 ? pad + safe.top : pad;
    final bottomPad = _logoAwareBottomPadding(pad, safe.bottom);
    final code = slide.customMarkdown;
    final lang = slide.codeLanguage.trim();
    final known = lang.isNotEmpty && allLanguages.containsKey(lang);

    final codeBg = _hexColor(profile.codeBackgroundColor);
    final codeFg = _hexColor(profile.codeTextColor);

    // The chosen monospace family, always backed by a generic monospace fallback
    // so an uninstalled face still renders fixed-width.
    final fallback = <String>['Menlo', 'Consolas', 'Courier New', 'monospace']
      ..removeWhere((f) => f == profile.codeFontFamily);
    final baseFont = w * 0.024;
    final maxFont = w * 0.040; // grow to fill, but never huge
    TextStyle monoAt(double size) => TextStyle(
      fontFamily: profile.codeFontFamily,
      fontFamilyFallback: fallback,
      fontSize: size,
      height: 1.4,
      color: codeFg,
    );

    // HighlightView throws on an unknown language, so fall back to plain (but
    // monospace) text. When syntax highlighting is off we always render plain
    // text so the whole block is one colour — needed for a CRT-green screen.
    final useHighlight = known && profile.codeHighlightSyntax;
    final highlightTheme = {
      ...atomOneDarkTheme,
      // Keep atom-one-dark's per-token colours but drop its own background so
      // our themed [codeBg] shows through unchanged.
      'root': (atomOneDarkTheme['root'] ?? const TextStyle()).copyWith(
        backgroundColor: codeBg,
        color: codeFg,
      ),
    };
    Widget buildCode(TextStyle style) => useHighlight
        ? HighlightView(
            code,
            language: lang,
            theme: highlightTheme,
            padding: EdgeInsets.zero,
            textStyle: style,
          )
        : Text(code, style: style);

    return Container(
      color: _hexColor(profile.slideBackgroundColor),
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, topPad, pad, bottomPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The slide title belongs to the slide, not inside the code window.
            if (slide.title.isNotEmpty) ...[
              _md(
                context,
                slide.title,
                _applyFont(
                  font,
                  TextStyle(
                    fontSize: w * 0.042,
                    fontWeight: FontWeight.bold,
                    color: _hexColor(profile.textColor),
                  ),
                ),
                linkColor: _hexColor(profile.accentColor),
              ),
              SizedBox(height: pad * 0.35),
            ],
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: codeBg,
                  borderRadius: BorderRadius.circular(w * 0.012),
                  border: Border.all(color: codeFg.withValues(alpha: 0.22)),
                ),
                padding: EdgeInsets.all(w * 0.03),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Size the code to fill the panel: scale up to use spare
                    // space (capped at [maxFont]) and down so long fragments
                    // still fit, rather than leaving a small block in a big box.
                    final measured = useHighlight
                        ? code.replaceAll('\t', '        ')
                        : code;
                    final natural = _measureMono(measured, monoAt(baseFont));
                    final availW = math.max(1.0, constraints.maxWidth - 1);
                    final availH = math.max(1.0, constraints.maxHeight - 1);
                    var scale = math.min(
                      availW / natural.width,
                      availH / natural.height,
                    );
                    if (!scale.isFinite || scale <= 0) scale = 1;
                    final size = math.min(baseFont * scale, maxFont);
                    return Align(
                      alignment: Alignment.topLeft,
                      child: buildCode(monoAt(size)),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Register highlight.js language definitions once, so [HighlightView] can
/// colour any common language without throwing.
bool _highlightReady = false;

void _ensureHighlightLanguages() {
  if (_highlightReady) return;
  allLanguages.forEach(highlight.registerLanguage);
  _highlightReady = true;
}

// ── Shared helper ─────────────────────────────────────────────────────────────
