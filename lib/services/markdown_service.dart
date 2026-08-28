import 'dart:convert';
import 'package:characters/characters.dart';
import 'package:uuid/uuid.dart';
import '../models/chart.dart';
import '../models/cockpit.dart';
import '../models/deck.dart';
import '../models/improvement_y01.dart';
import '../models/marp_style.dart';
import '../models/menu.dart';
import '../models/privacy_disposition.dart';
import '../models/quality_disposition.dart';
import '../models/display_window_spec.dart';
import '../services/display_window_service.dart';
import '../models/document_signature.dart';
import '../models/finding_spec.dart';
import '../models/seal_record.dart';
import '../models/question.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import 'improvement/gantt_dsl.dart';
import '../models/used_tool.dart';
import '../models/timeline.dart';
import '../models/video_source.dart';
import 'front_matter_merge.dart';
import 'callout_codec.dart';
import 'markdown_front_matter_codec.dart';
import 'markdown_table_codec.dart';
import 'marp_source_preservation.dart';
import 'miauw_codec.dart';
import '../utils/content_hash.dart';
import '../utils/deck_markdown_dashes.dart';
import '../utils/log.dart';
import '../utils/markdown_paste_cleanup.dart';

part 'markdown_service_helpers.dart';
part 'markdown_service_parse.dart';
part 'markdown_parse/markdown_service_parse_body.dart';
part 'markdown_parse/markdown_service_parse_directives.dart';
part 'markdown_parse/markdown_service_parse_columns.dart';
part 'markdown_parse/markdown_service_parse_front_matter.dart';
part 'markdown_service_finding.dart';
part 'markdown_service_fenced.dart';
part 'markdown_service_serialize.dart';

const _uuid = Uuid();

/// Converts between a [Deck] and the Marp Markdown on disk, in both directions.
///
/// This class is where OciDeck's central premise lives: the `.md` is the source
/// of truth, and everything the editor knows must survive a round trip through
/// it. The contract is therefore **lossless in both directions** — parse a file
/// and serialise it back and you get the same bytes, apart from normalisation
/// this class performs deliberately. The round-trip tests exist to keep that
/// true; treat a failure there as a defect in this class, not in the test.
///
/// Anything Marp itself does not define is carried in places Marp ignores —
/// front-matter keys and HTML comments — so a deck stays readable by other Marp
/// tooling. See `docs/FILE_FORMAT.md` for the format this class implements; it
/// is the specification, and this class is the implementation of it.
///
/// What not to expect: it does not render (that is `marp_html_service.dart`),
/// it does not touch the filesystem (that is [FileService]), and it does not
/// validate a deck's *meaning* — a structurally valid deck that says something
/// silly parses fine.
class MarkdownService {
  // ── Generation ──────────────────────────────────────────────────────────────

  /// Serialise a deck to Marp markdown.
  ///
  /// The styling (the [ThemeProfile]) is deliberately NOT written: een `.md`
  /// draagt alleen de inhoud (de "basis"), en de app legt er het actieve
  /// stijlprofiel overheen bij het openen. De beamer-payload — de enige lezer
  /// die de styling nergens anders vandaan kan halen — krijgt het profiel naast
  /// de markdown mee in dezelfde boodschap; zie `buildBeamerMarkdown`.
  String generateDeck(
    Deck deck, {
    bool inlineChartData = false,
    bool forExport = false,
    bool includeFormatVersion = true,
    bool legacySignatureLines = false,
  }) {
    final buf = StringBuffer();
    buf.writeln('---');
    // De front matter wordt niet opnieuw opgebouwd maar chirurgisch bijgewerkt:
    // alleen de sleutels die OciDeck bezit gaan door de generator, elke andere
    // regel uit het geopende bestand blijft staan waar hij stond.
    for (final line in mergeFrontMatter(
      original: deck.frontMatterSource,
      generated: ownedFrontMatterLines(
        deck,
        includeFormatVersion: includeFormatVersion,
        legacySignatureLines: legacySignatureLines,
      ),
    )) {
      buf.writeln(line);
    }
    buf.writeln('---');
    buf.writeln();

    // Een render-kopie van een vrije-tekstpagina heeft geen gedaante in het
    // bestandsformaat: hij draagt de héle body en verschilt alleen in
    // [Slide.renderPage], dat niet geserialiseerd wordt. Wie zo'n lijst tóch
    // uitschrijft, krijgt dezelfde dia N keer achter elkaar met steeds de
    // volledige tekst. De filter staat hier en niet bij de aanroeper, want de
    // regel geldt overal: `expandRichTextForRender` levert een lijst om te
    // tékenen, nooit om weg te schrijven.
    final slides = [
      for (final slide in deck.slides)
        if (slide.renderPage == 0) slide,
    ];
    for (int i = 0; i < slides.length; i++) {
      if (i > 0) {
        buf.writeln('---');
        buf.writeln();
      }
      buf.write(
        generateSlide(
          slides[i],
          themeProfile: deck.themeProfile,
          inlineChartData: inlineChartData,
          forExport: forExport,
        ),
      );
    }
    return buf.toString();
  }

  /// De inhoudstekst waarover een zegel van vóór 0.1.0 werd gehasht: de
  /// markdown van het deck zonder de zegelvelden, zonder de formaatversie en
  /// zonder de front matter van de gebruiker.
  ///
  /// **Alleen nog om zo'n oud zegel te blijven controleren.** Nieuwe zegels gaan
  /// over de bytes van de `.md` ([DocumentIntegrity]); dit is precies de vorm
  /// die dat verving. Ze was nergens vastgelegd behalve in deze methode, dus
  /// niemand buiten OciDeck kon haar narekenen, en elke wijziging aan de
  /// serialisator zou "intact" stil in "gemanipuleerd" veranderen. Dat is dan
  /// ook de reden dat deze code niet meer mag bewegen: hij is geen serialisatie
  /// maar een archiefstuk.
  ///
  /// De zegelvelden zelf vallen erbuiten zodat de hash niet circulair is; de
  /// formaatversie omdat die de codering beschrijft en niet de inhoud; en de
  /// front matter van de gebruiker — een eigen `style: |`-blok, commentaar, een
  /// handmatige `header:` — omdat een zegel dat op andermans regels afgaat, vals
  /// alarm slaat zodra iemand zijn eigen CSS bijstelt.
  ///
  /// Die laatste uitzondering geldt alleen hier, in de oude vorm. Een hash over
  /// het bestand kan geen regels overslaan zonder dat het oordeel van OciDeck
  /// gaat afwijken van dat van de ontvanger, en juist dat verschil was de reden
  /// om te verhuizen. Wat het valse alarm daar wegneemt is de bevriezing zelf:
  /// een afgerond deck is alleen-lezen. Zie docs/FILE_FORMAT.md §6.6.
  String canonicalContentForSeal(Deck deck) {
    return generateDeck(
      includeFormatVersion: false,
      // De zegelsleutels schrijft de generator niet meer, dus die vallen hier
      // vanzelf buiten; de handtekening viel er destijds juist ónder en moet er
      // dus bij. Leeggemaakte [frontMatterSource] zodat mergeFrontMatter niets
      // te bewaren heeft.
      legacySignatureLines: true,
      deck.copyWith(frontMatterSource: const []),
    );
  }

  /// Write [rows] as a GitHub-flavoured markdown table (first row = header).
  /// [alignments] zet de GFM-scheidingsrij met colons (`:---`/`:---:`/`---:`);
  /// leeg of korter dan het aantal kolommen = kale `---` (GFM-default = links).
  void _writeTable(
    StringBuffer buf,
    List<List<String>> rows, {
    List<TableAlign>? alignments,
  }) {
    if (rows.isEmpty) return;
    final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    if (colCount == 0) return;

    String cell(List<String> row, int c) =>
        encodeMarkdownTableCell(c < row.length ? row[c] : '');

    String renderRow(List<String> row) =>
        '| ${List.generate(colCount, (c) => cell(row, c)).join(' | ')} |';

    buf.writeln(renderRow(rows.first));
    buf.writeln(markdownTableSeparatorRow(colCount, alignments));
    for (var i = 1; i < rows.length; i++) {
      buf.writeln(renderRow(rows[i]));
    }
  }

  /// De per-slide classificaties: TLP (welke slides achtergehouden worden bij
  /// een lager deelniveau) en de privacydispositie. Beide reizen mee in de
  /// markdown, zodat de keuze het bestand niet verlaat.
  ///
  /// De dispositie wordt alleen geschreven als de slide er een heeft; `null`
  /// betekent "erf de stand van het deck", en dat schrijven zou elke bestaande
  /// .md bij het eerste opslaan dikker maken zonder dat er iets veranderd is.
  /// De markeringen die bepalen of een slide het publiek bereikt: overslaan en
  /// verdieping. Beide alleen geschreven wanneer ze aanstaan, zodat een deck dat
  /// ze niet gebruikt byte-identiek blijft. (TLP schrijft
  /// [_writeSlideClassification].)
  void _writeAudienceMarkers(StringBuffer buf, Slide slide) {
    if (slide.skipped) {
      buf.writeln();
      buf.writeln('<!-- skip -->');
    }
    if (slide.isDetail) {
      buf.writeln();
      buf.writeln('<!-- ocideck_detail -->');
    }
  }

  void _writeSlideClassification(StringBuffer buf, Slide slide) {
    if (slide.tlp != TlpLevel.none) {
      buf.writeln();
      buf.writeln('<!-- tlp: ${slide.tlp.key} -->');
    }
    final privacy = slide.privacy;
    if (privacy != null) {
      buf.writeln();
      buf.writeln('<!-- ocideck_privacy: ${privacy.key} -->');
    }
    if (slide.quality.isResolved) {
      buf.writeln();
      buf.writeln('<!-- ocideck_quality: ${slide.quality.key} -->');
    }
  }

  String generateSlide(
    Slide slide, {
    ThemeProfile? themeProfile,
    bool inlineChartData = false,
    bool forExport = false,
  }) {
    // De export krijgt de projectie, en dan zónder het directief: een
    // al-toegepaste limiet die als ocideck_view_* blijft meereizen vuurt bij
    // de ontvanger opnieuw — over het ingebakken bijschrift en de Overig-rij
    // heen, die dan als data meedingen (bewaker-bevinding #672). Het
    // geëxporteerde .md is wat de ontvanger ziet, zonder verborgen hendel.
    final activeSlide = forExport
        ? slide.projectionWithViewLimit().copyWith(clearViewLimit: true)
        : slide;
    return _generateSlideImpl(
      activeSlide,
      themeProfile: themeProfile,
      inlineChartData: inlineChartData,
      forExport: forExport,
    );
  }

  String _generateSlideImpl(
    Slide slide, {
    ThemeProfile? themeProfile,
    bool inlineChartData = false,
    bool forExport = false,
  }) {
    final buf = StringBuffer();
    final cssClass = slide.cssClass.isNotEmpty
        ? slide.cssClass
        : slide.type.marpClass;
    final hasLogo = themeProfile?.logoPath?.isNotEmpty == true;
    final classes = [
      if (cssClass.isNotEmpty) cssClass,
      // Reserve logo space only when the logo is actually shown on this slide.
      if (hasLogo && slide.showLogo) 'logo-safe',
      // Mark slides that opt out of the logo so the theme can hide it.
      if (hasLogo && !slide.showLogo) 'no-logo',
      // Mark slides that opt out of the footer. Older presentations lack this
      // token and therefore keep the existing default: footer shown.
      if (!slide.showFooter) 'no-footer',
      // Image slide with the title above the image instead of overlaid on it.
      if (slide.type == SlideType.image && slide.imageTitleAbove)
        'image-title-above',
      // Table slides that may be edited live during a presentation. Absent by
      // default, so tables stay read-only unless the author opts in.
      if (slide.type == SlideType.table && slide.tableEditable)
        'table-editable',
      // Table slides that mark expired ISO dates. Absent by default, so an
      // existing table never changes appearance.
      if (slide.type == SlideType.table && slide.tableMarkOverdue)
        'table-overdue',
      // Timeline layout/animation options ride along as extra class tokens so
      // they round-trip without a JSON block (the base `timeline` token comes
      // from marpClass above).
      if (slide.type == SlideType.timeline)
        ...timelineClassTokens(slide.timelineLayout, slide.timelineReveal),
      // Keuze-menu-indeling (#1162) rijdt op dezelfde manier mee; `grid` is de
      // standaard en schrijft niets, zodat bestaande menudia's niet wijzigen.
      if (slide.type == SlideType.menu) ...menuClassTokens(slide.menuLayout),
    ];

    _writeSlideDirectives(buf, slide, classes, forExport);

    switch (slide.type) {
      case SlideType.title:
        _writeTitleSlide(buf, slide);
      case SlideType.section:
        _writeSectionSlide(buf, slide);
      case SlideType.bullets:
        _writeBulletsSlide(buf, slide, themeProfile, forExport);
      // Een keuze-menu (#1162) bewaart zijn blokken als gewone link-bullets, dus
      // schrijft het weg als een bullets-dia; de `_class: menu` uit marpClass
      // onderscheidt het bij het teruglezen.
      case SlideType.menu:
        _writeBulletsSlide(buf, slide, themeProfile, forExport);
      case SlideType.twoBullets:
        _writeTwoBulletsSlide(buf, slide, themeProfile, forExport);
      case SlideType.bulletsImage:
        _writeBulletsImageSlide(buf, slide, themeProfile, forExport);
      case SlideType.twoImages:
        _writeTwoImagesSlide(buf, slide);
      case SlideType.image:
        _writeImageSlide(buf, slide);
      case SlideType.video:
        _writeVideoSlide(buf, slide, forExport);
      case SlideType.quote:
        _writeQuoteSlide(buf, slide);
      case SlideType.table:
        _writeTableSlide(buf, slide);
      case SlideType.freeMarkdown:
        _writeFreeMarkdownSlide(buf, slide);
      case SlideType.code:
        _writeCodeSlide(buf, slide);
      case SlideType.chart:
        _writeChartSlide(buf, slide, inlineChartData);
      case SlideType.cockpit:
        _writeCockpitSlide(buf, slide);
      case SlideType.timeline:
        _writeTimelineSlide(buf, slide);
      case SlideType.question:
        _writeQuestionSlide(buf, slide);
      // Zie [_writeTableSlide] voor waarom deze zeven hetzelfde wegschrijven.
      case SlideType.scorecard:
      case SlideType.assets:
      case SlideType.discoveries:
      case SlideType.checklist:
      case SlideType.scopeMatrix:
      case SlideType.controlStatus:
      case SlideType.findingsSummary:
      // Een matrix is óók echt een Markdown-tabel (PROCESS_IMPROVEMENT §3.1):
      // het sjabloon rijdt mee als commentaar, de afgeleide kolom (RPN) wordt
      // niet geschreven — die staat niet in [Slide.tableRows].
      case SlideType.matrix:
        _writeTableSlide(buf, slide);
      case SlideType.gantt:
        _writeTableSlide(buf, slide);
      case SlideType.signOff:
        _writeSignOffSlide(buf, slide);
      case SlideType.finding:
        _writeScaffoldSlide(buf, slide);
      case SlideType.canvas:
        _writeCanvasSlide(buf, slide);
      case SlideType.tree:
      case SlideType.flow:
      case SlideType.phaseGate:
        _writeBulletsSlide(buf, slide, themeProfile, forExport);
    }

    if (slide.audioPath.isNotEmpty) {
      final autoplay = slide.audioAutoplay ? ' autoplay' : '';
      buf.writeln();
      buf.writeln(
        '<audio src="${slide.audioPath}" controls$autoplay style="width:100%;"></audio>',
      );
    }

    if (slide.advanceDuration > 0) {
      buf.writeln();
      buf.writeln(
        '<!-- advance: ${slide.advanceDuration.toStringAsFixed(1)} -->',
      );
    }

    _writeAudienceMarkers(buf, slide);

    _writeSlideClassification(buf, slide);

    if (slide.notes.isNotEmpty) {
      buf.writeln();
      buf.writeln('<!--');
      buf.writeln(_escapeNotes(slide.notes));
      buf.writeln('-->');
    }

    buf.writeln();
    final generated = buf.toString();
    if (!slide.marpStyle.headingFit) return generated;
    return generated.replaceFirstMapped(
      RegExp(r'^(#{1,6}\s+.*)$', multiLine: true),
      (match) => '${match.group(1)}\n<!-- fit -->',
    );
  }

  // ── Parsing ─────────────────────────────────────────────────────────────────

  /// Best-effort parse of Marp markdown into a Deck. Returns null if the
  /// content cannot be parsed at all.
  Deck? parseDeck(String markdown, {String? filePath}) {
    // Normalise line endings up front. A Windows (CRLF) or classic-Mac (CR)
    // file would otherwise miss the `---\n` frontmatter start and the
    // `\n---\n` slide separators, collapsing the whole deck into one block.
    final normalized = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    try {
      // De zegelhash gaat over de bytes zoals ze binnenkwamen, niet over de
      // genormaliseerde tekst: een `.md` met CRLF is een ánder bestand, en het
      // zegel hoort dat te zeggen in plaats van het weg te poetsen.
      return _doParse(
        normalized,
        filePath: filePath,
        fileHash: sha512HexOfText(markdown),
      );
    } catch (e, s) {
      logError('MarkdownService.parseDeck: parse markdown', e, s);
      return null;
    }
  }

  /// Splits a deck body (front matter already stripped) into slide blocks on
  /// lines that are exactly `---`, but never when that `---` sits inside a
  /// fenced code block (```` ``` ```` or `~~~`). A separator-looking line inside
  /// a code sample, a diff hunk or an embedded YAML document therefore no longer
  /// tears the slide in two. Shared with the markdown validator so the checker
  /// and the parser agree on exactly where the slide boundaries are.
  static List<String> splitSlideBlocks(String body) {
    final lines = body.split('\n');
    final blocks = <String>[];
    final current = <String>[];
    String? fenceChar; // '`' or '~' while inside a fence, else null.
    var fenceLen = 0; // de lengte van de openende rij, zie [isBareFence].
    for (final line in lines) {
      final trimmed = line.trimLeft();
      if (fenceChar == null) {
        if (line == '---') {
          blocks.add(current.join('\n'));
          current.clear();
          continue;
        }
        if (trimmed.startsWith('```')) {
          fenceChar = '`';
          fenceLen = _leadingRun(trimmed, '`');
        } else if (trimmed.startsWith('~~~')) {
          fenceChar = '~';
          fenceLen = _leadingRun(trimmed, '~');
        }
      } else if (isBareFence(trimmed, fenceChar) &&
          trimmed.length >= fenceLen) {
        // Alleen een rij die minstens even lang is sluit het blok. Een kortere
        // rij binnenin is inhoud — precies waarvoor CommonMark langere fences
        // heeft — en mag de slide dus niet in tweeën scheuren.
        fenceChar = null;
        fenceLen = 0;
      }
      current.add(line);
    }
    blocks.add(current.join('\n'));
    return blocks;
  }

  /// Hoeveel [char]s [trimmed] achter elkaar begint.
  static int _leadingRun(String trimmed, String char) {
    var n = 0;
    while (n < trimmed.length && trimmed[n] == char) {
      n++;
    }
    return n;
  }

  /// True when [trimmed] is a bare fence line: three or more of [fenceChar] and
  /// nothing else. An opening ```` ```dart ```` carries an info string, so it
  /// never reads as a closing fence.
  static bool isBareFence(String trimmed, String fenceChar) {
    if (trimmed.length < 3) return false;
    for (var i = 0; i < trimmed.length; i++) {
      if (trimmed[i] != fenceChar) return false;
    }
    return true;
  }

  /// Cheap frontmatter probe for the disk-wide presentation scan: reads only the
  /// `--- … ---` header (no slide body, no Deck construction) and reports whether
  /// the file declares `marp: true`, plus its `theme`/`title`. [head] may be a
  /// truncated prefix of the file — if the closing `---` is missing we still
  /// parse whatever header lines are present.
  ({bool marp, String? theme, String? title}) sniffFrontmatter(String head) {
    final norm = head.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (!norm.startsWith('---\n')) {
      return (marp: false, theme: null, title: null);
    }
    final end = norm.indexOf('\n---\n', 4);
    final frontMatter = end == -1 ? norm.substring(4) : norm.substring(4, end);

    bool marp = false;
    String? theme;
    String? title;
    for (final rawLine in frontMatter.split('\n')) {
      // Sleutels op kolom 0, net als de volledige parse: een ingesprongen regel
      // hoort bij het blok erboven en is geen deck-veld.
      final key = frontMatterKeyOf(rawLine);
      if (key == null) continue;
      final value = rawLine.substring(rawLine.indexOf(':') + 1).trim();
      switch (key) {
        case 'marp':
          marp = value == 'true';
        case 'theme':
          theme = value;
        case 'title':
          title = parseMarkdownYamlScalar(value);
      }
    }
    return (marp: marp, theme: theme, title: title);
  }
}

/// De directive-commentaren bovenaan een slide, plus de scheidingsregel erna.
///
/// Top-level en niet op [MarkdownService]: hij raakt geen instantiestaat, en
/// de klasse zit tegen haar plafond (#672 duwde eroverheen).
void _writeSlideDirectives(
  StringBuffer buf,
  Slide slide,
  List<String> classes,
  bool forExport,
) {
  if (classes.isNotEmpty) {
    buf.writeln('<!-- _class: ${classes.join(' ')} -->');
  }
  if (slide.marpStyle.hasColor) {
    buf.writeln('<!-- _color: ${slide.marpStyle.color} -->');
  }
  if (slide.marpStyle.hasBackgroundColor) {
    buf.writeln(
      '<!-- _backgroundColor: ${slide.marpStyle.backgroundColor} -->',
    );
  }
  if (slide.marpStyle.hasBackgroundImage) {
    buf.writeln(
      '<!-- _backgroundImage: ${slide.marpStyle.backgroundImage} -->',
    );
  }
  if (slide.marpStyle.hasHeader) {
    buf.writeln('<!-- _header: ${slide.marpStyle.header} -->');
  }
  if (slide.marpStyle.hasFooter) {
    buf.writeln('<!-- _footer: ${slide.marpStyle.footer} -->');
  }
  for (final line in slide.preservedMarpLines) {
    buf.writeln(line);
  }
  // Finding-group linkage (PENTEST_MIAUW §3.1): a shared id + role tie a
  // header card to its detail/evidence slides. Written for any slide that
  // joins a group — a `finding` header, but also a `bullets` detail or an
  // `image` evidence slide — so the whole group round-trips as a unit. Role is
  // only meaningful alongside an id, so both ride together.
  if (slide.findingId.isNotEmpty) {
    buf.writeln('<!-- ocideck_finding_id: ${slide.findingId} -->');
    buf.writeln('<!-- ocideck_finding_role: ${slide.findingRole.name} -->');
  }
  // Niet-lineaire navigatie (#1162): het stabiele anker waar deze dia van een
  // menublok of sprong-uit het doel van kan zijn, en de eigen sprong-uit. Beide
  // leeg = een gewone lineaire dia zonder anker; dan schrijven we niets.
  if (slide.anchor.isNotEmpty) {
    buf.writeln('<!-- ocideck_slide_anchor: ${slide.anchor} -->');
  }
  if (slide.nextAnchor.isNotEmpty) {
    buf.writeln('<!-- ocideck_next: ${slide.nextAnchor} -->');
  }
  // Taalbewuste getalnotatie (opt-in per kolom): de kolomindices waarvoor de
  // celwaarden bij het renderen als getal geformatteerd worden. De ruwe
  // celinhoud blijft staan; dit is puur een render-instructie.
  if (slide.tableNumberColumns.isNotEmpty) {
    final cols = [
      for (var c = 0; c < slide.tableNumberColumns.length; c++)
        if (slide.tableNumberColumns[c]) c,
    ];
    if (cols.isNotEmpty) {
      buf.writeln('<!-- ocideck_table_num_cols: ${cols.join(',')} -->');
    }
  }
  // AI-assist markers (AI_ASSIST §16.3): the fields whose text was drafted by
  // AI and not yet reviewed. Persisted so the seal gate survives a save/open.
  if (slide.aiAssistedFields.isNotEmpty) {
    buf.writeln(
      '<!-- ocideck_ai_assisted: ${slide.aiAssistedFields.join(', ')} -->',
    );
  }
  // Checklist↔scope-object link (feedback #8): the scope object this checklist
  // covers, so it round-trips as a unit with the scope matrix.
  if (slide.type == SlideType.checklist && slide.checklistScope.isNotEmpty) {
    buf.writeln('<!-- ocideck_checklist_scope: ${slide.checklistScope} -->');
  }
  // Welk verbetersjabloon de tabel volgt (PROCESS_IMPROVEMENT §3.1). Alleen dit
  // rijdt mee; de kolommen staan zichtbaar in de tabelkop en de afgeleide RPN
  // staat er per ontwerp niet.
  if (slide.improvementTemplateId.isNotEmpty) {
    buf.writeln('<!-- ocideck_template: ${slide.improvementTemplateId} -->');
  }
  if (slide.improvementLayout.isNotEmpty) {
    buf.writeln('<!-- ocideck_layout: ${slide.improvementLayout} -->');
  }
  if (slide.type == SlideType.gantt && slide.ganttScale != 'auto') {
    buf.writeln('<!-- ocideck_gantt_scale: ${slide.ganttScale} -->');
  }
  if (slide.type == SlideType.gantt && slide.ganttSections) {
    buf.writeln('<!-- ocideck_gantt_sections: true -->');
  }
  // Non-destructive view limit for data-driven slides.
  final viewComments = slide.viewLimit?.toComments() ?? const {};
  for (final entry in viewComments.entries) {
    buf.writeln('<!-- ${entry.key}: ${entry.value} -->');
  }
  // Media-redactiemarkering, alleen voor de export. Op een geprojecteerde slide
  // (privacy) is [Slide.mediaRedacted] gezet en het beeldpad leeggehaald; de
  // widget-exports (PDF/PPTX) tekenen dan een zwart vlak, maar de HTML-export
  // werkt op deze markdown en zag alleen een lege plek — de tekst liet wél
  // zwarte blokken zien, het beeld verdween spoorloos. De marker geeft de
  // HTML-renderer iets om dat vlak alsnog te tekenen. Nooit in een bewaard
  // bestand: [mediaRedacted] bestaat alleen in de projectie, en de poort staat
  // óók op [forExport].
  final mediaRedactedMarker = forExport && slide.mediaRedacted;
  if (mediaRedactedMarker) {
    buf.writeln('<!-- ocideck_media_redacted -->');
  }
  if (classes.isNotEmpty ||
      slide.findingId.isNotEmpty ||
      slide.aiAssistedFields.isNotEmpty ||
      slide.checklistScope.isNotEmpty ||
      slide.improvementTemplateId.isNotEmpty ||
      slide.improvementLayout.isNotEmpty ||
      (slide.type == SlideType.gantt && slide.ganttScale != 'auto') ||
      (slide.type == SlideType.gantt && slide.ganttSections) ||
      viewComments.isNotEmpty ||
      mediaRedactedMarker) {
    buf.writeln();
  }
}
