// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterTable on _FullscreenPresenterState {
  bool get _currentSlideIsTable => _currentSlide.type == SlideType.table;

  /// Of de huidige dia een tabel is die de auteur in de bouwer als
  /// "bewerkbaar tijdens presenteren" heeft aangemerkt. Alleen dan mag de
  /// live-bewerking aangezet worden (standaard staan tabellen op alleen-lezen).
  bool get _currentSlideTableEditable =>
      _currentSlideIsTable && _currentSlide.tableEditable;

  void _exitTableEditMode() {
    if (!_tableEditMode) return;
    _rebuild(() {
      _tableEditMode = false;
      _tableEditRow = null;
      _tableEditCol = null;
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
    _rebuild(() {
      _tableEditMode = true;
      _tableEditRow = 0;
      _tableEditCol = 0;
      _tool = null;
    });
    _advanceTimer?.cancel();
    _onLaserMove(null);
    // Geen focus naar de root: dan kan de geselecteerde cel zelf focus pakken
    // en vangen de pijltjes de tekstcursor op i.p.v. de presentatie. De
    // toetsenbordevents bereiken [_handleKey] nog steeds via bubbling vanuit de
    // cel. Bij het verlaten zet [_exitTableEditMode] de focus terug op de root.
  }

  void _selectTableCell(int row, int col) {
    if (!_tableEditMode) return;
    _rebuild(() {
      _tableEditRow = row;
      _tableEditCol = col;
    });
  }

  void _updateTableCell({
    required int slideIndex,
    required int row,
    required int col,
    required String value,
  }) {
    if (slideIndex < 0 || slideIndex >= widget.slides.length) return;
    final slide = widget.slides[slideIndex];
    if (slide.type != SlideType.table) return;
    final rows = slide.tableRows.map((r) => List<String>.from(r)).toList();
    if (rows.isEmpty) return;
    final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    while (rows.length <= row) {
      rows.add(List<String>.filled(colCount, ''));
    }
    while (rows[row].length <= col) {
      rows[row].add('');
    }
    rows[row][col] = value;
    final updated = slide.copyWith(tableRows: rows);
    _rebuild(() => _replaceSlide(widget.slides, slideIndex, updated));
    widget.onSlideChanged?.call(updated);
    _pushTableToAudience(slideIndex, updated);
  }

  /// Vult vanaf cel (row, col) een geplakte tabel in en laat het raster
  /// meegroeien, zodat plakken net als in de editor rijen/kolommen toevoegt.
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

  /// Voegt onderaan de tabel een lege rij toe en selecteert de eerste cel
  /// ervan. Werkt ook terwijl een cel in bewerking is, zodat Tab op de laatste
  /// cel een rij kan aanmaken.
  void _addTableRow() {
    if (!_tableEditMode) return;
    final slideIndex = _index.clamp(0, widget.slides.length - 1);
    final slide = widget.slides[slideIndex];
    if (slide.type != SlideType.table) return;
    final rows = slide.tableRows.map((r) => List<String>.from(r)).toList();
    final colCount = rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
    rows.add(List<String>.filled(colCount, ''));
    final updated = slide.copyWith(tableRows: rows);
    _rebuild(() {
      _replaceSlide(widget.slides, slideIndex, updated);
      _tableEditRow = rows.length - 1;
      _tableEditCol = 0;
    });
    widget.onSlideChanged?.call(updated);
    _pushTableToAudience(slideIndex, updated);
  }

  /// Tab loopt door de cellen: aan het einde van een rij naar de volgende
  /// rij, en op de allerlaatste cel voegt het onderaan een nieuwe rij toe.
  /// Shift+Tab loopt terug en stopt bij de eerste cel.
  void _tabTableCell({required bool backwards}) {
    if (!_tableEditMode) return;
    final slide = _currentSlide;
    if (slide.type != SlideType.table) return;
    final rows = slide.tableRows.where((r) => r.isNotEmpty).toList();
    if (rows.isEmpty) return;
    final rowCount = rows.length;
    final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    var row = _tableEditRow ?? 0;
    var col = _tableEditCol ?? 0;
    if (backwards) {
      col -= 1;
      if (col < 0) {
        if (row == 0) return;
        row -= 1;
        col = colCount - 1;
      }
    } else {
      col += 1;
      if (col >= colCount) {
        col = 0;
        row += 1;
      }
      if (row >= rowCount) {
        _addTableRow();
        return;
      }
    }
    _selectTableCell(row, col);
  }

  /// Toetsen tijdens live tabelbewerking.
  ///
  /// Tijdens het bewerken mogen letters (incl. 'e'), cijfers, spatie en
  /// leestekens géén presentatie- of toggle-rol hebben: ze horen in de cel
  /// thuis. Daarom vangen we hier alléén de navigatie (pijltjes/Tab) en het
  /// afsluiten (Esc) af; al het overige laten we los zodat het naar het
  /// tekstveld gaat. We leunen bewust niet op [_textFieldFocused] om dit te
  /// bepalen — die focusstatus is niet altijd betrouwbaar, waardoor een letter
  /// je vroeger soms uit de bewerking gooide. Pijltjes verplaatsen de celkeuze
  /// alleen als er geen tekstveld focus heeft; staat de cursor in een cel, dan
  /// vangt het veld ze zelf op om de tekstcursor te bewegen.
  KeyEventResult _handleTableEditKey(
    LogicalKeyboardKey key, {
    bool shift = false,
  }) {
    switch (key) {
      case LogicalKeyboardKey.escape:
        _exitTableEditMode();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        _tabTableCell(backwards: shift);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.arrowUp:
        // Pijltjes bewegen de tekstcursor binnen de cel, niet tussen cellen of
        // slides. We geven het event vrij (ignored) zodat het naar de tekst-
        // bewerkingsacties van het geselecteerde celveld doorvloeit. Tussen
        // cellen wissel je met Tab, afsluiten doe je met Esc.
        return KeyEventResult.ignored;
      default:
        return KeyEventResult.ignored;
    }
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
