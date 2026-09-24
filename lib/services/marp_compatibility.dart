import '../models/markdown_validation.dart';
import '../models/marp_compatibility.dart';
import 'deck_vocabulary.dart';
import 'front_matter_merge.dart';
import 'markdown_front_matter_codec.dart';
import 'markdown_service.dart';
import 'marp_source_preservation.dart';

/// Toetst deck-markdown aan wat Marpit/Marp CLI ermee doet — de andere kant
/// van [MarkdownValidator], die toetst of OciDeck de bron begrijpt.
///
/// Regelgebaseerd, geen renderer: elke regel hieronder staat in de Marpit/Marp
/// documentatie of is gepind aan de echte gepinde Marp CLI in
/// `tool/marp-check/run.sh` (sectie H). Headless — geen Flutter-imports —
/// zodat de markdown-modus, de opslaan-poort en tests dezelfde uitslag delen.
class MarpCompatibility {
  static final _reHtmlComment = RegExp(r'<!--\s*(.*?)\s*-->');
  static final _reDirectiveKey = RegExp(
    r'^(_[A-Za-z][\w-]*|[A-Za-z][\w-]*)\s*:',
  );
  static final _reClassDirective = RegExp(r'<!--\s*_class:\s*([^>]+?)\s*-->');
  static final _reWhitespace = RegExp(r'\s+');
  static final _reFenceOpen = RegExp(r'^\s*(`{3,}|~{3,})([A-Za-z0-9_-]*)\s*$');
  static final _reImage = RegExp(r'!\[[^\]]*\]\(([^)\s]+)');
  static final _reSrcAttr = RegExp(r'''src=["']([^"']+)["']''');
  static final _reVideoAudio = RegExp(r'<(video|audio)\b');
  static final _reTaskItem = RegExp(r'^\s*[-*+]\s+\[[ xX]\]\s');
  static final _reAbsolutePath = RegExp(r'^(/|~/|file://|[A-Za-z]:[\\/])');
  static final _reManualRedaction = RegExp(r'\[\[.+?\]\]');
  static final _reUnclosedYamlQuote = RegExp(r'''^(?:"[^"]*|'[^']*)$''');

  /// Marp CLI leest deze sleutels voor HTML-meta — ze zijn niet "genegeerd".
  static const _marpMetaKeys = {
    'title',
    'author',
    'description',
    'keywords',
    'url',
    'image',
  };

  /// Toets [markdown] aan de Marp-regels.
  ///
  /// [deckScope] = de hele presentatie (front matter meenemen); `false` voor
  /// de per-slide buffer in markdown-modus, die geen front matter draagt.
  /// [context] bepaalt of thema- en mediapaden naast het bestand mogen
  /// verondersteld worden.
  MarpCompatReport check(
    String markdown, {
    MarpCompatContext context = MarpCompatContext.project,
    bool deckScope = true,
  }) {
    // Zelfde normalisatie als parser en validator, zodat de drie het eens
    // zijn over regelgrenzen.
    markdown = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final findings = <MarkdownValidationIssue>[];
    var deckTlp = 'none';

    var body = markdown;
    var bodyStartLine = 1;

    if (deckScope) {
      final lines = markdown.split('\n');
      if (lines.isEmpty || lines.first != '---') {
        findings.add(
          _finding(
            line: 1,
            severity: MarkdownValidationSeverity.error,
            code: 'marp.frontMatter',
          ),
        );
      } else {
        final closeIndex = _frontMatterClose(lines);
        if (closeIndex == -1) {
          findings.add(
            _finding(
              line: 1,
              severity: MarkdownValidationSeverity.error,
              code: 'marp.frontMatter',
            ),
          );
          // Het hele document geldt dan als inhoud: de `---`-regels leest de
          // body-check als scheidingen, net als Marp dat zou doen.
        } else {
          deckTlp = _checkFrontMatter(lines, closeIndex, context, findings);
          body = lines.sublist(closeIndex + 1).join('\n');
          bodyStartLine = closeIndex + 2;
        }
      }
    }

    _checkBody(body, bodyStartLine, context, deckTlp, findings);
    findings.sort((a, b) => a.line.compareTo(b.line));

    final status =
        findings.any((f) => f.severity == MarkdownValidationSeverity.error)
        ? MarpCompatStatus.incompatible
        : findings.any((f) => f.severity == MarkdownValidationSeverity.warning)
        ? MarpCompatStatus.degraded
        : MarpCompatStatus.compatible;
    return MarpCompatReport(status: status, findings: findings);
  }

  int _frontMatterClose(List<String> lines) {
    for (var i = 1; i < lines.length; i++) {
      if (lines[i] == '---') return i;
    }
    return -1;
  }

  /// Toetst de front matter en geeft het deckbrede TLP-niveau terug.
  String _checkFrontMatter(
    List<String> lines,
    int closeIndex,
    MarpCompatContext context,
    List<MarkdownValidationIssue> findings,
  ) {
    var marpKey = false;
    var deckTlp = 'none';
    var hasCallouts = false;
    final seenKeys = <String>{};
    final ignoredKeys = <String>[];
    var firstIgnoredLine = 1;

    for (var i = 1; i < closeIndex; i++) {
      final line = lines[i];
      if (isFrontMatterContinuation(line)) continue;
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      if (line.contains('\t')) {
        findings.add(
          _finding(
            line: i + 1,
            severity: MarkdownValidationSeverity.error,
            code: 'marp.yaml',
          ),
        );
        continue;
      }

      final key = frontMatterKeyOf(line);
      if (key == null) {
        if (trimmed.contains(':')) {
          findings.add(
            _finding(
              line: i + 1,
              severity: MarkdownValidationSeverity.warning,
              code: 'marp.yaml',
            ),
          );
        }
        continue;
      }
      if (!seenKeys.add(key)) {
        findings.add(
          _finding(
            line: i + 1,
            severity: MarkdownValidationSeverity.error,
            code: 'marp.yaml',
          ),
        );
        continue;
      }

      final value = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      _checkYamlValue(value, i + 1, findings);

      switch (key) {
        case 'marp':
          marpKey = true;
          if (value != 'true') {
            findings.add(
              _finding(
                line: i + 1,
                severity: MarkdownValidationSeverity.error,
                code: 'marp.frontMatter',
              ),
            );
          }
        case 'theme':
          final theme = parseMarkdownYamlScalar(value);
          if (!kMarpBuiltinThemes.contains(theme) &&
              context == MarpCompatContext.bareFile) {
            findings.add(
              _finding(
                line: i + 1,
                severity: MarkdownValidationSeverity.warning,
                code: 'marp.theme',
              ),
            );
          }
        case 'headingDivider':
          findings.add(
            _finding(
              line: i + 1,
              severity: MarkdownValidationSeverity.warning,
              code: 'marp.layout',
            ),
          );
        case 'size':
          final size = parseMarkdownYamlScalar(value);
          if (size != '16:9' && size != '4:3') {
            findings.add(
              _finding(
                line: i + 1,
                severity: MarkdownValidationSeverity.warning,
                code: 'marp.layout',
              ),
            );
          }
        case 'tlp':
          deckTlp = parseMarkdownYamlScalar(value).toLowerCase();
        case 'privacy':
          if (parseMarkdownYamlScalar(value).toLowerCase() == 'redact') {
            findings.add(
              _finding(
                line: i + 1,
                severity: MarkdownValidationSeverity.error,
                code: 'marp.privacy',
              ),
            );
          }
        case 'ocideck_callouts':
          hasCallouts = true;
        default:
          // Sleutels die Marp niet kent doen daar niets; het bijbehorende
          // gedrag (timing, tlp, metadata) vervalt. Samengevoegd tot één
          // info-bevinding zodat de lijst niet volstaat met ruis.
          if (!kMarpitDirectiveNames.contains(key) &&
              !_marpMetaKeys.contains(key)) {
            ignoredKeys.add(key);
            if (ignoredKeys.length == 1) firstIgnoredLine = i + 1;
          }
      }
    }

    _addFrontMatterSummaries(
      findings,
      hasMarpKey: marpKey,
      hasCallouts: hasCallouts,
      ignoredKeys: ignoredKeys,
      firstIgnoredLine: firstIgnoredLine,
    );
    return deckTlp;
  }

  void _addFrontMatterSummaries(
    List<MarkdownValidationIssue> findings, {
    required bool hasMarpKey,
    required bool hasCallouts,
    required List<String> ignoredKeys,
    required int firstIgnoredLine,
  }) {
    if (!hasMarpKey) {
      findings.add(
        _finding(
          line: 1,
          severity: MarkdownValidationSeverity.error,
          code: 'marp.frontMatter',
        ),
      );
    }
    if (hasCallouts) {
      findings.add(
        _finding(
          line: 1,
          severity: MarkdownValidationSeverity.warning,
          code: 'marp.ocideckFeature',
        ),
      );
    }
    if (ignoredKeys.isNotEmpty) {
      findings.add(
        _finding(
          line: firstIgnoredLine,
          severity: MarkdownValidationSeverity.informational,
          code: 'marp.ocideckFeature',
        ),
      );
    }
  }

  /// Scalar-niveau YAML-toetsen waar js-yaml (en dus marp-cli) op faalt.
  /// Bewust geen volledige YAML-parser — `package:yaml` is een dev-dependency.
  void _checkYamlValue(
    String value,
    int line,
    List<MarkdownValidationIssue> findings,
  ) {
    if (value.isEmpty) return;
    if (value.startsWith('*') || value.startsWith('&')) {
      findings.add(
        _finding(
          line: line,
          severity: MarkdownValidationSeverity.error,
          code: 'marp.yaml',
        ),
      );
      return;
    }
    if (_reUnclosedYamlQuote.hasMatch(value)) {
      findings.add(
        _finding(
          line: line,
          severity: MarkdownValidationSeverity.error,
          code: 'marp.yaml',
        ),
      );
    }
  }

  void _checkBody(
    String body,
    int bodyStartLine,
    MarpCompatContext context,
    String deckTlp,
    List<MarkdownValidationIssue> findings,
  ) {
    final blocks = MarkdownService.splitSlideBlocks(body);
    var blockStartLine = bodyStartLine;

    // Gegroepeerde info-bevindingen: één regel per categorie, op de eerste
    // plek waar die voorkomt.
    var ocideckCommentCount = 0;
    var firstOcideckCommentLine = 0;
    var videoAudioCount = 0;
    var firstVideoAudioLine = 0;
    var taskItemCount = 0;
    var firstTaskItemLine = 0;
    final unknownDirectives = <String>{};
    var firstUnknownDirectiveLine = 0;

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final blockLines = block.split('\n');
      int lineNo(int index) => blockStartLine + index;
      final fenced = _fencedLineIndexes(blockLines);

      // _class-tokens die buiten OciDeck niets betekenen.
      final classMatch = _reClassDirective.firstMatch(block);
      if (classMatch != null) {
        final tokens = (classMatch.group(1) ?? '')
            .split(_reWhitespace)
            .where((t) => t.isNotEmpty)
            .toList();
        final ocideckOnly = tokens
            .where(kOciDeckOnlyClassTokens.contains)
            .toList();
        if (ocideckOnly.isNotEmpty) {
          final classLine = blockLines.indexWhere(
            (l) => l.contains('<!-- _class:'),
          );
          findings.add(
            _finding(
              line: lineNo(classLine >= 0 ? classLine : 0),
              severity: MarkdownValidationSeverity.warning,
              code: 'marp.ocideckFeature',
            ),
          );
        }
      }

      for (var j = 0; j < blockLines.length; j++) {
        final trimmed = blockLines[j].trim();

        // OciDeck-fences renderen bij Marp als letterlijk codeblok.
        final fenceMatch = _reFenceOpen.firstMatch(trimmed);
        if (fenceMatch != null && !fenced.contains(j)) {
          final info = fenceMatch.group(2) ?? '';
          if (kOciDeckFenceTypes.contains(info)) {
            findings.add(
              _finding(
                line: lineNo(j),
                severity: MarkdownValidationSeverity.warning,
                code: 'marp.ocideckFeature',
              ),
            );
          }
        }
        if (fenced.contains(j)) continue;

        if (_reManualRedaction.hasMatch(trimmed)) {
          findings.add(
            _finding(
              line: lineNo(j),
              severity: MarkdownValidationSeverity.error,
              code: 'marp.privacy',
            ),
          );
        }

        if (_reTaskItem.hasMatch(trimmed)) {
          taskItemCount++;
          if (taskItemCount == 1) firstTaskItemLine = lineNo(j);
        }
        if (_reVideoAudio.hasMatch(trimmed)) {
          videoAudioCount++;
          if (videoAudioCount == 1) firstVideoAudioLine = lineNo(j);
        }
        for (final match in _reImage.allMatches(trimmed)) {
          _checkMediaUri(match.group(1)!, lineNo(j), context, findings);
        }
        for (final match in _reSrcAttr.allMatches(trimmed)) {
          _checkMediaUri(match.group(1)!, lineNo(j), context, findings);
        }

        for (final match in _reHtmlComment.allMatches(trimmed)) {
          final content = match.group(1)!;
          if (content.contains('\n')) continue; // notitieblok, geen directive
          _checkComment(
            content,
            lineNo(j),
            deckTlp,
            findings,
            onOcideckComment: () {
              ocideckCommentCount++;
              if (ocideckCommentCount == 1) {
                firstOcideckCommentLine = lineNo(j);
              }
            },
            onUnknownDirective: (key) {
              if (unknownDirectives.add(key) && unknownDirectives.length == 1) {
                firstUnknownDirectiveLine = lineNo(j);
              }
            },
          );
        }
      }

      blockStartLine += blockLines.length + 1;
    }

    // `---` direct onder tekst: OciDeck splitst altijd, Marp leest het
    // mogelijk als setext-kop. Staat los van de blok-loop omdat de grens
    // zélf de bevinding is.
    _checkSetextSeparators(body, bodyStartLine, findings);

    _addBodySummaries(
      findings,
      ocideckCommentCount: ocideckCommentCount,
      firstOcideckCommentLine: firstOcideckCommentLine,
      unknownDirectives: unknownDirectives,
      firstUnknownDirectiveLine: firstUnknownDirectiveLine,
      videoAudioCount: videoAudioCount,
      firstVideoAudioLine: firstVideoAudioLine,
      taskItemCount: taskItemCount,
      firstTaskItemLine: firstTaskItemLine,
    );
  }

  void _addBodySummaries(
    List<MarkdownValidationIssue> findings, {
    required int ocideckCommentCount,
    required int firstOcideckCommentLine,
    required Set<String> unknownDirectives,
    required int firstUnknownDirectiveLine,
    required int videoAudioCount,
    required int firstVideoAudioLine,
    required int taskItemCount,
    required int firstTaskItemLine,
  }) {
    if (ocideckCommentCount > 0) {
      findings.add(
        _finding(
          line: firstOcideckCommentLine,
          severity: MarkdownValidationSeverity.informational,
          code: 'marp.ocideckFeature',
        ),
      );
    }
    if (unknownDirectives.isNotEmpty) {
      findings.add(
        _finding(
          line: firstUnknownDirectiveLine,
          severity: MarkdownValidationSeverity.informational,
          code: 'marp.ocideckFeature',
        ),
      );
    }
    if (videoAudioCount > 0) {
      findings.add(
        _finding(
          line: firstVideoAudioLine,
          severity: MarkdownValidationSeverity.informational,
          code: 'marp.ocideckFeature',
        ),
      );
    }
    if (taskItemCount > 0) {
      findings.add(
        _finding(
          line: firstTaskItemLine,
          severity: MarkdownValidationSeverity.informational,
          code: 'marp.ocideckFeature',
        ),
      );
    }
  }

  /// Comment-directives op een slide. Marpit-richtlijnen (`footer:`,
  /// `_paginate:`) doen bij Marp wél iets — geen bevinding. OciDeck-semantiek
  /// (skip, tlp) is een warning; het overige OciDeck- en onbekende spul gaat
  /// gegroepeerd als info.
  void _checkComment(
    String content,
    int line,
    String deckTlp,
    List<MarkdownValidationIssue> findings, {
    required void Function() onOcideckComment,
    required void Function(String key) onUnknownDirective,
  }) {
    if (content == 'skip') {
      findings.add(
        _finding(
          line: line,
          severity: MarkdownValidationSeverity.warning,
          code: 'marp.skip',
        ),
      );
      return;
    }
    if (content.startsWith('tlp:')) {
      final slideTlp = content.substring('tlp:'.length).trim().toLowerCase();
      final withheld = _tlpRank(slideTlp) > _tlpRank(deckTlp);
      findings.add(
        _finding(
          line: line,
          severity: withheld
              ? MarkdownValidationSeverity.error
              : MarkdownValidationSeverity.warning,
          code: withheld ? 'marp.tlpExposure' : 'marp.ocideckFeature',
        ),
      );
      return;
    }
    if (content.startsWith('ocideck_privacy:') &&
        content.substring('ocideck_privacy:'.length).trim().toLowerCase() ==
            'redact') {
      findings.add(
        _finding(
          line: line,
          severity: MarkdownValidationSeverity.error,
          code: 'marp.privacy',
        ),
      );
      return;
    }
    if (marpitDirectiveKey(content) != null) return; // Marp's eigen directive
    final keyMatch = _reDirectiveKey.firstMatch(content);
    if (keyMatch == null) {
      // Kale tokens zonder `key:`-vorm (zoals `<!-- ocideck_detail -->`).
      if (content.startsWith('ocideck_')) onOcideckComment();
      return;
    }
    final key = keyMatch.group(1)!;
    if (key.startsWith('_')) {
      // Spot-vorm van een Marpit-richtlijn (`_paginate:`, `_footer:`):
      // Marp past die op deze dia toe.
      if (kMarpitDirectiveNames.contains(key.substring(1))) return;
      onUnknownDirective(key);
      return;
    }
    if (key == 'advance' || key.startsWith('ocideck_')) {
      onOcideckComment();
      return;
    }
    onUnknownDirective(key);
  }

  void _checkMediaUri(
    String uri,
    int line,
    MarpCompatContext context,
    List<MarkdownValidationIssue> findings,
  ) {
    if (uri.startsWith('mem:')) {
      if (context == MarpCompatContext.bareFile) {
        findings.add(
          _finding(
            line: line,
            severity: MarkdownValidationSeverity.warning,
            code: 'marp.media',
          ),
        );
      }
      return;
    }
    if (_reAbsolutePath.hasMatch(uri)) {
      findings.add(
        _finding(
          line: line,
          severity: MarkdownValidationSeverity.warning,
          code: 'marp.media',
        ),
      );
    }
  }

  /// Indexes van regels strikt binnen een fenced blok — hun inhoud is
  /// verbatim, dus commentaren en media daarin zijn voorbeelden.
  Set<int> _fencedLineIndexes(List<String> lines) {
    final inside = <int>{};
    String? fenceChar;
    var fenceLength = 0;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (fenceChar == null) {
        if (trimmed.startsWith('```')) {
          fenceChar = '`';
          fenceLength = _fenceRunLength(trimmed, '`');
        } else if (trimmed.startsWith('~~~')) {
          fenceChar = '~';
          fenceLength = _fenceRunLength(trimmed, '~');
        }
      } else if (MarkdownService.isBareFence(trimmed, fenceChar) &&
          _fenceRunLength(trimmed, fenceChar) >= fenceLength) {
        fenceChar = null;
        fenceLength = 0;
      } else {
        inside.add(i);
      }
    }
    return inside;
  }

  /// Marp leest `---` direct onder een tekstregel mogelijk als setext-kop
  /// (H2) in plaats van slide-scheiding; OciDeck splitst er altijd. Gepind
  /// aan echte Marp in `tool/marp-check` sectie H.
  void _checkSetextSeparators(
    String body,
    int bodyStartLine,
    List<MarkdownValidationIssue> findings,
  ) {
    final lines = body.split('\n');
    String? fenceChar;
    var fenceLength = 0;
    var previousTextLine = false;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (fenceChar == null) {
        if (lines[i] == '---' && previousTextLine) {
          findings.add(
            _finding(
              line: bodyStartLine + i,
              severity: MarkdownValidationSeverity.warning,
              code: 'marp.layout',
            ),
          );
          previousTextLine = false;
          continue;
        }
        if (trimmed.startsWith('```')) {
          fenceChar = '`';
          fenceLength = _fenceRunLength(trimmed, '`');
        } else if (trimmed.startsWith('~~~')) {
          fenceChar = '~';
          fenceLength = _fenceRunLength(trimmed, '~');
        }
      } else if (MarkdownService.isBareFence(trimmed, fenceChar) &&
          _fenceRunLength(trimmed, fenceChar) >= fenceLength) {
        fenceChar = null;
        fenceLength = 0;
      }
      previousTextLine = fenceChar == null && _isParagraphLine(lines[i]);
    }
  }

  /// Alleen boven een gewone alinea is `---` dubbelzinnig (setext H2). Boven
  /// koppen, HTML/commentaar, lijsten, quotes en tabelrijen is de streep
  /// ook voor Marp gewoon een scheiding.
  static final _reBlockStart = RegExp(r'^\s*(<|#|>|-|\+|\*|\||\d+[.)]\s)');
  bool _isParagraphLine(String line) {
    final trimmed = line.trim();
    return trimmed.isNotEmpty &&
        trimmed != '---' &&
        !_reBlockStart.hasMatch(line);
  }

  int _fenceRunLength(String line, String fenceChar) {
    var length = 0;
    while (length < line.length && line[length] == fenceChar) {
      length++;
    }
    return length;
  }

  int _tlpRank(String value) => switch (value) {
    'clear' => 1,
    'green' => 2,
    'amber' => 3,
    'amber+strict' => 4,
    'red' => 5,
    _ => 0,
  };

  MarkdownValidationIssue _finding({
    required int line,
    required MarkdownValidationSeverity severity,
    required String code,
  }) => MarkdownValidationIssue(line: line, severity: severity, code: code);
}
