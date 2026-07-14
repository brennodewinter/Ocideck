import 'dart:convert';

import '../models/deck.dart';
import '../models/markdown_validation.dart';
import 'markdown_service.dart';
import '../utils/log.dart';

/// Validates deck markdown against what [MarkdownService] can parse reliably.
class MarkdownValidator {
  // Hoisted regexes: de validator draait per validatiepass over elke regel van
  // elk slide-blok; inline `RegExp(...)` hercompileerde dezelfde patronen
  // honderden keren per pass.
  static final _reHtmlCommentMultiline = RegExp(r'<!--([\s\S]*?)-->');
  static final _reInlineComment = RegExp(r'<!--.*?-->');
  // A comment that opens with `_key:` or `ocideck_key:` is clearly an attempted
  // directive (prose speaker notes never start that way), so an unknown one is
  // worth flagging rather than silently dropping.
  static final _reDirectiveKey = RegExp(
    r'^(_[A-Za-z][\w-]*|ocideck_[A-Za-z0-9_-]+)\s*:',
  );
  static final _reFence = RegExp(r'^\s*```');
  static final _reClassDirective = RegExp(r'<!--\s*_class:\s*([^>]+?)\s*-->');
  static final _reClassOpen = RegExp(r'<!--\s*_class:');
  static final _reWhitespace = RegExp(r'\s+');
  static final _reUnclosedImage = RegExp(r'!\[[^\]]*\]\([^)]*$');
  static final _reVideoSrc = RegExp(r'src="([^"]+)"');
  static final _reChartFenceLoose = RegExp(r'^\s*```chart\s*$');
  static final _reChartFence = RegExp(r'^```chart\s*$');
  static final _reCockpitFenceLoose = RegExp(r'^\s*```cockpit\s*$');
  static final _reCockpitFence = RegExp(r'^```cockpit\s*$');
  static final _reFenceClose = RegExp(r'^```\s*$');
  static final _reLeadingPipe = RegExp(r'^\|');
  static final _reTrailingPipe = RegExp(r'\|$');
  static final _reSeparatorCell = RegExp(r'^:?-+:?$');
  static final _reDivOpen = RegExp(r'<div\b');
  static final _reDivClose = RegExp(r'</div>');

  static const _knownClassTokens = {
    'title',
    'section',
    'two-bullets',
    'split',
    'quote',
    'video',
    'table',
    'code',
    'chart',
    'cockpit',
    'question',
    'timeline',
    'finding',
    'findings-summary',
    'checklist',
    'scope-matrix',
    'sign-off',
    'timeline-horizontal',
    'timeline-vertical',
    'timeline-steps',
    'timeline-static',
    'logo-safe',
    'no-logo',
    'no-footer',
    'table-editable',
  };

  static const _validListStyles = {
    'bullets',
    'numbered',
    'checklist',
    'richText',
  };

  // Front-matter keys MarkdownService._doParse actually reads. `marp` is the
  // canonical Marp marker OciDeck assumes and deliberately ignores. Anything
  // else (a typo, or a Marp option OciDeck does not implement like `header`,
  // `footer`, `size`, `style`) is silently dropped by the parser, so the
  // validator warns that it has no effect.
  static const _knownFrontMatterKeys = {
    'marp',
    'theme',
    'paginate',
    'title',
    'author',
    'organization',
    'version',
    'date',
    'description',
    'keywords',
    'tlp',
    'ocideck_target_seconds',
    'ocideck_show_rehearsal_summary',
    'ocideck_play_only',
    'ocideck_finalized',
    'ocideck_seal_hash',
    'ocideck_seal_algo',
    'ocideck_seal_at',
    'ocideck_sig_name',
    'ocideck_sig_role',
    'ocideck_sig_cert',
    'ocideck_sig_date',
    'ocideck_sig_statement',
    'ocideck_sig_typed',
    'ocideck_sig_image',
    'ocideck_style_profile',
  };

  // Comment directives `_parseBlockDirectives` understands. A comment that looks
  // like a directive (`_key:` / `ocideck_key:`) but is not one of these is
  // dropped without effect — e.g. Marp's per-slide `_paginate`, `_header`,
  // `_footer`, `_color` — so the validator flags it.
  static const _supportedCommentDirectives = {
    '_class',
    '_style',
    'tlp',
    'advance',
    'skip',
    'ocideck_list_style',
    'ocideck_checklist_progress',
    'ocideck_continue_numbering',
    'ocideck_continue_split',
    'ocideck_title_image_overlay',
    'ocideck_title_text_color',
    'ocideck_bullet_marker',
    'ocideck_timeline_duration',
    'ocideck_timeline_current',
    'ocideck_two_bullets_left',
    'ocideck_two_bullets_right',
    'ocideck_two_bullets_left_title',
    'ocideck_two_bullets_right_title',
    // Per-slide attestation link comments (PENTEST_MIAUW §3.1 / AI_ASSIST §16.3):
    // the parser lifts these in `_parseFindingLink`, so the checker must not flag
    // them as unsupported.
    'ocideck_finding_id',
    'ocideck_finding_role',
    'ocideck_ai_assisted',
    // Per-image directives the parser lifts before the generic scan
    // (crop focal point + WCAG alt-text, AI_ASSIST §6.1).
    'ocideck_image_focus',
    'ocideck_image_focus2',
    'ocideck_image_alt',
    'ocideck_image_alt2',
    // Per-slide privacy disposition (PRIVACY_SHIELD §4.2): accept / shield /
    // redact. Zonder deze regel meldt de checker een onbekende directive.
    'ocideck_privacy',
  };

  MarkdownValidationResult validate(String markdown) {
    // Normalise line endings like MarkdownService.parseDeck does. Without this
    // a Windows (CRLF) or classic-Mac (CR) document would fail the `lines.first
    // == '---'` front-matter probe and the `---` slide split, so the validator
    // would silently skip those checks while the parser (which normalises) still
    // succeeds — the two would disagree.
    markdown = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final issues = <MarkdownValidationIssue>[];
    if (markdown.trim().isEmpty) {
      issues.add(
        const MarkdownValidationIssue(
          line: 1,
          severity: MarkdownValidationSeverity.warning,
          message: 'De presentatie is leeg.',
        ),
      );
      return MarkdownValidationResult(issues);
    }

    final lines = markdown.split('\n');
    _validateFrontMatter(lines, issues);
    _validateHtmlComments(lines, issues);
    _validateCommentDirectives(markdown, issues);

    final body = _stripFrontMatter(markdown);
    final bodyStartLine = markdown.length - body.length > 0
        ? markdown
              .substring(0, markdown.length - body.length)
              .split('\n')
              .length
        : 1;

    final blocks = MarkdownService.splitSlideBlocks(body);
    if (blocks.every((block) => block.trim().isEmpty)) {
      issues.add(
        MarkdownValidationIssue(
          line: bodyStartLine,
          severity: MarkdownValidationSeverity.error,
          message: 'Geen slides gevonden.',
        ),
      );
    }

    var blockStartLine = bodyStartLine;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i].trim();
      if (block.isEmpty) {
        blockStartLine += 1;
        continue;
      }
      _validateSlideBlock(
        block: block,
        slideNumber: i + 1,
        startLine: blockStartLine,
        issues: issues,
      );
      // Per slide: a fence opened in one slide and another left open in the
      // next would cancel out in a document-wide count (false negative).
      _validateFenceBalance(
        block.split('\n'),
        issues,
        lineOffset: blockStartLine - 1,
      );
      blockStartLine += block.split('\n').length + 1;
    }

    if (MarkdownService().parseDeck(markdown) == null) {
      issues.add(
        const MarkdownValidationIssue(
          line: 1,
          severity: MarkdownValidationSeverity.error,
          message:
              'De markdown kon niet worden ingelezen. Controleer de structuur.',
        ),
      );
    }

    issues.sort((a, b) => a.line.compareTo(b.line));
    return MarkdownValidationResult(issues);
  }

  void _validateFrontMatter(
    List<String> lines,
    List<MarkdownValidationIssue> issues,
  ) {
    if (lines.isEmpty || lines.first != '---') return;

    final closingIndex = _indexOfFrontMatterClose(lines);
    if (closingIndex == -1) {
      issues.add(
        const MarkdownValidationIssue(
          line: 1,
          severity: MarkdownValidationSeverity.error,
          message:
              'Front matter is niet afgesloten. Sluit af met een regel `---`.',
        ),
      );
      return;
    }

    for (var i = 1; i < closingIndex; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (!line.contains(':')) {
        issues.add(
          MarkdownValidationIssue(
            line: i + 1,
            severity: MarkdownValidationSeverity.warning,
            message: 'Front matter-regel heeft geen sleutel:waarde-vorm.',
          ),
        );
        continue;
      }
      final key = line.substring(0, line.indexOf(':')).trim();
      if (key == 'tlp') {
        final value = line.substring(line.indexOf(':') + 1).trim();
        if (!_isValidTlpKey(value)) {
          issues.add(
            MarkdownValidationIssue(
              line: i + 1,
              severity: MarkdownValidationSeverity.error,
              message:
                  'Onbekend TLP-niveau "$value". Gebruik clear, green, amber, amber+strict of red.',
            ),
          );
        }
      } else if (!_knownFrontMatterKeys.contains(key)) {
        issues.add(
          MarkdownValidationIssue(
            line: i + 1,
            severity: MarkdownValidationSeverity.warning,
            message:
                'Onbekende front-matter sleutel "$key" wordt genegeerd (typefout of niet-ondersteunde MARP-optie).',
          ),
        );
      }
    }
  }

  int _indexOfFrontMatterClose(List<String> lines) {
    for (var i = 1; i < lines.length; i++) {
      if (lines[i] == '---') return i;
    }
    return -1;
  }

  String _stripFrontMatter(String markdown) {
    if (!markdown.startsWith('---\n')) return markdown;
    final end = markdown.indexOf('\n---\n', 4);
    if (end == -1) return markdown;
    return markdown.substring(end + 5).trim();
  }

  void _validateHtmlComments(
    List<String> lines,
    List<MarkdownValidationIssue> issues,
  ) {
    // Balanscontrole over regelgrenzen heen: een meerregelig
    // `<!-- … -->` (zoals geserialiseerde sprekersnotities) mag geen fout
    // geven, terwijl een écht niet-afgesloten commentaar dat wél doet.
    int? openCommentLine;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      var searchStart = 0;
      while (searchStart <= line.length) {
        if (openCommentLine == null) {
          final openIndex = line.indexOf('<!--', searchStart);
          if (openIndex == -1) break;
          openCommentLine = i + 1;
          searchStart = openIndex + 4;
        } else {
          final closeIndex = line.indexOf('-->', searchStart);
          if (closeIndex == -1) break;
          openCommentLine = null;
          searchStart = closeIndex + 3;
        }
      }
    }
    if (openCommentLine != null) {
      issues.add(
        MarkdownValidationIssue(
          line: openCommentLine,
          severity: MarkdownValidationSeverity.error,
          message: 'HTML-commentaar is niet afgesloten met `-->`.',
        ),
      );
    }
  }

  /// Flags HTML comments that *look* like a directive — they open with a
  /// reserved `_key:` or `ocideck_key:` token — but name a directive OciDeck
  /// does not implement (so the parser drops them silently). Plain prose
  /// comments are speaker notes and are intentionally left alone, so genuine
  /// notes no longer trigger a spurious warning.
  void _validateCommentDirectives(
    String markdown,
    List<MarkdownValidationIssue> issues,
  ) {
    for (final match in _reHtmlCommentMultiline.allMatches(markdown)) {
      final content = match.group(1)!.trim();
      final keyMatch = _reDirectiveKey.firstMatch(content);
      if (keyMatch == null) continue;
      final key = keyMatch.group(1)!;
      if (_supportedCommentDirectives.contains(key)) continue;
      final line = markdown.substring(0, match.start).split('\n').length;
      issues.add(
        MarkdownValidationIssue(
          line: line,
          severity: MarkdownValidationSeverity.warning,
          message: 'Directive `$key` wordt niet ondersteund en genegeerd.',
        ),
      );
    }
  }

  void _validateFenceBalance(
    List<String> lines,
    List<MarkdownValidationIssue> issues, {
    int lineOffset = 0,
  }) {
    // Track real open/close state rather than parity: two opened-but-never-
    // closed fences make an even count, which a parity check reads as balanced.
    // The same open/close model the slide splitter uses keeps them consistent.
    String? fenceChar;
    int? openLine;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (fenceChar == null) {
        if (trimmed.startsWith('```')) {
          fenceChar = '`';
          openLine = lineOffset + i + 1;
        } else if (trimmed.startsWith('~~~')) {
          fenceChar = '~';
          openLine = lineOffset + i + 1;
        }
      } else if (MarkdownService.isBareFence(trimmed, fenceChar)) {
        fenceChar = null;
        openLine = null;
      }
    }
    if (fenceChar != null && openLine != null) {
      issues.add(
        MarkdownValidationIssue(
          line: openLine,
          severity: MarkdownValidationSeverity.error,
          message: 'Codeblok is niet afgesloten met ```.',
        ),
      );
    }
  }

  void _validateSlideBlock({
    required String block,
    required int slideNumber,
    required int startLine,
    required List<MarkdownValidationIssue> issues,
  }) {
    final blockLines = block.split('\n');
    int lineNo(int index) => startLine + index;
    // Lines strictly inside a fenced code block: their content is verbatim, so
    // an HTML tag or image shown there is a sample, not real markup. Structural
    // checks (div balance, unclosed image/media) skip them to avoid false
    // positives on code slides.
    final fenced = _fencedLineIndexes(blockLines);

    final classMatch = _reClassDirective.firstMatch(block);
    if (classMatch == null &&
        _reClassOpen.hasMatch(block) &&
        classMatch == null) {
      final badLine = blockLines.indexWhere(
        (line) => line.contains('<!--') && line.contains('_class:'),
      );
      if (badLine >= 0) {
        issues.add(
          MarkdownValidationIssue(
            line: lineNo(badLine),
            severity: MarkdownValidationSeverity.error,
            message:
                'Slide $slideNumber: `_class`-commentaar is ongeldig. Gebruik `<!-- _class: … -->`.',
          ),
        );
      }
    }

    final cssClass = classMatch?.group(1)?.trim() ?? '';
    final classTokens = cssClass
        .split(_reWhitespace)
        .where((token) => token.isNotEmpty)
        .toList();

    for (final token in classTokens) {
      if (!_knownClassTokens.contains(token)) {
        final classLine = blockLines.indexWhere(
          (line) => line.contains('<!-- _class:'),
        );
        issues.add(
          MarkdownValidationIssue(
            line: lineNo(classLine >= 0 ? classLine : 0),
            severity: MarkdownValidationSeverity.warning,
            message:
                'Slide $slideNumber: onbekende class "$token". Dit kan het slidetype beïnvloeden.',
          ),
        );
      }
    }

    _validateBlockLines(
      blockLines: blockLines,
      classTokens: classTokens,
      slideNumber: slideNumber,
      startLine: startLine,
      fenced: fenced,
      issues: issues,
    );
    if (classTokens.contains('cockpit')) {
      _validateCockpitSlide(blockLines, slideNumber, lineNo, issues);
    }
    if (classTokens.contains('split')) {
      _validateSplitSlide(blockLines, slideNumber, lineNo, issues);
    }
    if (classTokens.contains('two-bullets')) {
      _validateTwoBulletsSlide(blockLines, slideNumber, lineNo, issues);
    }
    if (classTokens.contains('table')) {
      _validateTableSlide(blockLines, slideNumber, lineNo, issues);
    }

    _validateDivBalance(blockLines, slideNumber, lineNo, fenced, issues);
  }

  /// Indexes of lines that sit strictly inside a fenced code block (the fence
  /// markers themselves are excluded). Uses the same fence detection as
  /// [MarkdownService.splitSlideBlocks] so both agree on what "inside code" is.
  Set<int> _fencedLineIndexes(List<String> lines) {
    final inside = <int>{};
    String? fenceChar;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (fenceChar == null) {
        if (trimmed.startsWith('```')) {
          fenceChar = '`';
        } else if (trimmed.startsWith('~~~')) {
          fenceChar = '~';
        }
      } else if (MarkdownService.isBareFence(trimmed, fenceChar)) {
        fenceChar = null;
      } else {
        inside.add(i);
      }
    }
    return inside;
  }

  void _validateBlockLines({
    required List<String> blockLines,
    required List<String> classTokens,
    required int slideNumber,
    required int startLine,
    required Set<int> fenced,
    required List<MarkdownValidationIssue> issues,
  }) {
    int lineNo(int index) => startLine + index;
    for (var i = 0; i < blockLines.length; i++) {
      final line = blockLines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('<!-- tlp:')) {
        final value = trimmed
            .substring('<!-- tlp:'.length)
            .replaceAll('-->', '')
            .trim();
        if (!_isValidTlpKey(value)) {
          issues.add(
            MarkdownValidationIssue(
              line: lineNo(i),
              severity: MarkdownValidationSeverity.error,
              message: 'Slide $slideNumber: onbekend TLP-niveau "$value".',
            ),
          );
        }
      }

      if (trimmed.startsWith('<!-- advance:')) {
        final value = trimmed
            .substring('<!-- advance:'.length)
            .replaceAll('-->', '')
            .trim();
        final parsed = double.tryParse(value);
        if (parsed == null || !parsed.isFinite) {
          issues.add(
            MarkdownValidationIssue(
              line: lineNo(i),
              severity: MarkdownValidationSeverity.error,
              message:
                  'Slide $slideNumber: advance-waarde "$value" is geen getal.',
            ),
          );
        }
      }

      if (trimmed.startsWith('<!-- ocideck_list_style:')) {
        final value = trimmed
            .substring('<!-- ocideck_list_style:'.length)
            .replaceAll('-->', '')
            .trim();
        if (!_validListStyles.contains(value)) {
          issues.add(
            MarkdownValidationIssue(
              line: lineNo(i),
              severity: MarkdownValidationSeverity.error,
              message:
                  'Slide $slideNumber: onbekende lijststijl "$value". Gebruik bullets, numbered, checklist of richText.',
            ),
          );
        }
      }

      for (final prefix in const [
        'ocideck_two_bullets_left:',
        'ocideck_two_bullets_right:',
        'ocideck_two_bullets_left_title:',
        'ocideck_two_bullets_right_title:',
      ]) {
        if (trimmed.startsWith('<!-- $prefix')) {
          final encoded = trimmed
              .substring('<!-- $prefix'.length)
              .replaceAll('-->', '')
              .trim();
          if (!_isValidEncodedPayload(prefix, encoded)) {
            issues.add(
              MarkdownValidationIssue(
                line: lineNo(i),
                severity: MarkdownValidationSeverity.error,
                message:
                    'Slide $slideNumber: `$prefix`-commentaar bevat ongeldige base64/JSON.',
              ),
            );
          }
        }
      }

      // The remaining checks are for real markup; inside a fenced code block an
      // image or media tag is a verbatim sample, not markup to validate.
      if (fenced.contains(i)) continue;

      if (_reUnclosedImage.hasMatch(trimmed)) {
        issues.add(
          MarkdownValidationIssue(
            line: lineNo(i),
            severity: MarkdownValidationSeverity.error,
            message:
                'Slide $slideNumber: afbeeldings-markdown is niet afgesloten met `)`.',
          ),
        );
      }

      if (trimmed.startsWith('<video') && !trimmed.endsWith('>')) {
        issues.add(
          MarkdownValidationIssue(
            line: lineNo(i),
            severity: MarkdownValidationSeverity.error,
            message:
                'Slide $slideNumber: `<video>`-tag is onvolledig of niet afgesloten.',
          ),
        );
      } else if (trimmed.startsWith('<video') &&
          _reVideoSrc.firstMatch(trimmed) == null) {
        issues.add(
          MarkdownValidationIssue(
            line: lineNo(i),
            severity: MarkdownValidationSeverity.error,
            message:
                'Slide $slideNumber: `<video>` mist een `src="…"`-attribuut.',
          ),
        );
      }

      if (trimmed.startsWith('<audio') && !trimmed.endsWith('>')) {
        issues.add(
          MarkdownValidationIssue(
            line: lineNo(i),
            severity: MarkdownValidationSeverity.error,
            message:
                'Slide $slideNumber: `<audio>`-tag is onvolledig of niet afgesloten.',
          ),
        );
      }
    }

    if (classTokens.contains('code')) {
      _validateCodeSlide(blockLines, slideNumber, lineNo, issues);
    }
    if (classTokens.contains('chart')) {
      _validateChartSlide(blockLines, slideNumber, lineNo, issues);
    }
  }

  void _validateCodeSlide(
    List<String> blockLines,
    int slideNumber,
    int Function(int) lineNo,
    List<MarkdownValidationIssue> issues,
  ) {
    final fences = blockLines.where((line) => _reFence.hasMatch(line)).toList();
    if (fences.length < 2) {
      final firstFence = blockLines.indexWhere(
        (line) => _reFence.hasMatch(line),
      );
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(firstFence >= 0 ? firstFence : 0),
          severity: MarkdownValidationSeverity.error,
          message:
              'Slide $slideNumber: broncode-slide vereist een fenced ```-blok.',
        ),
      );
    }
  }

  void _validateChartSlide(
    List<String> blockLines,
    int slideNumber,
    int Function(int) lineNo,
    List<MarkdownValidationIssue> issues,
  ) {
    _validateFencedJson(
      blockLines: blockLines,
      slideNumber: slideNumber,
      lineNo: lineNo,
      issues: issues,
      fence: 'chart',
      label: 'grafiek',
      fenceOpenLoose: _reChartFenceLoose,
      fenceOpen: _reChartFence,
    );
  }

  void _validateCockpitSlide(
    List<String> blockLines,
    int slideNumber,
    int Function(int) lineNo,
    List<MarkdownValidationIssue> issues,
  ) {
    _validateFencedJson(
      blockLines: blockLines,
      slideNumber: slideNumber,
      lineNo: lineNo,
      issues: issues,
      fence: 'cockpit',
      label: 'cockpit',
      fenceOpenLoose: _reCockpitFenceLoose,
      fenceOpen: _reCockpitFence,
    );
  }

  /// Gedeelde controle voor slides met een verplicht fenced JSON-blok
  /// (```chart / ```cockpit): blok aanwezig, afgesloten, niet leeg en geldige
  /// JSON-map. [fence] is de fence-infostring, [label] het woord in de
  /// Nederlandse meldingen ('grafiek', 'cockpit').
  void _validateFencedJson({
    required List<String> blockLines,
    required int slideNumber,
    required int Function(int) lineNo,
    required List<MarkdownValidationIssue> issues,
    required String fence,
    required String label,
    required RegExp fenceOpenLoose,
    required RegExp fenceOpen,
  }) {
    final openingIndex = blockLines.indexWhere(
      (line) => fenceOpenLoose.hasMatch(line.trim()),
    );
    if (openingIndex < 0) {
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(0),
          severity: MarkdownValidationSeverity.error,
          message:
              'Slide $slideNumber: $label-slide vereist een ```$fence-blok.',
        ),
      );
      return;
    }

    final jsonLines = <String>[];
    var inFence = false;
    var closingIndex = -1;
    for (var i = 0; i < blockLines.length; i++) {
      final trimmed = blockLines[i].trim();
      if (fenceOpen.hasMatch(trimmed)) {
        inFence = true;
        continue;
      }
      if (inFence && _reFenceClose.hasMatch(trimmed)) {
        closingIndex = i;
        break;
      }
      if (inFence) jsonLines.add(blockLines[i]);
    }

    if (closingIndex < 0) {
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(openingIndex),
          severity: MarkdownValidationSeverity.error,
          message: 'Slide $slideNumber: ```$fence-blok is niet afgesloten.',
        ),
      );
      return;
    }

    final raw = jsonLines.join('\n').trim();
    if (raw.isEmpty) {
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(openingIndex + 1),
          severity: MarkdownValidationSeverity.warning,
          message: 'Slide $slideNumber: $label-specificatie is leeg.',
        ),
      );
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        issues.add(
          MarkdownValidationIssue(
            line: lineNo(openingIndex + 1),
            severity: MarkdownValidationSeverity.error,
            message:
                'Slide $slideNumber: $label-JSON moet een object `{…}` zijn.',
          ),
        );
      }
    } catch (e) {
      logWarning('MarkdownValidator: $fence JSON parse failed', e);
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(openingIndex + 1),
          severity: MarkdownValidationSeverity.error,
          message: 'Slide $slideNumber: $label-JSON is ongeldig.',
        ),
      );
    }
  }

  void _validateSplitSlide(
    List<String> blockLines,
    int slideNumber,
    int Function(int) lineNo,
    List<MarkdownValidationIssue> issues,
  ) {
    _requireDiv(
      blockLines: blockLines,
      className: 'split-text',
      slideNumber: slideNumber,
      lineNo: lineNo,
      issues: issues,
    );
    _requireDiv(
      blockLines: blockLines,
      className: 'split-image',
      slideNumber: slideNumber,
      lineNo: lineNo,
      issues: issues,
    );
  }

  void _validateTwoBulletsSlide(
    List<String> blockLines,
    int slideNumber,
    int Function(int) lineNo,
    List<MarkdownValidationIssue> issues,
  ) {
    _requireDiv(
      blockLines: blockLines,
      className: 'ocideck-two-bullets',
      slideNumber: slideNumber,
      lineNo: lineNo,
      issues: issues,
    );
  }

  void _requireDiv({
    required List<String> blockLines,
    required String className,
    required int slideNumber,
    required int Function(int) lineNo,
    required List<MarkdownValidationIssue> issues,
  }) {
    final openIndex = blockLines.indexWhere(
      (line) => line.contains('<div class="$className"'),
    );
    if (openIndex < 0) {
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(0),
          severity: MarkdownValidationSeverity.error,
          message: 'Slide $slideNumber: verwacht `<div class="$className">`.',
        ),
      );
      return;
    }

    var depth = 0;
    var closed = false;
    for (var i = openIndex; i < blockLines.length; i++) {
      final line = blockLines[i];
      if (line.contains('<div')) depth++;
      if (line.contains('</div>')) {
        depth--;
        if (depth == 0) {
          closed = true;
          break;
        }
      }
    }
    if (!closed) {
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(openIndex),
          severity: MarkdownValidationSeverity.error,
          message:
              'Slide $slideNumber: `<div class="$className">` is niet afgesloten.',
        ),
      );
    }
  }

  void _validateTableSlide(
    List<String> blockLines,
    int slideNumber,
    int Function(int) lineNo,
    List<MarkdownValidationIssue> issues,
  ) {
    final tableLineIndexes = <int>[];
    for (var i = 0; i < blockLines.length; i++) {
      if (blockLines[i].trim().startsWith('|')) {
        tableLineIndexes.add(i);
      }
    }
    if (tableLineIndexes.isEmpty) {
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(0),
          severity: MarkdownValidationSeverity.warning,
          message: 'Slide $slideNumber: tabel-slide bevat geen tabel.',
        ),
      );
      return;
    }

    if (tableLineIndexes.length == 1) {
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(tableLineIndexes.first),
          severity: MarkdownValidationSeverity.error,
          message:
              'Slide $slideNumber: tabel mist een scheidingsrij (`| --- |`).',
        ),
      );
      return;
    }

    final separatorIndex = tableLineIndexes[1];
    final cells = blockLines[separatorIndex]
        .trim()
        .replaceFirst(_reLeadingPipe, '')
        .replaceFirst(_reTrailingPipe, '')
        .split('|')
        .map((cell) => cell.trim())
        .toList();
    if (!cells.every((cell) => _reSeparatorCell.hasMatch(cell))) {
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(separatorIndex),
          severity: MarkdownValidationSeverity.error,
          message:
              'Slide $slideNumber: tweede tabelrij moet een scheidingsrij zijn (`| --- |`).',
        ),
      );
    }
  }

  void _validateDivBalance(
    List<String> blockLines,
    int slideNumber,
    int Function(int) lineNo,
    Set<int> fenced,
    List<MarkdownValidationIssue> issues,
  ) {
    var depth = 0;
    int? firstOpenLine;
    for (var i = 0; i < blockLines.length; i++) {
      // A `<div>` inside a code fence is sample text, and one inside a comment
      // is not markup either — neither should shift the balance.
      if (fenced.contains(i)) continue;
      final line = blockLines[i].replaceAll(_reInlineComment, '');
      final opens = _reDivOpen.allMatches(line).length;
      final closes = _reDivClose.allMatches(line).length;
      if (opens > 0 && firstOpenLine == null) firstOpenLine = i;
      depth += opens - closes;
      if (depth < 0) {
        issues.add(
          MarkdownValidationIssue(
            line: lineNo(i),
            severity: MarkdownValidationSeverity.error,
            message: 'Slide $slideNumber: overtollige `</div>`.',
          ),
        );
        depth = 0;
      }
    }
    if (depth > 0 && firstOpenLine != null) {
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(firstOpenLine),
          severity: MarkdownValidationSeverity.error,
          message:
              'Slide $slideNumber: niet alle `<div>`-tags zijn afgesloten.',
        ),
      );
    }
  }

  bool _isValidTlpKey(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'none') return true;
    return TlpLevel.values.any((level) => level.key == normalized);
  }

  bool _isValidEncodedPayload(String prefix, String encoded) {
    if (encoded.isEmpty) return prefix.contains('_title');
    try {
      final decoded = utf8.decode(base64Url.decode(encoded.trim()));
      if (prefix.contains('_title')) return true;
      final raw = jsonDecode(decoded);
      return raw is List;
    } catch (e) {
      logWarning('MarkdownValidator: encoded payload is not valid', e);
      return false;
    }
  }
}
