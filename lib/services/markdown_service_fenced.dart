// Part of the markdown_service library — see markdown_service.dart.
// Split out for navigability (fenced-block parsers: code/chart/cockpit/question); all imports live in the main library
// file.
part of 'markdown_service.dart';

// Hoisted hot-path regexes (zie markdown_service_parse.dart): deze draaien in
// de per-regel lus van elke fenced-blok-parser.
final _reFenceInfo = RegExp(r'^\s*```(.*)$');
final _reImageMdAllowEmpty = RegExp(r'!\[[^\]]*\]\(([^)]*)\)');
final _reHtmlTag = RegExp(r'<[^>]+>');

/// Wat één pass over een fenced slide-blok oplevert. De vier fenced slidetypes
/// (code/chart/cockpit/question) delen dezelfde structuur — optionele
/// `# titel`, het fenced blok, optionele afbeelding+bijschrift en `<audio>` —
/// en verschillen alleen in welke velden ze gebruiken en hoe de blok-inhoud
/// wordt getransformeerd.
class _FencedScan {
  String title = '';

  /// Infostring van de openende fence (bij code-slides de taal).
  String fenceInfo = '';
  final content = <String>[];
  String imagePath = '';
  String imageCaption = '';
  String audioPath = '';
  bool audioAutoplay = false;

  String get contentJoined => content.join('\n');
}

/// Scant [remaining] regel voor regel: fence-inhoud gaat naar
/// [_FencedScan.content], daarbuiten worden titel, afbeelding, bijschrift en
/// audio herkend. Velden die een slidetype niet gebruikt, negeert de parser.
_FencedScan _scanFencedBlock(String remaining) {
  final scan = _FencedScan();
  var inFence = false;
  for (final line in remaining.split('\n')) {
    final fence = _reFenceInfo.firstMatch(line);
    if (fence != null) {
      if (!inFence) {
        inFence = true;
        scan.fenceInfo = fence.group(1)!.trim();
      } else {
        inFence = false;
      }
      continue;
    }
    if (inFence) {
      scan.content.add(line);
      continue;
    }
    final t = line.trim();
    if (t.startsWith('# ') && scan.title.isEmpty) {
      scan.title = t.substring(2).trim();
    } else if (t.startsWith('![')) {
      final m = _reImageMdAllowEmpty.firstMatch(t);
      if (m != null) scan.imagePath = m.group(1) ?? '';
    } else if (t.startsWith('<div class="image-caption">')) {
      scan.imageCaption = _decodeCaption(_decodeImageCaption(t));
    } else if (t.startsWith('<audio')) {
      final audio = _parseAudioAttrs(t);
      scan.audioPath = audio.$1;
      scan.audioAutoplay = audio.$2;
    }
  }
  return scan;
}

/// De class-afgeleiden die elke fenced parser nodig heeft: de resterende
/// css-class zonder het type-token en de presentatievlaggen, plus
/// showLogo/showFooter uit de no-logo/no-footer-tokens.
({String effectiveClass, bool showLogo, bool showFooter}) _classFlags(
  String cssClass,
  String typeToken,
) {
  final tokens = cssClass.split(_reWhitespace);
  final effective = tokens
      .where(
        (c) =>
            c.isNotEmpty &&
            c != typeToken &&
            c != 'logo-safe' &&
            c != 'no-logo' &&
            c != 'no-footer',
      )
      .join(' ');
  return (
    effectiveClass: effective,
    showLogo: !tokens.contains('no-logo'),
    showFooter: !tokens.contains('no-footer'),
  );
}

extension _MarkdownFenced on MarkdownService {
  /// Parse a `<!-- _class: code -->` slide: an optional `# title`, the fenced
  /// code block (its info string is the language) and an optional `<audio>`.
  Slide _parseCodeBlock({
    required String remaining,
    required String cssClass,
    required String notes,
    required double advanceDuration,
    required bool skipped,
    TlpLevel tlp = TlpLevel.none,
  }) {
    final scan = _scanFencedBlock(remaining);
    final flags = _classFlags(cssClass, 'code');
    return Slide(
      id: _uuid.v4(),
      type: SlideType.code,
      title: scan.title,
      customMarkdown: scan.contentJoined,
      codeLanguage: scan.fenceInfo,
      audioPath: scan.audioPath,
      audioAutoplay: scan.audioAutoplay,
      cssClass: flags.effectiveClass,
      notes: notes,
      advanceDuration: advanceDuration,
      showLogo: flags.showLogo,
      showFooter: flags.showFooter,
      skipped: skipped,
      tlp: tlp,
    );
  }

  /// Parse a `<!-- _class: chart -->` slide: the fenced ```chart JSON block and
  /// an optional `<audio>`. The JSON is kept verbatim in [Slide.customMarkdown].
  Slide _parseChartBlock({
    required String remaining,
    required String cssClass,
    required String notes,
    required double advanceDuration,
    required bool skipped,
    TlpLevel tlp = TlpLevel.none,
  }) {
    final scan = _scanFencedBlock(remaining);
    final flags = _classFlags(cssClass, 'chart');
    return Slide(
      id: _uuid.v4(),
      type: SlideType.chart,
      customMarkdown: scan.contentJoined.trim(),
      audioPath: scan.audioPath,
      audioAutoplay: scan.audioAutoplay,
      cssClass: flags.effectiveClass,
      notes: notes,
      advanceDuration: advanceDuration,
      showLogo: flags.showLogo,
      showFooter: flags.showFooter,
      skipped: skipped,
      tlp: tlp,
    );
  }

  /// Parse a `<!-- _class: cockpit -->` slide: the fenced ```cockpit JSON block
  /// and an optional `<audio>`. The JSON is kept in [Slide.customMarkdown].
  Slide _parseCockpitBlock({
    required String remaining,
    required String cssClass,
    required String notes,
    required double advanceDuration,
    required bool skipped,
    TlpLevel tlp = TlpLevel.none,
  }) {
    final scan = _scanFencedBlock(remaining);
    final flags = _classFlags(cssClass, 'cockpit');
    return Slide(
      id: _uuid.v4(),
      type: SlideType.cockpit,
      title: scan.title,
      customMarkdown: CockpitSpec.parse(scan.contentJoined.trim()).toBlock(),
      audioPath: scan.audioPath,
      audioAutoplay: scan.audioAutoplay,
      cssClass: flags.effectiveClass,
      notes: notes,
      advanceDuration: advanceDuration,
      showLogo: flags.showLogo,
      showFooter: flags.showFooter,
      skipped: skipped,
      tlp: tlp,
    );
  }

  /// Parse a `<!-- _class: question -->` slide: an optional `# title`, an
  /// optional `![](image)` with caption, and the fenced ```` ```question ````
  /// JSON block (kept in [Slide.customMarkdown]).
  Slide _parseQuestionBlock({
    required String remaining,
    required String cssClass,
    required String notes,
    required double advanceDuration,
    required bool skipped,
    TlpLevel tlp = TlpLevel.none,
    int imageSize = 0,
  }) {
    final scan = _scanFencedBlock(remaining);
    final flags = _classFlags(cssClass, 'question');
    return Slide(
      id: _uuid.v4(),
      type: SlideType.question,
      title: scan.title,
      imagePath: scan.imagePath,
      imageCaption: scan.imageCaption,
      imageSize: imageSize,
      audioPath: scan.audioPath,
      audioAutoplay: scan.audioAutoplay,
      customMarkdown: QuestionSpec.parse(scan.contentJoined.trim()).toBlock(),
      cssClass: flags.effectiveClass,
      notes: notes,
      advanceDuration: advanceDuration,
      showLogo: flags.showLogo,
      showFooter: flags.showFooter,
      skipped: skipped,
      tlp: tlp,
    );
  }

  String _stripInlineHtml(String value) {
    return value.replaceAll(_reHtmlTag, ' ').replaceAll(_reWhitespace, ' ');
  }
}
