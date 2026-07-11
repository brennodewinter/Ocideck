import '../models/eis_entry.dart';

/// The MIAUW compliance schema (PENTEST_MIAUW §1/§9). This first increment ships
/// a **curated, bundled subset** of the 92 EIS across the four parts (Algemeen /
/// Interacties / Executie / Rapportage) as in-repo `const` data — no asset
/// wiring, no network — exactly as the CWE catalog does. Content-derivable EIS
/// carry a [EisCheck]; organisational EIS are manual confirmations.
///
/// The **full** 92-EIS schema (parsed from the MIAUW workbook) is a later,
/// provisioned data pack (§6); this stays the always-on offline floor that
/// drives the compliance overview.
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
  // ── 1 · Algemeen ──────────────────────────────────────────────────────────
  EisEntry(
    id: '1.1',
    part: EisPart.algemeen,
    title: 'Digitale aanlevering met integriteitshash',
    derivation: EisDerivation.automatic,
    check: EisCheck.sealed,
  ),
  EisEntry(
    id: '1.2',
    part: EisPart.algemeen,
    title: 'Rapporteur benoemd',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '1.3',
    part: EisPart.algemeen,
    title: 'Verplichte certificering (OSCP/OSEP/OSCE/OSWE/eWPTX)',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '1.4',
    part: EisPart.algemeen,
    title: 'Bewijs van certificering',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '1.5',
    part: EisPart.algemeen,
    title: 'Rapportversie vastgelegd',
    derivation: EisDerivation.automatic,
    check: EisCheck.reportVersion,
  ),
  EisEntry(
    id: '1.6',
    part: EisPart.algemeen,
    title: 'Ondertekening voor waarheidsgetrouwe rapportage',
    derivation: EisDerivation.automatic,
    check: EisCheck.signOff,
  ),
  EisEntry(
    id: '1.7',
    part: EisPart.algemeen,
    title: 'Zeven PTES-fasen doorlopen',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '1.8',
    part: EisPart.algemeen,
    title: 'Vertrouwelijkheid afgesproken',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '1.9',
    part: EisPart.algemeen,
    title: 'Distributie vastgelegd',
    derivation: EisDerivation.manual,
  ),
  // ── 2 · Interacties / Plan van aanpak ─────────────────────────────────────
  EisEntry(
    id: '2.1',
    part: EisPart.interacties,
    title: 'Intakegesprek gehouden',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.2',
    part: EisPart.interacties,
    title: 'Scope met standaard per objecttype',
    derivation: EisDerivation.automatic,
    check: EisCheck.scopeMatrix,
  ),
  EisEntry(
    id: '2.3',
    part: EisPart.interacties,
    title: 'Eigendom, jurisdictie en akkoord',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.4',
    part: EisPart.interacties,
    title: 'Taal en doelstelling vastgelegd',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '2.5',
    part: EisPart.interacties,
    title: 'Vrijwaring getekend',
    derivation: EisDerivation.manual,
  ),
  // ── 3 · Executie ──────────────────────────────────────────────────────────
  EisEntry(
    id: '3.1',
    part: EisPart.executie,
    title: 'Assume breach als uitgangspunt',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '3.2',
    part: EisPart.executie,
    title: 'CVSS 4.0-scores toegekend aan bevindingen',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasCvss,
  ),
  EisEntry(
    id: '3.3',
    part: EisPart.executie,
    title: 'Bewijslast met hashes',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '3.4',
    part: EisPart.executie,
    title: 'Scanresultaten gevalideerd',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '3.5',
    part: EisPart.executie,
    title: 'Toegangspaden gedocumenteerd',
    derivation: EisDerivation.manual,
  ),
  // ── 4 · Rapportage ────────────────────────────────────────────────────────
  EisEntry(
    id: '4.1',
    part: EisPart.rapportage,
    title: 'Hoofdstukindeling volgens MIAUW',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.2',
    part: EisPart.rapportage,
    title: 'Bevindingenlijst aanwezig',
    derivation: EisDerivation.automatic,
    check: EisCheck.findingsPresent,
  ),
  EisEntry(
    id: '4.3',
    part: EisPart.rapportage,
    title: 'Managementsamenvatting aanwezig',
    derivation: EisDerivation.automatic,
    check: EisCheck.managementSummary,
  ),
  EisEntry(
    id: '4.4',
    part: EisPart.rapportage,
    title: 'Scope-hoofdstuk aanwezig',
    derivation: EisDerivation.automatic,
    check: EisCheck.scopeMatrix,
  ),
  EisEntry(
    id: '4.5',
    part: EisPart.rapportage,
    title: 'Tijdlijn opgenomen',
    derivation: EisDerivation.automatic,
    check: EisCheck.timeline,
  ),
  EisEntry(
    id: '4.7.1',
    part: EisPart.rapportage,
    title: 'Elke bevinding benoemt het scope-object',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasScope,
  ),
  EisEntry(
    id: '4.7.2',
    part: EisPart.rapportage,
    title: 'Elke bevinding heeft een CVSS-score en vectorstring',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasCvss,
  ),
  EisEntry(
    id: '4.7.3',
    part: EisPart.rapportage,
    title: 'Elke bevinding heeft een beschrijving',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasDescription,
  ),
  EisEntry(
    id: '4.7.4',
    part: EisPart.rapportage,
    title: 'Elke bevinding heeft bevestiging / reproductie',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasConfirmation,
  ),
  EisEntry(
    id: '4.7.5',
    part: EisPart.rapportage,
    title: 'Elke bevinding beschrijft de mogelijke impact',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasImpact,
  ),
  EisEntry(
    id: '4.7.6',
    part: EisPart.rapportage,
    title: 'Elke bevinding heeft een aanbeveling',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasRecommendation,
  ),
  EisEntry(
    id: '4.7.7',
    part: EisPart.rapportage,
    title: 'Elke bevinding legt een CWE-koppeling',
    derivation: EisDerivation.automatic,
    check: EisCheck.everyFindingHasCwe,
  ),
  EisEntry(
    id: '4.10',
    part: EisPart.rapportage,
    title: 'Ontvangen documenten met SHA1',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.11',
    part: EisPart.rapportage,
    title: 'Accounts gedocumenteerd',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.12',
    part: EisPart.rapportage,
    title: 'Scans gedocumenteerd',
    derivation: EisDerivation.manual,
  ),
  EisEntry(
    id: '4.13',
    part: EisPart.rapportage,
    title: 'Checklists per standaard aanwezig',
    derivation: EisDerivation.automatic,
    check: EisCheck.checklistPresent,
  ),
];
