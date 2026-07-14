// Massa-persoonsgegevens.
//
// Eén e-mailadres op een slide is een contactgegeven. Veertig e-mailadressen in
// een tabel is een geëxporteerde ledenlijst, en dat is een heel ander gesprek —
// met de AVG, met de functionaris gegevensbescherming, en met de mensen op die
// lijst.
//
// De scanner ziet die veertig adressen al, veertig keer. Maar veertig losse
// meldingen zijn precies wat een gebruiker leert wegklikken: het paneel loopt over
// en de boodschap verdwijnt in het geraas. Wat er ontbreekt is het inzicht dat
// erboven ligt.
//
// Twee signalen, en het eerste is verreweg het sterkste:
//
//   1. Een TABELKOP die zegt wat de kolom is — "Naam", "E-mail", "BSN",
//      "Geboortedatum". Dat is een geplakte CSV, en de kop zegt letterlijk dat de
//      cellen eronder persoonsgegevens zijn. Bijna geen vals-positieven: niemand
//      noemt een kolom "BSN" als er geen BSN's in staan.
//
//   2. Dezelfde regel die N keer vuurt op één slide. Ruwer, maar het vangt de
//      geplakte lijst die geen tabel is.

import '../../models/privacy_finding.dart';
import '../../models/slide.dart';

/// Vanaf hoeveel treffers van dezelfde regel op één slide het massa-werk wordt.
///
/// Drie is laag genoeg om een geplakte lijst te vangen en hoog genoeg om een
/// gewone contactslide (naam, mail, telefoon) met rust te laten.
const int kBulkThreshold = 3;

/// Vanaf hoeveel datarijen een tabel met een persoonsgegeven-kop meetelt.
///
/// Eén rij onder de kop is een voorbeeld. Drie is een lijst.
const int kBulkTableRows = 3;

/// Tabelkoppen die zeggen dat de kolom eronder persoonsgegevens bevat.
///
/// Meertalig, want de scanner draait in 31 talen en een Duitse tabel heeft een
/// kolom `Name`. Data, geen UI — deze woorden worden nooit getoond, alleen
/// vergeleken, dus ze gaan niet door de l10n heen.
const Set<String> personalColumnHeaders = {
  // Naam
  'naam', 'achternaam', 'voornaam', 'volledige naam',
  'name', 'full name', 'first name', 'last name', 'surname',
  'nom', 'prénom', 'nombre', 'apellido', 'nome', 'cognome',
  // Contact
  'e-mail', 'email', 'e-mailadres', 'mailadres', 'e-mail address',
  'telefoon', 'telefoonnummer', 'phone', 'telephone', 'mobile', 'mobiel',
  'adres', 'address', 'straat', 'woonplaats', 'postcode', 'zip',
  // Identificatoren
  'bsn', 'burgerservicenummer', 'sofinummer', 'ssn',
  'personnummer', 'pesel', 'nif', 'dni', 'codice fiscale',
  'paspoortnummer', 'passport', 'rijbewijs',
  // Bijzonder / gevoelig
  'geboortedatum', 'geboortedag', 'date of birth', 'dob', 'birthdate',
  'geslacht', 'gender', 'sex',
  'diagnose', 'diagnosis', 'medicatie', 'patiënt', 'patient',
  'salaris', 'salary', 'iban', 'rekeningnummer', 'bank account',
};

/// Normaliseert een kop voor vergelijking.
String _normaliseHeader(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'[*_`:]'), '').trim();

/// Kolomkoppen van [slide] die een persoonsgegeven aankondigen.
///
/// De eerste rij van een tabel is de kop (zo slaat OciDeck ze op).
List<String> personalColumnsIn(Slide slide) {
  if (slide.tableRows.length < kBulkTableRows + 1) return const [];
  return [
    for (final header in slide.tableRows.first)
      if (personalColumnHeaders.contains(_normaliseHeader(header))) header,
  ];
}

/// Regels die per treffer al een melding geven en dus niet opnieuw als massa
/// hoeven te tellen.
///
/// Een data-URI of een gebruikerspad is per definitie enkelvoudig; drie ervan is
/// geen ledenlijst. Alleen persoonsgegevens tellen mee.
bool _countsTowardsBulk(PrivacyFinding f) =>
    f.family == PrivacyFamily.identifier ||
    f.family == PrivacyFamily.contact ||
    f.family == PrivacyFamily.financial;

/// Levert de massa-bevinding op wanneer één regel te vaak vuurt op één slide.
///
/// Bewust één bevinding per regel, niet per treffer: veertig losse meldingen zijn
/// precies wat een gebruiker leert wegklikken.
Iterable<PrivacyFinding> bulkFindingsFor(
  Slide slide,
  int slideIndex,
  List<PrivacyFinding> findings,
) sync* {
  // 1. De tabelkop. Het sterkste signaal: niemand noemt een kolom "BSN" als er
  //    geen BSN's in staan.
  final columns = personalColumnsIn(slide);
  if (columns.isNotEmpty) {
    yield PrivacyFinding(
      ruleId: 'bulk.table_column',
      family: PrivacyFamily.bulk,
      confidence: PrivacyConfidence.certain,
      slideIndex: slideIndex,
      field: 'tableRows',
      start: 0,
      end: 0,
      maskedSample: '${slide.tableRows.length - 1}×${columns.length}',
    );
  }

  // 2. Dezelfde regel die te vaak vuurt. Ruwer, maar het vangt de geplakte lijst
  //    die geen tabel is.
  final counts = <String, int>{};
  for (final f in findings) {
    if (!_countsTowardsBulk(f)) continue;
    if (f.confidence != PrivacyConfidence.certain) continue;
    counts[f.ruleId] = (counts[f.ruleId] ?? 0) + 1;
  }

  for (final entry in counts.entries) {
    if (entry.value < kBulkThreshold) continue;
    yield PrivacyFinding(
      ruleId: 'bulk.repeat',
      family: PrivacyFamily.bulk,
      confidence: PrivacyConfidence.certain,
      slideIndex: slideIndex,
      field: 'bullets',
      start: 0,
      end: 0,
      // Het aantal, niet de waarden. Dít is wat de gebruiker moet weten.
      maskedSample: '${entry.value}× ${entry.key}',
    );
  }
}
