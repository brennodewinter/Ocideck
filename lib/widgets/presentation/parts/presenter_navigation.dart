// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterNavigation on _FullscreenPresenterState {
  /// Meld de slidewissel aan schermlezers (WCAG 4.1.3, statusberichten):
  /// visueel verandert de hele slide, maar zonder aankondiging merkt een
  /// schermlezer-gebruiker de wissel niet op.
  void _announceSlide() {
    final total = widget.slides.length;
    if (total == 0 || !mounted) return;
    final slide = widget.slides[_index.clamp(0, total - 1)];
    final title = stripInlineMarkdown(slide.title).trim();
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${context.l10n.d('Slide')} ${_index + 1}/$total'
      '${title.isEmpty ? '' : ': $title'}',
      TextDirection.ltr,
    );
  }

  void _next() {
    if (_userNotesMode) return;
    // Eerste toets/klik op een blanco scherm haalt het scherm terug.
    if (_blank != _Blank.none) {
      _rebuild(() => _blank = _Blank.none);
      return;
    }
    if (_tableEditMode) return;
    final plan = _richTextPlanFor(_currentSlide);
    if (plan != null && _richTextPage < plan.pageCount - 1) {
      _setRichTextPage(_richTextPage + 1);
      return;
    }
    // Een tijdlijn in stapmodus onthult eerst zijn volgende gebeurtenis.
    if (_timelineHasMoreSteps) {
      _rebuild(() => _timelineStep++);
      _syncAudience();
      _announceSlide();
      return;
    }
    // Een vraag-slide houdt je vast tot er (juist) is geantwoord.
    if (_questionBlocksAdvance) {
      // Na een fout antwoord (retry-modus) start een klik een nieuwe poging.
      if (_questionRetryPending) {
        _startQuestionRound(_currentSlide);
      } else {
        _nudgeQuestion();
      }
      return;
    }
    if (_index < widget.slides.length - 1) {
      _persistUserNoteFromController();
      _rebuild(() {
        _index++;
        _richTextPage = 0;
        _timelineStep = 0;
      });
      _loadUserNoteIntoController();
      _scheduleAdvance();
      _announceSlide();
    } else {
      // Voorbij de laatste slide klikken/tikken verlaat de presentatie, zodat je
      // er na de laatste slide gewoon "doorheen" loopt i.p.v. vast te lopen en
      // Esc te moeten zoeken. Alleen handmatige navigatie komt hier langs; de
      // auto-play loopt via [_autoAdvance] en blijft op de laatste slide staan.
      _exit();
    }
  }

  void _prev() {
    if (_userNotesMode) return;
    if (_blank != _Blank.none) {
      _rebuild(() => _blank = _Blank.none);
      return;
    }
    if (_tableEditMode) return;
    if (_richTextPage > 0) {
      _setRichTextPage(_richTextPage - 1);
      return;
    }
    // Stap terug binnen een tijdlijn voordat we naar de vorige slide gaan.
    if (_slideUsesTimelineSteps(_currentSlide) && _timelineStep > 0) {
      _rebuild(() => _timelineStep--);
      _syncAudience();
      _announceSlide();
      return;
    }
    if (_index > 0) {
      _persistUserNoteFromController();
      _rebuild(() {
        _index--;
        final prevPlan = _richTextPlanFor(widget.slides[_index]);
        _richTextPage = prevPlan != null ? prevPlan.pageCount - 1 : 0;
        _timelineStep = 0;
      });
      _loadUserNoteIntoController();
      _scheduleAdvance();
      _announceSlide();
    }
  }

  /// Spring direct naar een slide (vanuit het rasteroverzicht).
  void _jumpTo(int index) {
    _persistUserNoteFromController();
    _rebuild(() {
      _index = index.clamp(0, widget.slides.length - 1);
      _richTextPage = 0;
      _timelineStep = 0;
      _blank = _Blank.none;
      _gridOpen = false;
      _tableEditMode = false;
      _tableEditRow = null;
      _tableEditCol = null;
    });
    _loadUserNoteIntoController();
    _scheduleAdvance();
    _announceSlide();
  }

  /// Ga rechtstreeks naar slide [index] zonder het raster te openen (Home/End).
  void _goTo(int index) {
    if (_blank != _Blank.none) {
      _rebuild(() => _blank = _Blank.none);
      return;
    }
    final target = index.clamp(0, widget.slides.length - 1);
    if (target == _index) return;
    _persistUserNoteFromController();
    _rebuild(() {
      _index = target;
      _richTextPage = 0;
      _timelineStep = 0;
      _tableEditMode = false;
      _tableEditRow = null;
      _tableEditCol = null;
    });
    _loadUserNoteIntoController();
    _scheduleAdvance();
    _announceSlide();
  }

  /// Open de doeltijd-invoer (toets K): cijfers worden voortaan als MMSS
  /// gelezen. Een lege invoer laat de huidige doeltijd ongemoeid.
  void _beginTargetInput() {
    _clearTyped();
    _rebuild(() {
      _targetInput = true;
      _targetTyped = '';
    });
  }

  void _cancelTargetInput() {
    _rebuild(() {
      _targetInput = false;
      _targetTyped = '';
    });
  }

  /// Lees [_targetTyped] als MMSS en zet de doeltijd. Leeg = ongewijzigd,
  /// nul = aftelling uit.
  void _commitTarget() {
    final raw = _targetTyped;
    _rebuild(() {
      _targetInput = false;
      _targetTyped = '';
    });
    if (raw.isEmpty) return;
    final n = int.tryParse(raw) ?? 0;
    final secs = (n ~/ 100) * 60 + (n % 100);
    _rebuild(
      () => _rehearsal.target = secs <= 0 ? null : Duration(seconds: secs),
    );
  }

  void _appendDigit(String d) {
    _rebuild(() {
      _typed += d;
      if (_typed.length > 4) _typed = _typed.substring(_typed.length - 4);
    });
    _typedTimer?.cancel();
    _typedTimer = Timer(const Duration(milliseconds: 2500), _clearTyped);
  }

  void _clearTyped() {
    _typedTimer?.cancel();
    _typedTimer = null;
    if (_typed.isNotEmpty) _rebuild(() => _typed = '');
  }

  /// Spring naar het getypte slidenummer (1-gebaseerd) en wis de invoer.
  void _commitTyped() {
    final n = int.tryParse(_typed);
    _clearTyped();
    if (n != null) _goTo(n - 1);
  }

  /// Verplaats de rastercursor en houd 'm in beeld.
  void _moveGridCursor(int delta) {
    _rebuild(() {
      _gridCursor = (_gridCursor + delta).clamp(0, widget.slides.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollGridToCursor());
  }

  void _setGridCursor(int index) {
    _rebuild(() {
      _gridCursor = index.clamp(0, widget.slides.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollGridToCursor());
  }

  /// Scroll het raster zo dat de cursorrij zichtbaar is (met wat context).
  void _scrollGridToCursor() {
    if (!_gridScroll.hasClients) return;
    final row = _gridCols == 0 ? 0 : _gridCursor ~/ _gridCols;
    final target = (row - 1) * _gridRowExtent; // één rij context erboven
    final max = _gridScroll.position.maxScrollExtent;
    _gridScroll.animateTo(
      target.clamp(0.0, max),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _toggleGrid() {
    _rebuild(() {
      _gridOpen = !_gridOpen;
      if (_gridOpen) {
        _blank = _Blank.none;
        _gridCursor = _index;
      }
    });
    if (_gridOpen) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollGridToCursor(),
      );
    }
  }

  /// Zet het scherm op zwart/wit, of terug naar de slide bij dezelfde toets.
  void _toggleBlank(_Blank target) {
    _rebuild(() {
      _blank = _blank == target ? _Blank.none : target;
      if (_blank != _Blank.none) _gridOpen = false;
    });
  }

  void _toggleHelp() {
    _rebuild(() => _helpOpen = !_helpOpen);
  }

  void _togglePresenterView() {
    _rebuild(() => _presenterView = !_presenterView);
  }

  void _resetTimer() {
    _rebuild(() => _rehearsal.reset());
  }
}
