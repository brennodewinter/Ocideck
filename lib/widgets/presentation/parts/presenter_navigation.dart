// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

/// Het id van de dia die bij het verlaten van de presentatie in beeld is (#1111),
/// zodat de editor daarna díe dia selecteert en niet terugspringt naar de
/// startdia. Via het **id**, niet de rauwe render-index: de presenter toont
/// uitgeklapte findings-pagina's, dus render-index ≠ bron-dia-index — de launcher
/// mapt het id terug op de bron-dia, net als `onSlideChanged`. Een leeg deck (de
/// `total == 0`-exit in [build]) geeft null. Top-level zodat het de toch al forse
/// [_FullscreenPresenterState] niet verder laat groeien.
String? _exitSlideId(List<Slide> slides, int index) =>
    slides.isEmpty ? null : slides[index.clamp(0, slides.length - 1)].id;

/// De render-index van de eerste dia met [anchor] (#1162), of null als geen dia
/// het draagt — dan valt een sprong fail-safe terug op lineair. Zoekt in de
/// render-uitgeklapte lijst, dus een sprong landt op de eerste pagina van de
/// doeldia. Top-level zodat het de forse [_FullscreenPresenterState] niet groeit.
int? _indexOfAnchor(List<Slide> slides, String anchor) {
  if (anchor.isEmpty) return null;
  for (var i = 0; i < slides.length; i++) {
    if (slides[i].anchor == anchor) return i;
  }
  return null;
}

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

  /// Meld een stap-onthulling aan schermlezers (§12.2): welke bullet zichtbaar
  /// werd en hoeveel callout-targets ermee kwamen. Voor een tijdlijn-stap meldt
  /// dit het nieuwe gebeurtenisnummer.
  void _announceStep() {
    if (!mounted) return;
    final slide = _currentSlide;
    final plan = _planFor(slide);
    if (plan is TimelineStepPlan) {
      final n = plan.revealedEventCount(_stepIndex);
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${context.l10n.d('Gebeurtenis')} $n/${plan.eventCount}',
        TextDirection.ltr,
      );
    } else if (plan is CalloutRevealStepPlan) {
      final bulletCount = plan.revealedBulletCount(_stepIndex);
      // Het aantal markeringen dat bij *deze* stap verscheen — niet het totaal
      // dat al stond (§12.2). Anders meldt een bullet zonder verwijzing de
      // markeringen van de vorige stap opnieuw, en telde één verwijzing met
      // twee targets voor één.
      final marks = plan.marksAtStep(_stepIndex);
      final position =
          '${context.l10n.d('Punt')} $bulletCount/${plan.bullets.length}';
      final msg = marks == 0
          ? position
          : '$position, $marks '
                '${marks == 1 ? context.l10n.d('markering') : context.l10n.d('markeringen')}';
      SemanticsService.sendAnnouncement(
        View.of(context),
        msg,
        TextDirection.ltr,
      );
    }
  }

  /// Ga voorwaarts naar [target] en onthoud de dia die je verlaat op de
  /// retrace-stack, zodat "terug" langs de werkelijke route loopt (#1162).
  void _advanceTo(int target) {
    _commitActiveInk();
    _persistUserNoteFromController();
    _rebuild(() {
      _jumpHistory.add(_index);
      _index = target;
      _richTextPage = 0;
      // Een andere dia begint weer bij de eerste menucategorie (#1162).
      _menuCategory = 0;
      _stepIndex = 0;
    });
    _loadUserNoteIntoController();
    _scheduleAdvance();
    _announceSlide();
  }

  /// Spring naar de dia met [anchor] (#1162, een klik op een keuze-menublok).
  /// Onbekend anker = niets doen (fail-safe). De sprong gaat via [_advanceTo], dus
  /// "terug" keert netjes terug naar de menudia.
  void _jumpToAnchor(String anchor) {
    final target = _indexOfAnchor(widget.slides, anchor);
    if (target != null) _advanceTo(target);
  }

  void _next({bool allowInUserNotes = false}) {
    // Met het notitiepaneel open bladert alleen PgUp/PgDn expliciet door;
    // klikken en overige toetsen blijven bij het tekstveld.
    if (_userNotesMode && !allowInUserNotes) return;
    // Navigeren maakt een half getypt slidenummer irrelevant: meteen wissen
    // i.p.v. de badge nog 2,5 s te laten staan.
    _clearTyped();
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
    // Een slide in stapmodus (tijdlijn of callout-reveal) onthult eerst zijn
    // volgende stap voordat hij naar de volgende dia gaat (§7).
    if (_planHasMoreSteps) {
      _rebuild(() => _stepIndex++);
      _syncAudience();
      _announceStep();
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
    // Een per-dia sprong-uit (#1162) gaat vóór de lineaire volgorde: is er een
    // vindbaar doelanker, dan springen we daarheen — ook voorbij de laatste dia,
    // zodat een tak vanaf het eind terug naar het menu kan keren.
    final jumpIndex = _indexOfAnchor(widget.slides, _currentSlide.nextAnchor);
    if (jumpIndex != null) {
      _advanceTo(jumpIndex);
    } else if (_index < widget.slides.length - 1) {
      _advanceTo(_index + 1);
    } else {
      // Voorbij de laatste slide klikken/tikken verlaat de presentatie, zodat je
      // er na de laatste slide gewoon "doorheen" loopt i.p.v. vast te lopen en
      // Esc te moeten zoeken. Alleen handmatige navigatie komt hier langs; de
      // auto-play loopt via [_autoAdvance] en blijft op de laatste slide staan.
      _exit();
    }
  }

  void _prev({bool allowInUserNotes = false}) {
    if (_userNotesMode && !allowInUserNotes) return;
    _clearTyped();
    if (_blank != _Blank.none) {
      _rebuild(() => _blank = _Blank.none);
      return;
    }
    if (_tableEditMode) return;
    if (_richTextPage > 0) {
      _setRichTextPage(_richTextPage - 1);
      return;
    }
    // Stap terug binnen een plan (tijdlijn of callout-reveal) voordat we naar
    // de vorige slide gaan (§7).
    if (_planFor(_currentSlide).hasSteps && _stepIndex > 0) {
      _rebuild(() => _stepIndex--);
      _syncAudience();
      _announceStep();
      return;
    }
    // "Terug" volgt de werkelijke route (#1162): pop de dia die we het laatst
    // verlieten. Zo keer je na een menusprong terug náár het menu i.p.v. naar de
    // vorige brondia. Een lineair deck heeft `[0,1,2,…]` op de stack, dus dit valt
    // samen met het oude `_index--`. Is de stack leeg (bv. gestart middenin het
    // deck), dan gewoon één brondia terug.
    final target = _jumpHistory.isNotEmpty
        ? _jumpHistory.removeLast().clamp(0, widget.slides.length - 1)
        : (_index > 0 ? _index - 1 : null);
    if (target == null) return;
    _commitActiveInk();
    _persistUserNoteFromController();
    _rebuild(() {
      _index = target;
      final prevPlan = _richTextPlanFor(widget.slides[_index]);
      _richTextPage = prevPlan != null ? prevPlan.pageCount - 1 : 0;
      _stepIndex = 0;
    });
    _loadUserNoteIntoController();
    _scheduleAdvance();
    _announceSlide();
  }

  /// Spring direct naar een slide (vanuit het rasteroverzicht).
  void _jumpTo(int index) {
    _commitActiveInk();
    _persistUserNoteFromController();
    _rebuild(() {
      _index = index.clamp(0, widget.slides.length - 1);
      _richTextPage = 0;
      // Een andere dia begint weer bij de eerste menucategorie (#1162).
      _menuCategory = 0;
      _stepIndex = 0;
      _blank = _Blank.none;
      _gridOpen = false;
      _tableEditMode = false;
      _tableEditRow = null;
      _tableEditCol = null;
      // Een expliciete teleport breekt de route: "terug" is daarna lineair (#1162).
      _jumpHistory.clear();
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
    _commitActiveInk();
    _persistUserNoteFromController();
    _rebuild(() {
      _index = target;
      _richTextPage = 0;
      // Een andere dia begint weer bij de eerste menucategorie (#1162).
      _menuCategory = 0;
      _stepIndex = 0;
      _tableEditMode = false;
      _tableEditRow = null;
      _tableEditCol = null;
      // Een expliciete teleport breekt de route: "terug" is daarna lineair (#1162).
      _jumpHistory.clear();
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
