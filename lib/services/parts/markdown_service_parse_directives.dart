// Part of the markdown_service library — see ../markdown_service.dart.
// Split out for navigability (het per-slide directive-blok: de `<!-- ... -->`
// comments die de parser vóór de generieke regelwandeling oplicht). Verhuisd
// zonder gedragswijziging; alle imports leven in het hoofdbestand.
part of '../markdown_service.dart';

extension _MarkdownParseDirectives on MarkdownService {
  /// Parse the leading `<!-- _class -->` marker and every other `<!-- ... -->`
  /// directive comment (advance/skip/tlp/_style/two-bullets/timeline/list-style/
  /// checklist/title-image/title-colour/bullet-marker), accumulating presenter
  /// notes from any non-directive comment. Returns the stripped body plus all
  /// the decoded directive values.
  ({
    String cssClass,
    String remaining,
    String notes,
    double advanceDuration,
    bool skipped,
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
  })
  _parseBlockDirectives(String block) {
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
    remaining = remaining.replaceAllMapped(_reHtmlComment, (m) {
      final content = m.group(1)!.trim();
      if (content.startsWith('advance:')) {
        // Clamp fail-closed: double.tryParse accepts Infinity/NaN/overflow
        // literals, and `(Infinity * 1000).round()` throws in the auto-advance
        // timer. Mirror the presentationTargetSeconds clamp (0..86400s).
        final d = double.tryParse(content.substring(8).trim()) ?? 0;
        advanceDuration = (d.isFinite && d > 0) ? d.clamp(0, 86400) : 0;
      } else if (content == 'skip') {
        skipped = true;
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
      } else if (!content.startsWith('_')) {
        notesBuffer.write(notesBuffer.isEmpty ? content : '\n$content');
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
