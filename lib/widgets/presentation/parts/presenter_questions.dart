// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterQuestions on _FullscreenPresenterState {
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
    // twee opties waarvan er géén als juist is aangemerkt levert een lege
    // [correctIndices] op, dus elk antwoord telt als fout. In de standaard
    // retry-stand vergrendelt zo'n fout niet, waardoor de presentatie muurvast
    // kwam te zitten op een slide die per definitie niet te halen was — alleen
    // afsluiten hielp nog. De tekenroutines hierboven noemen dit geval al
    // "niet presenteerbaar"; hier stond de bijpassende uitweg te smal.
    if (view.correctIndices.isEmpty) return false;
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
    _pushQuestion();
    if (view.hasTimer) _startQuestionTimer(slide.id);
  }

  QuestionView _drawQuestionRound(QuestionSpec spec) {
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
      case QuestionKind.multipleChoice:
        return _drawSingleChoice(spec, base);
    }
  }

  /// Multiple choice: één willekeurig goed antwoord + een willekeurige greep
  /// foute antwoorden, geschud. Eén juist antwoord.
  QuestionView _drawSingleChoice(QuestionSpec spec, QuestionView base) {
    final correct = spec.correctAnswers;
    final wrong = spec.wrongAnswers;
    if (correct.isEmpty || wrong.isEmpty) {
      // Niet presenteerbaar: toon wat er is, zonder timer, en blokkeer niet.
      final all = spec.answers.where((a) => a.text.trim().isNotEmpty).toList();
      return QuestionView(
        options: all.map((a) => a.text).toList(),
        correctIndices: [
          for (var i = 0; i < all.length; i++)
            if (all[i].correct) i,
        ],
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

  /// Meerdere juiste antwoorden: een willekeurige greep met ten minste één goed
  /// én (indien beschikbaar) één fout antwoord. De kijker kiest álle juiste.
  QuestionView _drawMultiCorrect(QuestionSpec spec, QuestionView base) {
    final correct = spec.correctAnswers;
    final wrong = spec.wrongAnswers;
    if (correct.isEmpty) {
      final all = spec.answers.where((a) => a.text.trim().isNotEmpty).toList();
      return QuestionView(
        options: all.map((a) => a.text).toList(),
        correctIndices: [
          for (var i = 0; i < all.length; i++)
            if (all[i].correct) i,
        ],
        multi: true,
      );
    }
    final rng = math.Random();
    final n = spec.optionCount;
    final correctPool = [...correct]..shuffle(rng);
    final wrongPool = [...wrong]..shuffle(rng);
    // Laat ruimte voor minstens één fout antwoord als die er is.
    final maxCorrectShown = wrongPool.isNotEmpty
        ? math.min(correctPool.length, n - 1)
        : math.min(correctPool.length, n);
    final kCorrect = 1 + rng.nextInt(math.max(1, maxCorrectShown));
    final chosenCorrect = correctPool.take(kCorrect).toList();
    final fill = (n - chosenCorrect.length).clamp(0, wrongPool.length);
    final shown = [...chosenCorrect, ...wrongPool.take(fill)]..shuffle(rng);
    final correctSet = chosenCorrect.toSet();
    return base.copyWith(
      options: shown.map((a) => a.text).toList(),
      correctIndices: [
        for (var i = 0; i < shown.length; i++)
          if (correctSet.contains(shown[i])) i,
      ],
      multi: true,
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
      _rebuild(() {
        _questionViews[slide.id] = view.copyWith(
          selectedIndices: [optionIndex],
          result: QuestionResult.correct,
          revealed: true,
          locked: true,
        );
      });
      _pushQuestion();
    } else {
      _resolveWrong(slide.id, selected: [optionIndex]);
    }
  }

  /// Bevestig de selectie bij een meervoudige vraag: goed wanneer precies de
  /// juiste verzameling is aangevinkt (meerdere-juiste) of wanneer de aangetikte
  /// volgorde exact klopt (volgorde-vraag).
  void _onAnswerSubmit({int? slideIndex}) {
    if (slideIndex != null && slideIndex != _index) return;
    final slide = _currentSlide;
    if (slide.type != SlideType.question) return;
    final view = _questionViews[slide.id];
    if (view == null || !view.multi || view.revealed || view.locked) return;
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
      _rebuild(() {
        _questionViews[slide.id] = view.copyWith(
          result: QuestionResult.correct,
          revealed: true,
          locked: true,
        );
      });
      _pushQuestion();
    } else {
      _resolveWrong(slide.id, selected: view.selectedIndices);
    }
  }

  /// Verwerk een fout antwoord of een verlopen timer: toon het juiste antwoord
  /// en bepaal, op basis van [QuestionSpec.onWrong], of er een verse poging
  /// volgt (retry) of dat de slide vergrendeld wordt zodat je verder mag.
  void _resolveWrong(String slideId, {List<int> selected = const []}) {
    final view = _questionViews[slideId];
    if (view == null) return;
    final slide = _currentSlide;
    final spec = QuestionSpec.parse(slide.customMarkdown);
    final lock = spec.onWrong == QuestionOnWrong.lockAndContinue;
    _rebuild(() {
      _questionViews[slideId] = view.copyWith(
        selectedIndices: selected,
        result: QuestionResult.wrong,
        revealed: true,
        locked: lock,
        remainingMs: 0,
      );
    });
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
