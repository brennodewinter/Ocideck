// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability (rich-text/timeline/checklist content helpers); all imports live in the main library
// file. These _FullscreenPresenterState methods relocate verbatim into an
// extension — same library, same members, no behaviour change.
part of '../fullscreen_presenter.dart';

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
    final contentH = w * 9 / 16 - (split ? w * 0.042 * 2 : w * 0.05 * 2);
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
    _persistUserNoteFromController();
    _rebuild(() => _richTextPage = page);
    _loadUserNoteIntoController();
    _syncAudience();
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
}
