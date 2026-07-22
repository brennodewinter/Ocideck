import 'package:flutter/foundation.dart';

/// Tijd die tijdens een oefenrun aan één slide is besteed.
///
/// Sessie-only: niets hiervan wordt op schijf bewaard (geen prefs, geen `.md`).
/// Het bestand blijft inhoud; oefentijden leven alleen in het draaiende
/// presenter-venster.
@immutable
class SlideTiming {
  /// Stabiele slide-id binnen de sessie ([Slide.id]).
  final String slideId;

  /// 0-gebaseerde positie waarop de slide voor het eerst werd getoond. Dient
  /// alleen voor een stabiele weergavevolgorde in de samenvatting.
  final int index;

  /// Opgetelde wandkloktijd op deze slide over de hele run (een slide kan
  /// meerdere keren bezocht zijn).
  final Duration spent;

  const SlideTiming({
    required this.slideId,
    required this.index,
    required this.spent,
  });
}

/// Eén beantwoorde poging op een vraagslide: hoe lang erover gedaan is en of
/// het antwoord goed was.
///
/// Bewust per póging en niet per vraag opgeteld: een vraag die in de
/// 'opnieuw proberen'-stand staat wordt net zo vaak beantwoord als nodig, en
/// juist het verloop daarvan zegt iets — de derde poging binnen vijf seconden
/// is een ander verhaal dan één poging van twee minuten.
@immutable
class QuestionAttempt {
  /// Stabiele slide-id binnen de sessie ([Slide.id]).
  final String slideId;

  /// 0-gebaseerde positie van de vraagslide, voor een stabiele volgorde.
  final int index;

  /// Tijd tussen het tonen van deze ronde en het antwoord.
  final Duration spent;

  /// Of deze poging goed was. Een verlopen antwoordtijd telt als fout.
  final bool correct;

  const QuestionAttempt({
    required this.slideId,
    required this.index,
    required this.spent,
    required this.correct,
  });
}

/// Samenvatting van één oefenrun in de huidige sessie: totale tijd, de
/// (optionele) doeltijd, de tijd per slide en de beantwoorde vragen. Puur
/// beschrijvend — er zit geen pacing-advies in, alleen gemeten tijd.
@immutable
class RehearsalRun {
  final Duration total;
  final Duration? target;
  final List<SlideTiming> perSlide;

  /// Elke beantwoorde vraagpoging, in de volgorde waarin ze beantwoord zijn.
  final List<QuestionAttempt> questionAttempts;

  const RehearsalRun({
    required this.total,
    required this.target,
    required this.perSlide,
    this.questionAttempts = const [],
  });

  /// Verschil t.o.v. de doeltijd: positief = over de tijd, negatief = ruim
  /// binnen. Null wanneer er geen doeltijd was.
  Duration? get delta => target == null ? null : total - target!;
}
