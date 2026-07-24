// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterNotes on _FullscreenPresenterState {
  void _onUserNoteTextChanged() {
    if (!_userNotesMode || _userNoteCtrl == null) return;
    final slide = widget.slides[_index.clamp(0, widget.slides.length - 1)];
    final text = _userNoteCtrl!.text;
    final next = Map<String, String>.from(_userNotes);
    final key = _userNoteKeyFor(slide);
    if (text.trim().isEmpty) {
      next.remove(key);
      if (_userNotesMultiPage(slide) && _richTextPage == 0) {
        next.remove(slide.id);
      }
    } else {
      next[key] = text;
      if (_userNotesMultiPage(slide) && _richTextPage == 0) {
        next.remove(slide.id);
      }
    }
    _userNotes = next;
    widget.onUserNotesChanged?.call(Map<String, String>.from(_userNotes));
  }

  void _persistUserNoteFromController() {
    if (!_userNotesMode || _userNoteCtrl == null) return;
    final slide = widget.slides[_index.clamp(0, widget.slides.length - 1)];
    final text = _userNoteCtrl!.text;
    final next = Map<String, String>.from(_userNotes);
    final key = _userNoteKeyFor(slide);
    if (text.trim().isEmpty) {
      next.remove(key);
      if (_userNotesMultiPage(slide) && _richTextPage == 0) {
        next.remove(slide.id);
      }
    } else {
      next[key] = text;
      if (_userNotesMultiPage(slide) && _richTextPage == 0) {
        next.remove(slide.id);
      }
    }
    _userNotes = next;
    widget.onUserNotesChanged?.call(Map<String, String>.from(_userNotes));
  }

  void _loadUserNoteIntoController() {
    if (!_userNotesMode || _userNoteCtrl == null) return;
    final slide = widget.slides[_index.clamp(0, widget.slides.length - 1)];
    final text = _userNoteTextFor(slide);
    if (_userNoteCtrl!.text == text) return;
    _userNoteCtrl!.removeListener(_onUserNoteTextChanged);
    _userNoteCtrl!.text = text;
    _userNoteCtrl!.addListener(_onUserNoteTextChanged);
  }

  void _openUserNotesMode() {
    _rebuild(() {
      _userNotesMode = true;
      _userNoteCtrl ??= TextEditingController();
      _userNoteCtrl!.removeListener(_onUserNoteTextChanged);
      _userNoteCtrl!.text = _userNoteTextFor(
        widget.slides[_index.clamp(0, widget.slides.length - 1)],
      );
      _userNoteCtrl!.addListener(_onUserNoteTextChanged);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _userNotesFocusNode.requestFocus();
    });
  }

  void _closeUserNotesMode() {
    if (!_userNotesMode) return;
    _persistUserNoteFromController();
    _rebuild(() {
      _userNotesMode = false;
      _userNoteCtrl?.removeListener(_onUserNoteTextChanged);
      _userNoteCtrl?.dispose();
      _userNoteCtrl = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _toggleUserNotesMode() {
    if (_userNotesMode) {
      _closeUserNotesMode();
    } else {
      _openUserNotesMode();
    }
  }

  /// Lokaal paneel voor gebruikersnotities (ontvanger/cursist); nooit op beamer.
  Widget _buildUserNotesOverlay() {
    final l10n = context.l10n;
    final profile = widget.themeProfile;
    final slide = _currentSlide;
    final pageCount = _richTextPageCountFor(slide);
    final showPageLabel = pageCount > 1;
    final bg = AppTheme.parseHexColor(profile.slideBackgroundColor);
    final fg = AppTheme.parseHexColor(profile.textColor);
    final accent = AppTheme.parseHexColor(profile.accentColor);
    return Positioned(
      top: 24,
      right: 24,
      bottom: 24,
      width: 360,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.edit_note_outlined, color: accent, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.d('Mijn notities'),
                                style: TextStyle(
                                  fontFamily: profile.fontFamily,
                                  color: fg,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (showPageLabel)
                                Text(
                                  '${l10n.d('Pagina')} ${_richTextPage + 1} / $pageCount',
                                  style: TextStyle(
                                    fontFamily: profile.fontFamily,
                                    color: fg.withValues(alpha: 0.55),
                                    fontSize: 11,
                                  ),
                                ),
                              Text(
                                l10n.d('PgUp/PgDn bladert door de slides'),
                                style: TextStyle(
                                  fontFamily: profile.fontFamily,
                                  color: fg.withValues(alpha: 0.45),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: l10n.d('Sluiten'),
                          onPressed: _closeUserNotesMode,
                          icon: Icon(
                            Icons.close,
                            color: fg.withValues(alpha: 0.6),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: NotesModeToggle(
                        mode: _userNotesEditorMode,
                        onModeChanged: (mode) =>
                            _rebuild(() => _userNotesEditorMode = mode),
                        style: NotesModeToggleStyle.compact,
                        foregroundColor: fg,
                        accentColor: accent,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: accent.withValues(alpha: 0.35)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: KeyedSubtree(
                    key: const ValueKey('presenter-user-notes'),
                    child: MarkdownNotesEditor(
                      key: ValueKey(
                        'presenter-user-notes-${slide.id}-p$_richTextPage',
                      ),
                      controller: _userNoteCtrl!,
                      focusNode: _userNotesFocusNode,
                      mode: _userNotesEditorMode,
                      onModeChanged: (mode) =>
                          _rebuild(() => _userNotesEditorMode = mode),
                      showModeToggle: false,
                      expand: true,
                      compactToolbar: true,
                      editorTheme: MarkdownEditorTheme.presenterOverlay(
                        panelBackground: bg,
                        panelText: fg,
                        accent: accent,
                        fontFamily: profile.fontFamily,
                      ),
                      hintText: l10n.d('Gebruikersnotities voor deze slide...'),
                      minLines: 8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotes(Slide slide) {
    final l10n = context.l10n;
    final pageCount = _richTextPageCountFor(slide);
    final notes = speakerNoteForPage(slide.notes, _richTextPage, pageCount);
    final showPageLabel = pageCount > 1;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PresenterPalette.bg2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PresenterPalette.surface2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showPageLabel)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${l10n.d('Pagina')} ${_richTextPage + 1} / $pageCount',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Expanded(
            child: notes.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      l10n.d('Geen notities voor deze slide.'),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Text(
                      notes,
                      style: const TextStyle(
                        color: PresenterPalette.text,
                        fontSize: 17,
                        height: 1.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
