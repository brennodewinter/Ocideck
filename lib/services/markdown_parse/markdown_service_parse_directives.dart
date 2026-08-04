// Part of the markdown_service library — see ../markdown_service.dart.
// Split out for navigability (het per-slide directive-blok: de `<!-- ... -->`
// comments die de parser vóór de generieke regelwandeling oplicht). Verhuisd
// zonder gedragswijziging; alle imports leven in het hoofdbestand.
part of '../markdown_service.dart';

/// Wat [_MarkdownParseDirectives._parseBlockDirectives] uit één slideblok
/// haalt: de body zonder richtlijnen, plus elke richtlijn die erin stond.
/// De waarde na [prefix] in [content], maar alleen als [current] nog leeg is —
/// eerste vondst wint (#1162). De serialiser zet zo'n richtlijn bovenaan, dus een
/// gelijknamige regel verderop staat in de dia-tekst en mag de waarde niet
/// overschrijven. Top-level zodat `_parseBlockDirectives` niet verder groeit.
String _firstDirective(String content, String prefix, String current) =>
    current.isNotEmpty ? current : content.substring(prefix.length).trim();

typedef _BlockDirectives = ({
  String cssClass,
  String remaining,
  String notes,
  double advanceDuration,
  bool skipped,
  bool isDetail,
  TlpLevel tlp,
  PrivacyDisposition? privacy,
  QualityDisposition quality,
  List<String> bullets,
  List<String> bullets2,
  ListStyle listStyle,
  int? timelineAnimationMs,
  int? timelineCurrentIndex,
  bool showChecklistProgress,
  bool continueNumbering,
  bool continuesSplit,
  bool titleImageOverlay,
  String titleTextColorOverride,
  BulletMarker? bulletMarkerOverride,
  String columnTitle1,
  String columnTitle2,
  int styleImageWidth,
  DisplayWindowSpec? viewLimit,
  String improvementTemplateId,
  String improvementLayout,
  String anchor,
  String nextAnchor,
  String ganttScale,
  bool ganttSections,
});

/// Neemt [content] op in het notitieblok en haalt het uit de body.
///
/// Sprekersnotities schrijft de serialiser altijd over meerdere regels (`<!--`,
/// de tekst, `-->`); élke richtlijn past op één regel. Dat verschil is het enige
/// waaraan notities te herkennen zijn, en zonder die toets ging het twee kanten
/// op mis: een door de auteur getypte opmerking in de tekst verdween uit de body
/// en dook op ín de notities, en een notitie die toevallig met `skip` of `tlp:`
/// begon werd als richtlijn opgegeten. Beide zonder melding.
///
/// Een `_`-voorvoegsel blijft een Marp-richtlijn en gaat er nog steeds uit; wat
/// verder op één regel staat en niet herkend wordt, is van de auteur en blijft
/// staan waar het staat.
/// Of een onbekend commentaar van één regel als sprekersnotitie telt.
///
/// Alleen wanneer er verder niets meer volgt op de slide ([tail] is leeg op
/// eventuele andere commentaren na). In een handgeschreven `.md` is een
/// commentaarregel onderaan de gangbare afspraak voor een notitie, en die blijft
/// zo werken.
///
/// Staat het commentaar middenín de tekst, dan is het een opmerking van de
/// auteur en hoort het te blijven staan waar het staat. Vroeger werd het uit de
/// body gehaald en bij de notities gezet: inhoud die van plek verspringt zonder
/// dat iemand erom vroeg, en op de plek zelf niet meer terug te vinden.
bool _isTailNote(String tail) =>
    tail.replaceAll(_reHtmlComment, '').trim().isEmpty;

String _takeNote(StringBuffer notes, String content) {
  notes.write(notes.isEmpty ? content : '\n$content');
  return '';
}

extension _MarkdownParseDirectives on MarkdownService {
  /// Parse the leading `<!-- _class -->` marker and every other `<!-- ... -->`
  /// directive comment (advance/skip/tlp/_style/two-bullets/timeline/list-style/
  /// checklist/title-image/title-colour/bullet-marker), accumulating presenter
  /// notes from any non-directive comment. Returns the stripped body plus all
  /// the decoded directive values.
  _BlockDirectives _parseBlockDirectives(String block) {
    String cssClass = '';
    String remaining = block;

    final classMatch = _reClassDirective.firstMatch(block);
    if (classMatch != null) {
      cssClass = classMatch.group(1) ?? '';
      remaining = block.replaceFirst(classMatch.group(0)!, '').trim();
    }

    // Extract presenter notes and advance timing from HTML comments
    final notesBuffer = StringBuffer();
    double advanceDuration = 0;
    bool skipped = false;
    bool isDetail = false;
    TlpLevel slideTlp = TlpLevel.none;
    PrivacyDisposition? slidePrivacy;
    var slideQuality = QualityDisposition.warn;
    final bullets = <String>[];
    var bullets2 = <String>[];
    var listStyle = ListStyle.bullets;
    int? timelineAnimationMs;
    int? timelineCurrentIndex;
    var showChecklistProgress = false;
    var continueNumbering = false;
    var continuesSplit = false;
    var titleImageOverlay = true;
    var titleTextColorOverride = '';
    BulletMarker? bulletMarkerOverride;
    var columnTitle1 = '';
    var columnTitle2 = '';
    // bulletsImage slides store their panel width in `<!-- _style:
    // --image-width: N%; -->`; capture it before the comment is stripped.
    int styleImageWidth = 0;
    var improvementTemplateId = '';
    var improvementLayout = '';
    var anchor = '';
    var nextAnchor = '';
    var ganttScale = 'auto';
    var ganttSections = false;
    final viewComments = <String, String>{};
    final source = remaining;
    remaining = source.replaceAllMapped(_reHtmlComment, (m) {
      final raw = m.group(1)!;
      final content = raw.trim();
      // Meerregelig is altijd een notitieblok — richtlijnen passen op één regel.
      if (raw.contains('\n')) return _takeNote(notesBuffer, content);
      if (content.startsWith('advance:')) {
        // Clamp fail-closed: double.tryParse accepts Infinity/NaN/overflow
        // literals, and `(Infinity * 1000).round()` throws in the auto-advance
        // timer. Mirror the presentationTargetSeconds clamp (0..86400s).
        final d = double.tryParse(content.substring(8).trim()) ?? 0;
        advanceDuration = (d.isFinite && d > 0) ? d.clamp(0, 86400) : 0;
      } else if (content == 'skip') {
        skipped = true;
      } else if (content == 'ocideck_detail') {
        isDetail = true;
      } else if (content.startsWith('tlp:')) {
        slideTlp = TlpLevelX.fromKey(content.substring(4));
      } else if (content.startsWith('ocideck_privacy:')) {
        slidePrivacy = PrivacyDispositionX.fromKey(content.substring(16));
      } else if (content.startsWith('ocideck_quality:')) {
        slideQuality = QualityDispositionX.fromKey(content.substring(16));
      } else if (content.startsWith('_style:')) {
        final w = _reImageWidthStyle.firstMatch(content);
        if (w != null) styleImageWidth = int.tryParse(w.group(1)!) ?? 0;
      } else if (content.startsWith('ocideck_two_bullets_left:')) {
        bullets
          ..clear()
          ..addAll(_decodeBullets(content.substring(25)));
      } else if (content.startsWith('ocideck_two_bullets_left_title:')) {
        columnTitle1 = _decodeText(content.substring(31));
      } else if (content.startsWith('ocideck_two_bullets_right_title:')) {
        columnTitle2 = _decodeText(content.substring(32));
      } else if (content.startsWith('ocideck_two_bullets_right:')) {
        bullets2 = _decodeBullets(content.substring(26));
      } else if (content.startsWith('ocideck_timeline_')) {
        final t = _parseTimelineDirective(
          content,
          animationMs: timelineAnimationMs,
          currentIndex: timelineCurrentIndex,
        );
        timelineAnimationMs = t.animationMs;
        timelineCurrentIndex = t.currentIndex;
      } else if (content.startsWith('ocideck_list_style:')) {
        listStyle = _listStyleFrom(content.substring(19));
      } else if (content.startsWith('ocideck_checklist_progress:')) {
        showChecklistProgress = _flagAfter(
          content,
          'ocideck_checklist_progress:',
        );
      } else if (content.startsWith('ocideck_continue_numbering:')) {
        continueNumbering = _flagAfter(content, 'ocideck_continue_numbering:');
      } else if (content.startsWith('ocideck_continue_split:')) {
        continuesSplit = _flagAfter(content, 'ocideck_continue_split:');
      } else if (content.startsWith('ocideck_title_image_overlay:')) {
        titleImageOverlay = _flagAfter(
          content,
          'ocideck_title_image_overlay:',
          defaultTrue: true,
        );
      } else if (content.startsWith('ocideck_title_text_color:')) {
        titleTextColorOverride = content
            .substring('ocideck_title_text_color:'.length)
            .trim();
      } else if (content.startsWith('ocideck_bullet_marker:')) {
        bulletMarkerOverride =
            _bulletMarkerFrom(content.substring(22)) ?? bulletMarkerOverride;
      } else if (content.startsWith('ocideck_template:')) {
        // Eerste vondst wint, zoals bij de groepskoppeling: de serialiser zet
        // deze richtlijn bovenaan, dus een gelijknamige regel verderop staat in
        // de tékst van de dia en mag de waarde niet overschrijven.
        if (improvementTemplateId.isEmpty) {
          improvementTemplateId = content
              .substring('ocideck_template:'.length)
              .trim();
        }
      } else if (content.startsWith('ocideck_layout:')) {
        if (improvementLayout.isEmpty) {
          improvementLayout = content
              .substring('ocideck_layout:'.length)
              .trim();
        }
      } else if (content.startsWith('ocideck_gantt_scale:')) {
        if (ganttScale == 'auto') {
          ganttScale = content.substring('ocideck_gantt_scale:'.length).trim();
        }
      } else if (content.startsWith('ocideck_gantt_sections:')) {
        ganttSections =
            content.substring('ocideck_gantt_sections:'.length).trim() ==
            'true';
      } else if (content.startsWith('ocideck_slide_anchor:')) {
        anchor = _firstDirective(content, 'ocideck_slide_anchor:', anchor);
      } else if (content.startsWith('ocideck_next:')) {
        nextAnchor = _firstDirective(content, 'ocideck_next:', nextAnchor);
      } else if (content.startsWith('ocideck_view_')) {
        _collectViewComment(viewComments, content);
      } else if (!content.startsWith('_')) {
        // Geen richtlijn die wij kennen: notitie of opmerking? Zie [_isTailNote].
        if (_isTailNote(source.substring(m.end))) {
          return _takeNote(notesBuffer, content);
        }
        return m.group(0)!;
      }
      return '';
    }).trim();
    final notes = _unescapeNotes(notesBuffer.toString().trim());

    return (
      cssClass: cssClass,
      remaining: remaining,
      notes: notes,
      advanceDuration: advanceDuration,
      skipped: skipped,
      isDetail: isDetail,
      tlp: slideTlp,
      privacy: slidePrivacy,
      quality: slideQuality,
      bullets: bullets,
      bullets2: bullets2,
      listStyle: listStyle,
      timelineAnimationMs: timelineAnimationMs,
      timelineCurrentIndex: timelineCurrentIndex,
      showChecklistProgress: showChecklistProgress,
      continueNumbering: continueNumbering,
      continuesSplit: continuesSplit,
      titleImageOverlay: titleImageOverlay,
      titleTextColorOverride: titleTextColorOverride,
      bulletMarkerOverride: bulletMarkerOverride,
      columnTitle1: columnTitle1,
      columnTitle2: columnTitle2,
      styleImageWidth: styleImageWidth,
      viewLimit: viewComments.isEmpty
          ? null
          : DisplayWindowSpec.fromComments(viewComments),
      improvementTemplateId: improvementTemplateId,
      improvementLayout: improvementLayout,
      anchor: anchor,
      nextAnchor: nextAnchor,
      ganttScale: ganttScale,
      ganttSections: ganttSections,
    );
  }

  /// De twee timeline-directives: animatieduur en het gemarkeerde event.
  ///
  /// Het bestand bewaart het mensvriendelijke, 1-gebaseerde eventnummer; alles
  /// buiten bereik wordt genegeerd (fail-safe: dan geen markering).
  ({int? animationMs, int? currentIndex}) _parseTimelineDirective(
    String content, {
    required int? animationMs,
    required int? currentIndex,
  }) {
    if (content.startsWith('ocideck_timeline_duration:')) {
      final ms = int.tryParse(content.substring(26).trim());
      if (ms != null) {
        return (
          animationMs: clampTimelineDuration(ms),
          currentIndex: currentIndex,
        );
      }
    } else if (content.startsWith('ocideck_timeline_current:')) {
      final n = int.tryParse(
        content.substring('ocideck_timeline_current:'.length).trim(),
      );
      if (n != null && n >= 1 && n <= timelineMaxEvents) {
        return (animationMs: animationMs, currentIndex: n - 1);
      }
    }
    return (animationMs: animationMs, currentIndex: currentIndex);
  }

  /// De waarde van een boolean-directive: `<!-- prefix true -->`.
  ///
  /// [defaultTrue] keert de betekenis om voor directives die alleen worden
  /// weggeschreven om iets *uit* te zetten (dan is alles behalve `false` waar).
  bool _flagAfter(String content, String prefix, {bool defaultTrue = false}) {
    final value = content.substring(prefix.length).trim();
    return defaultTrue ? value != 'false' : value == 'true';
  }

  /// De lijststijl uit een `ocideck_list_style:`-directive.
  ///
  /// Een onbekende naam wordt een gewone opsomming: een deck uit een nieuwere
  /// versie hoort leesbaar te blijven, niet leeg.
  ListStyle _listStyleFrom(String raw) {
    final name = raw.trim();
    return ListStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => ListStyle.bullets,
    );
  }

  /// De bulletmarkering uit een `ocideck_bullet_marker:`-directive, of `null`
  /// als de naam onbekend is — dan blijft de themastandaard staan.
  BulletMarker? _bulletMarkerFrom(String raw) {
    final name = raw.trim();
    final match = BulletMarker.values.where((m) => m.name == name);
    return match.isEmpty ? null : match.first;
  }
}

/// Eén `ocideck_view_*`-commentaar in de verzamelmap, of niets.
///
/// Zonder dubbele punt is er geen waarde: overslaan, niet struikelen. Een
/// optioneel, negeerbaar aanwijzinkje mag nooit het hele bestand gijzelen —
/// een RangeError hier maakte parseDeck null en daarmee het deck onopenbaar
/// (bewaker-bevinding op #672).
void _collectViewComment(Map<String, String> viewComments, String content) {
  final colon = content.indexOf(':');
  if (colon > 0) {
    viewComments[content.substring(0, colon).trim()] = content
        .substring(colon + 1)
        .trim();
  }
}
