import '../models/eis_entry.dart';

/// The full MIAUW compliance schema (PENTEST_MIAUW §1/§9): all 88 testable EIS
/// across the four parts (Algemeen / Interacties / Executie / Rapportage; the
/// four part-section rows are modelled by [EisPart], not listed here), parsed
/// from the authoritative MIAUW workbook
/// (github.com/brennodewinter/Informatiebeveiligingsonderzoek, EUPL-1.2) and
/// bundled as in-repo `const` data — no asset wiring, no network — exactly as
/// the CWE catalog does. Content-derivable EIS carry a [EisCheck] and score
/// automatically; the organisational EIS are manual confirmations (a human
/// attestation via `deck.miauwConfirmations`, or a client waiver).
///
/// This is the always-on offline floor that drives the compliance overview; the
/// provisioned data pack (§6) can carry the same schema for out-of-band updates.
/// Titles are bundled normative content: data, not localised UI. They are Dutch
/// only — no bundled catalog or pack manifest carries a language dimension
/// today. (§12 describes NL+EN provisioning; that does not exist, so do not read
/// this as §12 sanctioning Dutch-only.)
/// `4.6` is an empty number in the source workbook, and the two `2.2.9` rows in
/// the workbook are disambiguated as `2.2.9` / `2.2.9b`.
class MiauwEisCatalog {
  MiauwEisCatalog._();

  static final MiauwEisCatalog instance = MiauwEisCatalog._();

  /// All bundled requirements, in schema order.
  List<EisEntry> get entries => _entries;

  /// The requirement with [id] (e.g. `4.7.2`), or null when not in the subset.
  EisEntry? byId(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// The requirements of one [part], in schema order.
  List<EisEntry> forPart(EisPart part) => [
    for (final e in _entries)
      if (e.part == part) e,
  ];
}

const List<EisEntry> _entries = [
  EisEntry(
    id: '1.1',
    part: EisPart.algemeen,
    title: 'De onderzoeksrapportage wordt digitaal verstrekt.',
    derivation: EisDerivation.automatic,
    check: EisCheck.sealed,
  ),
  EisEntry(
    id: '1.2',
    part: EisPart.algemeen,
    title:
        'Aanwijzing en beschrijving rapporteur, opsteller of hoofdonderzoeker',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '1.3',
    part: EisPart.algemeen,
    title:
        'Beschrijving van de verplichte certificering, waarover de rapporteur beschikt',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '1.4',
    part: EisPart.algemeen,
    title: 'Bewijs certificering',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '1.5',
    part: EisPart.algemeen,
    title: 'Benoemen van de versie van de rapportage',
    derivation: EisDerivation.automatic,
    check: EisCheck.reportVersion,
  ),
  EisEntry(
    id: '1.6',
    part: EisPart.algemeen,
    title: 'Handtekening voor waarheidsgetrouwe rapportage',
    derivation: EisDerivation.automatic,
    check: EisCheck.signOff,
  ),
  EisEntry(
    id: '1.7',
    part: EisPart.algemeen,
    title: 'Proces van de Pentest Execution Standard volgen',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '1.8',
    part: EisPart.algemeen,
    title: 'Vertrouwelijkheid',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '1.9',
    part: EisPart.algemeen,
    title: 'Verspreiding',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.1',
    part: EisPart.interacties,
    title: 'Beschrijving intakegesprek',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.1.1',
    part: EisPart.interacties,
    title: 'Er wordt benoemd wanneer het gesprek heeft plaats gevonden.',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.1.2',
    part: EisPart.interacties,
    title: 'Deelnemers',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.1.3',
    part: EisPart.interacties,
    title: 'Informatieverstrekking',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2',
    part: EisPart.interacties,
    title:
        'Er is een beschrijving van de scope van het onderzoek. Deze bevat de relevante selectie van onderdelen en objecten volgens sub 2.2.1 t/m 2.2.8. De scope komt overeen met de behoeftes uit het intakegesprek en past binnen de afgesproken tijdspanne.',
    derivation: EisDerivation.automatic,
    check: EisCheck.scopeMatrix,
  ),
  EisEntry(
    id: '2.2.1',
    part: EisPart.interacties,
    title: 'Scope - Aanvalsperspectieven',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2.2',
    part: EisPart.interacties,
    title: 'Scope - Objecten',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2.3',
    part: EisPart.interacties,
    title: 'Scopeonderdeel - Infrastructuur',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2.4',
    part: EisPart.interacties,
    title: 'Scopeonderdeel - Webapplicatie',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2.5',
    part: EisPart.interacties,
    title: 'Scopeonderdeel - IoT',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2.6',
    part: EisPart.interacties,
    title: 'Scopeonderdeel - Firmware',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2.7',
    part: EisPart.interacties,
    title: 'Scopeonderdeel - API',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2.8',
    part: EisPart.interacties,
    title: 'Scopeonderdeel - Mobiele Applicatie',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2.9',
    part: EisPart.interacties,
    title: 'Scopeonderdeel – CIS Controls',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2.9b',
    part: EisPart.interacties,
    title: 'Vaststelling scope en objecten',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2.10',
    part: EisPart.interacties,
    title: 'Eigenaarschap scope',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2.11',
    part: EisPart.interacties,
    title: 'Jurisdictie scope-objecten',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2.12',
    part: EisPart.interacties,
    title: 'Accordering scope',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.3',
    part: EisPart.interacties,
    title:
        'Voorafgaand aan de pentest is afgesproken en vastgelegd in welke taal de rapportage dient te worden geschreven.',
    // Was manual — filed as unprovable while it was merely unrecordable: the
    // deck had nowhere to put the language. It does now (front matter
    // `language`), so the record itself is the proof.
    derivation: EisDerivation.automatic,
    check: EisCheck.reportLanguage,
  ),
  EisEntry(
    id: '2.4',
    part: EisPart.interacties,
    title:
        'Een plan van aanpak bevat het doel van de penetratietest en eventuele secundaire doelstelling(en) indien deze naar voren zijn gekomen in het intakegesprek.',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.5',
    part: EisPart.interacties,
    title:
        'Er dient een vrijwaringsverklaring te worden getekend tussen opdrachtgever en opdrachtnemer voor het uitvoeren van de penetratietest, in deze vrijwaringsverklaring is specifiek verwezen naar de scope',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '3.1',
    part: EisPart.executie,
    title:
        'Er wordt getest ervan uitgaande dat een aanvaller op reeds toegang tot een netwerkomgeving heeft (assume breach)',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '3.2',
    part: EisPart.executie,
    title: 'Gebruik CVSS-scores',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasCvss,
  ),
  EisEntry(
    id: '3.2.1',
    part: EisPart.executie,
    title: 'Berekening CVSS-score',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '3.3',
    part: EisPart.executie,
    title: 'Bewijslast',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '3.4',
    part: EisPart.executie,
    title: 'Validatie scanresultaten',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '3.5',
    part: EisPart.executie,
    title: 'Documenteren toegangswegen',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.1',
    part: EisPart.rapportage,
    title: 'Hoofdstukindeling',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.1.1',
    part: EisPart.rapportage,
    title: 'Hoofdstukindeling - Inhoudsopgave',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.1.2',
    part: EisPart.rapportage,
    title: 'Hoofdstukindeling - Methodologie',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.1.2.1',
    part: EisPart.rapportage,
    title: 'Hoofdstukindeling - Methodologie - CVSS',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.1.3',
    part: EisPart.rapportage,
    title: 'Hoofstukdindeling - Documentbeheer',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.1.4',
    part: EisPart.rapportage,
    title: 'Hoofstukdindeling - Versiebeheer',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.1.5',
    part: EisPart.rapportage,
    title: 'Hoofdstukindeling - Distributielijst',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.1.6',
    part: EisPart.rapportage,
    title: 'Hoofdstukindeling - Aanleiding',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.1.7',
    part: EisPart.rapportage,
    title: 'Doelstelling',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.2',
    part: EisPart.rapportage,
    title: 'Bevindingenlijst',
    derivation: EisDerivation.automatic,
    check: EisCheck.findingsPresent,
  ),
  EisEntry(
    id: '4.3',
    part: EisPart.rapportage,
    title: 'Managementsamenvatting',
    derivation: EisDerivation.automatic,
    check: EisCheck.managementSummary,
  ),
  EisEntry(
    id: '4.3.1',
    part: EisPart.rapportage,
    title: 'Managementsamenvatting - Start/einddatum',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.3.2',
    part: EisPart.rapportage,
    title: 'Managementsamenvatting - Overzicht gebruikte standaarden',
    // Blijft handmatig tot het overzicht ook echt in het rapport staat. Het
    // deck kán de standaarden vastleggen (front matter `standards`), maar die
    // vastlegging wordt nergens gerenderd: hij bereikt het auditdossier en een
    // dialoog, niet de slides die de klant krijgt. Deze eis vraagt om een
    // overzicht ín de managementsamenvatting, dus vastleggen alleen voldoet er
    // niet aan. Zie CHANGELOG 2026-07-18.
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.3.3',
    part: EisPart.rapportage,
    title: 'Managementsamenvatting - CIA-scores',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.3.4',
    part: EisPart.rapportage,
    title: 'Managementsamenvatting - Root-cause analyse',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.3.5',
    part: EisPart.rapportage,
    title: 'Managementsamenvatting - Overzicht bevindingen',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.4',
    part: EisPart.rapportage,
    title: 'Scope',
    derivation: EisDerivation.automatic,
    check: EisCheck.scopeMatrix,
  ),
  EisEntry(
    id: '4.4.1',
    part: EisPart.rapportage,
    title: 'Scope - overeenkomst met Plan van Aanpak',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.4.2',
    part: EisPart.rapportage,
    title: 'Scope - Assume Breach principe',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.5',
    part: EisPart.rapportage,
    title: 'Tijdslijn (verloop van penetratietest) - reproduceerbaarheid',
    derivation: EisDerivation.automatic,
    check: EisCheck.timeline,
  ),
  EisEntry(
    id: '4.6',
    part: EisPart.rapportage,
    title: 'Gereserveerd (leeg nummer in het MIAUW-schema)',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.7',
    part: EisPart.rapportage,
    title: 'Hoofdstuk - Bevindingen',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.7.1',
    part: EisPart.rapportage,
    title: 'Hoofdstuk - Bevindingen - Scope-object',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasScope,
  ),
  EisEntry(
    id: '4.7.2',
    part: EisPart.rapportage,
    title: 'Hoofdstuk - Bevindingen - CVSS-score',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasCvss,
  ),
  EisEntry(
    id: '4.7.3',
    part: EisPart.rapportage,
    title: 'Hoofdstuk - Bevindingen - CVSS Vector string',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasCvss,
  ),
  EisEntry(
    id: '4.7.4',
    part: EisPart.rapportage,
    title: 'Hoofdstuk - Bevindingen - Beschrijving kwetsbaarheid',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasDescription,
  ),
  EisEntry(
    id: '4.7.5',
    part: EisPart.rapportage,
    title: 'Hoofdstuk - Bevindingen - Bevestiging kwetsbaarheid',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasConfirmation,
  ),
  EisEntry(
    id: '4.7.6',
    part: EisPart.rapportage,
    title: 'Hoofdstuk - Bevindingen - Mogelijke impact',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasImpact,
  ),
  EisEntry(
    id: '4.7.7',
    part: EisPart.rapportage,
    title: 'Hoofdstuk - Bevindingen - Aanbeveling',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasRecommendation,
  ),
  EisEntry(
    id: '4.8',
    part: EisPart.rapportage,
    title: 'Bijlages',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.8.1',
    part: EisPart.rapportage,
    title: 'Bijlages - Verklarende woordenlijst',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.8.2',
    part: EisPart.rapportage,
    title: 'Bijlages - Hulpmiddelen',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.8.2.1',
    part: EisPart.rapportage,
    title: 'Bijlages - Hulpmiddelen - Beschrijving',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.8.2.2',
    part: EisPart.rapportage,
    title: 'Bijlages - Hulpmiddelen - Versie-nummer',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.8.2.3',
    part: EisPart.rapportage,
    title: 'Bijlages - Hulpmiddelen - Publieke referentie (URL)',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.8.3',
    part: EisPart.rapportage,
    title: 'Bijlages - Ontvangen documenten',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.8.3.1',
    part: EisPart.rapportage,
    title: 'Bijlages - Ontvangen documenten - Beschrijving',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.8.3.2',
    part: EisPart.rapportage,
    title: 'Bijlages - Ontvangen documenten - SHA1-hashes',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.8.4',
    part: EisPart.rapportage,
    title: 'Bijlages - Ontvangen bestanden',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.8.4.1',
    part: EisPart.rapportage,
    title: 'Bijlages - Ontvangen bestanden - Beschrijving',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.8.4.2',
    part: EisPart.rapportage,
    title: 'Bijlages - Ontvangen bestanden - SHA1-hashes',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.9',
    part: EisPart.rapportage,
    title: 'Bijlages - Gebruikte accounts',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.9.1',
    part: EisPart.rapportage,
    title: 'Bijlages - Gebruikte accounts - Scope-object',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.9.2',
    part: EisPart.rapportage,
    title: 'Bijlages - Gebruikte accounts - Beschrijving',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.10',
    part: EisPart.rapportage,
    title: 'Bijlages - Uitgevoerde scans',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.10.1',
    part: EisPart.rapportage,
    title: 'Bijlages - Uitgevoerde scans - Scan-resultaat - Scope-object',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.10.2',
    part: EisPart.rapportage,
    title: 'Bijlages - Uitgevoerde scans - Scan-resultaat - Output',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.11',
    part: EisPart.rapportage,
    title: 'Bijlages - Bewijsmateriaal',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.11.1',
    part: EisPart.rapportage,
    title: 'Bijlages - Bewijsmateriaal - SHA1-hashes',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.12',
    part: EisPart.rapportage,
    title: 'Bijlages - Checklists',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.12.1',
    part: EisPart.rapportage,
    title: 'Bijlages - Checklists - Per standaard',
    derivation: EisDerivation.automatic,
    check: EisCheck.checklistPresent,
  ),
  EisEntry(
    id: '4.13',
    part: EisPart.rapportage,
    title: 'Bijlages - Lijst van onbenaderbare/onbereikbare scope-objecten',
    derivation: EisDerivation.manual,
  ),
];
