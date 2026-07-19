// De staat van een badge op een thumbnail, en de kleur die daarbij hoort.
//
// Eén vocabulaire voor kwaliteit én privacy, omdat de gebruiker ze naast elkaar
// ziet en er dus hetzelfde van moet kunnen aflezen. Grijs betekent overal
// hetzelfde: hier is iets gevonden, en jij hebt gezegd dat het zo mag.

import 'package:flutter/material.dart';

import '../../models/markdown_validation.dart';
import '../../models/privacy_finding.dart';
import '../../models/slide_quality.dart';
import '../../theme/app_theme.dart';

/// Hoe luid een badge spreekt.
enum SlideBadgeTone {
  /// Niets gevonden — geen badge.
  none,

  /// Gevonden, maar wij zijn er zelf niet zeker van. Onderbreekt niet.
  hint,

  /// Gevonden en waarschijnlijk terecht.
  warning,

  /// Gevonden en ernstig.
  error,

  /// Gevonden, en de auteur heeft gezegd dat het zo hoort.
  ///
  /// Bewust een eigen stand en niet [none]. Een afgehandelde melding
  /// wégpoetsen maakt van accepteren hetzelfde als verbergen: de slide ziet er
  /// daarna uit als een slide waarop niets gevonden is, en dat is een ander
  /// verhaal. Grijs zegt: er is hier iets, en jij weet ervan.
  accepted,
}

extension SlideBadgeToneX on SlideBadgeTone {
  bool get isVisible => this != SlideBadgeTone.none;

  /// Of deze stand nog om een beslissing vraagt. Stuurt de dubbelklik: een
  /// gekleurde badge accepteer je, een grijze draai je terug.
  bool get isOpen =>
      this == SlideBadgeTone.hint ||
      this == SlideBadgeTone.warning ||
      this == SlideBadgeTone.error;

  /// De achtergrondkleur van het badge-plaatje.
  Color get background => switch (this) {
    SlideBadgeTone.none => Colors.transparent,
    SlideBadgeTone.hint => AppTheme.badgeHintOverlay,
    SlideBadgeTone.warning => AppTheme.badgeWarningOverlay,
    SlideBadgeTone.error => AppTheme.badgeErrorOverlay,
    SlideBadgeTone.accepted => AppTheme.badgeAcceptedOverlay,
  };

  Color get foreground => switch (this) {
    SlideBadgeTone.accepted => AppTheme.slate200,
    _ => Colors.white,
  };
}

/// De luidste stand die deze kwaliteitsmeldingen rechtvaardigen.
///
/// Tips tellen bewust niet mee. Een tip is advies over vakmanschap — "deze
/// bullet bevat twee zinnen" — en op elke slide met een tip een badge zetten
/// maakt de hele lijst bont zonder iemand iets te vertellen.
SlideBadgeTone qualityBadgeTone(
  Iterable<SlideQualityIssue> issues, {
  required bool accepted,
}) {
  final actionable = issues.where(
    (i) => i.severity != MarkdownValidationSeverity.informational,
  );
  if (actionable.isEmpty) return SlideBadgeTone.none;
  if (accepted) return SlideBadgeTone.accepted;
  return actionable.any((i) => i.severity == MarkdownValidationSeverity.error)
      ? SlideBadgeTone.error
      : SlideBadgeTone.warning;
}

/// Dezelfde vraag voor privacy, met één verschil: een onzekere treffer krijgt
/// hier wél een badge.
///
/// Bij kwaliteit is een tip advies over vakmanschap; bij privacy is een onzekere
/// treffer een mogelijk persoonsgegeven. Dat zijn niet dezelfde belangen — dus
/// niet dezelfde drempel. De gedempte toon houdt het verschil zichtbaar: hij
/// zegt "kijk hier even", niet "hier gaat iets mis", en dat is precies wat een
/// regel betekent die de contextpoort niet haalde.
SlideBadgeTone privacyBadgeTone(
  Iterable<PrivacyFinding> findings, {
  required bool accepted,
}) {
  if (findings.isEmpty) return SlideBadgeTone.none;
  if (accepted) return SlideBadgeTone.accepted;
  return findings.any((f) => f.confidence != PrivacyConfidence.possible)
      ? SlideBadgeTone.warning
      : SlideBadgeTone.hint;
}

/// De zwaarste van twee standen — behalve als er al beslist is.
///
/// [SlideBadgeTone.accepted] wint altijd: zodra de auteur de slide heeft
/// afgehandeld, spreekt de badge niet meer luid, hoe ernstig de melding op
/// zichzelf ook was. Dat ís de beslissing.
SlideBadgeTone worstBadgeTone(SlideBadgeTone a, SlideBadgeTone b) {
  if (a == SlideBadgeTone.accepted || b == SlideBadgeTone.accepted) {
    return SlideBadgeTone.accepted;
  }
  return a.index >= b.index ? a : b;
}
