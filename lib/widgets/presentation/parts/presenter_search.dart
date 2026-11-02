// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
part of '../fullscreen_presenter.dart';

typedef _PresenterSearchPage = ({Slide slide, int index, int page});

extension _PresenterSearch on _FullscreenPresenterState {
  Future<void> _openSearch() async {
    if (_searchOpen) return;
    if (!_dual || widget.audience!.isClosed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.d(
              'Start met een apart presentatorvenster om privé te zoeken.',
            ),
          ),
        ),
      );
      return;
    }
    // Ook doorgestuurde clickertoetsen mogen tijdens zoeken niet navigeren.
    _searchOpen = true;
    _autoPlay = false;
    _advanceTimer?.cancel();
    _progress.value = 0;
    if (_timedSession.phase == _TimedSessionPhase.countdown) {
      _timedSession.prepare();
    } else {
      _timedSession.pauseIfRunning();
    }
    final pages = <_PresenterSearchPage>[];
    for (var i = 0; i < widget.slides.length; i++) {
      final slide = widget.slides[i];
      if (!slideReachesAudience(
        slide,
        presentationTlp: widget.tlp,
        includeDetail: true,
      )) {
        continue;
      }
      final plan = _richTextPlanFor(slide);
      if (plan == null || plan.pageCount <= 1) {
        pages.add((slide: slide, index: i, page: 0));
      } else {
        for (var p = 0; p < plan.pageCount; p++) {
          pages.add((
            slide: slide.copyWith(
              title: p == 0 ? slide.title : '',
              subtitle: p == 0 ? slide.subtitle : '',
              notes: speakerNoteForPage(slide.notes, p, plan.pageCount),
              customMarkdown: plan.markdownForPage(p),
            ),
            index: i,
            page: p,
          ));
        }
      }
    }
    try {
      final target = await showDialog<_PresenterSearchPage>(
        context: context,
        builder: (_) => _PresenterSearchDialog(
          pages: pages,
          canShow: !_timedManualAdvanceBlocked(this),
          session: _searchSession,
        ),
      );
      if (!mounted) return;
      // De publicatieactie toetst de bestaande sessie- en projectiegrenzen opnieuw.
      if (target != null &&
          !widget.audience!.isClosed &&
          !_timedManualAdvanceBlocked(this) &&
          target.index < widget.slides.length &&
          widget.slides[target.index].id == target.slide.id &&
          slideReachesAudience(
            widget.slides[target.index],
            presentationTlp: widget.tlp,
            includeDetail: true,
          )) {
        _jumpTo(target.index);
        if (target.page > 0) _setRichTextPage(target.page);
      }
    } finally {
      _searchOpen = false;
      if (mounted) {
        _rebuild(() {});
        _focusNode.requestFocus();
      }
    }
  }
}

class _PresenterSearchSession {
  String query = '';
  bool notes = false;
  int selected = 0;
  bool entered = false;
  int wrapDirection = 0;
}

class _PresenterSearchDialog extends StatefulWidget {
  const _PresenterSearchDialog({
    required this.pages,
    required this.canShow,
    required this.session,
  });
  final List<_PresenterSearchPage> pages;
  final bool canShow;
  final _PresenterSearchSession session;

  @override
  State<_PresenterSearchDialog> createState() => _PresenterSearchDialogState();
}

class _PresenterSearchDialogState extends State<_PresenterSearchDialog> {
  late final _query = TextEditingController(text: widget.session.query);
  final _scroll = ScrollController();

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = widget.session;
    final matches = searchDeckText(
      Deck(title: '', slides: [for (final p in widget.pages) p.slide]),
      session.query,
      includeNotes: session.notes,
    );
    final index = session.selected.clamp(
      0,
      matches.isEmpty ? 0 : matches.length - 1,
    );
    final selected = matches.isEmpty ? null : matches[index];
    void step(int delta) {
      if (matches.isEmpty) return;
      setState(() {
        session.wrapDirection =
            session.entered &&
                (index + delta < 0 || index + delta >= matches.length)
            ? delta
            : 0;
        session.selected = session.entered
            ? (index + delta) % matches.length
            : (delta < 0 ? matches.length - 1 : 0);
        session.entered = true;
      });
      _scroll.jumpTo(0);
    }

    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        title: Text(l10n.d('Privé zoeken')),
        content: SizedBox(
          width: 680,
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.d(
                        'Het publiek blijft op de huidige dia tot je Toon dia kiest. Automatisch doorspelen is gepauzeerd. Deel alleen het publieksvenster, niet je hele bureaublad.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _queryField(step),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.d('Ook in sprekersnotities')),
                      value: session.notes,
                      onChanged: (value) => setState(() {
                        session.notes = value ?? false;
                        session.selected = 0;
                        session.entered = false;
                        session.wrapDirection = 0;
                      }),
                    ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            session.query.isEmpty
                                ? l10n.d('Typ om te zoeken')
                                : matches.isEmpty
                                ? l10n.d(
                                    'Geen resultaten. Probeer een kortere zoektekst.',
                                  )
                                : '${index + 1}/${matches.length}',
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.d('Vorige treffer'),
                          onPressed: matches.isEmpty ? null : () => step(-1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: l10n.d('Volgende treffer'),
                          onPressed: matches.isEmpty ? null : () => step(1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                      ],
                    ),
                    if (session.wrapDirection != 0)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          session.wrapDirection < 0
                              ? l10n.d('Verder vanaf het einde')
                              : l10n.d('Verder vanaf het begin'),
                        ),
                      ),
                    if (selected != null)
                      Semantics(
                        liveRegion: true,
                        child: _result(
                          matches[index],
                          index,
                          index,
                          preview: true,
                        ),
                      ),
                  ],
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _result(matches[i], i, index),
                  childCount: matches.length,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.d('Sluiten')),
          ),
          FilledButton(
            onPressed: selected == null || !widget.canShow
                ? null
                : () =>
                      Navigator.pop(context, widget.pages[selected.slideIndex]),
            child: Text(l10n.d('Toon dia')),
          ),
        ],
      ),
    );
  }

  Widget _queryField(ValueChanged<int> step) {
    final l10n = context.l10n;
    final session = widget.session;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () => step(1),
        const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
            step(-1),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () => step(1),
        const SingleActivator(
          LogicalKeyboardKey.numpadEnter,
          shift: true,
        ): () =>
            step(-1),
      },
      child: TextField(
        key: const ValueKey('presenter-search-query'),
        controller: _query,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onEditingComplete: () {},
        decoration: InputDecoration(labelText: l10n.d('Zoeken')),
        onChanged: (value) => setState(() {
          session.query = value;
          session.selected = 0;
          session.entered = false;
          session.wrapDirection = 0;
        }),
        onSubmitted: (_) =>
            step(HardwareKeyboard.instance.isShiftPressed ? -1 : 1),
      ),
    );
  }

  Widget _result(
    DeckTextMatch match,
    int i,
    int index, {
    bool preview = false,
  }) {
    final l10n = context.l10n;
    final session = widget.session;
    final page = widget.pages[match.slideIndex];
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final range in findAllMatches(match.context, session.query)) {
      spans.add(TextSpan(text: match.context.substring(cursor, range.start)));
      spans.add(
        TextSpan(
          text: match.context.substring(range.start, range.end),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.underline,
          ),
        ),
      );
      cursor = range.end;
    }
    spans.add(TextSpan(text: match.context.substring(cursor)));
    return ListTile(
      selected: i == index,
      title: Text(
        '${l10n.d('Slide')} ${page.index + 1} · ${l10n.d(match.fieldLabel)}${page.page > 0 ? ' · ${l10n.d('Pagina')} ${page.page + 1}' : ''}',
      ),
      subtitle: Text.rich(TextSpan(children: spans)),
      onTap: preview
          ? null
          : () => setState(() {
              session.selected = i;
              session.entered = true;
            }),
    );
  }
}
