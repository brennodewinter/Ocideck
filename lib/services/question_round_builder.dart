import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;

import '../models/question.dart';

/// Trekt één speelronde voor een vraag-slide: gegeven de auteursspecificatie
/// [QuestionSpec] levert [draw] de [QuestionView] die zowel het presentatie- als
/// het publieksscherm tonen. De willekeur — welke foute antwoorden meedoen en in
/// welke volgorde — zit hier, zodat een kijker de vorige ronde niet kan
/// naspelen.
///
/// Bewust een losse klasse en geen methoden meer op `_FullscreenPresenterState`:
/// dit is pure rekenkunde over het model (geen widget, geen `setState`, geen
/// vensterkanaal) en dus op zichzelf te toetsen. De presenter roept alleen [draw]
/// aan en houdt zelf de timer, het oefenlogboek en de vensters bij.
class QuestionRoundBuilder {
  /// [random] is injecteerbaar zodat een test een vaste trekking kan afdwingen;
  /// standaard krijgt elke bouwer een verse bron. De presenter maakt per ronde
  /// een nieuwe bouwer, dus dat blijft één verse trekking per vraag — precies
  /// zoals het eerder ging toen elke tekenroutine haar eigen `math.Random()`
  /// maakte.
  QuestionRoundBuilder({math.Random? random}) : _rng = random ?? math.Random();

  final math.Random _rng;

  /// Trek een nieuwe ronde voor [spec]. [trueLabel]/[falseLabel] zijn de
  /// gelokaliseerde "Juist"/"Onjuist"-teksten voor [QuestionKind.trueFalse]; de
  /// bouwer kent de taallaag zelf niet.
  QuestionView draw(
    QuestionSpec spec, {
    required String trueLabel,
    required String falseLabel,
  }) {
    if (!spec.hasValidAnswerCount) {
      return const QuestionView(answerable: false);
    }
    final view = _byKind(spec, trueLabel: trueLabel, falseLabel: falseLabel);
    // Een vraag die niet te halen is, krijgt ook geen aftelling: die zou alleen
    // maar aftikken naar een fout die nergens toe leidt.
    return view.answerable
        ? view
        : view.copyWith(totalSeconds: 0, remainingMs: 0);
  }

  QuestionView _byKind(
    QuestionSpec spec, {
    required String trueLabel,
    required String falseLabel,
  }) {
    final base = QuestionView(
      totalSeconds: spec.timeLimitSeconds,
      remainingMs: spec.timeLimitSeconds * 1000,
    );
    switch (spec.kind) {
      case QuestionKind.trueFalse:
        return base.copyWith(
          options: [trueLabel, falseLabel],
          correctIndices: [spec.statementIsTrue ? 0 : 1],
        );
      case QuestionKind.multipleCorrect:
        return _multiCorrect(spec, base);
      case QuestionKind.ordering:
        return _ordering(spec, base);
      case QuestionKind.imagePair:
        return _imagePair(spec, base);
      case QuestionKind.openText:
        return _openText(spec, base);
      case QuestionKind.multipleChoice:
        return _singleChoice(spec, base);
      case QuestionKind.matching:
        return _matching(spec, base);
      case QuestionKind.fillIn:
        return _fillIn(spec, base);
      case QuestionKind.hotspot:
        return _hotspot(spec, base);
    }
  }

  // De drie eLearning-vraagsoorten hieronder zijn wél te schrijven en op te
  // slaan, maar nog níet te beantwoorden: de presenter heeft geen
  // koppelkolommen, geen invulvelden en geen aanklikbare regio's. Ze leveren
  // daarom bewust `answerable: false`.
  //
  // Dat is geen voorzichtigheid maar een noodzaak. `_questionBlocksAdvance`
  // houdt het doorbladeren tegen zolang een vraag `answerable` is en nog niet
  // beantwoord is. Met `answerable: true` en geen bruikbare antwoordkant kwam de
  // presentatie muurvast te zitten — alleen afsluiten hielp nog; precies de
  // storing die dat commentaar als eerder opgelost beschrijft. Zet dit pas op
  // `true` samen met de presenter-kant, niet ervoor.

  /// Matching: toont de linkerkolom als leeslijst. De koppeling zelf kan de
  /// kijker nog niet leggen.
  ///
  /// De geschudde rechterkolom is hier bewust weg. Die reisde mee terwijl
  /// `correctIndices` in díe lijst wees en `options` de linkerkolom was — twee
  /// verschillende lijsten met één indexruimte. Elk antwoord dat daarop
  /// beoordeeld werd, was toeval. Komt de presenter-kant er, dan hoort de
  /// rechterkolom een eigen veld op [QuestionView] te krijgen, geen tweede
  /// betekenis van een bestaand veld.
  QuestionView _matching(QuestionSpec spec, QuestionView base) =>
      base.copyWith(
        options: [for (final p in spec.pairs) p.left],
        answerable: false,
      );

  /// FillIn: toont de vraag; de invulvelden zelf kan de kijker nog niet vullen.
  ///
  /// `openText` stond hier aan, maar `_submitTypedAnswer` toetst tegen
  /// `spec.correctAnswers` en die is voor fillIn leeg — het invoerveld slikte
  /// elke poging zonder één reactie.
  QuestionView _fillIn(QuestionSpec spec, QuestionView base) =>
      base.copyWith(answerable: false);

  /// Hotspot: toont de vraag; de regio's zijn nog niet aanklikbaar.
  ///
  /// De regio's kwamen hier als `correctIndices` binnen zonder dat er ooit
  /// `options` bij stonden — nul aanklikbare tegels, dus een vraag die per
  /// definitie onbeantwoordbaar was en tóch het doorbladeren blokkeerde.
  QuestionView _hotspot(QuestionSpec spec, QuestionView base) =>
      base.copyWith(answerable: false);

  /// Beeldpaar: twee afbeeldingen, één juiste. Het willekeurige zit in de kant
  /// waarop de juiste belandt, zodat de kijker de vorige ronde niet kan
  /// naspelen. De editor biedt twee plekken, maar wie er in de Markdown meer
  /// neerzet krijgt hier elke ronde een vers paar — vandaar dat er één juiste
  /// en één foute getrókken worden en niet simpelweg de eerste twee genomen.
  QuestionView _imagePair(QuestionSpec spec, QuestionView base) {
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
    final rng = _rng;
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
  QuestionView _openText(QuestionSpec spec, QuestionView base) =>
      base.copyWith(openText: true, answerable: spec.isPresentable);

  /// Multiple choice: één willekeurig goed antwoord + een willekeurige greep
  /// foute antwoorden, geschud. Eén juist antwoord.
  QuestionView _singleChoice(QuestionSpec spec, QuestionView base) {
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
    final rng = _rng;
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
  QuestionView _multiCorrect(QuestionSpec spec, QuestionView base) {
    final all = spec.filledAnswers;
    final shown = [...all]..shuffle(_rng);
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
  QuestionView _ordering(QuestionSpec spec, QuestionView base) {
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
    final rng = _rng;
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
}
