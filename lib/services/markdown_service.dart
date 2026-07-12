import 'dart:convert';
import 'package:characters/characters.dart';
import 'package:uuid/uuid.dart';
import '../models/chart.dart';
import '../models/cockpit.dart';
import '../models/deck.dart';
import '../models/document_signature.dart';
import '../models/finding_spec.dart';
import '../models/question.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../models/timeline.dart';
import '../models/video_source.dart';
import '../utils/deck_markdown_dashes.dart';
import '../utils/log.dart';
import '../utils/markdown_paste_cleanup.dart';

part 'markdown_service_helpers.dart';
part 'markdown_service_parse.dart';
part 'markdown_service_finding.dart';
part 'markdown_service_fenced.dart';
part 'markdown_service_serialize.dart';

const _uuid = Uuid();

// Hoisted regexes (zie markdown_service_parse.dart voor het patroon):
// _reUnescapedPipe draait per tabelrij, de YAML-checks per frontmatter-veld.
final _reYamlSpecial = RegExp(r'[:#"\n]');
final _reYamlLeadingSigil = RegExp(r'''^[\[\]{}>|*&!%@`,?-]''');
final _reUnescapedPipe = RegExp(r'(?<!\\)\|');

class MarkdownService {
  // ── Generation ──────────────────────────────────────────────────────────────

  /// Serialise a deck to Marp markdown.
  ///
  /// The styling (the [ThemeProfile]) is deliberately NOT written to the file:
  /// a saved `.md` holds only the content (the "base"), and the app applies the
  /// active style profile when it opens the deck. [inlineStyleProfile] re-adds
  /// the profile for transient, non-file payloads — currently only the markdown
  /// streamed to the audience (beamer) window, which has no other way to learn
  /// the styling. It must stay false for anything written to disk.
  String generateDeck(
    Deck deck, {
    bool inlineChartData = false,
    bool inlineStyleProfile = false,
    bool forExport = false,
  }) {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('marp: true');
    buf.writeln('theme: ${deck.theme}');
    if (deck.paginate) buf.writeln('paginate: true');
    // General presentation metadata (also picked up by Marp where applicable).
    if (deck.title.isNotEmpty) {
      buf.writeln('title: ${_yamlScalar(deck.title)}');
    }
    if (deck.author.isNotEmpty) {
      buf.writeln('author: ${_yamlScalar(deck.author)}');
    }
    if (deck.organization.isNotEmpty) {
      buf.writeln('organization: ${_yamlScalar(deck.organization)}');
    }
    if (deck.version.isNotEmpty) {
      buf.writeln('version: ${_yamlScalar(deck.version)}');
    }
    if (deck.date.isNotEmpty) {
      buf.writeln('date: ${_yamlScalar(deck.date)}');
    }
    if (deck.description.isNotEmpty) {
      buf.writeln('description: ${_yamlScalar(deck.description)}');
    }
    if (deck.keywords.isNotEmpty) {
      buf.writeln('keywords: ${_yamlScalar(deck.keywords)}');
    }
    if (deck.tlp != TlpLevel.none) {
      buf.writeln('tlp: ${deck.tlp.key}');
    }
    if (deck.presentationTargetSeconds > 0) {
      buf.writeln('ocideck_target_seconds: ${deck.presentationTargetSeconds}');
    }
    // Default (true) stays out of the front matter; only persist an opt-out.
    if (!deck.showRehearsalSummary) {
      buf.writeln('ocideck_show_rehearsal_summary: false');
    }
    // 'Alleen afspelen'-vergrendeling: default (false) blijft uit de front
    // matter; enkel de opt-in wordt bewaard.
    if (deck.playOnly) {
      buf.writeln('ocideck_play_only: true');
    }
    // Documentintegriteit (§8 A1). De handtekening is inhoud en valt daarom
    // ónder het zegel; ze wordt vóór de zegelvelden geschreven zodat de
    // canonicalisatie (die enkel de zegelvelden weglaat) haar meeneemt.
    _writeSignature(buf, deck.signature);
    if (deck.finalized) {
      buf.writeln('ocideck_finalized: true');
    }
    if (deck.sealHash.isNotEmpty) {
      buf.writeln('ocideck_seal_hash: ${_yamlScalar(deck.sealHash)}');
      buf.writeln('ocideck_seal_algo: ${_yamlScalar(deck.sealAlgo)}');
      buf.writeln('ocideck_seal_at: ${_yamlScalar(deck.sealAt)}');
    }
    if (deck.sealTimestampToken.isNotEmpty) {
      buf.writeln('ocideck_seal_tsr: ${deck.sealTimestampToken}');
    }
    if (inlineStyleProfile) {
      buf.writeln(
        'ocideck_style_profile: ${base64Url.encode(utf8.encode(jsonEncode(deck.themeProfile.toJson())))}',
      );
    }
    if (deck.miauwWaivers.isNotEmpty) {
      buf.writeln(
        'ocideck_miauw_waivers: ${base64Url.encode(utf8.encode(jsonEncode(deck.miauwWaivers)))}',
      );
    }
    buf.writeln('---');
    buf.writeln();

    for (int i = 0; i < deck.slides.length; i++) {
      if (i > 0) {
        buf.writeln('---');
        buf.writeln();
      }
      buf.write(
        generateSlide(
          deck.slides[i],
          themeProfile: deck.themeProfile,
          inlineChartData: inlineChartData,
          forExport: forExport,
        ),
      );
    }
    return buf.toString();
  }

  /// Writes the (optional) visual signature as plain front-matter lines. Each
  /// non-empty field rides along as its own `ocideck_sig_*` key so the block
  /// stays human-readable and round-trips. Nothing is written for an absent or
  /// empty signature, so the default document has no signature noise.
  void _writeSignature(StringBuffer buf, DocumentSignature? sig) {
    if (sig == null || sig.isEmpty) return;
    void line(String key, String value) {
      if (value.isNotEmpty) buf.writeln('$key: ${_yamlScalar(value)}');
    }

    line('ocideck_sig_name', sig.name);
    line('ocideck_sig_role', sig.role);
    line('ocideck_sig_cert', sig.certification);
    line('ocideck_sig_date', sig.date);
    line('ocideck_sig_statement', sig.statement);
    line('ocideck_sig_typed', sig.typedSignature);
    line('ocideck_sig_image', sig.imagePath);
  }

  /// The canonical content string the document seal (§8 A1) hashes over: the
  /// deck's markdown with all integrity metadata (the finalise flag and the
  /// `ocideck_seal_*` fields) stripped, so the hash never covers itself and
  /// stays stable across sealing and re-opening. Styling is already excluded by
  /// [generateDeck], so the seal is purely over content; the visible signature
  /// is deliberately kept, so tampering with it is detectable.
  String canonicalContentForSeal(Deck deck) {
    return generateDeck(
      deck.copyWith(
        finalized: false,
        sealHash: '',
        sealAlgo: '',
        sealAt: '',
        // The RFC3161 token is added *after* sealing and timestamps the hash, so
        // it must stay out of the content the hash covers (else it is circular).
        sealTimestampToken: '',
      ),
    );
  }

  /// Render a string as a YAML scalar, quoting/escaping only when needed so the
  /// front matter stays readable.
  String _yamlScalar(String v) {
    final needsQuote =
        v.isEmpty ||
        v != v.trim() ||
        _reYamlSpecial.hasMatch(v) ||
        _reYamlLeadingSigil.hasMatch(v);
    if (!needsQuote) return v;
    final escaped = v
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }

  /// Decode a base64url-JSON front-matter value ([key] for logging) to a map,
  /// or null on corruption — a bad token must never fail the whole deck parse
  /// (which would blank the audience window). Shared by the `ocideck_*` keys
  /// that store a structured value this way (style profile, MIAUW waivers).
  Map<String, Object?>? _decodeBase64JsonMap(String value, String key) {
    try {
      return Map<String, Object?>.from(
        jsonDecode(utf8.decode(base64Url.decode(value))) as Map,
      );
    } catch (e, s) {
      logError('MarkdownService: decode $key', e, s);
      return null;
    }
  }

  /// Inverse of [_yamlScalar] for the simple line-based front matter parser.
  String _parseScalar(String raw) {
    final s = raw.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return _unescape(s.substring(1, s.length - 1));
    }
    return s;
  }

  String _unescape(String s) {
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == r'\'[0] && i + 1 < s.length) {
        final next = s[i + 1];
        if (next == 'n') {
          out.write('\n');
          i++;
        } else if (next == '"') {
          out.write('"');
          i++;
        } else if (next == r'\'[0]) {
          out.write(r'\');
          i++;
        } else {
          out.write(s[i]);
        }
      } else {
        out.write(s[i]);
      }
    }
    return out.toString();
  }

  /// Write [rows] as a GitHub-flavoured markdown table (first row = header).
  void _writeTable(StringBuffer buf, List<List<String>> rows) {
    if (rows.isEmpty) return;
    final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    if (colCount == 0) return;

    String cell(List<String> row, int c) {
      final v = c < row.length ? row[c] : '';
      return v
          .replaceAll('\\', r'\\')
          .replaceAll('|', r'\|')
          // Escape an author-typed literal "<br>" before encoding real newlines
          // as "<br>", so the two are distinguishable on parse (otherwise a
          // literal "<br>" silently became a line break every load).
          .replaceAll('<br>', r'\<br>')
          .replaceAll('\n', '<br>');
    }

    String renderRow(List<String> row) =>
        '| ${List.generate(colCount, (c) => cell(row, c)).join(' | ')} |';

    buf.writeln(renderRow(rows.first));
    buf.writeln('| ${List.generate(colCount, (_) => '---').join(' | ')} |');
    for (var i = 1; i < rows.length; i++) {
      buf.writeln(renderRow(rows[i]));
    }
  }

  List<String> _splitTableRow(String line) {
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    return s
        .split(_reUnescapedPipe)
        .map((c) => _unescapeCell(c.trim()))
        .toList();
  }

  String _unescapeCell(String s) {
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == r'\'[0] && i + 1 < s.length) {
        final n = s[i + 1];
        // `\|`, `\\` and `\<` unescape to the literal char; a `\<` keeps a
        // following `br>` as literal text rather than an author newline.
        if (n == '|' || n == r'\'[0] || n == '<') {
          out.write(n);
          i++;
          continue;
        }
      }
      // An unescaped `<br>` is an author-inserted line break.
      if (s.startsWith('<br>', i)) {
        out.write('\n');
        i += 3; // skip 'br>'; the loop's i++ steps past the '<'
        continue;
      }
      out.write(s[i]);
    }
    return out.toString();
  }

  String generateSlide(
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
      // Table slides that may be edited live during a presentation. Absent by
      // default, so tables stay read-only unless the author opts in.
      if (slide.type == SlideType.table && slide.tableEditable)
        'table-editable',
      // Timeline layout/animation options ride along as extra class tokens so
      // they round-trip without a JSON block (the base `timeline` token comes
      // from marpClass above).
      if (slide.type == SlideType.timeline)
        ...timelineClassTokens(slide.timelineLayout, slide.timelineReveal),
    ];

    if (classes.isNotEmpty) {
      buf.writeln('<!-- _class: ${classes.join(' ')} -->');
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
    // AI-assist markers (AI_ASSIST §16.3): the fields whose text was drafted by
    // AI and not yet reviewed. Persisted so the seal gate survives a save/open.
    if (slide.aiAssistedFields.isNotEmpty) {
      buf.writeln(
        '<!-- ocideck_ai_assisted: ${slide.aiAssistedFields.join(', ')} -->',
      );
    }
    if (classes.isNotEmpty ||
        slide.findingId.isNotEmpty ||
        slide.aiAssistedFields.isNotEmpty) {
      buf.writeln();
    }

    switch (slide.type) {
      case SlideType.title:
        _writeTitleSlide(buf, slide);
      case SlideType.section:
        _writeSectionSlide(buf, slide);
      case SlideType.bullets:
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
      // Informatieveiligheid: `checklist` (§3.2), `scopeMatrix` (§4.4) en
      // `findingsSummary` (§4.3.4) serialiseren als een gewone Markdown-tabel.
      // `signOff` (§1.6/§8) heeft geen eigen dia-inhoud behalve een optionele kop
      // — de attestatie is deck-breed (`ocideck_sig_*`). Alleen `finding`
      // (P1-FIND) deelt nog de vrije-Markdown-scaffold-body.
      case SlideType.checklist:
      case SlideType.scopeMatrix:
      case SlideType.findingsSummary:
        _writeTableSlide(buf, slide);
      case SlideType.signOff:
        _writeSignOffSlide(buf, slide);
      case SlideType.finding:
        _writeScaffoldSlide(buf, slide);
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

    // Slides marked to be skipped during presenting/exporting. Persisted so the
    // skip state survives save/load round-trips.
    if (slide.skipped) {
      buf.writeln();
      buf.writeln('<!-- skip -->');
    }

    // Per-slide TLP classification (used to withhold the slide when sharing at
    // a lower level). Persisted so it survives save/load round-trips.
    if (slide.tlp != TlpLevel.none) {
      buf.writeln();
      buf.writeln('<!-- tlp: ${slide.tlp.key} -->');
    }

    if (slide.notes.isNotEmpty) {
      buf.writeln();
      buf.writeln('<!--');
      buf.writeln(_escapeNotes(slide.notes));
      buf.writeln('-->');
    }

    buf.writeln();
    return buf.toString();
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
      return _doParse(normalized, filePath: filePath);
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
        } else if (trimmed.startsWith('~~~')) {
          fenceChar = '~';
        }
      } else if (isBareFence(trimmed, fenceChar)) {
        fenceChar = null;
      }
      current.add(line);
    }
    blocks.add(current.join('\n'));
    return blocks;
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
      final line = rawLine.trim();
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();
      switch (key) {
        case 'marp':
          marp = value == 'true';
        case 'theme':
          theme = value;
        case 'title':
          title = _parseScalar(value);
      }
    }
    return (marp: marp, theme: theme, title: title);
  }
}
