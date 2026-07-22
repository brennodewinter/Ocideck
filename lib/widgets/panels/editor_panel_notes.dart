// Part of the editor_panel library — see editor_panel.dart.
// Split out for navigability (presenter/user notes fields); all imports live in the main
// library file. These top-level widgets relocate verbatim — no behaviour change.
part of 'editor_panel.dart';

class _NotesField extends StatefulWidget {
  final Slide slide;
  final int richTextPage;
  final int richTextPageCount;
  final ValueChanged<Slide> onUpdate;
  const _NotesField({
    required this.slide,
    required this.richTextPage,
    required this.richTextPageCount,
    required this.onUpdate,
  });

  @override
  State<_NotesField> createState() => _NotesFieldState();
}

class _NotesFieldState extends State<_NotesField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _noteText());
    _ctrl.addListener(_emit);
  }

  String _noteText() => speakerNoteForPage(
    widget.slide.notes,
    widget.richTextPage,
    widget.richTextPageCount,
  );

  void _reloadController() {
    _ctrl.removeListener(_emit);
    _ctrl.text = _noteText();
    _ctrl.addListener(_emit);
  }

  @override
  void didUpdateWidget(_NotesField old) {
    super.didUpdateWidget(old);
    if (old.slide.id != widget.slide.id ||
        old.richTextPage != widget.richTextPage ||
        old.slide.notes != widget.slide.notes) {
      _reloadController();
    }
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(
        notes: updateSpeakerNoteForPage(
          widget.slide.notes,
          widget.richTextPage,
          widget.richTextPageCount,
          _ctrl.text,
        ),
      ),
    );
  }

  void _discardNotes() {
    if (_ctrl.text.trim().isEmpty) return;
    _ctrl.removeListener(_emit);
    _ctrl.text = '';
    _ctrl.addListener(_emit);
    widget.onUpdate(
      widget.slide.copyWith(
        notes: updateSpeakerNoteForPage(
          widget.slide.notes,
          widget.richTextPage,
          widget.richTextPageCount,
          '',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: AppTheme.notesBg,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: AppTheme.notesBorder),
        child: ExpansionTile(
          // Leeg begint ingeklapt, gevuld begint open: het paneel toont wat er
          // ís, en kost geen schermruimte aan wat er niet is. De sleutel hoort
          // erbij — `initiallyExpanded` wordt door ExpansionTile alleen in zijn
          // eigen initState gelezen, dus zonder een sleutel die per slide en
          // per pagina verandert, blijft de stand van de vorige slide hangen.
          // Binnen dezelfde slide verandert de sleutel niet, zodat handmatig
          // open- of dichtklappen blijft staan terwijl je typt.
          key: ValueKey(
            'speaker-notes-tile-${widget.slide.id}-p${widget.richTextPage}',
          ),
          initiallyExpanded: _noteText().trim().isNotEmpty,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: const Icon(Icons.notes, size: 18, color: AppTheme.amber700),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.d('Sprekersnotities'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.warningFg,
                  ),
                ),
              ),
              _NotesDiscardButton(
                key: ValueKey('discard-speaker-notes-${widget.slide.id}'),
                controller: _ctrl,
                onDiscard: _discardNotes,
                color: AppTheme.amber700,
              ),
            ],
          ),
          subtitle: _notesPageSubtitle(
            l10n,
            pageIndex: widget.richTextPage,
            pageCount: widget.richTextPageCount,
            emptyHint: l10n.d('Notities voor tijdens het presenteren'),
            hasContent: _noteText().isNotEmpty,
            accent: AppTheme.amber600,
          ),
          children: [
            SizedBox(
              height: _notesEditorHeight(context),
              child: MarkdownNotesEditor.legacy(
                key: ValueKey(
                  'speaker-notes-${widget.slide.id}-p${widget.richTextPage}',
                ),
                controller: _ctrl,
                expand: true,
                baseStyle: TextStyle(
                  fontSize: 12,
                  color: AppTheme.notesText,
                  height: 1.45,
                ),
                linkColor: AppTheme.amber700,
                codeBackground: AppTheme.notesCodeBg,
                hintText: l10n.d('Sprekersnotities...'),
                minLines: 10,
                contentPadding: const EdgeInsets.all(10),
                inputDecoration: InputDecoration(
                  hintText: l10n.d('Sprekersnotities...'),
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.amber600,
                  ),
                  filled: true,
                  fillColor: AppTheme.paper,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppTheme.notesBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppTheme.notesBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppTheme.amber500),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Gebruikersnotities veld ────────────────────────────────────────────────────

class _UserNotesField extends StatefulWidget {
  final Slide slide;
  final String note;
  final int richTextPage;
  final int richTextPageCount;
  final ValueChanged<String> onChanged;

  const _UserNotesField({
    required this.slide,
    required this.note,
    required this.richTextPage,
    required this.richTextPageCount,
    required this.onChanged,
  });

  @override
  State<_UserNotesField> createState() => _UserNotesFieldState();
}

class _UserNotesFieldState extends State<_UserNotesField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.note);
    _ctrl.addListener(_emit);
  }

  @override
  void didUpdateWidget(_UserNotesField old) {
    super.didUpdateWidget(old);
    if (old.slide.id != widget.slide.id ||
        old.note != widget.note ||
        old.richTextPage != widget.richTextPage) {
      _ctrl.removeListener(_emit);
      _ctrl.text = widget.note;
      _ctrl.addListener(_emit);
    }
  }

  void _emit() => widget.onChanged(_ctrl.text);

  void _discardNotes() {
    if (_ctrl.text.trim().isEmpty) return;
    _ctrl.removeListener(_emit);
    _ctrl.text = '';
    _ctrl.addListener(_emit);
    widget.onChanged('');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: AppTheme.infoBg,
      child: Theme(
        data: Theme.of(
          context,
        ).copyWith(dividerColor: AppTheme.userNotesBorder),
        child: ExpansionTile(
          // Zie _NotesField: leeg dicht, gevuld open, en de sleutel zorgt dat
          // die afweging per slide en per pagina opnieuw wordt gemaakt.
          key: ValueKey(
            'user-notes-tile-${widget.slide.id}-p${widget.richTextPage}',
          ),
          initiallyExpanded: widget.note.trim().isNotEmpty,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Icon(
            Icons.edit_note_outlined,
            size: 18,
            color: AppTheme.accentFg,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.d('Gebruikersnotities'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.userNotesAccent,
                  ),
                ),
              ),
              _NotesDiscardButton(
                key: ValueKey('discard-user-notes-${widget.slide.id}'),
                controller: _ctrl,
                onDiscard: _discardNotes,
                color: AppTheme.accent,
              ),
            ],
          ),
          subtitle: _notesPageSubtitle(
            l10n,
            pageIndex: widget.richTextPage,
            pageCount: widget.richTextPageCount,
            emptyHint: l10n.d('Notities voor de ontvanger tijdens een cursus'),
            hasContent: widget.note.trim().isNotEmpty,
            accent: AppTheme.blue400,
          ),
          children: [
            SizedBox(
              height: _notesEditorHeight(context),
              child: MarkdownNotesEditor.legacy(
                key: ValueKey(
                  'user-notes-${widget.slide.id}-p${widget.richTextPage}',
                ),
                controller: _ctrl,
                expand: true,
                baseStyle: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.userNotesText,
                  height: 1.45,
                ),
                linkColor: AppTheme.accentFg,
                codeBackground: AppTheme.infoBg,
                hintText: l10n.d('Gebruikersnotities voor deze slide...'),
                minLines: 10,
                contentPadding: const EdgeInsets.all(10),
                inputDecoration: InputDecoration(
                  hintText: l10n.d('Gebruikersnotities voor deze slide...'),
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.userNotesBorderFocus,
                  ),
                  filled: true,
                  fillColor: AppTheme.paper,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                      color: AppTheme.userNotesBorder,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                      color: AppTheme.userNotesBorder,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppTheme.blue500),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget? _notesPageSubtitle(
  AppLocalizations l10n, {
  required int pageIndex,
  required int pageCount,
  required String emptyHint,
  required bool hasContent,
  required Color accent,
}) {
  if (pageCount <= 1) {
    if (hasContent) return null;
    return Text(emptyHint, style: TextStyle(fontSize: 11, color: accent));
  }
  return Text(
    hasContent
        ? '${l10n.d('Pagina')} ${pageIndex + 1} / $pageCount'
        : '${l10n.d('Pagina')} ${pageIndex + 1} / $pageCount · $emptyHint',
    style: TextStyle(fontSize: 11, color: accent),
  );
}
