---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: SAFARI digital sovereignty assessment
language: en
standards: SAFARI@0.9, ECSF
---

<!-- _class: title -->

# SAFARI digital sovereignty assessment

---
# How to Use This Workdeck

- First, define the scope, assertion, desired levels, and intended assurance level.
- For each key question, record the finding, a traceable source reference, and the evidence level.
- Treat missing or refused evidence as a finding with evidence level 0.
- Apply the six scoring rules before setting the level for each SOV objective.
- Formulate the assurance opinion only after quality control and post-date events have been assessed.
---

<!-- _class: table table-editable -->

# Document management and engagement team

| Field | Completion |
| --- | --- |
| Organization | … |
| Service or system | … |
| Supplier | … |
| Client | … |
| Person responsible for the claim | … |
| Executive auditor or consultant | … |
| Independent reviewer | … |
| Reference date and assessment period | … |
| Report version and date | … |
| TLP classification and distribution list | … |

---
<!-- _class: table table-editable -->

# Object and Scope

| Scope Component | Description |
| --- | --- |
| Assessed applications, platforms, and infrastructure | … |
| Direct suppliers | … |
| Relevant sub-suppliers and supply chain parties | … |
| Types of data | Personal data / corporate data / government data / classified information |
| Legal orders per party | … |
| Management-, support-, build- and signing locations | … |
| Explicit exclusions with justification | … |
| Normative framework version | SAFARI v0.9 (concept; voluntary methodology) |
---
<!-- _class: table table-editable -->

# Organization’s Assertion

| Component | Description |
| --- | --- |
| Object | [Organization] has assessed the sovereignty position regarding [service], provided by [supplier], according to ISO 27001:2022. |
| Time Period | The assessment covers the situation as of [date] within the scope established at [date]. |
| Framework | The assessment has been conducted according to SAFARI v0.9, a voluntary concept methodology linked to ISO 27001:2022 and the eight objectives of the ECSF. |
| Outcome | The organization states that it meets the chosen level [0-4] for [SOV code or all objectives]. |
| Exception | The outcome is based on the available evidence as of the date of assessment; changes may affect the outcome. |
| Owner and Formal Approval | … |
---
<!-- _class: table table-editable -->

# Desired Levels and Core Objectives

| Code | Objective | Core Objective | Recommended Minimum | Desired | Justification for Deviation |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | Strategic | Yes | 2 | … | … |
| SOV-2 | Legal and Regulatory | Yes | 2 | … | … |
| SOV-3 | Data and AI | Yes | 3 (2 only low-sensitivity and without personal data) | … | … |
| SOV-4 | Operational | Yes | 3 (2 only low-sensitivity, replaceable and without personal data) | … | … |
| SOV-5 | Supply Chain | Yes | 3 (2 only low-sensitivity and without personal data) | … | … |
| SOV-6 | Technology | Yes | 3 (2 only low-sensitivity and without personal data) | … | … |
| SOV-7 | Security and Compliance | Yes | 2 | … | … |
| SOV-8 | Sustainability | Yes | 1 | … | … |
---

<!-- _class: table table-editable -->

# Assurance approach

| Part | Choice and substantiation |
| --- | --- |
| Command type | Consultancy / limited assurance / reasonable assurance |
| Goals within the assurance assertion | … |
| Materiality and risk-oriented selection | … |
| Activities per type of evidence | Inspection / observation / re-execution / confirmation / analysis |
| Sampling approach and populations | … |
| Experts deployed | Legal / technical / sustainability / other: … |
| Independence and conflicts of interest | … |
| Restrictions on access or operations | … |

---
<!-- _class: table table-editable -->

# Formal Assurance Acceptance

| Acceptance Criterion | Assessment and Source | Outcome |
| --- | --- | --- |
| SAFARI is suitable as a criterion for the assertion and intended users | … | Yes / No |
| The responsible party acknowledges its responsibility for the assertion | … | Yes / No |
| Rational objective, intended users and distribution circle are defined | … | Yes / No |
| Independence, ethics, expertise and necessary experts are ensured | … | Yes / No |
| Assignment terms and desired level of assurance are agreed | … | Yes / No |
| Sufficient suitable evidence is expected to be available | … | Yes / No |
| Acceptance decision | Only proceed if all criteria ‘yes’ | Accept / Reject |
---

<!-- _class: table -->

# Levels of evidence

| Level | Name | Application |
| --- | --- | --- |
| 0 | No evidence | No substantiation, or evidence is missing or denied |
| 1 | Statement | Oral or written statement without further substantiation |
| 2 | Documentation | Contract, policy, procedure or report without independent verification |
| 3 | Technical evidence | Configuration, log, test or external legal advice obtained by the customer |
| 4 | Independent evidence | Collected or verified by an independent reviewing party |

---

<!-- _class: table table-editable -->

# Central evidence register

| Source ID | Document or registration | Owner | Date and version | Origin | Integrity and storage location |
| --- | --- | --- | --- | --- | --- |
| B-001 | … | … | … | Internal / supplier / external | … |
| B-002 | … | … | … | … | … |
| B-003 | … | … | … | … | … |
| B-004 | … | … | … | … | … |

---
<!-- _class: table -->

# Mandatory Scoring Rules

| Rule | Consequence for the Opinion |
| --- | --- |
| 0 · Legality | A legality risk always creates a gap in the relevant objective; advise a legal review. |
| 1 · Critical Questions | Evidence level 0 on a critical question limits the objective to a maximum level of 1. |
| 2 · Evidence bears the level | Evidence below the minimum of a question counts as 0. The objective evidence is the lowest evidence on critical questions; level 2, 3 and 4 require at least the same evidence level. |
| 3 · Weakest Link | The SEAL total level is the lowest established level of the core objectives. |
| 4 · Binding Legal Order | If an enforceable foreign access is protected only by the full technical route; this does not change SOV-2 or the SEAL total. A service that needs to process readable data does not have this route. |
| 5 · Technical Route | If an enforceable foreign access is protected only by the full technical route; this does not change SOV-2 or the SEAL total. A service that needs to process readable data does not have this route. |
---

<!-- _class: section -->

# SOV-1 · Strategic sovereignty

---
<!-- _class: table -->

# SOV-1 · Key Questions

| Question · Type/Min | Question | Required Evidence |
| --- | --- | --- |
| 1.1 · K·2+ | Who are the ultimate shareholders and under what legal order are they registered? | UBO register, annual report, shareholder register |
| 1.2 · K·2+ | Can a parent company outside the EU enforce a strategic course change? | Group structure scheme, articles of association, board regulations |
| 1.3 · K·2+ | Does the agreement contain change-of-control clauses? | Contract text |
| 1.4 · O·1+ | Is technology and IP located in the EU entity or with a foreign parent? | IP registration, licensing agreements |
| 1.5 · O·2+ | Is supplier dependence explicitly discussed and documented at board level? | Board minutes, risk register |
| 1.6 · O·2+ | Is there an exit or continuity scenario for a change of ownership? | Continuity plan, exit strategy |
---
<!-- _class: table table-editable -->

# SOV-1 · Findings and Evidence

| Question · Type/Min | Factual Finding | Source ID | Evidence 0-4 | Impact / Risk |
| --- | --- | --- | --- | --- |
| 1.1 · UBOs and legal order (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.2 · Parent outside EU can enforce course (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.3 · Change-of-control (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.4 · Location technology and IP (O·1+) | … | … | … | L/M/H · J/O/S |
| 1.5 · Dependence on board level (O·2+) | … | … | … | L/M/H · J/O/S |
| 1.6 · Exit on ownership change (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-1 · Level determination

| Level | Label | Attribute | Min. proof |
| --- | --- | --- | --- |
| 0 | No insight | No insight into ownership or power structure | None |
| 1 | Insight | Insight available, but no guarantee in case of change of ownership | 1 |
| 2 | Contractual guarantee | Change-of-control and transparency are contractually recorded | 2 |
| 3 | Control | EU governance is separate and enforceable; influence outside the EU is severely limited | 3 |
| 4 | Strategic autonomy | Sustainably European embedded; dependence is explicitly weighed in a board decision | 4 |

---
<!-- _class: table table-editable -->

# SOV-1 · Conclusion Statement

| Justification for the Central Scorecard | Input |
| --- | --- |
| Factual situation and appropriate characteristic from the scale of levels | … |
| Lowest evidence on critical questions, with source IDs | … |
| Applied rules and any limitations | … |
| Key reason, risk and finding ID | … |
---

<!-- _class: section -->

# SOV-2 · Legal and jurisdictional sovereignty

---
<!-- _class: table -->

# SOV-2 · Critical Review Questions

| Question · type/min | Review Question | Required Evidence |
| --- | --- | --- |
| 2.1 · K·2+ | What rights apply to the contract and which court is competent? | Contract text with rights and forum choice |
| 2.2 · K·3+ | Can the EU outside the EU enforce access or cooperation and does independent legal protection exist? | Legal advice, group structure and analysis per legal order |
| 2.3 · K·2+ | Does a notification obligation apply to a government request for data access? | Contract clause, transparency report |
| 2.6 · K·2+ | Are procedures for challenging foreign legal requests documented contractually? | Contract clause, provider policy |
| 2.7 · K·2+ | Is the legality of data substantiated with regard to all relevant legal jurisdictions? | DPIA, data transfer assessment, Data Act measures, rating and sector rules |
---
<!-- _class: table -->

# SOV-2 · Supporting Review Questions

| Question · type/min | Review Question | Required Evidence |
| --- | --- | --- |
| 2.4 · O·2+ | Is there a source code escrow and under what conditions is it accessible? | Escrow agreement, notarized statement |
| 2.5 · O·2+ | Can contractual rights be effectively enforced before an EU court? | Legal advice, contract analysis |
---
<!-- _class: table table-editable -->

# SOV-2 · Findings and Evidence

| Question · type/min | Factual Finding | Source ID | Evidence 0-4 | Impact / Risk |
| --- | --- | --- | --- | --- |
| 2.1 · Right and competent court (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.2 · Foreign enforcement and legal protection (K·3+) | … | … | … | L/M/H · J/O/S |
| 2.3 · Government access notification obligation (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.4 · Source code escrow (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.5 · Enforceable before EU court (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.6 · Challenge foreign requests (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.7 · Legality of data types (K·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-2 · Level determination

| Level | Label | Attribute | Min. proof |
| --- | --- | --- | --- |
| 0 | No insight | Applicable law and jurisdiction are unclear | None |
| 1 | Consciousness | Legal analysis without contractual guarantee | 1 |
| 2 | Contractual anchoring | Choice of law, choice of forum and reporting obligations established; residual exposure was analyzed | 2 |
| 3 | Practical mastery | Dispute procedures and escrow are set up and demonstrably feasible | 3 |
| 4 | Effective enforceability | Rights are effectively enforceable and extraterritorial risks are periodically assessed | 4 |

---
<!-- _class: table table-editable -->

# SOV-2 · Conclusion Statement

| Justification for the Central Scorecard | Input |
| --- | --- |
| Factual situation and appropriate characteristic from the scale of levels | … |
| Lowest evidence on critical questions, with source IDs | … |
| Application of rules 0 and 4 and any limitations | … |
| Key reason, risk and finding ID | … |
---

<!-- _class: section -->

# SOV-3 · Data and AI Sovereignty

---
<!-- _class: table -->

# SOV-3 · Review Questions

| Question · type/min | Review Question | Required Evidence |
| --- | --- | --- |
| 3.1 · K·3+ | Who manages the encryption keys: customer, provider or third party? | Architecture, key policy, BYOK or HYOK configuration |
| 3.2 · K·3+ | Is demonstrably who, when and from which location data has been accessed? | Logs, audit trail, SIEM reporting |
| 3.3 · K·2+ | Do storage and processing, including backups, telemetry and support, remain demonstrably in the EU? | DPIA, architecture, subprocessors, data center locations |
| 3.4 · O·2+ | Is the use of data for AI training or model improvement contractually excluded? | Contract, processor agreement |
| 3.5 · O·2+ | Can data demonstrably be permanently deleted, including backups and derived datasets? | Deletion certificate, procedure, contract |
| 3.6 · O·2+ | Is support access regulated and is this logged? | Support policy, logs, contract |
---
<!-- _class: table table-editable -->

# SOV-3 · Findings and Evidence

| Question · type/min | Factual Finding | Source ID | Evidence 0-4 | Impact / Risk |
| --- | --- | --- | --- | --- |
| 3.1 · Key management (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.2 · Traceable data access (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.3 · Storage and processing in EU (K·2+) | … | … | … | L/M/H · J/O/S |
| 3.4 · No AI training with data (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.5 · Permanent deletion (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.6 · Regulated support access (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-3 · Level determination

| Level | Label | Attribute | Min. proof |
| --- | --- | --- | --- |
| 0 | No control | Provider has actual access and key control | None |
| 1 | EU storage | EU storage agreed; access or key control is shared or unclear | 1 |
| 2 | Technically reinforced | Customer-driven key management and access restrictions; provider can still access keys or readable data | 2 |
| 3 | Shielded control | Only customer manages keys; provider does not see any readable data; processing remains in the EU | 3 |
| 4 | Full control | Full control over data, keys, AI models and processing | 4 |

---
<!-- _class: table table-editable -->

# SOV-3 · Conclusion Statement

| Justification for the Central Scorecard | Input |
| --- | --- |
| Factual situation and appropriate characteristic from the scale of levels | … |
| Lowest evidence on critical questions, with source IDs | … |
| Application of rules 0 and 5 and any limitations | … |
| Key reason, risk and finding ID | … |
---

<!-- _class: section -->

# SOV-4 · Operational sovereignty

---
<!-- _class: table -->

# SOV-4 · Toetsvragen

| Vraag · type/min. | Toetsvraag | Vereist bewijs |
| --- | --- | --- |
| 4.1 · K·2+ | Is de migratie gedocumenteerd en getest, en zijn data en configuraties volledig exporteerbaar? | Migratieprocedure, exporttest, Data Act clausules |
| 4.2 · K·2+ | Kunnen incidentafhandeling en dagelijks beheer volledig door EU-personeel worden uitgevoerd? | Personeelsoverzicht, supportlocatie, SLA |
| 4.3 · O·2+ | Is exploitatiekennis overdraagbaar en niet uitsluitend bij de leverancier aanwezig? | Trainingsplan, kennisborging, documentatie |
| 4.4 · O·2+ | Heeft de eigen organisatie volledige technische documentatie en runbooks? | Documentatie-inventaris, runbooks |
| 4.5 · O·1+ | Zijn kritieke onderaannemers bekend en realistisch vervangbaar? | Subprocessorlijst, alternatievenanalyse |
| 4.6 · O·2+ | Is er een exit-scenario met realistische overstaptijd en kosten? | Exitstrategie, migratiebusinesscase |
---
<!-- _class: table table-editable -->

# SOV-4 · Bevindingen en bewijs

| Vraag · type/min. | Feitelijke bevinding | Bron-ID | Bewijs 0-4 | Impact / risico |
| --- | --- | --- | --- | --- |
| 4.1 · Geteste migratie en export (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.2 · Beheer volledig door EU-personeel (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.3 · Overdraagbare exploitatiekennis (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.4 · Documentatie en runbooks (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.5 · Vervangbare onderaannemers (O·1+) | … | … | … | L/M/H · J/O/S |
| 4.6 · Realistische exit (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-4 · Level determination

| Level | Label | Attribute | Min. proof |
| --- | --- | --- | --- |
| 0 | Dependent | Operation completely dependent on non-EU supplier or personnel | None |
| 1 | Impressionable | EU operation on paper; critical actions outside the EU can be influenced | 1 |
| 2 | Exploitable with dependencies | EU exploitation possible; important dependencies or lock-in remain | 2 |
| 3 | Meaningful control | EU actors control operation; support access is EU-bound, logged and permitted; exit is realistic | 3 |
| 4 | In control | Full EU operation without critical non-EU dependencies | 4 |

---
<!-- _class: table table-editable -->

# SOV-4 · Doelconclusie

| Onderbouwing voor de centrale scorekaart | Invulling |
| --- | --- |
| Feitelijke situatie en passend kenmerk uit de niveauschaal | … |
| Laagste bewijs op kritische vragen, met bron-ID's | … |
| Toepassing van regel 5 en eventuele begrenzing | … |
| Belangrijkste reden, risico en bevinding-ID | … |
---

<!-- _class: section -->

# SOV-5 · Chain sovereignty

---
<!-- _class: table -->

# SOV-5 · Toetsvragen

| Vraag · type/min. | Toetsvraag | Vereist bewijs |
| --- | --- | --- |
| 5.1 · K·2+ | Is een actuele SBOM beschikbaar voor de software in de dienst? | SBOM, leveranciersverklaring |
| 5.2 · O·1+ | Zijn herkomst van hardware en firmware en niet-EU-afhankelijkheden bekend? | Hardware-inventaris, firmwareoverzicht, verklaring |
| 5.3 · K·2+ | Kunnen updates vóór brede uitrol worden gefaseerd, gevalideerd en teruggedraaid? | Updatebeleid, configuratie, testrapport |
| 5.4 · O·1+ | Zijn locatie en jurisdictie van build- en signing-infrastructuur bekend? | Technische documentatie, architectuurschema |
| 5.5 · K·2+ | Zijn alle subleveranciers bekend en is een wijzigingsmelding contractueel geregeld? | Subprocessorlijst, contractclausule |
| 5.6 · O·2+ | Zijn auditrechten voor subleveranciers contractueel verankerd? | Contractclausules, auditrapportages |
---
<!-- _class: table table-editable -->

# SOV-5 · Bevindingen en bewijs

| Vraag · type/min. | Feitelijke bevinding | Bron-ID | Bewijs 0-4 | Impact / risico |
| --- | --- | --- | --- | --- |
| 5.1 · Actuele SBOM (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.2 · Herkomst hardware en firmware (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.3 · Updates valideren en terugdraaien (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.4 · Build- en signingrechtsorde (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.5 · Subleveranciers en wijzigingsmelding (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.6 · Auditrechten subleveranciers (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-5 · Level determination

| Level | Label | Attribute | Min. proof |
| --- | --- | --- | --- |
| 0 | No influence | Critical chain completely outside EU influence | None |
| 1 | Opaque | EU law formally applies, but the chain is opaque | 1 |
| 2 | Understanding with dependencies | Chain insightful; material non-EU dependencies remain | 2 |
| 3 | Meaningful influence | Critical links are diversified; updates are verifiable; build and signing chain is known | 3 |
| 4 | Transparent and in control | Full transparency without critical non-EU dependencies | 4 |

---
<!-- _class: table table-editable -->

# SOV-5 · Doelconclusie

| Onderbouwing voor de centrale scorekaart | Invulling |
| --- | --- |
| Feitelijke situatie en passend kenmerk uit de niveauschaal | … |
| Laagste bewijs op kritische vragen, met bron-ID's | … |
| Toepassing van regel 5 en eventuele begrenzing | … |
| Belangrijkste reden, risico en bevinding-ID | … |
---

<!-- _class: section -->

# SOV-6 · Technological sovereignty

---
<!-- _class: table -->

# SOV-6 · Toetsvragen

| Vraag · type/min. | Toetsvraag | Vereist bewijs |
| --- | --- | --- |
| 6.1 · K·2+ | Zijn alle API's gebaseerd op open en publiek gedocumenteerde standaarden? | API-documentatie, standaardenregister |
| 6.2 · K·2+ | Kan alle data zonder verlies van kernfunctionaliteit naar een open formaat worden geëxporteerd? | Exporttest, technische documentatie |
| 6.3 · O·2+ | Welke softwarelicenties en beperkingen voor aanpassing of hergebruik gelden? | Licentietekst, juridische analyse |
| 6.4 · O·2+ | Is een broncode-auditrecht of escrow overeengekomen? | Escrowovereenkomst, auditrapport |
| 6.5 · O·1+ | Is de hele stack gedocumenteerd, inclusief gesloten componenten en alternatieven? | Architectuur, componentenregister |
| 6.6 · O·2+ | Is migratie naar een alternatief realistisch en getest? | Migratietest, exitstrategie, alternatievenanalyse |
---
<!-- _class: table table-editable -->

# SOV-6 · Bevindingen en bewijs

| Vraag · type/min. | Feitelijke bevinding | Bron-ID | Bewijs 0-4 | Impact / risico |
| --- | --- | --- | --- | --- |
| 6.1 · Open en gedocumenteerde API's (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.2 · Verliesvrije open data-export (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.3 · Licenties en hergebruik (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.4 · Broncode-audit of escrow (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.5 · Gedocumenteerde stack (O·1+) | … | … | … | L/M/H · J/O/S |
| 6.6 · Geteste migratie naar alternatief (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-6 · Level determination

| Level | Label | Attribute | Min. proof |
| --- | --- | --- | --- |
| 0 | Closed | Closed ecosystem; migration is practically impossible | None |
| 1 | Lock in | Some linkability; lock-in remains dominant | 1 |
| 2 | Migrateable | Interoperability and export are arranged; audit and escrow options exist | 2 |
| 3 | Meaningfully autonomous | Replaceability is tested and critical software is auditable or open source | 3 |
| 4 | In control | Full control over integration and standards without critical closed dependencies | 4 |

---
<!-- _class: table table-editable -->

# SOV-6 · Key Finding

| Supporting Evidence for Central Scorecard | Input |
| --- | --- |
| Factual situation and fitting characteristic from the scale levels | … |
| Lowest evidence on critical questions, with source IDs | … |
| Application of Rule 5 and any limitations | … |
| Key reason, risk, and finding ID | … |
---

<!-- _class: section -->

# SOV-7 · Security and Compliance Sovereignty

---
<!-- _class: table -->

# SOV-7 · Test Questions

| Question · Type/Min. | Question | Required Evidence |
| --- | --- | --- |
| 7.1 · C·3+ | Is the provider certified against a recognized standard and is the audit subject to EU oversight? | Certificate, audit report, scope |
| 7.2 · C·2+ | Is the SOC located in the EU and operating under EU jurisdiction? | SOC location, contract, SLA |
| 7.3 · O·3+ | Is compliance with NIS2, DORA, GDPR and CRA demonstrable and externally verified? | Compliance report, supervisory authority, audit |
| 7.4 · C·2+ | Who performs vulnerability management and patching and can this be done independently in the EU? | Patch policy, SLA, technical documentation |
| 7.5 · C·2+ | Are audit rights practically executable, including system and log access? | Contractual audit rights, executed audit report |
| 7.6 · O·2+ | Is the data breach and incident reporting procedure GDPR-compliant and demonstrably established? | Incident plan, processor agreement, reporting registry |
---
<!-- _class: table table-editable -->

# SOV-7 · Findings and Evidence

| Question · Type/Min. | Fact Finding | Source ID | Evidence 0-4 | Impact / Risk |
| --- | --- | --- | --- | --- |
| 7.1 · Certification under EU oversight (C·3+) | … | … | … | L/M/H · J/O/S |
| 7.2 · SOC in EU under EU law (C·2+) | … | … | … | L/M/H · J/O/S |
| 7.3 · Externally verified compliance (O·3+) | … | … | … | L/M/H · J/O/S |
| 7.4 · EU-vulnerability management (C·2+) | … | … | … | L/M/H · J/O/S |
| 7.5 · Practically executable audit rights (C·2+) | … | … | … | L/M/H · J/O/S |
| 7.6 · GDPR-compliant reporting procedure (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-7 · Level determination

| Level | Label | Attribute | Min. proof |
| --- | --- | --- | --- |
| 0 | Dependent | Security operations fully under non-EU control | None |
| 1 | Impressionable compliant | Formal compliance; implementation outside the EU remains subject to influence | 1 |
| 2 | Contractually guaranteed | EU jurisdiction, audit and reporting obligations are contractually regulated | 2 |
| 3 | EU operations | EU security operations are effective and independent audits are possible | 3 |
| 4 | In control | Full control over monitoring, incident response, patching and compliance | 4 |

---
<!-- _class: table table-editable -->

# SOV-7 · Key Finding

| Supporting Evidence for Central Scorecard | Input |
| --- | --- |
| Factual situation and fitting characteristic from the scale levels | … |
| Lowest evidence on critical questions, with source IDs | … |
| Applied rules and any limitations | … |
| Key reason, risk, and finding ID | … |
---

<!-- _class: section -->

# SOV-8 · Sustainability Sovereignty

---
<!-- _class: table -->

# SOV-8 · Test Questions

| Question · Type/Min. | Question | Required Evidence |
| --- | --- | --- |
| 8.1 · C·2+ | What is the measured PUE per datacenter location? | Datacenter reporting, independent measurement |
| 8.2 · O·2+ | Is energy demonstrably renewable and are certificates independently verified? | Energy certificates, independent report |
| 8.3 · O·2+ | Is CO2 emissions and water consumption transparent and externally verified? | ESG report, auditor’s statement, GRI |
| 8.4 · O·1+ | Is hardware lifecycle and e-waste policy documented and verifiable? | Policy, ISO 14001 certificate |
| 8.5 · O·1+ | Is dependency on critical raw materials assessed? | Risk analysis, supplier declaration |
| 8.6 · O·1+ | Does the provider fall under CSRD and are reports publicly available; if not, does it report voluntarily? | Annual report, CSRD or voluntary report |
---
<!-- _class: table table-editable -->

# SOV-8 · Findings and Evidence

| Question · Type/Min. | Fact Finding | Source ID | Evidence 0-4 | Impact / Risk |
| --- | --- | --- | --- | --- |
| 8.1 · Measured PUE per location (C·2+) | … | … | … | L/M/H · J/O/S |
| 8.2 · Verified renewable energy (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.3 · CO2 and water externally verified (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.4 · Lifecycle and e-waste policy (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.5 · Critical raw materials assessed (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.6 · CSRD or voluntary reporting (O·1+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-8 · Level determination

| Level | Label | Attribute | Min. proof |
| --- | --- | --- | --- |
| 0 | Opaque | No transparency; dominant non-EU dependence on energy or materials | None |
| 1 | Basic reporting | Basic reporting available; major structural dependencies remain | 1 |
| 2 | Transparent with dependencies | Transparency and contract requirements present; material dependencies remain | 2 |
| 3 | Influence | Significant EU influence on energy source and circular chain | 3 |
| 4 | Sustainable | Fully sustainable, transparent and EU-anchored with structural monitoring | 4 |

---
<!-- _class: table table-editable -->

# SOV-8 · Key Finding

| Supporting Evidence for Central Scorecard | Input |
| --- | --- |
| Factual situation and fitting characteristic from the scale levels | … |
| Lowest evidence on critical questions, with source IDs | … |
| Applied rules and any limitations | … |
| Key reason, risk, and finding ID | … |
---

<!-- _class: section -->

# Conclusion and assurance opinion

---

<!-- _class: table table-editable -->

# Legality per data type · Line 0

| Data type | Test frame | Substantiation and source ID | Outcome | Affected SOV target |
| --- | --- | --- | --- | --- |
| Personal Data | GDPR, including transfer and appropriate measures | … | Substantiated / risk | … |
| Non-personal business information | Data Act Article 32 | … | Substantiated / risk | … |
| Government or classified information | Applicable national and EU rules | … | Substantiated / risk | … |
| Regulated sector data | NIS2, DORA or sector-specific rules | … | Substantiated / risk | … |

---

<!-- _class: table table-editable -->

# Exposure to Legal Orders · Rule 4

| Party and legal order | Can government force? | Independent judicial process? | Is notification allowed to the customer? | Impact on proof and level |
| --- | --- | --- | --- | --- |
| … | Yes / no / unsure | Yes / no / unsure | Yes / no / unsure | … |
| … | … | … | … | … |
| … | … | … | … | … |

---
<!-- _class: table table-editable -->

# Rule 4 · Mandatory Outcome

| Condition or Consequence | Determination and Source ID |
| --- | --- |
| A government can enforce access or cooperation | Yes / no / uncertain: … |
| Independent legal proceedings are absent or notification to the recipient is prohibited | Yes / no / uncertain: … |
| If both apply: Questions 2.3, 2.5 and 2.6 are considered as evidence level 0 | Applied / n.v.t.: … |
| If both apply: SOV-2 is maximum level 1 | Applied / n.v.t.: … |
| If control exists within that legal order, then SOV-1 is also maximum level 1 | Applied / n.v.t.: … |
| Remaining Exposure | … |
---
<!-- _class: table table-editable -->

# Technical Route · Rule 5

| Condition | Outcome and Source ID |
|---|---|
| SOV-3 is at least level 3: keys exclusively with the customer; provider has no readable data access | … |
| No management or support access to readable data | … |
| SOV-5 is at least level 3: updates pre-validated and reversible; build and signing chain known | … |
| SOV-6 is at least level 3: operation of critical software verifiable | … |
| The service does not need to process data in a readable format | Yes / No |
| All conditions met | Only ‘yes’ if all preceding outcomes are positive: … |
| Result | Can support Rule 0; does not change SOV-2 or the SEAL total level. |
---
<!-- _class: table table-editable -->

# SAFARI Scorecard

| Code | Weight | Assessed 0-4 | Evidence 0-4 | Judgment Against Chosen Standard | Source Conclusion |
|---|---|---|---|---|---|
| SOV-1 | 15% | … | … | Meets / Gap / N.V.T. | … |
| SOV-2 | 10% | … | … | Meets / Gap / N.V.T. | … |
| SOV-3 | 10% | … | … | Meets / Gap / N.V.T. | … |
| SOV-4 | 15% | … | … | Meets / Gap / N.V.T. | … |
| SOV-5 | 20% | … | … | Meets / Gap / N.V.T. | … |
| SOV-6 | 15% | … | … | Meets / Gap / N.V.T. | … |
| SOV-7 | 10% | … | … | Meets / Gap / N.V.T. | … |
| SOV-8 | 5% | … | … | Meets / Gap / N.V.T. | … |
---
<!-- _class: table table-editable -->

# Overall Outcome

| Component | Outcome and Justification |
|---|---|
| SEAL Total Level · Lowest Core Objective | … |
| Weighted ECSF Score · Σ (assessed level / 4 × weight) | …% |
| Largest Gaps | … |
| Critical Dependencies | … |
| Desired Levels Under Recommendation | … |
| Legality Risks | … |
| Solvable Internally | … |
| Supplier Cooperation Required | … |
---

<!-- _class: table table-editable -->

# Indicative CADA position

| Part | Outcome and source ID |
| --- | --- |
| Relevance | Public sector / Critical activity / NIS2 sector / N/A |
| Target CADA level | 1 / 2 / 3 / 4 / n/a |
| Indicative achievable level | 1 / 2 / 3 / 4 / none |
| Unmet requirements | … |
| Evidential limitation | … |
| Mandatory wording | Indication based on the proposal; no judgment on conformity. |

---

<!-- _class: table table-editable -->

# Assurance assessment per target

| Goal | Proof critical questions | Legality risk | Type of judgment | Wording and caveats |
| --- | --- | --- | --- | --- |
| SOV-… | Lowest level: … | Yes / no | None / limited / reasonable | … |
| SOV-… | … | … | … | … |
| SOV-… | … | … | … | … |

---
<!-- _class: table -->

# Assurance Formulation Assistance

| Type | Condition | Standard Formulation |
|---|---|---|
| No Judgment | A critical question has evidence level 0 or 1 | Based on the available evidence, no judgment can be made regarding [objective] with respect to [service]. |
| Limited Certainty | All critical questions at least 2; not all at least 3 | Based on our work, we have found no evidence that [assertion] is incorrect. We provide a limited degree of certainty. |
| Reasonable Certainty | All critical questions at least 3 | Based on our work, we consider that [assertion]. We provide a reasonable degree of certainty. |
---

<!-- _class: table table-editable -->

# Findings and recommendations

| ID | SOV | Finding | Impact | Recommendation | Owner | Term |
| --- | --- | --- | --- | --- | --- | --- |
| F-01 | … | … | High / Mid / Low | … | … | … |
| F-02 | … | … | … | … | … | … |
| F-03 | … | … | … | … | … | … |

---

<!-- _class: table table-editable -->

# Quality control and events after reference date

| Control | Outcome and reviewer reference |
| --- | --- |
| Scope and assertion are established before execution | … |
| All critical questions have been covered or reported as limitations | … |
| Source references are traceable and levels of evidence are imitable | … |
| Scoring rules 0 to 5 have been demonstrably applied | … |
| Arithmetic and textual consistency has been checked | … |
| Independent review has been completed | … |
| Events after the reference date have been assessed | … |
| Outstanding differences of opinion have been processed | … |

---
<!-- _class: table table-editable -->

# Organization’s Assertion Confirmation

| Assertion | Fulfillment |
|---|---|
| Name and Function of Responsible Party | … |
| Declaration | The assertion, scope, and chosen standards have been fully and truthfully confirmed. |
| Date | … |
| Agreement | Yes / No |
---
<!-- _class: table table-editable -->

# Independent Quality Review

| Review | Fulfillment |
|---|---|
| Name and Function of Reviewer | … |
| Independent of Execution | Yes / No |
| Review Conclusion and any Outstanding Points | … |
| Date | … |
| Approval for Signature | Yes / No |
---
<!-- _class: sign-off -->

# Assurance Opinion Signature
---
# Sources and License

- Methodology: SAFARI v0.9 (concept), Brenno de Winter and Stichting LibreKAT.
- Status: Voluntary methodology. The minimum standards are advisory; rules 0 to and including 5 are binding for those who implement SAFARI.
- Starting Point: European Cloud Sovereignty Framework, supplemented with ISO 27001:2022 and an ISAE 3000 assurance structure.
- Full Methodology: https://pawprint.vigilis.online/LibreKAT/Safari
- This template content is a reworking of SAFARI and is subject to CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
- Always populate the current version, reference date, professional standards, and local legal requirements.
