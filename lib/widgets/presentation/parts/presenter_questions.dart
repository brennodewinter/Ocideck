// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterQuestions on _FullscreenPresenterState {
  /// Of de kijker nu een antwoord staat te typen. Afgeleid uit de vraag zelf,
  /// niet apart bijgehouden: zodra er een openstaande getypte vraag op het
  /// scherm staat, horen de toetsen in het invoerveld en niet bij de
  /// sneltoetsen — anders springt een "3" in het antwoord naar slide 3.
  bool get _answerInput {
    final v = _currentQuestionView;
    return v != null && v.openText && v.answerable && !v.revealed && !v.locked;
  }

  /// De live vraag-toestand voor de huidige slide, of null als het geen
  /// vraag-slide is.
  QuestionView? get _currentQuestionView {
    final slide = _currentSlide;
    if (slide.type != SlideType.question) return null;
    return _questionViews[slide.id];
  }

  /// Of doorbladeren vanaf de huidige slide geblokkeerd is omdat een vraag nog
  /// niet (juist) is beantwoord.
  bool get _questionBlocksAdvance {
    final slide = _currentSlide;
    if (slide.type != SlideType.question) return false;
    final view = _questionViews[slide.id];
    if (view == null) return true; // nog niet beantwoord
    // Een onbeantwoordbare vraag mag nooit blokkeren. De maat daarvoor is of er
    // een juist antwoord te géven valt, niet of er opties staan: een vraag met
    // twee opties waarvan er géén als juist is aangemerkt is per definitie niet
    // te halen, dus elk antwoord telt als fout. In de standaard retry-stand
    // vergrendelt zo'n fout niet, waardoor de presentatie muurvast kwam te
    // zitten op zo'n slide — alleen afsluiten hielp nog. De tekenroutines
    // hieronder merken dat geval aan met [QuestionView.answerable].
    if (!view.answerable) return false;
    return !view.passed;
  }

  /// Badge die uitlegt waarom auto-advance stilstaat op een vraagslide;
  /// zonder dit leek de voortgang gewoon "kapot" te zijn.
  Widget _buildQuestionWaitBadge(BuildContext context) {
    return Positioned(
      left: 16,
      bottom: 16,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.hourglass_top_outlined,
                size: 15,
                color: Colors.white70,
              ),
              const SizedBox(width: 7),
              Text(
                context.l10n.d('Wacht op antwoord…'),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// True wanneer de wacht-op-antwoord-badge getoond moet worden: alleen als
  /// auto-play aan staat en een onbeantwoorde vraag het doorschakelen tegenhoudt.
  bool get _showQuestionWaitBadge =>
      _autoPlay && _questionBlocksAdvance && _blank == _Blank.none;

  /// Trek een nieuwe willekeurige set antwoorden voor [slide] en start de timer.
  void _startQuestionRound(Slide slide) {
    final spec = QuestionSpec.parse(slide.customMarkdown);
    final view = _drawQuestionRound(spec);
    _rebuild(() => _questionViews[slide.id] = view);
    // De klok voor déze poging loopt vanaf nu; het tijdenoverzicht na afloop
    // toont elke poging apart.
    if (view.answerable) _rehearsal.startQuestion(slide.id, _index);
    _pushQuestion();
    if (view.hasTimer) _startQuestionTimer(slide.id);
  }

  QuestionView _drawQuestionRound(QuestionSpec spec) {
    final view = _drawByKind(spec);
    // Een vraag die niet te halen is, krijgt ook geen aftelling: die zou alleen
    // maar aftikken naar een fout die nergens toe leidt.
    return view.answerable
        ? view
        : view.copyWith(totalSeconds: 0, remainingMs: 0);
  }

  QuestionView _drawByKind(QuestionSpec spec) {
    final base = QuestionView(
      totalSeconds: spec.timeLimitSeconds,
      remainingMs: spec.timeLimitSeconds * 1000,
    );
    switch (spec.kind) {
      case QuestionKind.trueFalse:
        return base.copyWith(
          options: [context.l10n.d('Juist'), context.l10n.d('Onjuist')],
          correctIndices: [spec.statementIsTrue ? 0 : 1],
        );
      case QuestionKind.multipleCorrect:
        return _drawMultiCorrect(spec, base);
      case QuestionKind.ordering:
        return _drawOrdering(spec, base);
      case QuestionKind.imagePair:
        return _drawImagePair(spec, base);
      case QuestionKind.openText:
        return _drawOpenText(spec, base);
      case QuestionKind.multipleChoice:
        return _drawSingleChoice(spec, base);
    }
  }

  /// Beeldpaar: twee afbeeldingen, één juiste. Het willekeurige zit in de kant
  /// waarop de juiste belandt, zodat de kijker de vorige ronde niet kan
  /// naspelen. De editor biedt twee plekken, maar wie er in de Markdown meer
  /// neerzet krijgt hier elke ronde een vers paar — vandaar dat er één juiste
  /// en één foute getrókken worden en niet simpelweg de eerste twee genomen.
  QuestionView _drawImagePair(QuestionSpec spec, QuestionView base) {
    final pool = spec.filledAnswers;
    if (!spec.isPresentable) {
      return QuestionView(
        options: [for (final a in pool) a.text],
        optionImages: [for (final a in pool) a.image],
        correctIndices: [
          for (var i = 0; i < pool.length; i++)
            if (pool[i].correct) i,
        ],
        answerable: false,
      );
    }
    final rng = math.Random();
    final correct = spec.correctAnswers;
    final wrong = spec.wrongAnswers;
    final shown = <QuestionAnswer>[
      correct[rng.nextInt(correct.length)],
      wrong[rng.nextInt(wrong.length)],
    ]..shuffle(rng);
    return base.copyWith(
      options: [for (final a in shown) a.text],
      optionImages: [for (final a in shown) a.image],
      correctIndices: [
        for (var i = 0; i < shown.length; i++)
          if (shown[i].correct) i,
      ],
    );
  }

  /// Getypt antwoord: er valt niets te tonen tot het antwoord binnen is. De
  /// juiste antwoorden blijven bewust uit de [QuestionView] tot het onthullen —
  /// dit is de weergavetoestand, dus wat erin staat komt op het scherm.
  QuestionView _drawOpenText(QuestionSpec spec, QuestionView base) =>
      base.copyWith(openText: true, answerable: spec.isPresentable);

  /// Multiple choice: één willekeurig goed antwoord + een willekeurige greep
  /// foute antwoorden, geschud. Eén juist antwoord.
  QuestionView _drawSingleChoice(QuestionSpec spec, QuestionView base) {
    final correct = spec.correctAnswers;
    final wrong = spec.wrongAnswers;
    if (correct.isEmpty || wrong.isEmpty) {
      // Niet presenteerbaar: toon wat er is, zonder timer, en blokkeer niet.
      final all = spec.filledAnswers;
      return QuestionView(
        options: all.map((a) => a.text).toList(),
        correctIndices: [
          for (var i = 0; i < all.length; i++)
            if (all[i].correct) i,
        ],
        answerable: false,
      );
    }
    final rng = math.Random();
    final chosenCorrect = correct[rng.nextInt(correct.length)];
    final wrongPool = [...wrong]..shuffle(rng);
    final wrongCount = (spec.optionCount - 1).clamp(0, wrong.length);
    final options = <QuestionAnswer>[
      chosenCorrect,
      ...wrongPool.take(wrongCount),
    ]..shuffle(rng);
    return base.copyWith(
      options: options.map((a) => a.text).toList(),
      correctIndices: [options.indexOf(chosenCorrect)],
    );
  }

  /// Meerdere juiste antwoorden: álle antwoorden, geschud. De kijker moet hier
  /// "alle juiste" aanwijzen, en dat is een onmogelijke opdracht in een set
  /// waar er willekeurig een paar van weggelaten zijn — je kunt niet weten of
  /// het er twee of vijf zijn, en een antwoord dat gisteren goed was ontbreekt
  /// vandaag. Alleen de vólgorde is willekeurig; het aantal getoonde opties uit
  /// de editor geldt hier dan ook niet.
  QuestionView _drawMultiCorrect(QuestionSpec spec, QuestionView base) {
    final all = spec.filledAnswers;
    final shown = [...all]..shuffle(math.Random());
    final indices = [
      for (var i = 0; i < shown.length; i++)
        if (shown[i].correct) i,
    ];
    return base.copyWith(
      options: shown.map((a) => a.text).toList(),
      correctIndices: indices,
      multi: true,
      answerable: indices.isNotEmpty,
    );
  }

  /// Volgorde-vraag: trek een willekeurige greep van [QuestionSpec.optionCount]
  /// antwoorden (hun onderlinge auteursvolgorde is de juiste volgorde) en toon
  /// ze geschud — nooit toevallig al in de juiste volgorde.
  QuestionView _drawOrdering(QuestionSpec spec, QuestionView base) {
    final pool = spec.filledAnswers;
    if (pool.length < 2) {
      // Niet presenteerbaar: toon wat er is, zonder timer, en blokkeer niet.
      return QuestionView(
        options: pool.map((a) => a.text).toList(),
        correctIndices: [for (var i = 0; i < pool.length; i++) i],
        multi: true,
        ordering: true,
        answerable: false,
      );
    }
    final rng = math.Random();
    final count = spec.optionCount.clamp(2, pool.length);
    // Greep uit de pool; sorteren herstelt de (juiste) auteursvolgorde.
    final chosen = (([
      for (var i = 0; i < pool.length; i++) i,
    ]..shuffle(rng)).take(count).toList()..sort());
    final display = [...chosen];
    do {
      display.shuffle(rng);
    } while (listEquals(display, chosen));
    return base.copyWith(
      options: [for (final i in display) pool[i].text],
      correctIndices: [for (final i in chosen) display.indexOf(i)],
      multi: true,
      ordering: true,
    );
  }

  void _startQuestionTimer(String slideId) {
    _questionTimer?.cancel();
    _questionTimer = Timer.periodic(
      const Duration(milliseconds: _questionTickMs),
      (_) {
        if (!mounted) return;
        final view = _questionViews[slideId];
        if (view == null || view.revealed) {
          _questionTimer?.cancel();
          return;
        }
        final remaining = view.remainingMs - _questionTickMs;
        if (remaining <= 0) {
          _questionTimer?.cancel();
          _rebuild(() {
            _questionViews[slideId] = view.copyWith(remainingMs: 0);
          });
          _resolveWrong(slideId);
        } else {
          _rebuild(() {
            _questionViews[slideId] = view.copyWith(remainingMs: remaining);
          });
          _pushQuestion();
        }
      },
    );
  }

  /// Een optie is aangetikt (op dit scherm of op het publieksvenster). Bij
  /// enkelvoudige vragen evalueert dit meteen; bij meerkeuze-met-meerdere-juiste
  /// wisselt het alleen de selectie (bevestigen gaat via [_onAnswerSubmit]).
  void _onAnswerSelected(int optionIndex, {int? slideIndex}) {
    if (slideIndex != null && slideIndex != _index) return;
    final slide = _currentSlide;
    if (slide.type != SlideType.question) return;
    final view = _questionViews[slide.id];
    if (view == null || view.revealed || view.locked) return;
    if (optionIndex < 0 || optionIndex >= view.options.length) return;
    if (view.multi) {
      final selected = [...view.selectedIndices];
      if (!selected.remove(optionIndex)) selected.add(optionIndex);
      _rebuild(() {
        _questionViews[slide.id] = view.copyWith(selectedIndices: selected);
      });
      _pushQuestion();
      return;
    }
    _questionTimer?.cancel();
    if (view.isCorrect(optionIndex)) {
      _resolveCorrect(slide.id, view, selected: [optionIndex]);
    } else {
      _resolveWrong(slide.id, selected: [optionIndex]);
    }
  }

  /// Verwerk een goed antwoord: onthullen, vergrendelen en de poging opnemen in
  /// het tijdenoverzicht.
  void _resolveCorrect(
    String slideId,
    QuestionView view, {
    List<int>? selected,
    String expectedAnswer = '',
    double matchScore = 0,
  }) {
    _rebuild(() {
      _questionViews[slideId] = view.copyWith(
        selectedIndices: selected ?? view.selectedIndices,
        result: QuestionResult.correct,
        revealed: true,
        locked: true,
        expectedAnswer: expectedAnswer,
        matchScore: matchScore,
      );
    });
    _rehearsal.finishQuestion(correct: true);
    _pushQuestion();
  }

  /// Bevestig de selectie bij een meervoudige vraag: goed wanneer precies de
  /// juiste verzameling is aangevinkt (meerdere-juiste) of wanneer de aangetikte
  /// volgorde exact klopt (volgorde-vraag).
  void _onAnswerSubmit({int? slideIndex}) {
    if (slideIndex != null && slideIndex != _index) return;
    final slide = _currentSlide;
    if (slide.type != SlideType.question) return;
    final view = _questionViews[slide.id];
    if (view == null || view.revealed || view.locked) return;
    if (view.openText) {
      _submitTypedAnswer(slide, view);
      return;
    }
    if (!view.multi) return;
    if (view.selectedIndices.isEmpty) return;
    // Een volgorde-antwoord telt pas als álle opties een plek hebben.
    if (view.ordering && !view.orderComplete) return;
    _questionTimer?.cancel();
    final selected = view.selectedIndices.toSet();
    final correct = view.correctIndices.toSet();
    final ok = view.ordering
        ? view.orderMatches
        : selected.length == correct.length && selected.containsAll(correct);
    if (ok) {
      _resolveCorrect(slide.id, view);
    } else {
      _resolveWrong(slide.id, selected: view.selectedIndices);
    }
  }

  /// De kijker heeft zijn getypte antwoord bijgewerkt. Alleen bijhouden en
  /// doorgeven; beoordelen gebeurt pas bij bevestigen.
  void _onAnswerTextChanged(String text) {
    final slide = _currentSlide;
    if (slide.type != SlideType.question) return;
    final view = _questionViews[slide.id];
    if (view == null || !view.openText || view.revealed || view.locked) return;
    _rebuild(() {
      _questionViews[slide.id] = view.copyWith(typedAnswer: text);
    });
    _pushQuestion();
  }

  /// Beoordeel een getypt antwoord: goed zodra het genoeg lijkt op een van de
  /// juiste antwoorden. "Genoeg" is [QuestionSpec.similarityThreshold] — de
  /// auteur bepaalt zelf of een typefout mag.
  void _submitTypedAnswer(Slide slide, QuestionView view) {
    if (view.typedAnswer.trim().isEmpty) return;
    final spec = QuestionSpec.parse(slide.customMarkdown);
    final accepted = [for (final a in spec.correctAnswers) a.text];
    if (accepted.isEmpty) return; // niets om tegen af te zetten
    // Tegen het bést passende antwoord afzetten, niet tegen het eerste: bij
    // meerdere goed gerekende antwoorden is de correctie anders onnavolgbaar.
    final match = bestAnswerMatch(view.typedAnswer, accepted);
    _questionTimer?.cancel();
    if (match.score >= spec.similarityThreshold) {
      _resolveCorrect(
        slide.id,
        view,
        expectedAnswer: match.answer,
        matchScore: match.score,
      );
    } else {
      _resolveWrong(
        slide.id,
        matchScore: match.score,
        expectedAnswer: match.answer,
      );
    }
  }

  /// Verwerk een fout antwoord of een verlopen timer: toon het juiste antwoord
  /// en bepaal, op basis van [QuestionSpec.onWrong], of er een verse poging
  /// volgt (retry) of dat de slide vergrendeld wordt zodat je verder mag.
  void _resolveWrong(
    String slideId, {
    List<int> selected = const [],
    double matchScore = 0,
    String expectedAnswer = '',
  }) {
    final view = _questionViews[slideId];
    if (view == null) return;
    final slide = _currentSlide;
    final spec = QuestionSpec.parse(slide.customMarkdown);
    final lock = spec.onWrong == QuestionOnWrong.lockAndContinue;
    // Pas nú mag het juiste antwoord op het scherm — en dus pas nú in de
    // [QuestionView], die de weergave aanstuurt. Bij een verlopen antwoordtijd
    // komt het hier niet mee, dus wordt het alsnog opgezocht bij wat er stond.
    final expected = !view.openText
        ? ''
        : (expectedAnswer.isNotEmpty
              ? expectedAnswer
              : bestAnswerMatch(view.typedAnswer, [
                  for (final a in spec.correctAnswers) a.text,
                ]).answer);
    _rebuild(() {
      _questionViews[slideId] = view.copyWith(
        selectedIndices: selected,
        result: QuestionResult.wrong,
        revealed: true,
        locked: lock,
        remainingMs: 0,
        expectedAnswer: expected,
        matchScore: matchScore,
      );
    });
    _rehearsal.finishQuestion(correct: false);
    _pushQuestion();
    // Bij retry blijft de fout-feedback staan; een verse set komt pas na een
    // klik (zie [_questionRetryPending] + [_next]), niet automatisch.
  }

  /// True wanneer een fout antwoord is getoond en de presentator op een klik
  /// (volgende/tik) een nieuwe poging moet starten — alleen in de retry-modus.
  bool get _questionRetryPending {
    final slide = _currentSlide;
    if (slide.type != SlideType.question) return false;
    final view = _questionViews[slide.id];
    if (view == null) return false;
    return view.revealed && view.result == QuestionResult.wrong && !view.locked;
  }

  /// Push de huidige vraag-toestand naar het publieksvenster.
  void _pushQuestion() {
    final aw = widget.audience?.controller;
    if (aw == null) return;
    final view = _currentQuestionView;
    audienceChannel
        .invokeMethod('question', {'index': _index, 'view': view?.toJson()})
        .catchError((Object e) {
          // Audience-window sync is best-effort, but a fully silent failure
          // left the beamer out of sync with no trace; make it observable.
          logWarning('FullscreenPresenter: audience window sync failed', e);
          return null;
        });
  }

  /// Geef visuele/auditieve feedback dat de vraag eerst beantwoord moet worden.
  void _nudgeQuestion() {
    if (!mounted) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      context.l10n.d('Beantwoord eerst de vraag.'),
      TextDirection.ltr,
    );
  }
}
