// Wat er met de kwaliteitsmeldingen van een slide gebeurt.
//
// De kwaliteitscontrole kon tot nu toe alleen maar gelijk hebben. Contrast,
// tekstdichtheid, ontbrekende alt-tekst: allemaal terecht in het algemeen, en
// allemaal soms onterecht op deze ene slide. Een titelbeeld dat met opzet
// rustig contrasteert, een tabel die nu eenmaal veel rijen heeft — daar viel
// niets over te zeggen. De melding bleef staan, de badge bleef oranje, en het
// enige wat de auteur leerde was dat hij badges kon negeren.
//
// Dat is precies de schade die de privacycontrole met haar disposities al
// vermijdt (zie `privacy_disposition.dart`), en om dezelfde reden krijgt de
// kwaliteitscontrole hem nu ook: een waarschuwing die je niet kunt beantwoorden
// leert je wegkijken, en daarna zie je de terechte waarschuwing ook niet meer.

/// De stand van een slide ten aanzien van haar kwaliteitsmeldingen.
///
/// Bewust twee waarden en geen vier: bij privacy bestaan `shield` en `redact`
/// omdat er iets met de ontvanger en met de gegevens zelf moet gebeuren. Een
/// contrastprobleem heeft geen ontvanger om te waarschuwen en niets om weg te
/// lakken — het is er, of de auteur zegt dat het zo bedoeld is.
enum QualityDisposition {
  /// Nog geen beslissing genomen. De meldingen staan in het kwaliteitspaneel en
  /// de badge op de thumbnail is gekleurd. Dit is de standaard.
  warn,

  /// Bewust zo gelaten. De meldingen blijven leesbaar, maar onderbreken niet
  /// meer: de badge wordt grijs en de export-gate telt ze niet mee.
  ///
  /// Let op wat hier *niet* staat: de meldingen verdwijnen niet. Ze grijs maken
  /// en laten staan is het hele punt — een geaccepteerd probleem moet nog steeds
  /// terug te vinden zijn, anders is accepteren hetzelfde als verbergen.
  accept,
}

extension QualityDispositionX on QualityDisposition {
  /// De stabiele sleutel in de markdown. `warn` is de standaard en wordt nooit
  /// weggeschreven, zodat bestaande bestanden niet groeien.
  String get key => switch (this) {
    QualityDisposition.warn => 'warn',
    QualityDisposition.accept => 'accept',
  };

  /// Of deze stand de meldingen als afgehandeld beschouwt.
  bool get isResolved => this != QualityDisposition.warn;

  /// Onbekende waarden vallen terug op `warn`.
  ///
  /// Een deck uit een nieuwere versie met een stand die wij niet kennen moet
  /// níét stilletjes als afgehandeld gelden: dan zou een oudere OciDeck
  /// meldingen onderdrukken die hij niet begrijpt. Terugvallen op de standaard
  /// betekent hooguit dat de auteur zijn keuze opnieuw maakt.
  static QualityDisposition fromKey(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'accept' => QualityDisposition.accept,
      _ => QualityDisposition.warn,
    };
  }
}
