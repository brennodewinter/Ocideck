// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterTable on _FullscreenPresenterState {
  bool get _currentSlideIsTable => _currentSlide.type == SlideType.table;

  /// Of de huidige dia een tabel is die de auteur in de bouwer als
  /// "bewerkbaar tijdens presenteren" heeft aangemerkt. Alleen dan mag de
  /// live-bewerking aangezet worden (standaard staan tabellen op alleen-lezen).
  /// Een weergavelimiet is een afgeleide projectie zonder veilige één-op-één
  /// rijmapping naar de bron; die blijft tijdens presenteren alleen-lezen.
  bool get _currentSlideTableEditable =>
      _currentSlideIsTable &&
      _currentSlide.tableEditable &&
      !(_currentSlide.viewLimit?.isActive ?? false);

  void _exitTableEditMode() {
    if (!_tableEditMode) return;
    _rebuild(() {
      _tableEditMode = false;
      _tableEditor?.dispose();
      _tableEditor = null;
    });
    _focusNode.requestFocus();
  }

  void _toggleTableEditMode() {
    // Alleen tabellen die de auteur expliciet bewerkbaar maakte mogen live
    // bewerkt worden; standaard zijn ze alleen-lezen.
    if (!_currentSlideTableEditable) return;
    if (_tableEditMode) {
      _exitTableEditMode();
      return;
    }
    final slideIndex = _index.clamp(0, widget.slides.length - 1);
    final slide = widget.slides[slideIndex];
    final editor = TableEditController(
      rows: slide.tableRows.where((row) => row.isNotEmpty).toList(),
      alignments: slide.tableColumnAlignments,
      onChanged: (rows, alignments) => _applyTableEdit(
        slideIndex: slideIndex,
        rows: rows,
        alignments: alignments,
      ),
    );
    _rebuild(() {
      _tableEditMode = true;
      _tableEditor = editor;
      _tool = null;
    });
    _advanceTimer?.cancel();
    _onLaserMove(null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _tableEditor == editor) editor.focusCell(0, 0);
    });
  }

  void _applyTableEdit({
    required int slideIndex,
    required List<List<String>> rows,
    required List<TableAlign> alignments,
  }) {
    if (slideIndex < 0 || slideIndex >= widget.slides.length) return;
    final slide = widget.slides[slideIndex];
    if (slide.type != SlideType.table) return;
    final updated = slide.copyWith(
      tableRows: [for (final row in rows) List<String>.from(row)],
      tableColumnAlignments: alignments,
    );
    _rebuild(() => _replaceSlide(widget.slides, slideIndex, updated));
    widget.onSessionEdit?.call(updated);
    _pushTableToAudience(slideIndex, updated);
  }

  /// Spiegel een tabelwijziging naar het publieksscherm (alleen bij dual).
  void _pushTableToAudience(int slideIndex, Slide updated) {
    if (!_dual) return;
    audienceChannel
        .invokeMethod('tableUpdate', {
          'slideIndex': slideIndex,
          'tableRows': updated.tableRows,
        })
        .catchError((Object e) {
          // Audience-window sync is best-effort, but a fully silent failure
          // left the beamer out of sync with no trace; make it observable.
          logWarning('FullscreenPresenter: audience window sync failed', e);
          return null;
        });
  }

  /// Toetsen tijdens live tabelbewerking.
  ///
  /// De gedeelde [TableEditController] handelt alle celtoetsen af. Alleen Esc
  /// hoort nog bij de presentator zelf: die sluit de live-bewerking.
  KeyEventResult _handleTableEditKey(LogicalKeyboardKey key) {
    if (key != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    _exitTableEditMode();
    return KeyEventResult.handled;
  }

  /// Zwevende banner tijdens live tabelbewerking.
  /// Subtiel, klikbaar potlood-icoon dat op tabeldia's de bewerkmodus toont en
  /// schakelt. Gedimd = uit, accentkleur = aan — hetzelfde als de E-toets.
  Widget _buildTableEditToggle() {
    final accent = AppTheme.parseHexColor(widget.themeProfile.accentColor);
    final active = _tableEditMode;
    return Tooltip(
      message: context.l10n.d('Tabel bewerken (E)'),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _toggleTableEditMode,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? accent.withValues(alpha: 0.92)
                  : Colors.black.withValues(alpha: 0.42),
              border: Border.all(
                color: active
                    ? Colors.white.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.22),
                width: active ? 1.5 : 1,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.5),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              active ? Icons.edit_note_rounded : Icons.edit_outlined,
              size: 22,
              color: active
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableEditBanner() {
    final l10n = context.l10n;
    final accent = AppTheme.parseHexColor(widget.themeProfile.accentColor);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.92),
                accent.withValues(alpha: 0.72),
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.edit_note_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                l10n.d('Tabel bewerken'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  l10n.d('Tab wisselt cel · Esc sluit'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
