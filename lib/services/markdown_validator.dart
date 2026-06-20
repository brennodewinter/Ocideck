import 'dart:convert';

import '../models/deck.dart';
import '../models/markdown_validation.dart';
import 'markdown_service.dart';

/// Validates deck markdown against what [MarkdownService] can parse reliably.
class MarkdownValidator {
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
    'logo-safe',
    'no-logo',
    'no-footer',
  };

  static const _validListStyles = {'bullets', 'numbered', 'checklist'};

  MarkdownValidationResult validate(String markdown) {
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
    _validateFenceBalance(lines, issues);

    final body = _stripFrontMatter(markdown);
    final bodyStartLine = markdown.length - body.length > 0
        ? markdown
              .substring(0, markdown.length - body.length)
              .split('\n')
              .length
        : 1;

    final blocks = body.split(RegExp(r'\n---\n'));
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
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final openCount = '<!--'.allMatches(line).length;
      final closeCount = '-->'.allMatches(line).length;
      if (openCount > closeCount) {
        issues.add(
          MarkdownValidationIssue(
            line: i + 1,
            severity: MarkdownValidationSeverity.error,
            message: 'HTML-commentaar is niet afgesloten met `-->`.',
          ),
        );
      }

      final classLike = RegExp(r'<!--\s*([^_][^>]*?)-->').firstMatch(line);
      if (classLike != null &&
          !line.contains('_class:') &&
          !line.contains('ocideck_') &&
          !line.contains('_style:') &&
          classLike.group(1)?.trim() != 'skip' &&
          !RegExp(r'^tlp:\s*\S').hasMatch(classLike.group(1)!.trim()) &&
          !RegExp(r'^advance:\s*[\d.]+').hasMatch(classLike.group(1)!.trim())) {
        issues.add(
          MarkdownValidationIssue(
            line: i + 1,
            severity: MarkdownValidationSeverity.warning,
            message:
                'Commentaar mist `_class:` of een bekende ocideck-sleutel.',
          ),
        );
      }
    }
  }

  void _validateFenceBalance(
    List<String> lines,
    List<MarkdownValidationIssue> issues,
  ) {
    var fenceCount = 0;
    int? firstFenceLine;
    for (var i = 0; i < lines.length; i++) {
      if (RegExp(r'^\s*```').hasMatch(lines[i])) {
        fenceCount++;
        firstFenceLine ??= i + 1;
      }
    }
    if (fenceCount.isOdd && firstFenceLine != null) {
      issues.add(
        MarkdownValidationIssue(
          line: firstFenceLine,
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

    final classMatch = RegExp(
      r'<!--\s*_class:\s*([^>]+?)\s*-->',
    ).firstMatch(block);
    if (classMatch == null &&
        RegExp(r'<!--\s*_class:').hasMatch(block) &&
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
        .split(RegExp(r'\s+'))
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
        if (double.tryParse(value) == null) {
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
                  'Slide $slideNumber: onbekende lijststijl "$value". Gebruik bullets, numbered of checklist.',
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

      if (RegExp(r'!\[[^\]]*\]\([^)]*$').hasMatch(trimmed)) {
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
          RegExp(r'src="([^"]+)"').firstMatch(trimmed) == null) {
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
    if (classTokens.contains('split')) {
      _validateSplitSlide(blockLines, slideNumber, lineNo, issues);
    }
    if (classTokens.contains('two-bullets')) {
      _validateTwoBulletsSlide(blockLines, slideNumber, lineNo, issues);
    }
    if (classTokens.contains('table')) {
      _validateTableSlide(blockLines, slideNumber, lineNo, issues);
    }

    _validateDivBalance(blockLines, slideNumber, lineNo, issues);
  }

  void _validateCodeSlide(
    List<String> blockLines,
    int slideNumber,
    int Function(int) lineNo,
    List<MarkdownValidationIssue> issues,
  ) {
    final fences = blockLines
        .where((line) => RegExp(r'^\s*```').hasMatch(line))
        .toList();
    if (fences.length < 2) {
      final firstFence = blockLines.indexWhere(
        (line) => RegExp(r'^\s*```').hasMatch(line),
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
    final openingIndex = blockLines.indexWhere(
      (line) => RegExp(r'^\s*```chart\s*$').hasMatch(line.trim()),
    );
    if (openingIndex < 0) {
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(0),
          severity: MarkdownValidationSeverity.error,
          message:
              'Slide $slideNumber: grafiek-slide vereist een ```chart-blok.',
        ),
      );
      return;
    }

    final jsonLines = <String>[];
    var inFence = false;
    var closingIndex = -1;
    for (var i = 0; i < blockLines.length; i++) {
      final trimmed = blockLines[i].trim();
      if (RegExp(r'^```chart\s*$').hasMatch(trimmed)) {
        inFence = true;
        continue;
      }
      if (inFence && RegExp(r'^```\s*$').hasMatch(trimmed)) {
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
          message: 'Slide $slideNumber: ```chart-blok is niet afgesloten.',
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
          message: 'Slide $slideNumber: grafiek-specificatie is leeg.',
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
                'Slide $slideNumber: grafiek-JSON moet een object `{…}` zijn.',
          ),
        );
      }
    } catch (_) {
      issues.add(
        MarkdownValidationIssue(
          line: lineNo(openingIndex + 1),
          severity: MarkdownValidationSeverity.error,
          message: 'Slide $slideNumber: grafiek-JSON is ongeldig.',
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
        .replaceFirst(RegExp(r'^\|'), '')
        .replaceFirst(RegExp(r'\|$'), '')
        .split('|')
        .map((cell) => cell.trim())
        .toList();
    if (!cells.every((cell) => RegExp(r'^:?-+:?$').hasMatch(cell))) {
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
    List<MarkdownValidationIssue> issues,
  ) {
    var depth = 0;
    int? firstOpenLine;
    for (var i = 0; i < blockLines.length; i++) {
      final line = blockLines[i];
      final opens = RegExp(r'<div\b').allMatches(line).length;
      final closes = RegExp(r'</div>').allMatches(line).length;
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
    } catch (_) {
      return false;
    }
  }
}
