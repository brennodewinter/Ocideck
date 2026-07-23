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

  /// Bevindingen die de auteur één voor één heeft beoordeeld en heeft laten
  /// staan (#651).
  ///
  /// **Ze houden de gate niet tegen, en ze zijn geen oplossing.** Dat lijkt
  /// tegenstrijdig maar is het niet: de gate en de nalevingsteller stellen
  /// verschillende vragen. De gate vraagt *heb je hiernaar gekeken* — en een
  /// terzijdelegging ís per definitie gekeken. MIAUW EIS 1.1 vraagt *hoeveel
  /// staat er in dit document*, en daar mag een oordeel van de auteur niets aan
  /// veranderen.
  ///
  /// Apart geteld en niet bij [accepted] opgeteld, want dat is een beslissing
  /// over een hele dia en dit over één treffer. De exportmelding noemt ze
  /// daarom met zoveel woorden: onzichtbaar meetellen was juist de fout die
  /// #740 meldde.
  final int setAside;

  const PrivacyExportSummary({
    this.unresolved = 0,
    this.accepted = 0,
    this.shielded = 0,
    this.redacted = 0,
    this.setAside = 0,
  });

  static const empty = PrivacyExportSummary();

  int get total => unresolved + accepted + shielded + redacted + setAside;
  bool get isEmpty => total == 0;
}

/// Telt de bevindingen van [deck] naar hun effectieve stand.
///
/// Alleen **zekere** bevindingen tellen als onafgehandeld. Een informatieve hint
/// — een 9-cijferig getal zonder contextwoord, een art. 9-trefwoord zonder
/// persoon erbij — mag geen export tegenhouden. Zou dat wel zo zijn, dan
/// blokkeert de gate op precies de gevallen waarvan we zelf zeggen dat we het
/// niet zeker weten, en dan wordt hij weggeklikt.
/// [isSetAside] zegt of de auteur deze ene bevinding heeft beoordeeld en heeft
/// laten staan (#651). Als predicaat meegegeven en niet zelf opgezocht: daar is
/// de scanner voor nodig, en deze functie hoort zuiver te blijven — zij telt,
/// zij scant niet.
PrivacyExportSummary summarisePrivacyForExport(
  Deck deck,
  PrivacyScanResult scan, {
  bool Function(PrivacyFinding)? isSetAside,
}) {
  var unresolved = 0;
  var accepted = 0;
  var shielded = 0;
  var redacted = 0;
  var setAside = 0;

  for (final finding in scan.findings) {
    if (finding.confidence != PrivacyConfidence.certain) continue;

    // Vóór de dispositie: een terzijdelegging gaat over deze ene treffer, en
    // dat oordeel is specifieker dan de stand van de dia eromheen.
    if (isSetAside != null && isSetAside(finding)) {
      setAside++;
      continue;
    }

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
    setAside: setAside,
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
  /// Een deck waarin alles bewust is geaccepteerd, geshield, geredigeerd of
  /// terzijdegelegd, gaat zonder onderbreking door. Dat is de hele bedoeling: de
  /// gate straft geen persoonsgegevens af, hij straft *onopgemerkte*
  /// persoonsgegevens af.
  ///
  /// Terzijdegelegde bevindingen tellen daarom niet mee (#740). Deden ze dat
  /// wel, dan onderbrak de export op iets dat het paneel niet meer toont — een
  /// blokkade zonder aanwijzing, en precies het soort melding dat mensen leren
  /// wegklikken. Ze staan wél in [PrivacyExportSummary.setAside], zodat de
  /// melding ze kan noemen.
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
