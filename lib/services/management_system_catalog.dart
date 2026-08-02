// ── DERDEN-INHOUD — NIET EUPL-1.2 (zie onder) ───────────────────────────────
//
// De clausule- en controlnummers met hun korte titels in dit bestand vormen de
// **index** van drie ISO-normen: ISO/IEC 27001:2022, ISO 9001:2015 en
// ISO/IEC 42001:2023. Anders dan de OWASP-catalogi (CC-BY-SA) of CWE (MITRE-
// terms) worden ISO-normen door ISO/NEN **verkocht** en is de normtekst
// auteursrechtelijk beschermd.
//
// Daarom draagt dit bestand **alleen de index**: het nummer plus de korte
// canonieke titel plus het thema/de clausule. Dat is dezelfde feitelijke lijst
// die elke ISMS/QMS-tool toont ("A.5.1 — Policies for information security").
// Zo'n functioneel label mist het eigen oorspronkelijk karakter dat het
// auteursrecht vereist (niet: "het is te kort" — lengte is niet de toets, zie
// HvJ-EU Infopaq C-5/08; wél: er is geen creatieve keuzevrijheid in een
// nummer + functiekop). De **normatieve eistekst, toelichtingen en leidraad
// staan hier NIET in.** Wie de eis wil lezen, koopt de norm.
//
// **Herkomst: de openbare ISO-catalogus, niet een gekochte normkopie.** De
// Annex A-controllijst en de clausulekoppen staan gratis op ISO's publieke
// catalogus (waar `reference_standards.dart` naar verwijst). We tikken dus geen
// aangeschafte, licentie-gebonden PDF over — er is geen ISO/NEN-gebruikscontract
// gevormd dat verder zou beperken dan het auteursrecht.
//
// **De titels blijven Engelse ISO-data en gaan NIET door l10n.** Een vertaling
// naar de officiële NEN-Nederlandse bewoording zou NEN's aparte vertaalrecht
// raken; laat een "behulpzame" vertaling naar de NL-titels dus achterwege.
//
// De header staat er om dezelfde reden als bij de CWE/WSTG/MASTG-catalogi: de
// inhoud is normatief materiaal van een ander, geen materiaal van ons, en dat
// hoort een lezer bovenaan te zien in plaats van af te leiden.
//
//   Bron: https://www.iso.org/  (officiële catalogus per norm)
//
// Zie docs/LICENSE_COMPLIANCE.md, "Bundled reference data", en het ontwerp in
// docs/design/ISO_MANAGEMENTSYSTEEM.md §9.

import '../models/management_system.dart';

/// De gebundelde index van de drie managementsysteemnormen (ISO_MANAGEMENTSYSTEEM
/// §7): per norm de secties (Annex A-thema's/-doelstellingen of clausules) en de
/// clausules/controls eronder, als in-repo `const`-data — geen asset-bedrading,
/// geen netwerk, precies zoals de CWE- en MIAUW-catalogi.
///
/// Titels zijn de canonieke Engelse index (data, geen vertaalde UI). Alleen de
/// index; de normtekst is niet gebundeld (zie de header en §9).
class ManagementSystemCatalog {
  ManagementSystemCatalog._();

  static final ManagementSystemCatalog instance = ManagementSystemCatalog._();

  /// De secties (thema's/doelstellingen/clausules) van [standard], in
  /// schema-volgorde.
  List<ControlSection> sectionsFor(ManagementSystemStandard standard) =>
      switch (standard) {
        ManagementSystemStandard.iso27001 => _iso27001Sections,
        ManagementSystemStandard.iso9001 => _iso9001Sections,
        ManagementSystemStandard.iso42001 => _iso42001Sections,
      };

  /// Alle clausules/controls van [standard], in schema-volgorde.
  List<ControlEntry> controlsFor(ManagementSystemStandard standard) =>
      switch (standard) {
        ManagementSystemStandard.iso27001 => _iso27001Controls,
        ManagementSystemStandard.iso9001 => _iso9001Controls,
        ManagementSystemStandard.iso42001 => _iso42001Controls,
      };

  /// De clausules/controls van één [sectionId] binnen [standard], in
  /// schema-volgorde. Leeg wanneer de sectie niet bestaat.
  List<ControlEntry> controlsInSection(
    ManagementSystemStandard standard,
    String sectionId,
  ) => [
    for (final c in controlsFor(standard))
      if (c.sectionId == sectionId) c,
  ];

  /// De control/clausule met [id] binnen [standard], of null wanneer die niet in
  /// de index staat.
  ControlEntry? byId(ManagementSystemStandard standard, String id) {
    for (final c in controlsFor(standard)) {
      if (c.id == id) return c;
    }
    return null;
  }
}

// ── ISO/IEC 27001:2022 — Annex A (93 controls, vier thema's) ─────────────────

const _iso27001Sections = <ControlSection>[
  ControlSection(id: 'A.5', title: 'Organizational controls'),
  ControlSection(id: 'A.6', title: 'People controls'),
  ControlSection(id: 'A.7', title: 'Physical controls'),
  ControlSection(id: 'A.8', title: 'Technological controls'),
];

const _iso27001Controls = <ControlEntry>[
  // A.5 Organizational controls (37)
  ControlEntry(
    id: 'A.5.1',
    sectionId: 'A.5',
    title: 'Policies for information security',
  ),
  ControlEntry(
    id: 'A.5.2',
    sectionId: 'A.5',
    title: 'Information security roles and responsibilities',
  ),
  ControlEntry(id: 'A.5.3', sectionId: 'A.5', title: 'Segregation of duties'),
  ControlEntry(
    id: 'A.5.4',
    sectionId: 'A.5',
    title: 'Management responsibilities',
  ),
  ControlEntry(
    id: 'A.5.5',
    sectionId: 'A.5',
    title: 'Contact with authorities',
  ),
  ControlEntry(
    id: 'A.5.6',
    sectionId: 'A.5',
    title: 'Contact with special interest groups',
  ),
  ControlEntry(id: 'A.5.7', sectionId: 'A.5', title: 'Threat intelligence'),
  ControlEntry(
    id: 'A.5.8',
    sectionId: 'A.5',
    title: 'Information security in project management',
  ),
  ControlEntry(
    id: 'A.5.9',
    sectionId: 'A.5',
    title: 'Inventory of information and other associated assets',
  ),
  ControlEntry(
    id: 'A.5.10',
    sectionId: 'A.5',
    title: 'Acceptable use of information and other associated assets',
  ),
  ControlEntry(id: 'A.5.11', sectionId: 'A.5', title: 'Return of assets'),
  ControlEntry(
    id: 'A.5.12',
    sectionId: 'A.5',
    title: 'Classification of information',
  ),
  ControlEntry(
    id: 'A.5.13',
    sectionId: 'A.5',
    title: 'Labelling of information',
  ),
  ControlEntry(id: 'A.5.14', sectionId: 'A.5', title: 'Information transfer'),
  ControlEntry(id: 'A.5.15', sectionId: 'A.5', title: 'Access control'),
  ControlEntry(id: 'A.5.16', sectionId: 'A.5', title: 'Identity management'),
  ControlEntry(
    id: 'A.5.17',
    sectionId: 'A.5',
    title: 'Authentication information',
  ),
  ControlEntry(id: 'A.5.18', sectionId: 'A.5', title: 'Access rights'),
  ControlEntry(
    id: 'A.5.19',
    sectionId: 'A.5',
    title: 'Information security in supplier relationships',
  ),
  ControlEntry(
    id: 'A.5.20',
    sectionId: 'A.5',
    title: 'Addressing information security within supplier agreements',
  ),
  ControlEntry(
    id: 'A.5.21',
    sectionId: 'A.5',
    title: 'Managing information security in the ICT supply chain',
  ),
  ControlEntry(
    id: 'A.5.22',
    sectionId: 'A.5',
    title: 'Monitoring, review and change management of supplier services',
  ),
  ControlEntry(
    id: 'A.5.23',
    sectionId: 'A.5',
    title: 'Information security for use of cloud services',
  ),
  ControlEntry(
    id: 'A.5.24',
    sectionId: 'A.5',
    title: 'Information security incident management planning and preparation',
  ),
  ControlEntry(
    id: 'A.5.25',
    sectionId: 'A.5',
    title: 'Assessment and decision on information security events',
  ),
  ControlEntry(
    id: 'A.5.26',
    sectionId: 'A.5',
    title: 'Response to information security incidents',
  ),
  ControlEntry(
    id: 'A.5.27',
    sectionId: 'A.5',
    title: 'Learning from information security incidents',
  ),
  ControlEntry(id: 'A.5.28', sectionId: 'A.5', title: 'Collection of evidence'),
  ControlEntry(
    id: 'A.5.29',
    sectionId: 'A.5',
    title: 'Information security during disruption',
  ),
  ControlEntry(
    id: 'A.5.30',
    sectionId: 'A.5',
    title: 'ICT readiness for business continuity',
  ),
  ControlEntry(
    id: 'A.5.31',
    sectionId: 'A.5',
    title: 'Legal, statutory, regulatory and contractual requirements',
  ),
  ControlEntry(
    id: 'A.5.32',
    sectionId: 'A.5',
    title: 'Intellectual property rights',
  ),
  ControlEntry(id: 'A.5.33', sectionId: 'A.5', title: 'Protection of records'),
  ControlEntry(
    id: 'A.5.34',
    sectionId: 'A.5',
    title: 'Privacy and protection of PII',
  ),
  ControlEntry(
    id: 'A.5.35',
    sectionId: 'A.5',
    title: 'Independent review of information security',
  ),
  ControlEntry(
    id: 'A.5.36',
    sectionId: 'A.5',
    title:
        'Compliance with policies, rules and standards for information security',
  ),
  ControlEntry(
    id: 'A.5.37',
    sectionId: 'A.5',
    title: 'Documented operating procedures',
  ),
  // A.6 People controls (8)
  ControlEntry(id: 'A.6.1', sectionId: 'A.6', title: 'Screening'),
  ControlEntry(
    id: 'A.6.2',
    sectionId: 'A.6',
    title: 'Terms and conditions of employment',
  ),
  ControlEntry(
    id: 'A.6.3',
    sectionId: 'A.6',
    title: 'Information security awareness, education and training',
  ),
  ControlEntry(id: 'A.6.4', sectionId: 'A.6', title: 'Disciplinary process'),
  ControlEntry(
    id: 'A.6.5',
    sectionId: 'A.6',
    title: 'Responsibilities after termination or change of employment',
  ),
  ControlEntry(
    id: 'A.6.6',
    sectionId: 'A.6',
    title: 'Confidentiality or non-disclosure agreements',
  ),
  ControlEntry(id: 'A.6.7', sectionId: 'A.6', title: 'Remote working'),
  ControlEntry(
    id: 'A.6.8',
    sectionId: 'A.6',
    title: 'Information security event reporting',
  ),
  // A.7 Physical controls (14)
  ControlEntry(
    id: 'A.7.1',
    sectionId: 'A.7',
    title: 'Physical security perimeters',
  ),
  ControlEntry(id: 'A.7.2', sectionId: 'A.7', title: 'Physical entry'),
  ControlEntry(
    id: 'A.7.3',
    sectionId: 'A.7',
    title: 'Securing offices, rooms and facilities',
  ),
  ControlEntry(
    id: 'A.7.4',
    sectionId: 'A.7',
    title: 'Physical security monitoring',
  ),
  ControlEntry(
    id: 'A.7.5',
    sectionId: 'A.7',
    title: 'Protecting against physical and environmental threats',
  ),
  ControlEntry(id: 'A.7.6', sectionId: 'A.7', title: 'Working in secure areas'),
  ControlEntry(
    id: 'A.7.7',
    sectionId: 'A.7',
    title: 'Clear desk and clear screen',
  ),
  ControlEntry(
    id: 'A.7.8',
    sectionId: 'A.7',
    title: 'Equipment siting and protection',
  ),
  ControlEntry(
    id: 'A.7.9',
    sectionId: 'A.7',
    title: 'Security of assets off-premises',
  ),
  ControlEntry(id: 'A.7.10', sectionId: 'A.7', title: 'Storage media'),
  ControlEntry(id: 'A.7.11', sectionId: 'A.7', title: 'Supporting utilities'),
  ControlEntry(id: 'A.7.12', sectionId: 'A.7', title: 'Cabling security'),
  ControlEntry(id: 'A.7.13', sectionId: 'A.7', title: 'Equipment maintenance'),
  ControlEntry(
    id: 'A.7.14',
    sectionId: 'A.7',
    title: 'Secure disposal or re-use of equipment',
  ),
  // A.8 Technological controls (34)
  ControlEntry(id: 'A.8.1', sectionId: 'A.8', title: 'User endpoint devices'),
  ControlEntry(
    id: 'A.8.2',
    sectionId: 'A.8',
    title: 'Privileged access rights',
  ),
  ControlEntry(
    id: 'A.8.3',
    sectionId: 'A.8',
    title: 'Information access restriction',
  ),
  ControlEntry(id: 'A.8.4', sectionId: 'A.8', title: 'Access to source code'),
  ControlEntry(id: 'A.8.5', sectionId: 'A.8', title: 'Secure authentication'),
  ControlEntry(id: 'A.8.6', sectionId: 'A.8', title: 'Capacity management'),
  ControlEntry(
    id: 'A.8.7',
    sectionId: 'A.8',
    title: 'Protection against malware',
  ),
  ControlEntry(
    id: 'A.8.8',
    sectionId: 'A.8',
    title: 'Management of technical vulnerabilities',
  ),
  ControlEntry(
    id: 'A.8.9',
    sectionId: 'A.8',
    title: 'Configuration management',
  ),
  ControlEntry(id: 'A.8.10', sectionId: 'A.8', title: 'Information deletion'),
  ControlEntry(id: 'A.8.11', sectionId: 'A.8', title: 'Data masking'),
  ControlEntry(
    id: 'A.8.12',
    sectionId: 'A.8',
    title: 'Data leakage prevention',
  ),
  ControlEntry(id: 'A.8.13', sectionId: 'A.8', title: 'Information backup'),
  ControlEntry(
    id: 'A.8.14',
    sectionId: 'A.8',
    title: 'Redundancy of information processing facilities',
  ),
  ControlEntry(id: 'A.8.15', sectionId: 'A.8', title: 'Logging'),
  ControlEntry(id: 'A.8.16', sectionId: 'A.8', title: 'Monitoring activities'),
  ControlEntry(id: 'A.8.17', sectionId: 'A.8', title: 'Clock synchronization'),
  ControlEntry(
    id: 'A.8.18',
    sectionId: 'A.8',
    title: 'Use of privileged utility programs',
  ),
  ControlEntry(
    id: 'A.8.19',
    sectionId: 'A.8',
    title: 'Installation of software on operational systems',
  ),
  ControlEntry(id: 'A.8.20', sectionId: 'A.8', title: 'Networks security'),
  ControlEntry(
    id: 'A.8.21',
    sectionId: 'A.8',
    title: 'Security of network services',
  ),
  ControlEntry(
    id: 'A.8.22',
    sectionId: 'A.8',
    title: 'Segregation of networks',
  ),
  ControlEntry(id: 'A.8.23', sectionId: 'A.8', title: 'Web filtering'),
  ControlEntry(id: 'A.8.24', sectionId: 'A.8', title: 'Use of cryptography'),
  ControlEntry(
    id: 'A.8.25',
    sectionId: 'A.8',
    title: 'Secure development life cycle',
  ),
  ControlEntry(
    id: 'A.8.26',
    sectionId: 'A.8',
    title: 'Application security requirements',
  ),
  ControlEntry(
    id: 'A.8.27',
    sectionId: 'A.8',
    title: 'Secure system architecture and engineering principles',
  ),
  ControlEntry(id: 'A.8.28', sectionId: 'A.8', title: 'Secure coding'),
  ControlEntry(
    id: 'A.8.29',
    sectionId: 'A.8',
    title: 'Security testing in development and acceptance',
  ),
  ControlEntry(id: 'A.8.30', sectionId: 'A.8', title: 'Outsourced development'),
  ControlEntry(
    id: 'A.8.31',
    sectionId: 'A.8',
    title: 'Separation of development, test and production environments',
  ),
  ControlEntry(id: 'A.8.32', sectionId: 'A.8', title: 'Change management'),
  ControlEntry(id: 'A.8.33', sectionId: 'A.8', title: 'Test information'),
  ControlEntry(
    id: 'A.8.34',
    sectionId: 'A.8',
    title: 'Protection of information systems during audit testing',
  ),
];

// ── ISO 9001:2015 — clausule 4–10 (geen Annex A) ────────────────────────────

const _iso9001Sections = <ControlSection>[
  ControlSection(id: '4', title: 'Context of the organization'),
  ControlSection(id: '5', title: 'Leadership'),
  ControlSection(id: '6', title: 'Planning'),
  ControlSection(id: '7', title: 'Support'),
  ControlSection(id: '8', title: 'Operation'),
  ControlSection(id: '9', title: 'Performance evaluation'),
  ControlSection(id: '10', title: 'Improvement'),
];

const _iso9001Controls = <ControlEntry>[
  ControlEntry(
    id: '4.1',
    sectionId: '4',
    title: 'Understanding the organization and its context',
  ),
  ControlEntry(
    id: '4.2',
    sectionId: '4',
    title: 'Understanding the needs and expectations of interested parties',
  ),
  ControlEntry(
    id: '4.3',
    sectionId: '4',
    title: 'Determining the scope of the quality management system',
  ),
  ControlEntry(
    id: '4.4',
    sectionId: '4',
    title: 'Quality management system and its processes',
  ),
  ControlEntry(id: '5.1', sectionId: '5', title: 'Leadership and commitment'),
  ControlEntry(id: '5.2', sectionId: '5', title: 'Policy'),
  ControlEntry(
    id: '5.3',
    sectionId: '5',
    title: 'Organizational roles, responsibilities and authorities',
  ),
  ControlEntry(
    id: '6.1',
    sectionId: '6',
    title: 'Actions to address risks and opportunities',
  ),
  ControlEntry(
    id: '6.2',
    sectionId: '6',
    title: 'Quality objectives and planning to achieve them',
  ),
  ControlEntry(id: '6.3', sectionId: '6', title: 'Planning of changes'),
  ControlEntry(id: '7.1', sectionId: '7', title: 'Resources'),
  ControlEntry(id: '7.2', sectionId: '7', title: 'Competence'),
  ControlEntry(id: '7.3', sectionId: '7', title: 'Awareness'),
  ControlEntry(id: '7.4', sectionId: '7', title: 'Communication'),
  ControlEntry(id: '7.5', sectionId: '7', title: 'Documented information'),
  ControlEntry(
    id: '8.1',
    sectionId: '8',
    title: 'Operational planning and control',
  ),
  ControlEntry(
    id: '8.2',
    sectionId: '8',
    title: 'Requirements for products and services',
  ),
  ControlEntry(
    id: '8.3',
    sectionId: '8',
    title: 'Design and development of products and services',
  ),
  ControlEntry(
    id: '8.4',
    sectionId: '8',
    title: 'Control of externally provided processes, products and services',
  ),
  ControlEntry(
    id: '8.5',
    sectionId: '8',
    title: 'Production and service provision',
  ),
  ControlEntry(
    id: '8.6',
    sectionId: '8',
    title: 'Release of products and services',
  ),
  ControlEntry(
    id: '8.7',
    sectionId: '8',
    title: 'Control of nonconforming outputs',
  ),
  ControlEntry(
    id: '9.1',
    sectionId: '9',
    title: 'Monitoring, measurement, analysis and evaluation',
  ),
  ControlEntry(id: '9.2', sectionId: '9', title: 'Internal audit'),
  ControlEntry(id: '9.3', sectionId: '9', title: 'Management review'),
  ControlEntry(id: '10.1', sectionId: '10', title: 'General'),
  ControlEntry(
    id: '10.2',
    sectionId: '10',
    title: 'Nonconformity and corrective action',
  ),
  ControlEntry(id: '10.3', sectionId: '10', title: 'Continual improvement'),
];

// ── ISO/IEC 42001:2023 — Annex A (38 controls, doelstellingen A.2–A.10) ──────

const _iso42001Sections = <ControlSection>[
  ControlSection(id: 'A.2', title: 'Policies related to AI'),
  ControlSection(id: 'A.3', title: 'Internal organization'),
  ControlSection(id: 'A.4', title: 'Resources for AI systems'),
  ControlSection(id: 'A.5', title: 'Assessing impacts of AI systems'),
  ControlSection(id: 'A.6', title: 'AI system life cycle'),
  ControlSection(id: 'A.7', title: 'Data for AI systems'),
  ControlSection(
    id: 'A.8',
    title: 'Information for interested parties of AI systems',
  ),
  ControlSection(id: 'A.9', title: 'Use of AI systems'),
  ControlSection(id: 'A.10', title: 'Third-party and customer relationships'),
];

const _iso42001Controls = <ControlEntry>[
  ControlEntry(id: 'A.2.2', sectionId: 'A.2', title: 'AI policy'),
  ControlEntry(
    id: 'A.2.3',
    sectionId: 'A.2',
    title: 'Alignment with other organizational policies',
  ),
  ControlEntry(id: 'A.2.4', sectionId: 'A.2', title: 'Review of the AI policy'),
  ControlEntry(
    id: 'A.3.2',
    sectionId: 'A.3',
    title: 'AI roles and responsibilities',
  ),
  ControlEntry(id: 'A.3.3', sectionId: 'A.3', title: 'Reporting of concerns'),
  ControlEntry(id: 'A.4.2', sectionId: 'A.4', title: 'Resource documentation'),
  ControlEntry(id: 'A.4.3', sectionId: 'A.4', title: 'Data resources'),
  ControlEntry(id: 'A.4.4', sectionId: 'A.4', title: 'Tooling resources'),
  ControlEntry(
    id: 'A.4.5',
    sectionId: 'A.4',
    title: 'System and computing resources',
  ),
  ControlEntry(id: 'A.4.6', sectionId: 'A.4', title: 'Human resources'),
  ControlEntry(
    id: 'A.5.2',
    sectionId: 'A.5',
    title: 'AI system impact assessment process',
  ),
  ControlEntry(
    id: 'A.5.3',
    sectionId: 'A.5',
    title: 'Documentation of AI system impact assessments',
  ),
  ControlEntry(
    id: 'A.5.4',
    sectionId: 'A.5',
    title: 'Assessing AI system impact on individuals or groups of individuals',
  ),
  ControlEntry(
    id: 'A.5.5',
    sectionId: 'A.5',
    title: 'Assessing societal impacts of AI systems',
  ),
  ControlEntry(
    id: 'A.6.1.2',
    sectionId: 'A.6',
    title: 'Objectives for responsible development of AI systems',
  ),
  ControlEntry(
    id: 'A.6.1.3',
    sectionId: 'A.6',
    title: 'Processes for responsible AI system design and development',
  ),
  ControlEntry(
    id: 'A.6.2.2',
    sectionId: 'A.6',
    title: 'AI system requirements and specification',
  ),
  ControlEntry(
    id: 'A.6.2.3',
    sectionId: 'A.6',
    title: 'Documentation of AI system design and development',
  ),
  ControlEntry(
    id: 'A.6.2.4',
    sectionId: 'A.6',
    title: 'AI system verification and validation',
  ),
  ControlEntry(id: 'A.6.2.5', sectionId: 'A.6', title: 'AI system deployment'),
  ControlEntry(
    id: 'A.6.2.6',
    sectionId: 'A.6',
    title: 'AI system operation and monitoring',
  ),
  ControlEntry(
    id: 'A.6.2.7',
    sectionId: 'A.6',
    title: 'AI system technical documentation',
  ),
  ControlEntry(
    id: 'A.6.2.8',
    sectionId: 'A.6',
    title: 'AI system recording of event logs',
  ),
  ControlEntry(
    id: 'A.7.2',
    sectionId: 'A.7',
    title: 'Data for development and enhancement of AI systems',
  ),
  ControlEntry(id: 'A.7.3', sectionId: 'A.7', title: 'Acquisition of data'),
  ControlEntry(
    id: 'A.7.4',
    sectionId: 'A.7',
    title: 'Quality of data for AI systems',
  ),
  ControlEntry(id: 'A.7.5', sectionId: 'A.7', title: 'Data provenance'),
  ControlEntry(id: 'A.7.6', sectionId: 'A.7', title: 'Data preparation'),
  ControlEntry(
    id: 'A.8.2',
    sectionId: 'A.8',
    title: 'System documentation and information for users',
  ),
  ControlEntry(id: 'A.8.3', sectionId: 'A.8', title: 'External reporting'),
  ControlEntry(
    id: 'A.8.4',
    sectionId: 'A.8',
    title: 'Communication of incidents',
  ),
  ControlEntry(
    id: 'A.8.5',
    sectionId: 'A.8',
    title: 'Information for interested parties',
  ),
  ControlEntry(
    id: 'A.9.2',
    sectionId: 'A.9',
    title: 'Processes for responsible use of AI systems',
  ),
  ControlEntry(
    id: 'A.9.3',
    sectionId: 'A.9',
    title: 'Objectives for responsible use of AI systems',
  ),
  ControlEntry(
    id: 'A.9.4',
    sectionId: 'A.9',
    title: 'Intended use of the AI system',
  ),
  ControlEntry(
    id: 'A.10.2',
    sectionId: 'A.10',
    title: 'Allocating responsibilities',
  ),
  ControlEntry(id: 'A.10.3', sectionId: 'A.10', title: 'Suppliers'),
  ControlEntry(id: 'A.10.4', sectionId: 'A.10', title: 'Customers'),
];
