// De export-gate voor privacybevindingen.
//
// De laatste schakel: detecteren en beslissen is niet genoeg als er vervolgens
// per ongeluk geëxporteerd wordt met bevindingen die niemand heeft bekeken.
//
// Maar een gate die *altijd* blokkeert, is een gate die wordt weggeklikt. Daarom
// drie standen, en de middelste is de standaard: waarschuwen. De gebruiker ziet
// wát er in zijn deck zit en mag er bewust langs. Alleen wie in een omgeving werkt
// waar het een procedure-eis is, zet de harde blokkade aan.

import '../../models/deck.dart';
import '../../models/privacy_disposition.dart';
import '../../models/privacy_finding.dart';

/// Wat er in dit deck zit, geteld naar wat de auteur ermee heeft gedaan.
class PrivacyExportSummary {
  /// Zekere bevindingen op een slide waarvoor nog geen beslissing is genomen.
  /// Dit zijn de enige die de gate tegenhouden.
  final int unresolved;

  final int accepted;
  final int shielded;
  final int redacted;

  const PrivacyExportSummary({
    this.unresolved = 0,
    this.accepted = 0,
    this.shielded = 0,
    this.redacted = 0,
  });

  static const empty = PrivacyExportSummary();

  int get total => unresolved + accepted + shielded + redacted;
  bool get isEmpty => total == 0;
}

/// Telt de bevindingen van [deck] naar hun effectieve stand.
///
/// Alleen **zekere** bevindingen tellen als onafgehandeld. Een informatieve hint
/// — een 9-cijferig getal zonder contextwoord, een art. 9-trefwoord zonder
/// persoon erbij — mag geen export tegenhouden. Zou dat wel zo zijn, dan
/// blokkeert de gate op precies de gevallen waarvan we zelf zeggen dat we het
/// niet zeker weten, en dan wordt hij weggeklikt.
PrivacyExportSummary summarisePrivacyForExport(
  Deck deck,
  PrivacyScanResult scan,
) {
  var unresolved = 0;
  var accepted = 0;
  var shielded = 0;
  var redacted = 0;

  for (final finding in scan.findings) {
    if (finding.confidence != PrivacyConfidence.certain) continue;

    final slide = finding.isDeckWide || finding.slideIndex >= deck.slides.length
        ? null
        : deck.slides[finding.slideIndex];
    final disposition = effectivePrivacyDisposition(
      deck: deck.privacy,
      slide: slide?.privacy,
    );

    switch (disposition) {
      case PrivacyDisposition.warn:
        unresolved++;
      case PrivacyDisposition.accept:
        accepted++;
      case PrivacyDisposition.shield:
        shielded++;
      case PrivacyDisposition.redact:
        redacted++;
    }
  }

  return PrivacyExportSummary(
    unresolved: unresolved,
    accepted: accepted,
    shielded: shielded,
    redacted: redacted,
  );
}

/// De uitkomst van de gate.
class PrivacyExportDecision {
  /// Mag er nu geëxporteerd worden, zonder verdere stappen?
  final bool allowed;

  /// Kan de gebruiker er bewust langs? Onwaar bij een harde blokkade.
  final bool canAcknowledge;

  final PrivacyExportSummary summary;

  const PrivacyExportDecision._({
    required this.allowed,
    this.canAcknowledge = true,
    this.summary = PrivacyExportSummary.empty,
  });

  const PrivacyExportDecision.allow() : this._(allowed: true);

  const PrivacyExportDecision.needsAcknowledgement(
    PrivacyExportSummary summary, {
    bool canAcknowledge = true,
  }) : this._(allowed: false, canAcknowledge: canAcknowledge, summary: summary);

  bool get hardBlocked => !allowed && !canAcknowledge;
}

/// De gate zelf.
class PrivacyExportPolicy {
  final PrivacyExportGate gate;

  const PrivacyExportPolicy({this.gate = PrivacyExportGate.warn});

  /// Er is niets te melden zolang er geen onafgehandelde zekere bevindingen zijn.
  ///
  /// Een deck waarin alles bewust is geaccepteerd, geshield of geredigeerd, gaat
  /// zonder onderbreking door. Dat is de hele bedoeling: de gate straft geen
  /// persoonsgegevens af, hij straft *onopgemerkte* persoonsgegevens af.
  PrivacyExportDecision evaluate(PrivacyExportSummary summary) {
    if (gate == PrivacyExportGate.off) {
      return const PrivacyExportDecision.allow();
    }
    if (summary.unresolved == 0) return const PrivacyExportDecision.allow();

    return PrivacyExportDecision.needsAcknowledgement(
      summary,
      canAcknowledge: gate != PrivacyExportGate.block,
    );
  }
}
