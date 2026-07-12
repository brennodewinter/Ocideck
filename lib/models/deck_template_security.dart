part of 'deck_template.dart';

// ── Informatieveiligheid: MIAUW-pentestrapport ───────────────────────────────
// A scaffold for a complete MIAUW-conforming pentest report (PENTEST_MIAUW
// §4.1 / P3-TPL). It lays out the four MIAUW parts — Algemeen, Plan van aanpak,
// Executie, Rapportage — as ready-to-fill slides, using the module-only slide
// types (`signOff`, `scopeMatrix`, `findingsSummary`, `finding`, `checklist`)
// where MIAUW asks for structured data and plain bullets for the narrative
// chapters. The document-management, version and distribution chapters (4.1.x)
// are rendered from the deck front matter, so they are not scaffolded as slides.
// The template only appears when the Informatieveiligheid module is on
// (DeckTemplate.requiresSecurityModule), so these types are always available.

// A structured module slide keyed only by its title; the type's own default
// (from Slide.create) seeds the table/spec the editor then fills.
Slide _securitySlide(SlideType type, String title) =>
    Slide.create(type).copyWith(title: title);

/// One example `finding` header card (§3.1/§4.7): a structured slide carrying
/// a fully-scaffolded [FindingSpec] the tester overwrites. It is a group
/// **header** by default (Slide.create), so the numbering + findings-list
/// services pick it up. Real evidence slides are added per finding by the
/// finding wizard; an empty placeholder image would not round-trip (it needs a
/// path), so the scaffold stays at the header the tester can build out.
Slide _findingScaffold() => Slide.create(SlideType.finding).copyWith(
  title: 'F-01 · Voorbeeldbevinding',
  customMarkdown: const FindingSpec(
    heading: 'F-01 · Voorbeeldbevinding',
    scopeObject: '<scope-object>',
    description:
        'Beschrijf hier feitelijk en technisch wat het beveiligingsprobleem is.',
    confirmation:
        'Beschrijf reproduceerbaar (met bewijs) hoe de bevinding is vastgesteld.',
    impact: 'Beschrijf de mogelijke technische en zakelijke impact.',
    recommendation: 'Beschrijf de concrete, haalbare mitigatie.',
  ).toMarkdown(),
);

List<Slide> _buildMiauwReport(String deckTitle) => [
  _title(deckTitle),

  // 1 · Algemeen — over de onderzoeker en het onderzoek (1.1–1.9)
  _section('1. Algemeen'),
  _bullets('Documentbeheer', [
    'Digitale levering van dit rapport, met verificatiehash (SHA-256).',
    'Rapporteur en verplichte certificering (OSCP/OSEP/OSCE/OSWE/eWPTX).',
    'Rapportversie en publicatiedatum.',
    'Vertrouwelijkheid en TLP-classificatie.',
    'Distributielijst: wie ontvangt dit rapport.',
  ]),
  _securitySlide(SlideType.signOff, 'Waarheidsgetrouwe rapportage'),

  // 2 · Plan van aanpak — intake, scope en afspraken (2.1–2.5)
  _section('2. Plan van aanpak'),
  _bullets('Opdracht en afbakening', [
    'Intake en aanleiding van het onderzoek.',
    'Doelstelling en onderzoeksvragen.',
    'Eigenaarschap, jurisdictie en akkoord op de scope.',
    'Rapportagetaal.',
    'Vrijwaring en juridische randvoorwaarden.',
  ]),
  _securitySlide(SlideType.scopeMatrix, 'Scope en standaarden'),

  // 3 · Executie — hoe er is getest (3.1–3.5)
  _section('3. Executie'),
  _bullets('Uitvoering', [
    'Assume breach als uitgangspunt.',
    'Kwalificatie met CVSS 4.0 (score + vectorstring).',
    'Bewijslast: hashes van bewijsmateriaal (SHA1/SHA-256).',
    'Validatie van scanresultaten (geen blind vertrouwen op de scanner).',
    'Documenteren van gebruikte toegangspaden.',
  ]),

  // 4 · Rapportage — samenvatting, bevindingen en bijlagen (4.1–4.13)
  _section('4. Rapportage'),
  _securitySlide(SlideType.findingsSummary, 'Managementsamenvatting'),
  _timeline('Tijdlijn van het onderzoek', const [
    TimelineEvent(
      marker: 'Intake',
      title: 'Aftrap',
      description: 'Scope en afspraken vastgesteld.',
    ),
    TimelineEvent(
      marker: 'Test',
      title: 'Uitvoering',
      description: 'Testperiode van het onderzoek.',
    ),
    TimelineEvent(
      marker: 'Rapport',
      title: 'Oplevering',
      description: 'Concept- en eindrapport.',
    ),
  ]),
  _findingScaffold(),
  _securitySlide(SlideType.checklist, 'Checklist per standaard'),
  _bullets('Bijlagen', [
    'Verklarende woordenlijst.',
    'Gebruikte tools.',
    'Ontvangen documenten en bestanden (met SHA1).',
    'Gebruikte accounts.',
    'Scanresultaten.',
    'Bewijsmateriaal (met SHA1).',
    'Checklists per standaard.',
    'Onbereikbare objecten.',
  ]),
];
