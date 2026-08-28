// Part of the markdown_service library — see markdown_service.dart.
// Split out for navigability (deck/block parsing core); all imports live in the main library
// file. These private MarkdownService parse methods relocate verbatim into
// an extension — same library, same members, no behaviour change.
part of 'markdown_service.dart';

// Welke slidetypes hun inhoud als tabel dragen staat níet hier maar in de
// registry naast de enum ([SlideTypeMeta.backedByTable]). De parser hield daar
// een tweede, handgeschreven lijst van bij, en een type daarin vergeten was
// stil verlies: het deck parseerde, de dia verscheen, en de rijen waren leeg.

// Hoisted hot-path regexes: compiled once at library load instead of on every
// line/slide while parsing (they ran in the per-line body loop and the
// slide-type inference, recompiling the same patterns thousands of times).
final _reWhitespace = RegExp(r'\s+');
final _reImageMd = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');
final _reLiItem = RegExp(r'<li[^>]*>(.*?)</li>', caseSensitive: false);
final _reHtmlList = RegExp(r'^</?(ul|ol)(?:\s[^>]*)?>$', caseSensitive: false);
final _reBullet = RegExp(r'^([-*+•◦▪▫–]|\d+[.)])\s+(.+)$');
final _reChecklistMark = RegExp(r'^\[[ xX]\]\s*');
final _reNumberedMark = RegExp(r'^\d+[.)]$');
// Slide splitting moved to the fence-aware MarkdownService.splitSlideBlocks so a
// `---` inside a code fence no longer tears a slide in two; the old
// `\n---\n`-regex split lived here.
final _reBgImage = RegExp(r'!\[bg');
final _reBgImageUrl = RegExp(r'!\[bg[^\]]*\]\(([^)]+)\)');
final _reBgImageSize = RegExp(r'!\[bg[^\]]*?(\d+)%[^\]]*\]');
// Title-column detection (#1405): `![bg left:W%]` / `![bg right:W%]`. Word
// boundaries avoid matching "leftovers" or similar substrings.
final _reBgSide = RegExp(r'!\[bg[^\]]*\b(left|right)\b');
final _reBgSideWidth = RegExp(r'!\[bg[^\]]*?(?:left|right):(\d+)%');
final _reClassDirective = RegExp(r'<!--\s*_class:\s*([^>]+?)\s*-->');
final _reHtmlComment = RegExp(r'<!--([\s\S]*?)-->', multiLine: true);
final _reImageWidthStyle = RegExp(r'--image-width:\s*(\d+)%');

/// `_class`-tokens van opgeheven slidetypes en het type dat ze nu opleveren.
///
/// Het losse 'actions'-type is opgeheven: het was een tabel met een vaste kop en
/// een getypeerde editor eroverheen. De rijen stonden al als gewone
/// Markdown-tabel op schijf, dus een bestaand deck migreert door het token als
/// `table` te lezen — geen dataconversie nodig.
const Map<String, SlideType> _retiredSlideTypeClasses = {
  'actions': SlideType.table,
};

/// Het slidetype dat één `_class`-token aanwijst, of null als het token geen
/// type is (`logo-safe`, `split`-varianten, een eigen CSS-klasse van de auteur).
SlideType? _slideTypeForClassToken(String token) =>
    slideTypeByMarpClass[token] ?? _retiredSlideTypeClasses[token];

/// Het slidetype dat [tokens] declareert: het eerste token dat een type is, of
/// null wanneer geen enkel token dat doet (dan beslist de inhoud).
SlideType? _declaredSlideType(Iterable<String> tokens) {
  for (final token in tokens) {
    final type = _slideTypeForClassToken(token);
    if (type != null) return type;
  }
  return null;
}

/// Mutable accumulator for [_MarkdownParse._parseBodyLines]: the per-line
/// handlers fill these fields as they walk a slide block's body.
class _BodyParse {
  _BodyParse(this.listStyle)
    : richTextHeaderPhase = listStyle == ListStyle.richText;

  String h1 = '';
  String h2 = '';
  String paragraph = '';
  String imagePath = '';
  String imagePath2 = '';
  String imageCaption = '';
  String imageCaption2 = '';
  int imageSize = 0;
  // Title-column side detection (#1405).
  bool sawBgLeft = false;
  bool sawBgRight = false;
  int bgLeftWidth = 0;
  int bgRightWidth = 0;
  String videoPath = '';
  bool videoAutoplay = false;
  int videoStartMs = 0;
  int videoEndMs = 0;
  String audioPath = '';
  bool audioAutoplay = false;
  String quote = '';

  /// Of er al een `>`-regel is gezien. Zonder dit is een citaat dat met een lege
  /// regel begint niet te onderscheiden van "nog geen citaat".
  bool quoteStarted = false;
  String quoteAuthor = '';
  final tableLines = <String>[];
  final richTextLines = <String>[];
  ListStyle listStyle;
  bool richTextHeaderPhase;

  /// Of er een item met een vinkje (`[x]`) of een nummer is gezien, en of er
  /// een gewoon item zonder allebei was. Samen laten ze de zichtbare opmaak de
  /// lijststijl ook naar bénéden bijstellen; zie [_MarkdownParse._parseBodyLines].
  bool sawMarkedItem = false;
  bool sawPlainItem = false;

  /// Of het blok de `split`-class draagt; één keer bepaald in
  /// [_MarkdownParse._parseBodyLines] zodat de per-regel handlers niet elke
  /// regel opnieuw de cssClass hoeven te splitsen.
  bool isSplit = false;

  /// Of we op dit moment binnen `<div class="split-image">` lezen — de stellage
  /// waar de serialiser de zij-afbeelding van een split-slide in zet.
  ///
  /// Nodig sinds de vrije tekst zélf afbeeldingen mag bevatten. Daarvóór gold
  /// "de eerste `![…]` op een split-slide is de zij-afbeelding", en dat is niet
  /// langer waar: een `![…]` in de `split-text`-helft is een afbeelding in de
  /// lopende tekst en hoort in de body te blijven staan.
  ///
  /// Veilig om op de stellage te leunen: deze tak geldt alleen voor een body met
  /// `<!-- ocideck_list_style: richText -->`, en die aanwijzing schrijft alleen
  /// OciDeck zelf — dus staat de `split-image`-div er ook. Een handgeschreven
  /// Marp-split-slide heeft geen richText-body en loopt langs de bullet-tak.
  bool inSplitImageDiv = false;
}

/// Title-column fields derived from native `bg left/right` Marp syntax.
({TitleColumnLayout layout, int width, int imageSize}) _titleColumnFields(
  SlideType type,
  bool sawLeft,
  bool sawRight,
  int leftWidth,
  int rightWidth,
  int imageSize,
) {
  if (type != SlideType.title || (!sawLeft && !sawRight)) {
    return (layout: TitleColumnLayout.none, width: 25, imageSize: imageSize);
  }
  final layout = sawLeft && sawRight
      ? TitleColumnLayout.both
      : sawLeft
      ? TitleColumnLayout.left
      : TitleColumnLayout.right;
  final parsedWidth = sawLeft ? leftWidth : rightWidth;
  return (
    layout: layout,
    width: parsedWidth == 0 ? 25 : parsedWidth,
    imageSize: 0,
  );
}

extension _MarkdownParse on MarkdownService {
  Deck _doParse(String markdown, {String? filePath, String fileHash = ''}) {
    final fm = _parseFrontMatter(markdown);

    final blocks = MarkdownService.splitSlideBlocks(fm.body);
    final slides = <Slide>[];
    for (final block in blocks) {
      final slide = _parseBlock(block.trim());
      if (slide != null) slides.add(slide);
    }

    // Koppel de callout-data uit de front matter aan de slides via hun anchor
    // (IMAGE_CALLOUTS.md §3: callouts leven op de Slide, de front matter is
    // alleen de opslaglocatie). Een slide zonder anchor krijgt geen callouts;
    // een anchor-blok zonder bijbehorende slide is een wees (§2.4) en blijft
    // in de front matter staan — de checker meldt het.
    if (fm.calloutBlock != null && fm.calloutBlock!.present) {
      final byAnchor = <String, CalloutSlideBlock>{};
      for (final blk in fm.calloutBlock!.blocks) {
        byAnchor[blk.anchor] = blk;
      }
      for (var i = 0; i < slides.length; i++) {
        final slide = slides[i];
        if (slide.anchor.isEmpty) continue;
        final blk = byAnchor[slide.anchor];
        if (blk?.typed == null) continue;
        slides[i] = slide.copyWith(
          callouts: blk!.typed!.callouts,
          calloutPresentation: blk.typed!.presentation,
          calloutReveal: blk.typed!.reveal,
        );
      }
    }

    final title =
        fm.presentationTitle ??
        (slides.isNotEmpty && slides.first.title.isNotEmpty
            ? slides.first.title
            : 'Presentatie');

    final projectPath = _projectPathFor(filePath);

    return Deck(
      title: title,
      theme: fm.theme,
      paginate: fm.paginate,
      marpStyle: fm.marpStyle,
      slides: slides.isEmpty ? [Slide.create(SlideType.title)] : slides,
      projectPath: projectPath,
      author: fm.author,
      organization: fm.organization,
      version: fm.version,
      date: fm.date,
      description: fm.description,
      keywords: fm.keywords,
      language: fm.language,
      standardsUsed: fm.standardsUsed,
      toolsUsed: fm.toolsUsed,
      tlp: fm.tlp,
      privacy: fm.privacy,
      presentationTargetSeconds: fm.presentationTargetSeconds.clamp(0, 86400),
      showRehearsalSummary: fm.showRehearsalSummary,
      playOnly: fm.playOnly,
      improvementFramework: fm.improvementFramework,
      improvementY01Metric: ImprovementY01Metric(
        name: fm.improvementY01,
        unit: fm.improvementY01Unit,
        usl: fm.improvementY01Usl,
        lsl: fm.improvementY01Lsl,
        target: fm.improvementY01Target,
        baseline: fm.improvementY01Baseline,
        goal: fm.improvementY01Goal,
      ),
      finalized: fm.finalized,
      sealHash: fm.sealHash,
      sealAlgo: fm.sealAlgo,
      // Een zegel dat nog uit de front matter komt is per definitie van vóór
      // 0.1.0 en gaat dus over de gecanonicaliseerde inhoud. Ligt er een
      // `.seal.json` naast, dan overschrijft die dit bij het openen.
      sealForm: SealForm.canonical,
      sealAt: fm.sealAt,
      sealTimestampToken: fm.sealTsr,
      signature: fm.signature.isEmpty ? null : fm.signature,
      fileHash: fileHash,
      miauw: _legacyMiauwDisposition(fm),
      frontMatterSource: fm.sourceLines,
      formatVersion: fm.formatVersion,
    );
  }

  /// Pulls the image crop focal-point comments out of [block] and returns the
  /// block with those comments removed plus the decoded points (centre default
  /// when absent). Handled here — not in [_parseBlockDirectives] — so the crop
  /// directive is stripped before the generic scan treats it as presenter notes,
  /// without lengthening that already-long method.
  ({double fx, double fy, double fx2, double fy2, int zoom, String block})
  _parseImageFocus(String block) {
    double fx = 0.5, fy = 0.5, fx2 = 0.5, fy2 = 0.5;
    int zoom = 0;
    final cleaned = block.replaceAllMapped(_reHtmlComment, (m) {
      final content = m.group(1)!.trim();
      if (content.startsWith('ocideck_image_focus:')) {
        final p = _parseFocalPair(content.substring(20));
        if (p != null) (fx, fy) = p;
        return '';
      }
      if (content.startsWith('ocideck_image_focus2:')) {
        final p = _parseFocalPair(content.substring(21));
        if (p != null) (fx2, fy2) = p;
        return '';
      }
      if (content.startsWith('ocideck_image_zoom:')) {
        // Clamp at parse like imageSize does (_cappedImageSize): a crafted
        // `<!-- ocideck_image_zoom: 999999 -->` must not blow the layout box.
        zoom = (int.tryParse(content.substring(19).trim()) ?? 0).clamp(0, 400);
        return '';
      }
      return m.group(0)!;
    });
    return (fx: fx, fy: fy, fx2: fx2, fy2: fy2, zoom: zoom, block: cleaned);
  }

  /// Parses an `x,y` image focal-point comment into a clamped (0..1) pair, or
  /// null when the value is malformed (fail-safe: the caller keeps the centre
  /// default). Plain split — no RegExp — so it stays cheap on the parse path.
  (double, double)? _parseFocalPair(String raw) {
    final parts = raw.trim().split(',');
    if (parts.length != 2) return null;
    final x = double.tryParse(parts[0].trim());
    final y = double.tryParse(parts[1].trim());
    if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
    return (x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
  }

  /// Lifts the WCAG alt-text comments (`ocideck_image_alt` / `…_alt2`, AI_ASSIST
  /// §6.1) out of [block] and decodes them (unescaping `-->` like presenter
  /// notes), so the directive is stripped before the generic scan treats it as
  /// notes. Mirrors [_parseImageFocus].
  ({String alt, String alt2, String block}) _parseImageAlt(String block) {
    var alt = '';
    var alt2 = '';
    final cleaned = block.replaceAllMapped(_reHtmlComment, (m) {
      final content = m.group(1)!.trim();
      // `_alt2` first: it is not a prefix of `_alt:` (the colon differs), but the
      // explicit order keeps the intent obvious.
      if (content.startsWith('ocideck_image_alt2:')) {
        alt2 = _unescapeNotes(
          content.substring('ocideck_image_alt2:'.length).trim(),
        );
        return '';
      }
      if (content.startsWith('ocideck_image_alt:')) {
        alt = _unescapeNotes(
          content.substring('ocideck_image_alt:'.length).trim(),
        );
        return '';
      }
      return m.group(0)!;
    });
    return (alt: alt, alt2: alt2, block: cleaned);
  }

  /// The stored body for a parsed slide: free-Markdown and the Informatieveiligheid
  /// scaffold types keep the whole remaining block; a richText bullet slide keeps
  /// its rich-text lines; every other type stores nothing (its own fields hold
  /// the content).
  String _parsedCustomMarkdown(
    SlideType type,
    String remaining,
    ListStyle listStyle,
    List<String> richTextLines,
  ) {
    if (type == SlideType.freeMarkdown ||
        type == SlideType.canvas ||
        type.usesScaffoldMarkdownBody) {
      var body = normalizeRichTextMarkdownForStorage(
        unescapeDeckMarkdownDashLines(remaining),
      );
      // Canvas writes `#` title separately from `##` regions; strip a leading
      // heading so it does not round-trip twice into customMarkdown.
      if (type == SlideType.canvas) {
        body = body.replaceFirst(RegExp(r'^#\s+[^\n]*\n*'), '');
      }
      return body;
    }
    if (listStyle == ListStyle.richText) {
      return normalizeRichTextMarkdownForStorage(
        unescapeDeckMarkdownDashLines(richTextLines.join('\n').trim()),
      );
    }
    return '';
  }

  /// The image size (`![bg N%]`) to store: the body value, or the `_style`
  /// `--image-width` when absent. `0` stays "auto"; capped at 400% so a crafted
  /// `![bg 900000%]` can't blow the layout box up.
  int _cappedImageSize(int bodySize, int styleImageWidth) {
    final size = bodySize == 0 && styleImageWidth > 0
        ? styleImageWidth
        : bodySize;
    return size > 400 ? 400 : size;
  }

  /// De projectmap van een deck: de map waarin het `.md`-bestand staat. Assets
  /// (afbeeldingen, thema's) worden daar relatief aan opgelost.
  static String? _projectPathFor(String? filePath) {
    if (filePath == null) return null;
    final sep = filePath.contains('/') ? '/' : '\\';
    final parts = filePath.split(sep);
    if (parts.length <= 1) return null;
    return parts.sublist(0, parts.length - 1).join(sep);
  }

  /// De slidetypes met een eigen gestructureerde body (chart, cockpit, finding,
  /// …), of null wanneer dit blok er geen is. Uitgetild uit [_parseBlock] om die
  /// binnen de lengte-ratchet te houden — en omdat het één samenhangend geval is.
  Slide? _structuredSlideOrNull(
    _BlockDirectives d,
    ({
      String findingId,
      FindingRole findingRole,
      List<String> aiAssistedFields,
      String checklistScope,
      String block,
    })
    link,
  ) {
    final structured = _tryStructuredSlide(
      cssClass: d.cssClass,
      remaining: d.remaining,
      notes: d.notes,
      advanceDuration: d.advanceDuration,
      skipped: d.skipped,
      isDetail: d.isDetail,
      tlp: d.tlp,
      styleImageWidth: d.styleImageWidth,
      findingId: link.findingId,
      findingRole: link.findingRole,
    );
    if (structured == null) return null;
    // De dispositie hangt aan de slide, niet aan het slidetype. Hier zetten in
    // plaats van door elke fenced-parser rijgen: één plek, geen gaten.
    return structured.copyWith(
      aiAssistedFields: link.aiAssistedFields,
      privacy: d.privacy,
      quality: d.quality,
      preservedMarpLines: d.preservedMarpLines,
      marpStyle: d.marpStyle,
    );
  }

  Slide? _parseBlock(String block) {
    if (block.isEmpty) return null;
    if (requiresWholeMarpBlockPreservation(block)) {
      return Slide(
        id: _uuid.v4(),
        type: SlideType.freeMarkdown,
        customMarkdown: block,
      );
    }

    // Lift the crop focal points and finding-group link out first, so those
    // directives are stripped before the generic comment scan would otherwise
    // read them as presenter notes.
    final focus = _parseImageFocus(block);
    final alt = _parseImageAlt(focus.block);
    final link = _parseFindingLink(alt.block);
    final d = _parseBlockDirectives(link.block);

    // Fenced (code/chart/cockpit/question) and finding-header slides carry
    // structured bodies the generic line parser below would mangle; they are
    // parsed up front from their class token.
    final structured = _structuredSlideOrNull(d, link);
    if (structured != null) return structured;

    final classTokens = d.cssClass.split(_reWhitespace);
    // De zichtbare kolommen zijn de inhoud. Alleen als er géén lijst-HTML staat
    // — een oud bestand waarvan de opmaak is weggeknipt, of een handgeschreven
    // blok met gewone Markdown-bullets — telt wat er verder in het blok stond.
    final columns = _declaredSlideType(classTokens) == SlideType.twoBullets
        ? _parseTwoColumnBullets(d.remaining)
        : null;
    final visibleColumns = columns != null && columns.found;
    // bullets may already hold the decoded two-column data; the line parser
    // appends to the same list, so pass it through by reference.
    final bullets = visibleColumns ? columns.left : d.bullets;
    final bullets2 = visibleColumns ? columns.right : d.bullets2;
    final body = _parseBodyLines(
      d.remaining.split('\n'),
      d.cssClass,
      d.listStyle,
      bullets,
      // Staat de inhoud al in de kolommen, dan zou de generieke regelwandeling
      // elk `<li>` van béíde kolommen nog eens op één hoop gooien.
      skipContentLines: visibleColumns,
    );

    final imageSize = _cappedImageSize(body.imageSize, d.styleImageWidth);

    final tableDecoded = _decodeTableWithAlignment(body.tableLines);
    final tableRows = tableDecoded.rows;
    // Vul de uitlijning aan tot het aantal kolommen: een scheidingsrij zonder
    // colons leverde een lege lijst op, en een raggede scheidingsrij een
    // kortere — beide behandelen we als "links" (de GFM-default).
    final colCount = tableRows.fold<int>(
      0,
      (m, r) => r.length > m ? r.length : m,
    );
    final tableAlignments = List<TableAlign>.generate(
      colCount,
      (c) => c < tableDecoded.alignments.length
          ? tableDecoded.alignments[c]
          : TableAlign.left,
    );

    final type = _inferSlideType(
      cssClass: d.cssClass,
      quote: body.quote,
      imagePath: body.imagePath,
      imagePath2: body.imagePath2,
      bullets: bullets,
      listStyle: body.listStyle,
      videoPath: body.videoPath,
      tableRows: tableRows,
      h1: body.h1,
      h2: body.h2,
      paragraph: body.paragraph,
    );

    final titleColumns = _titleColumnFields(
      type,
      body.sawBgLeft,
      body.sawBgRight,
      body.bgLeftWidth,
      body.bgRightWidth,
      imageSize,
    );
    final showLogo = !classTokens.contains('no-logo');
    final showFooter = !classTokens.contains('no-footer');
    final imageTitleAbove =
        type == SlideType.image && classTokens.contains('image-title-above');

    final effectiveClass = classTokens
        .where(
          (c) =>
              c.isNotEmpty &&
              c != type.marpClass &&
              !isOcideckWrittenClassToken(c),
        )
        .join(' ');

    return Slide(
      id: _uuid.v4(),
      type: type,
      title: body.h1,
      subtitle: type == SlideType.section ? body.paragraph : body.h2,
      bullets: bullets,
      bullets2: bullets2,
      // De zichtbare opmaak beslist over de lijststijl zodra ze er iets over
      // zegt; de richtlijn is niet meer dan de startwaarde.
      listStyle: visibleColumns
          ? (columns.listStyle ?? body.listStyle)
          : body.listStyle,
      showChecklistProgress: d.showChecklistProgress,
      continueNumbering: d.continueNumbering,
      continuesSplit: d.continuesSplit,
      // Een zichtbare `<h3>` boven een kolom is de kop; alleen zonder kolommen
      // telt de oude base64-richtlijn nog.
      columnTitle1: visibleColumns ? columns.leftTitle : d.columnTitle1,
      columnTitle2: visibleColumns ? columns.rightTitle : d.columnTitle2,
      imagePath: body.imagePath,
      imagePath2: body.imagePath2,
      imageCaption: body.imageCaption,
      imageCaption2: body.imageCaption2,
      imageAltText: alt.alt,
      imageAltText2: alt.alt2,
      imageFocalX: focus.fx,
      imageFocalY: focus.fy,
      imageFocalX2: focus.fx2,
      imageFocalY2: focus.fy2,
      imageZoom: focus.zoom,
      imageSize: titleColumns.imageSize,
      titleImageOverlay: d.titleImageOverlay,
      imageTitleAbove: imageTitleAbove,
      titleTextColorOverride: d.titleTextColorOverride,
      titleColumnLayout: titleColumns.layout,
      titleColumnWidth: titleColumns.width,
      bulletMarkerOverride: d.bulletMarkerOverride,
      videoPath: body.videoPath,
      videoAutoplay: body.videoAutoplay,
      videoStartMs: body.videoStartMs,
      videoEndMs: body.videoEndMs,
      audioPath: body.audioPath,
      audioAutoplay: body.audioAutoplay,
      quote: body.quote,
      quoteAuthor: body.quoteAuthor,
      customMarkdown: _parsedCustomMarkdown(
        type,
        d.remaining,
        body.listStyle,
        body.richTextLines,
      ),
      cssClass: effectiveClass,
      notes: d.notes,
      preservedMarpLines: d.preservedMarpLines,
      marpStyle: d.marpStyle,
      advanceDuration: d.advanceDuration,
      showLogo: showLogo,
      showFooter: showFooter,
      skipped: d.skipped,
      isDetail: d.isDetail,
      tlp: d.tlp,
      privacy: d.privacy,
      quality: d.quality,
      tableRows: type.backedByTable ? tableRows : const [],
      tableColumnAlignments: type.backedByTable ? tableAlignments : const [],
      tableNumberColumns: type == SlideType.table
          ? d.tableNumberColumns
          : const [],
      tableEditable:
          type == SlideType.table && classTokens.contains('table-editable'),
      tableMarkOverdue:
          type == SlideType.table && classTokens.contains('table-overdue'),
      viewLimit: d.viewLimit,
      menuLayout: type == SlideType.menu
          ? menuLayoutFromTokens(classTokens)
          : MenuLayout.grid,
      timelineLayout: type == SlideType.timeline
          ? timelineLayoutFromTokens(classTokens)
          : TimelineLayout.auto,
      timelineReveal: type == SlideType.timeline
          ? timelineRevealFromTokens(classTokens)
          : TimelineReveal.onEnter,
      timelineAnimationMs: d.timelineAnimationMs,
      timelineCurrentIndex: d.timelineCurrentIndex,
      findingId: link.findingId,
      findingRole: link.findingRole,
      aiAssistedFields: link.aiAssistedFields,
      checklistScope: link.checklistScope,
      // Alleen op een engine-dia betekenisvol; elders zou een meegelift
      // sjabloon-id een gewone tabel als matrix laten heropenen.
      improvementTemplateId: type.category == SlideCategory.procesverbetering
          ? d.improvementTemplateId
          : '',
      improvementLayout: type.category == SlideCategory.procesverbetering
          ? d.improvementLayout
          : '',
      anchor: d.anchor,
      nextAnchor: d.nextAnchor,
      ganttScale: type == SlideType.gantt ? d.ganttScale : ganttScaleAuto,
      ganttSections: type == SlideType.gantt && d.ganttSections,
    );
  }

  /// Structured slide types whose body the generic line parser would mangle:
  /// the fenced blocks (code/chart/cockpit/question) delegate to their own
  /// verbatim-body parsers, and a `finding` header is parsed as one opaque
  /// Markdown body. Returns the parsed slide, or null when [cssClass] is none of
  /// them (the caller falls through to the generic line walker).
  Slide? _tryStructuredSlide({
    required String cssClass,
    required String remaining,
    required String notes,
    required double advanceDuration,
    required bool skipped,
    required bool isDetail,
    required TlpLevel tlp,
    required int styleImageWidth,
    required String findingId,
    required FindingRole findingRole,
  }) {
    // Ook hier beslist de registry welk token welk type is; zie
    // [_declaredSlideType]. Vier types dragen een eigen fenced body.
    switch (_declaredSlideType(cssClass.split(_reWhitespace))) {
      case SlideType.code:
        return _parseCodeBlock(
          remaining: remaining,
          cssClass: cssClass,
          notes: notes,
          advanceDuration: advanceDuration,
          skipped: skipped,
          isDetail: isDetail,
          tlp: tlp,
        );
      case SlideType.chart:
        return _parseChartBlock(
          remaining: remaining,
          cssClass: cssClass,
          notes: notes,
          advanceDuration: advanceDuration,
          skipped: skipped,
          isDetail: isDetail,
          tlp: tlp,
        );
      case SlideType.cockpit:
        return _parseCockpitBlock(
          remaining: remaining,
          cssClass: cssClass,
          notes: notes,
          advanceDuration: advanceDuration,
          skipped: skipped,
          isDetail: isDetail,
          tlp: tlp,
        );
      case SlideType.question:
        return _parseQuestionBlock(
          remaining: remaining,
          cssClass: cssClass,
          notes: notes,
          advanceDuration: advanceDuration,
          skipped: skipped,
          isDetail: isDetail,
          tlp: tlp,
          imageSize: styleImageWidth,
        );
      default:
        break;
    }
    return _tryFindingSlide(
      cssClass: cssClass,
      remaining: remaining,
      notes: notes,
      advanceDuration: advanceDuration,
      skipped: skipped,
      isDetail: isDetail,
      tlp: tlp,
      findingId: findingId,
      findingRole: findingRole,
    );
  }
}

/// De v1-front-matter-kaarten als ongedateerde dispositie: het opwaardeerpad
/// voor een `.md` van vóór de sidecar. Top-level en geen methode: de klasse
/// zit tegen haar plafond, en dit raakt geen enkele parserstaat.
MiauwDisposition _legacyMiauwDisposition(_FrontMatter fm) =>
    MiauwDisposition.fromTexts(
      fm.legacyMiauwWaivers,
      fm.legacyMiauwConfirmations,
    );
