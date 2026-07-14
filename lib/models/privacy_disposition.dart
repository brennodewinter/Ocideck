// Wat er met een privacybevinding gebeurt.
//
// De scanner meldt; de auteur beslist. Een politiebriefing bevat per definitie
// persoonsgegevens en een pentestrapport bevat per definitie buitgemaakte
// credentials — de tool mag daar niet tegen vechten. Maar hij moet wél kunnen
// laten zien dát het erin zit, en de ontvanger kunnen waarschuwen.

/// De stand van een slide (of van het hele deck) ten aanzien van
/// privacybevindingen.
enum PrivacyDisposition {
  /// Nog geen beslissing genomen. De bevindingen staan in het kwaliteitspaneel;
  /// op de slide zelf is niets te zien. Dit is de standaard.
  warn,

  /// Bewust aanwezig, dit hoort hier. Geen melding meer, geen markering op de
  /// slide. De briefing van de recherche staat hierop.
  accept,

  /// Bewust aanwezig, én de ontvanger wordt gewaarschuwd: de slide krijgt een
  /// privacy-badge, net als een TLP-markering. Wie het deck krijgt, weet dat er
  /// persoonsgegevens in staan.
  shield,

  /// De gevonden gegevens worden onleesbaar gemaakt op het scherm en in de
  /// export. De bron-markdown houdt de oorspronkelijke tekst.
  redact,
}

extension PrivacyDispositionX on PrivacyDisposition {
  /// De stabiele sleutel in de markdown. `warn` is de standaard en wordt nooit
  /// weggeschreven.
  String get key => switch (this) {
    PrivacyDisposition.warn => 'warn',
    PrivacyDisposition.accept => 'accept',
    PrivacyDisposition.shield => 'shield',
    PrivacyDisposition.redact => 'redact',
  };

  /// Of deze stand de bevindingen als afgehandeld beschouwt. Een afgehandelde
  /// bevinding hoeft de gebruiker niet meer te onderbreken.
  bool get isResolved => this != PrivacyDisposition.warn;

  static PrivacyDisposition fromKey(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'accept' => PrivacyDisposition.accept,
      'shield' => PrivacyDisposition.shield,
      'redact' => PrivacyDisposition.redact,
      _ => PrivacyDisposition.warn,
    };
  }
}

/// De stand die werkelijk geldt voor een slide.
///
/// De slide overschrijft het deck. Anders dan bij TLP, waar het strengste niveau
/// wint: hier weet de auteur van de individuele slide het beter. Een deck op
/// `accept` (de hele briefing is bekend) met één slide op `redact` (dit ene
/// gegeven mag niemand zien) moet gewoon werken.
PrivacyDisposition effectivePrivacyDisposition({
  required PrivacyDisposition deck,
  required PrivacyDisposition? slide,
}) => slide ?? deck;

/// Hoe streng de export-gate is.
///
/// Waarschuwen is de standaard, want een gate die *altijd* blokkeert is een gate
/// die wordt weggeklikt. De harde blokkade is er voor omgevingen waar het een
/// procedure-eis is.
enum PrivacyExportGate {
  /// Niets zeggen bij export.
  off,

  /// Een samenvatting tonen; de gebruiker mag er bewust langs.
  warn,

  /// Weigeren zolang er onafgehandelde zekere bevindingen zijn.
  block,
}

extension PrivacyExportGateX on PrivacyExportGate {
  String get key => name;

  static PrivacyExportGate fromKey(String? raw) => switch (raw) {
    'off' => PrivacyExportGate.off,
    'block' => PrivacyExportGate.block,
    _ => PrivacyExportGate.warn,
  };
}

/// Voor wélke ontvanger deze export bedoeld is.
///
/// Eén bron, meerdere versies. Dat is geen luxe maar de kern van het
/// pentestrapport-scenario: de opdrachtgever moet de bevinding kúnnen natrekken,
/// dus die krijgt alles. De bredere kring krijgt hetzelfde rapport met de
/// persoonsgegevens eruit.
///
/// Zonder deze keuze zou je moeten kiezen tússen die twee — en dan wint in de
/// praktijk altijd de volledige versie, want die moet nu eenmaal de deur uit.
enum PrivacyExportProfile {
  /// Voor de opdrachtgever of de auditor. Alleen wat de auteur expliciet op
  /// `redact` heeft gezet, gaat eruit; de rest blijft leesbaar, zodat een derde
  /// partij de bevindingen kan controleren.
  full,

  /// Voor de bredere kring. Álles wat de scanner vindt gaat eruit, ook op slides
  /// die de auteur bewust heeft geaccepteerd — want "deze zaal mag het zien" is
  /// niet hetzelfde als "iedereen mag het zien".
  redacted,
}

extension PrivacyExportProfileX on PrivacyExportProfile {
  String get key => name;

  /// Het achtervoegsel in de bestandsnaam.
  ///
  /// Niet cosmetisch: de duurste fout die je met deze feature kunt maken, is het
  /// volledige exemplaar naar de brede kring sturen. Een verwisseling moet je
  /// kunnen *zien*, niet hoeven onthouden.
  String get fileSuffix =>
      this == PrivacyExportProfile.redacted ? '-geredigeerd' : '';

  static PrivacyExportProfile fromKey(String? raw) => raw == 'redacted'
      ? PrivacyExportProfile.redacted
      : PrivacyExportProfile.full;
}
