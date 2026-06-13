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

/// Samenvatting van één oefenrun in de huidige sessie: totale tijd, de
/// (optionele) doeltijd en de tijd per slide. Puur beschrijvend — er zit
/// geen pacing-advies in, alleen gemeten tijd.
@immutable
class RehearsalRun {
  final Duration total;
  final Duration? target;
  final List<SlideTiming> perSlide;

  const RehearsalRun({
    required this.total,
    required this.target,
    required this.perSlide,
  });

  /// Verschil t.o.v. de doeltijd: positief = over de tijd, negatief = ruim
  /// binnen. Null wanneer er geen doeltijd was.
  Duration? get delta => target == null ? null : total - target!;
}
