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
    var accepted = false;

    var body = markdown;
    var bodyStartLine = 1;

    if (deckScope) {
      final lines = markdown.split('\n');
      if (lines.isEmpty || lines.first != '---') {
        findings.add(
          const MarkdownValidationIssue(
            line: 1,
            severity: MarkdownValidationSeverity.error,
            message:
                'Front matter met `marp: true` ontbreekt: Marp-tools renderen dit als gewoon document, geen slides.',
          ),
        );
      } else {
        final closeIndex = _frontMatterClose(lines);
        if (closeIndex == -1) {
          findings.add(
            const MarkdownValidationIssue(
              line: 1,
              severity: MarkdownValidationSeverity.error,
              message:
                  'Front matter is niet afgesloten met `---`; Marp kan de sleutels niet lezen.',
            ),
          );
          // Het hele document geldt dan als inhoud: de `---`-regels leest de
          // body-check als scheidingen, net als Marp dat zou doen.
        } else {
          accepted = _checkFrontMatter(lines, closeIndex, context, findings);
          body = lines.sublist(closeIndex + 1).join('\n');
          bodyStartLine = closeIndex + 2;
        }
      }
    }

    _checkBody(body, bodyStartLine, context, findings);
    findings.sort((a, b) => a.line.compareTo(b.line));

    final status = findings.any(
      (f) => f.severity == MarkdownValidationSeverity.error,
    )
        ? MarpCompatStatus.incompatible
        : findings.any(
            (f) => f.severity == MarkdownValidationSeverity.warning,
          )
        ? (accepted ? MarpCompatStatus.accepted : MarpCompatStatus.degraded)
        : MarpCompatStatus.compatible;
    return MarpCompatReport(
      status: status,
      findings: findings,
      accepted: accepted,
    );
  }

  int _frontMatterClose(List<String> lines) {
    for (var i = 1; i < lines.length; i++) {
      if (lines[i] == '---') return i;
    }
    return -1;
  }

  /// Toetst de front-matter-regels. Geeft terug of de acceptatievlag aan
  /// staat; bevindingen gaan in [findings].
  bool _checkFrontMatter(
    List<String> lines,
    int closeIndex,
    MarpCompatContext context,
    List<MarkdownValidationIssue> findings,
  ) {
    var marpKey = false;
    var accepted = false;
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
          MarkdownValidationIssue(
            line: i + 1,
            severity: MarkdownValidationSeverity.error,
            message:
                'Tab in de front matter: YAML staat geen tabs toe, Marp faalt hierop.',
          ),
        );
        continue;
      }

      final key = frontMatterKeyOf(line);
      if (key == null) {
        if (trimmed.contains(':')) {
          findings.add(
            MarkdownValidationIssue(
              line: i + 1,
              severity: MarkdownValidationSeverity.warning,
              message: 'Front matter-regel heeft geen sleutel:waarde-vorm.',
            ),
          );
        }
        continue;
      }
      if (!seenKeys.add(key)) {
        findings.add(
          MarkdownValidationIssue(
            line: i + 1,
            severity: MarkdownValidationSeverity.error,
            message: 'Front-matter sleutel "$key" staat er dubbel in; YAML weigert dat.',
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
              MarkdownValidationIssue(
                line: i + 1,
                severity: MarkdownValidationSeverity.error,
                message:
                    '`marp: $value` schakelt Marp uit; gebruik `marp: true` voor slides.',
              ),
            );
          }
        case 'theme':
          final theme = parseMarkdownYamlScalar(value);
          if (!kMarpBuiltinThemes.contains(theme) &&
              context == MarpCompatContext.bareFile) {
            findings.add(
              MarkdownValidationIssue(
                line: i + 1,
                severity: MarkdownValidationSeverity.warning,
                message:
                    'Thema "$theme" is geen ingebouwd Marp-thema; als los .md-bestand mist de theme-definitie.',
              ),
            );
          }
        case 'headingDivider':
          findings.add(
            MarkdownValidationIssue(
              line: i + 1,
              severity: MarkdownValidationSeverity.warning,
              message:
                  '`headingDivider` laat Marp extra slides splitsen op koppen; het deck rendert dan anders dan OciDeck toont.',
            ),
          );
        case 'size':
          final size = parseMarkdownYamlScalar(value);
          if (size != '16:9' && size != '4:3') {
            findings.add(
              MarkdownValidationIssue(
                line: i + 1,
                severity: MarkdownValidationSeverity.warning,
                message:
                    '`size: $size` werkt alleen als het thema die maat definieert.',
              ),
            );
          }
        case kMarpCompatAcceptedKey:
          accepted = value == 'true';
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

    if (!marpKey) {
      findings.add(
        const MarkdownValidationIssue(
          line: 1,
          severity: MarkdownValidationSeverity.error,
          message:
              '`marp: true` ontbreekt in de front matter: Marp-tools renderen dit als gewoon document, geen slides. OciDeck schrijft de sleutel bij het opslaan terug.',
        ),
      );
    }
    if (hasCallouts) {
      findings.add(
        const MarkdownValidationIssue(
          line: 1,
          severity: MarkdownValidationSeverity.informational,
          message:
              '`ocideck_callouts` markeert afbeeldings-annotaties die Marp niet rendert.',
        ),
      );
    }
    if (ignoredKeys.isNotEmpty) {
      findings.add(
        MarkdownValidationIssue(
          line: firstIgnoredLine,
          severity: MarkdownValidationSeverity.informational,
          message:
              'Marp negeert ${ignoredKeys.length} sleutel(s) (${ignoredKeys.join(', ')}); bijbehorend gedrag vervalt in andere tools.',
        ),
      );
    }
    return accepted;
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
        MarkdownValidationIssue(
          line: line,
          severity: MarkdownValidationSeverity.error,
          message:
              'Waarde begint met een YAML-sigil ($value); js-yaml faalt hierop.',
        ),
      );
      return;
    }
    final quote = value[0];
    if ((quote == '"' || quote == "'") &&
        (value.length < 2 || !value.endsWith(quote))) {
      findings.add(
        MarkdownValidationIssue(
          line: line,
          severity: MarkdownValidationSeverity.error,
          message: 'Onafgesloten quote in de front matter-waarde.',
        ),
      );
    }
  }

  void _checkBody(
    String body,
    int bodyStartLine,
    MarpCompatContext context,
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
    final unknownDirectives = <String>[];
    var firstUnknownDirectiveLine = 0;

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final blockLines = block.split('\n');
      int lineNo(int index) => blockStartLine + index;
      final fenced = _fencedLineIndexes(blockLines);
      final slideNumber = i + 1;

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
            MarkdownValidationIssue(
              line: lineNo(classLine >= 0 ? classLine : 0),
              severity: MarkdownValidationSeverity.warning,
              message:
                  'Slide $slideNumber: class "${ocideckOnly.join(', ')}" bestaat niet in Marp; de inhoud rendert als platte markdown zonder dit type.',
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
              MarkdownValidationIssue(
                line: lineNo(j),
                severity: MarkdownValidationSeverity.warning,
                message:
                    'Slide $slideNumber: ```$info-blok toont in Marp als letterlijk codeblok.',
              ),
            );
          }
        }
        if (fenced.contains(j)) continue;

        if (_reTaskItem.hasMatch(trimmed)) {
          taskItemCount++;
          if (taskItemCount == 1) firstTaskItemLine = lineNo(j);
        }
        if (_reVideoAudio.hasMatch(trimmed)) {
          videoAudioCount++;
          if (videoAudioCount == 1) firstVideoAudioLine = lineNo(j);
        }
        for (final match in _reImage.allMatches(trimmed)) {
          _checkMediaUri(
            match.group(1)!,
            lineNo(j),
            slideNumber,
            context,
            findings,
          );
        }
        for (final match in _reSrcAttr.allMatches(trimmed)) {
          _checkMediaUri(
            match.group(1)!,
            lineNo(j),
            slideNumber,
            context,
            findings,
          );
        }

        for (final match in _reHtmlComment.allMatches(trimmed)) {
          final content = match.group(1)!;
          if (content.contains('\n')) continue; // notitieblok, geen directive
          _checkComment(
            content,
            lineNo(j),
            slideNumber,
            findings,
            onOcideckComment: () {
              ocideckCommentCount++;
              if (ocideckCommentCount == 1) {
                firstOcideckCommentLine = lineNo(j);
              }
            },
            onUnknownDirective: (key) {
              if (!unknownDirectives.contains(key)) unknownDirectives.add(key);
              if (unknownDirectives.length == 1) {
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

    if (ocideckCommentCount > 0) {
      findings.add(
        MarkdownValidationIssue(
          line: firstOcideckCommentLine,
          severity: MarkdownValidationSeverity.informational,
          message:
              '$ocideckCommentCount OciDeck-directive(s) (advance, ocideck_*) negeert Marp.',
        ),
      );
    }
    if (unknownDirectives.isNotEmpty) {
      findings.add(
        MarkdownValidationIssue(
          line: firstUnknownDirectiveLine,
          severity: MarkdownValidationSeverity.informational,
          message:
              'Onbekende directive(s) ${unknownDirectives.join(', ')} doen in Marp niets.',
        ),
      );
    }
    if (videoAudioCount > 0) {
      findings.add(
        MarkdownValidationIssue(
          line: firstVideoAudioLine,
          severity: MarkdownValidationSeverity.informational,
          message:
              '<video>/<audio> speelt in HTML-export, niet in de PDF/PPTX-export van marp-cli.',
        ),
      );
    }
    if (taskItemCount > 0) {
      findings.add(
        MarkdownValidationIssue(
          line: firstTaskItemLine,
          severity: MarkdownValidationSeverity.informational,
          message:
              '$taskItemCount tasklist-item(s) (- [ ]): Marp rendert die zonder checkbox-gedrag.',
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
    int slideNumber,
    List<MarkdownValidationIssue> findings, {
    required void Function() onOcideckComment,
    required void Function(String key) onUnknownDirective,
  }) {
    if (content == 'skip') {
      findings.add(
        MarkdownValidationIssue(
          line: line,
          severity: MarkdownValidationSeverity.warning,
          message:
              'Slide $slideNumber: `<!-- skip -->` bestaat niet in Marp; deze dia toont daar gewoon.',
        ),
      );
      return;
    }
    if (content.startsWith('tlp:')) {
      findings.add(
        MarkdownValidationIssue(
          line: line,
          severity: MarkdownValidationSeverity.warning,
          message:
              'Slide $slideNumber: `<!-- tlp: -->` houdt de dia in OciDeck achter; Marp toont hem gewoon.',
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
    int slideNumber,
    MarpCompatContext context,
    List<MarkdownValidationIssue> findings,
  ) {
    if (uri.startsWith('mem:')) {
      if (context == MarpCompatContext.bareFile) {
        findings.add(
          MarkdownValidationIssue(
            line: line,
            severity: MarkdownValidationSeverity.warning,
            message:
                'Slide $slideNumber: `mem:`-media resolveert alleen binnen deze OciDeck-sessie; in een los .md-bestand is de afbeelding weg.',
          ),
        );
      }
      return;
    }
    if (_reAbsolutePath.hasMatch(uri)) {
      findings.add(
        MarkdownValidationIssue(
          line: line,
          severity: MarkdownValidationSeverity.warning,
          message:
              'Slide $slideNumber: mediapad "$uri" werkt alleen op deze machine.',
        ),
      );
    }
  }

  /// Indexes van regels strikt binnen een fenced blok — hun inhoud is
  /// verbatim, dus commentaren en media daarin zijn voorbeelden.
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
    var previousTextLine = false;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (fenceChar == null) {
        if (lines[i] == '---' && previousTextLine) {
          findings.add(
            MarkdownValidationIssue(
              line: bodyStartLine + i,
              severity: MarkdownValidationSeverity.warning,
              message:
                  '`---` direct onder tekst: Marp kan dit als kop (setext) lezen in plaats van slide-scheiding; zet een lege regel ervoor.',
            ),
          );
          previousTextLine = false;
          continue;
        }
        if (trimmed.startsWith('```')) {
          fenceChar = '`';
        } else if (trimmed.startsWith('~~~')) {
          fenceChar = '~';
        }
      } else if (MarkdownService.isBareFence(trimmed, fenceChar)) {
        fenceChar = null;
      }
      previousTextLine =
          fenceChar == null &&
          _isParagraphLine(lines[i]);
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
}
