// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability (rich-text/timeline/checklist content helpers); all imports live in the main library
// file. These _FullscreenPresenterState methods relocate verbatim into an
// extension — same library, same members, no behaviour change.
part of '../fullscreen_presenter.dart';

/// Berekent en past de live-fix (#914) toe op de getoonde dia. Muteert [slides]
/// in-place — in-place opknippen vervangt één dia, splitsen voegt pagina's in —
/// en schrijft de knip door via de callbacks. Geeft terug wat de presenter nog
/// moet doen: een [flash]-melding tonen (niets veranderd), óf de weergave
/// verversen ([changed]).
///
/// Top-level, niet als lid van de extension: de klasse-plafondratchet telt élk
/// lid van _FullscreenPresenterState mee, en dit is puur rekenwerk over
/// argumenten. Een geredigeerde dia blijft ongemoeid — de zwarte blokken mogen
/// niet naar de bron terug (zie [Slide.contentRedacted]).
({String? flash, bool changed}) planLiveFix({
  required List<Slide> slides,
  required int index,
  required ThemeProfile theme,
  required String? projectPath,
  required AppLocalizations l10n,
  required ValueChanged<Slide>? onSlideChanged,
  required ValueChanged<String>? onSlideSplit,
}) {
  if (slides.isEmpty) return (flash: null, changed: false);
  final idx = index.clamp(0, slides.length - 1);
  final slide = slides[idx];
  if (slide.contentRedacted) {
    return (
      flash: l10n.d('Deze dia is geredigeerd en wordt niet aangepast.'),
      changed: false,
    );
  }
  final pages = safeFixForSlide(slide, theme, projectPath: projectPath);
  if (pages == null || pages.isEmpty) {
    return (
      flash: l10n.d('Geen probleem om hier op te lossen.'),
      changed: false,
    );
  }
  if (pages.length == 1) {
    // In-place: opgeknipte bullets op dezelfde dia; terugschrijven per-dia.
    slides[idx] = pages.first;
    onSlideChanged?.call(pages.first);
  } else {
    // Splitsen: deze pagina wordt korter en de rest komt erachter; de knip gaat
    // via het id op de bron (het aantal dia's verandert — eigen terugkoppeling).
    slides
      ..removeAt(idx)
      ..insertAll(idx, pages);
    onSlideSplit?.call(slide.id);
  }
  return (flash: null, changed: true);
}

/// Stuurt de (gewijzigde) dia-reeks als verse markdown naar het beamervenster en
/// laat het vanaf [index] herrenderen — na een live-fix (#914). Top-level, om
/// dezelfde reden als [planLiveFix]; spiegelt [buildBeamerMarkdown] naast zich.
void sendDeckReplaceToAudience(
  AudienceWindowHandle? audience, {
  required List<Slide> slides,
  required String? projectPath,
  required TlpLevel tlp,
  required String organization,
  required String reportLanguage,
  required int index,
}) {
  if (audience?.controller == null) return;
  final markdown = buildBeamerMarkdown(
    slides: slides,
    projectPath: projectPath,
    tlp: tlp,
    organization: organization,
    reportLanguage: reportLanguage,
  );
  audienceChannel
      .invokeMethod('replaceDeck', {'markdown': markdown, 'index': index})
      .catchError((Object e) {
        logWarning('FullscreenPresenter: audience deck replace failed', e);
        return null;
      });
}

extension _PresenterContent on _FullscreenPresenterState {
  RichTextLayoutPlan? _richTextPlanFor(Slide slide) {
    if (!slideUsesRichText(slide)) return null;
    const w = kReferenceSlideWidth;
    final split = slide.type.splitWithImage;
    final hPad = split ? w * 0.038 : w * 0.07;
    final imgFraction = split
        ? ((slide.imageSize > 0 ? slide.imageSize / 100.0 : 0.40).clamp(
            0.1,
            0.70,
          ))
        : 0.0;
    final contentW = split
        ? (w - imgFraction * w - hPad * 2).clamp(w * 0.12, w)
        : w - hPad * 2;
    // Same body height the preview renders at (logo reserve + footer included),
    // so navigation and the on-screen page badge agree on the page count.
    final contentH = richTextBodyAvailH(
      w,
      slide,
      widget.themeProfile,
      splitWithImage: split,
    );
    return planRichTextForSlide(
      slide: slide,
      profile: widget.themeProfile,
      w: w,
      availW: contentW,
      availH: contentH,
      font: widget.themeProfile.fontFamily,
      splitWithImage: split,
    );
  }

  int _richTextPageCountFor(Slide slide) =>
      _richTextPlanFor(slide)?.pageCount ?? 1;

  bool _userNotesMultiPage(Slide slide) => _richTextPageCountFor(slide) > 1;

  String _userNoteKeyFor(Slide slide) => userNoteStorageKey(
    slide.id,
    _richTextPage,
    multiPage: _userNotesMultiPage(slide),
  );

  String _userNoteTextFor(Slide slide) =>
      userNoteForPage(
        _userNotes,
        slide.id,
        _richTextPage,
        multiPage: _userNotesMultiPage(slide),
      ) ??
      '';

  void _setRichTextPage(int page) {
    _commitActiveInk();
    _persistUserNoteFromController();
    _rebuild(() => _richTextPage = page);
    _loadUserNoteIntoController();
    _syncAudience();
    // Annotations are scoped per page, so push this page's strokes to the beamer
    // — otherwise the audience keeps showing the previous page's marks.
    _pushInk();
  }

  // ── Tijdlijn stap-voor-stap ──────────────────────────────────────────────

  /// True wanneer [slide] zijn gebeurtenissen klik-voor-klik onthult.
  bool _slideUsesTimelineSteps(Slide slide) =>
      slide.type == SlideType.timeline &&
      slide.timelineReveal == TimelineReveal.steps;

  int _timelineEventCountFor(Slide slide) =>
      parseTimelineEvents(slide.bullets).length;

  /// Hoeveel gebeurtenissen nu zichtbaar moeten zijn, of null als de slide niet
  /// in stapmodus staat (dan toont de tijdlijn alles / tekent zichzelf in).
  /// Stap 0 toont al de eerste gebeurtenis, zodat de slide nooit leeg opent.
  int? _timelineRevealedFor(Slide slide) {
    if (!_slideUsesTimelineSteps(slide)) return null;
    final n = _timelineEventCountFor(slide);
    if (n <= 0) return 0;
    return (_timelineStep + 1).clamp(1, n);
  }

  /// True zolang er nog een volgende gebeurtenis te onthullen valt op de huidige
  /// tijdlijn-slide (dan houdt een klik je op de slide).
  bool get _timelineHasMoreSteps {
    final slide = _currentSlide;
    if (!_slideUsesTimelineSteps(slide)) return false;
    return _timelineStep < _timelineEventCountFor(slide) - 1;
  }

  void _toggleChecklistItem({
    required int slideIndex,
    required int column,
    required int itemIndex,
  }) {
    if (slideIndex < 0 || slideIndex >= widget.slides.length) return;
    final slide = widget.slides[slideIndex];
    // Vangnet achter de uitgeschakelde affordance: ook een bericht van het
    // zaalvenster mag een geredigeerde slide niet terugschrijven, want dan
    // landen de zwarte blokken in de bron. Zie [Slide.contentRedacted].
    if (slide.contentRedacted) return;
    final source = column == 1 ? slide.bullets2 : slide.bullets;
    if (itemIndex < 0 || itemIndex >= source.length) return;
    final updatedItems = List<String>.from(source);
    final item = updatedItems[itemIndex];
    updatedItems[itemIndex] = checklistBullet(
      level: bulletLevel(item),
      text: checklistItemText(item),
      checked: !checklistItemChecked(item),
    );
    final updated = column == 1
        ? slide.copyWith(bullets2: updatedItems)
        : slide.copyWith(bullets: updatedItems);
    _rebuild(() => widget.slides[slideIndex] = updated);
    widget.onSlideChanged?.call(updated);
    if (_dual) {
      audienceChannel
          .invokeMethod('checklistUpdate', {
            'slideIndex': slideIndex,
            'bullets': updated.bullets,
            'bullets2': updated.bullets2,
          })
          .catchError((Object e) {
            // Audience-window sync is best-effort, but a fully silent failure
            // left the beamer out of sync with no trace; make it observable.
            logWarning('FullscreenPresenter: audience window sync failed', e);
            return null;
          });
    }
  }

  Slide get _currentSlide =>
      widget.slides[_index.clamp(0, widget.slides.length - 1)];

  /// Lost het kwaliteitsprobleem op de getoonde dia ter plekke op (#914), met de
  /// veiligste structurele fix, zodat je niet hoeft te stoppen. Het rekenwerk zit
  /// in de top-level [planLiveFix] (telt niet mee voor het klasse-plafond); hier
  /// staat alleen wat state raakt: herbouwen, flashen, de beamer meewerken.
  void _fixCurrentSlide() {
    final outcome = planLiveFix(
      slides: widget.slides,
      index: _index,
      theme: widget.themeProfile,
      projectPath: widget.projectPath,
      l10n: context.l10n,
      onSlideChanged: widget.onSlideChanged,
      onSlideSplit: widget.onSlideSplit,
    );
    if (outcome.flash != null) {
      _flashFix(outcome.flash!);
      return;
    }
    if (!outcome.changed) return;
    // Het beamervenster rendert vanuit zijn eigen markdown-kopie: dat kanaal is
    // te smal voor een gewijzigd aantal dia's, dus krijgt het de verse reeks.
    _rebuild(() {});
    if (_dual) {
      _lastSentIndex = null; // dwing een verse positie-sync af na de herbouw
      sendDeckReplaceToAudience(
        widget.audience,
        slides: widget.slides,
        projectPath: widget.projectPath,
        tlp: widget.tlp,
        organization: widget.organization,
        reportLanguage: widget.reportLanguage,
        index: _index,
      );
    }
  }

  /// Toont een vluchtige melding onder in beeld en ruimt de vorige op.
  void _flashFix(String message) {
    _fixFlashTimer?.cancel();
    _rebuild(() => _fixFlash = message);
    _fixFlashTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) _rebuild(() => _fixFlash = null);
    });
  }
}
