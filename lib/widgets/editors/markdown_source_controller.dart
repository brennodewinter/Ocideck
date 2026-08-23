import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import '../../utils/text_search.dart';

/// Text controller that keeps Markdown as plain text while painting its
/// structure. Styling is a view concern: [text] remains byte-for-byte the
/// author's source and can still be parsed, copied and saved without cleanup.
class MarkdownSourceController extends TextEditingController {
  static final _fence = RegExp(r'^\s*```');
  static final _separator = RegExp(r'^\s*(---|\.\.\.)\s*$');
  static final _heading = RegExp(r'^#{1,6}\s+.*$');
  static final _directive = RegExp(r'<!--.*?-->');
  static final _marker = RegExp(r'^\s*(?:[-*+] |\d+\. |> )');
  static final _inlineCode = RegExp(r'`[^`\n]+`');
  static final _link = RegExp(r'!?\[[^\]\n]*\]\([^\)\n]+\)');
  static final _strong = RegExp(r'\*\*[^*\n]+\*\*|__[^_\n]+__');
  static final _emphasis = RegExp(
    r'(?<!\*)\*[^*\n]+\*(?!\*)|(?<!_)_[^_\n]+_(?!_)',
  );
  static final _property = RegExp(r'^\s*[A-Za-z_][\w-]*\s*:(?=\s|$)');

  List<TextMatchRange> _searchMatches = const [];
  int _activeSearchMatch = -1;
  String? _cachedSource;
  List<_SourceToken> _cachedTokens = const [];

  MarkdownSourceController({super.text});

  void showSearchMatches(List<TextMatchRange> matches, int activeIndex) {
    final indexed = <({TextMatchRange range, int original})>[
      for (var index = 0; index < matches.length; index++)
        (range: matches[index], original: index),
    ]..sort((left, right) => left.range.start.compareTo(right.range.start));
    _searchMatches = List.unmodifiable([
      for (final item in indexed) item.range,
    ]);
    _activeSearchMatch = indexed.indexWhere(
      (item) => item.original == activeIndex,
    );
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = text;
    if (source.isEmpty) return TextSpan(style: style, text: source);
    final tokens = _cachedSource == source
        ? _cachedTokens
        : (_cachedTokens = _tokens(source));
    _cachedSource = source;
    final boundaries = <int>{0, source.length};
    final delimiterMatches = _matchingDelimiters(source);
    for (final token in tokens) {
      boundaries
        ..add(token.start)
        ..add(token.end);
    }
    for (final match in _searchMatches) {
      boundaries
        ..add(match.start.clamp(0, source.length))
        ..add(match.end.clamp(0, source.length));
    }
    for (final match in delimiterMatches) {
      boundaries
        ..add(match.start)
        ..add(match.end);
    }
    final composing = value.composing;
    final paintsComposing =
        withComposing && composing.isValid && !composing.isCollapsed;
    if (paintsComposing) {
      boundaries
        ..add(composing.start.clamp(0, source.length))
        ..add(composing.end.clamp(0, source.length));
    }
    final points = boundaries.toList()..sort();
    final children = <InlineSpan>[];
    var tokenCursor = 0;
    var searchCursor = 0;
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      if (start == end) continue;
      var segmentStyle = style ?? const TextStyle();
      while (tokenCursor < tokens.length && tokens[tokenCursor].end <= start) {
        tokenCursor++;
      }
      for (
        var tokenIndex = tokenCursor;
        tokenIndex < tokens.length;
        tokenIndex++
      ) {
        final token = tokens[tokenIndex];
        if (token.start > start) break;
        if (token.start <= start && token.end >= end) {
          segmentStyle = segmentStyle.merge(token.style);
          break;
        }
      }
      if (delimiterMatches.any(
        (match) => match.start <= start && match.end >= end,
      )) {
        segmentStyle = segmentStyle.copyWith(
          backgroundColor: AppTheme.slate200,
          fontWeight: FontWeight.w700,
        );
      }
      while (searchCursor < _searchMatches.length &&
          _searchMatches[searchCursor].end <= start) {
        searchCursor++;
      }
      for (
        var matchIndex = searchCursor;
        matchIndex < _searchMatches.length;
        matchIndex++
      ) {
        final match = _searchMatches[matchIndex];
        if (match.start > start) break;
        if (match.start <= start && match.end >= end) {
          segmentStyle = segmentStyle.copyWith(
            backgroundColor: matchIndex == _activeSearchMatch
                ? AppTheme.findHighlightActive
                : AppTheme.findHighlight,
          );
          break;
        }
      }
      if (paintsComposing && composing.start <= start && composing.end >= end) {
        segmentStyle = segmentStyle.copyWith(
          decoration: TextDecoration.underline,
        );
      }
      children.add(
        TextSpan(text: source.substring(start, end), style: segmentStyle),
      );
    }
    return TextSpan(style: style, children: children);
  }

  List<TextRange> _matchingDelimiters(String source) {
    final selection = this.selection;
    if (!selection.isValid || !selection.isCollapsed || source.isEmpty) {
      return const [];
    }
    final cursor = selection.extentOffset.clamp(0, source.length);
    var index = cursor < source.length ? cursor : cursor - 1;
    const pairs = {'(': ')', '[': ']', '{': '}'};
    const reverse = {')': '(', ']': '[', '}': '{'};
    if (!pairs.containsKey(source[index]) &&
        !reverse.containsKey(source[index]) &&
        cursor > 0) {
      index = cursor - 1;
    }
    final char = source[index];
    if (pairs.containsKey(char)) {
      final close = pairs[char]!;
      var depth = 0;
      for (var i = index; i < source.length; i++) {
        if (source[i] == char) depth++;
        if (source[i] == close && --depth == 0) {
          return [
            TextRange(start: index, end: index + 1),
            TextRange(start: i, end: i + 1),
          ];
        }
      }
    } else if (reverse.containsKey(char)) {
      final open = reverse[char]!;
      var depth = 0;
      for (var i = index; i >= 0; i--) {
        if (source[i] == char) depth++;
        if (source[i] == open && --depth == 0) {
          return [
            TextRange(start: i, end: i + 1),
            TextRange(start: index, end: index + 1),
          ];
        }
      }
    }
    return const [];
  }

  List<_SourceToken> _tokens(String source) {
    final tokens = <_SourceToken>[];
    var offset = 0;
    var fenced = false;
    for (final line in source.split('\n')) {
      final end = offset + line.length;
      if (_fence.hasMatch(line)) {
        tokens.add(_SourceToken(offset, end, _fenceStyle));
        fenced = !fenced;
      } else if (fenced) {
        tokens.add(_SourceToken(offset, end, _codeStyle));
      } else {
        _addLineTokens(tokens, line, offset);
      }
      offset = end + 1;
    }
    tokens.sort((left, right) {
      final start = left.start.compareTo(right.start);
      return start != 0 ? start : right.end.compareTo(left.end);
    });
    return tokens;
  }

  void _addLineTokens(List<_SourceToken> out, String line, int offset) {
    void add(RegExp expression, TextStyle style) {
      for (final match in expression.allMatches(line)) {
        out.add(_SourceToken(offset + match.start, offset + match.end, style));
      }
    }

    if (_separator.hasMatch(line)) {
      out.add(_SourceToken(offset, offset + line.length, _separatorStyle));
      return;
    }
    add(_heading, _headingStyle);
    add(_directive, _directiveStyle);
    add(_marker, _markerStyle);
    add(_inlineCode, _codeStyle);
    add(_link, _linkStyle);
    add(_strong, _strongStyle);
    add(_emphasis, _emStyle);
    add(_property, _frontMatterKeyStyle);
  }

  static TextStyle get _headingStyle =>
      TextStyle(color: AppTheme.accentFg, fontWeight: FontWeight.w700);
  static TextStyle get _separatorStyle =>
      TextStyle(color: AppTheme.warningFg, fontWeight: FontWeight.w700);
  static TextStyle get _directiveStyle =>
      TextStyle(color: AppTheme.slate500, fontStyle: FontStyle.italic);
  static TextStyle get _markerStyle =>
      TextStyle(color: AppTheme.accentFg, fontWeight: FontWeight.w700);
  static TextStyle get _fenceStyle =>
      TextStyle(color: AppTheme.successFg, fontWeight: FontWeight.w700);
  static TextStyle get _codeStyle => TextStyle(color: AppTheme.successFg);
  static TextStyle get _linkStyle =>
      TextStyle(color: AppTheme.accentFg, decoration: TextDecoration.underline);
  static const _strongStyle = TextStyle(fontWeight: FontWeight.w700);
  static const _emStyle = TextStyle(fontStyle: FontStyle.italic);
  static TextStyle get _frontMatterKeyStyle =>
      TextStyle(color: AppTheme.warningFg, fontWeight: FontWeight.w600);
}

class _SourceToken {
  final int start;
  final int end;
  final TextStyle style;

  const _SourceToken(this.start, this.end, this.style);
}
