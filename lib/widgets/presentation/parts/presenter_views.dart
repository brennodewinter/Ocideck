// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability (slide canvas, audience & presenter views); all imports live in the main library
// file. These _FullscreenPresenterState methods relocate verbatim into an
// extension — same library, same members, no behaviour change.
part of '../fullscreen_presenter.dart';

extension _PresenterViews on _FullscreenPresenterState {
  /// A 16:9 slide sized to fit within the given constraints.
  Widget _slideCanvas(Slide slide) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        const ratio = 16.0 / 9.0;
        double slideW, slideH;
        if (w / h > ratio) {
          slideH = h;
          slideW = h * ratio;
        } else {
          slideW = w;
          slideH = w / ratio;
        }
        return Center(
          child: SizedBox(
            width: slideW,
            height: slideH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SlidePreviewWidget(
                  slide: slide,
                  projectPath: widget.projectPath,
                  themeProfile: widget.themeProfile,
                  cockpitColorScheme: widget.cockpitColorScheme,
                  onLinkTap: openExternalUrl,
                  slideNumber: _index + 1,
                  slideCount: widget.slides.length,
                  numberStart: numberedListStartFor(widget.slides, _index),
                  scopeCia: deckScopeCiaIndex(widget.slides),
                  fitScaleOverride: sharedSplitFitScale(
                    widget.slides,
                    _index,
                    widget.themeProfile,
                    widget.themeProfile.fontFamily,
                  ),
                  richTextPage: _richTextPage,
                  showRichTextPageControls:
                      (_richTextPlanFor(slide)?.pageCount ?? 1) > 1,
                  onRichTextPageChanged:
                      (_richTextPlanFor(slide)?.pageCount ?? 1) > 1
                      ? (page) => _setRichTextPage(page)
                      : null,
                  timelineRevealedCount: _timelineRevealedFor(slide),
                  tlp: widget.tlp,
                  organization: widget.organization,
                  showClassificationWatermark:
                      widget.showClassificationWatermark,
                  presentationMode: true,
                  onChecklistItemToggle: (column, itemIndex) =>
                      _toggleChecklistItem(
                        slideIndex: _index,
                        column: column,
                        itemIndex: itemIndex,
                      ),
                  questionView: _currentQuestionView,
                  onAnswerSelected: (i) => _onAnswerSelected(i),
                  onAnswerSubmit: () => _onAnswerSubmit(),
                  // Typen gebeurt op het presentatorscherm; het beamervenster
                  // spiegelt alleen mee (zie [SlidePreviewWidget.onAnswerTextChanged]).
                  onAnswerTextChanged: _onAnswerTextChanged,
                  tableEditMode:
                      _tableEditMode && slide.type == SlideType.table,
                  tableEditRow: _tableEditRow,
                  tableEditCol: _tableEditCol,
                  onTableCellSelected: (row, col) => _selectTableCell(row, col),
                  onTableCellChanged: (row, col, value) => _updateTableCell(
                    slideIndex: _index,
                    row: row,
                    col: col,
                    value: value,
                  ),
                  // Tijdens het presenteren speelt media en starten audio/video
                  // vanzelf; het media-einde stuurt auto-advance aan. In dual-
                  // schermmodus speelt de media op het beamervenster, niet hier,
                  // anders zou het geluid dubbel klinken.
                  enableMedia: !_dual,
                  autoplayMedia: !_dual,
                  allowRemoteMedia: widget.allowRemoteMedia,
                  onAudioComplete: () => _onMediaCompleted(kind: 'audio'),
                  onVideoComplete: () => _onMediaCompleted(kind: 'video'),
                ),
                // Annotatielaag bovenop de dia. Laat klikken door wanneer er
                // geen gereedschap actief is (zodat tikken blijft doorbladeren).
                AnnotationLayer(
                  // Navigatiepaden committen een streek-in-uitvoering eerst
                  // op de oude slide (via [_commitActiveInk]); de resetToken
                  // is het vangnet dat halve streken nooit op een andere
                  // slide/pagina laat belanden.
                  key: _annotationLayerKey,
                  resetToken: _currentInkKey(),
                  strokes: _currentStrokes,
                  tool: _tableEditMode ? null : _tool,
                  color: _inkColor,
                  width: _toolWidth,
                  interactive: !_tableEditMode,
                  onStrokesChanged: _onStrokesChanged,
                  onLaserMove: _onLaserMove,
                  onActiveStrokeChanged: _onActiveStroke,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Audience view (alleen de slide) ──────────────────────────────────────

  Widget _buildAudienceView(BuildContext context) {
    final total = widget.slides.length;
    final slide = widget.slides[_index.clamp(0, total - 1)];

    // Blanco scherm vult in publieksweergave het hele beeld.
    if (_blank != _Blank.none) return _blankFill();

    return MouseRegion(
      onHover: (_) => _revealAudienceControls(),
      child: GestureDetector(
        onTap: _tableEditMode ? null : _next,
        onSecondaryTap: _tableEditMode ? null : _prev,
        child: Stack(
          children: [
            SizedBox.expand(child: _slideCanvas(slide)),
            // Bij een quiz is "we wachten op een antwoord" ook voor de zaal
            // zinvolle informatie; zonder badge lijkt auto-play vastgelopen.
            if (_showQuestionWaitBadge) _buildQuestionWaitBadge(context),
            // Verborgen tenzij je de muis beweegt; zie [_buildAudienceControls].
            _buildAudienceControls(total),
          ],
        ),
      ),
    );
  }

  // ── Presenter view (slide + volgende + notities + tijd) ──────────────────

  Widget _buildPresenterView(BuildContext context) {
    final l10n = context.l10n;
    final total = widget.slides.length;
    final slide = widget.slides[_index.clamp(0, total - 1)];
    final hasNext = _index < total - 1;
    final nextSlide = hasNext ? widget.slides[_index + 1] : null;

    return Container(
      color: PresenterPalette.bgDeepest,
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hoofdgebied: huidige slide ───────────────────────────────────
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(l10n.d('HUIDIGE SLIDE')),
                const SizedBox(height: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                      onTap: _tableEditMode ? null : _next,
                      child: Stack(
                        children: [
                          Positioned.fill(child: _slideCanvas(slide)),
                          // Blanco scherm dekt alleen het slidevlak; jouw
                          // notities en klok blijven zichtbaar.
                          if (_blank != _Blank.none)
                            Positioned.fill(child: _blankFill()),
                          if (_progress > 0 && _blank == _Blank.none)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: LinearProgressIndicator(
                                value: _progress,
                                backgroundColor: Colors.white12,
                                color: Colors.white54,
                                minHeight: 3,
                              ),
                            ),
                          if (_showQuestionWaitBadge)
                            _buildQuestionWaitBadge(context),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _buildPresenterControls(total),
              ],
            ),
          ),
          const SizedBox(width: 20),

          // ── Zijbalk: klok, volgende slide, notities ─────────────────────
          SizedBox(
            width: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildClockBar(),
                const SizedBox(height: 16),
                _SectionLabel(l10n.d('VOLGENDE')),
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: nextSlide != null
                        ? Container(
                            color: Colors.black,
                            child: SlidePreviewWidget(
                              slide: nextSlide,
                              projectPath: widget.projectPath,
                              themeProfile: widget.themeProfile,
                              cockpitColorScheme: widget.cockpitColorScheme,
                              allowRemoteMedia: widget.allowRemoteMedia,
                              tlp: widget.tlp,
                              organization: widget.organization,
                              showClassificationWatermark:
                                  widget.showClassificationWatermark,
                              presentationMode: true,
                              scopeCia: deckScopeCiaIndex(widget.slides),
                              fitScaleOverride: sharedSplitFitScale(
                                widget.slides,
                                _index + 1,
                                widget.themeProfile,
                                widget.themeProfile.fontFamily,
                              ),
                            ),
                          )
                        : Container(
                            color: PresenterPalette.bg2,
                            alignment: Alignment.center,
                            child: Text(
                              l10n.d('Einde van de presentatie'),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 13,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                _SectionLabel(l10n.d('NOTITIES')),
                const SizedBox(height: 8),
                Expanded(child: _buildNotes(slide)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
