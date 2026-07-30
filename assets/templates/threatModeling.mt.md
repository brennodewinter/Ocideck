---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: Threat modeling session
language: mt
---

<!-- _class: title -->

# Sessjoni tal-immudellar tat-theddid

[[OCIDECK_SEG]]] 

Sistema · Data · Facilitator · Parteċipanti

[[OCIDECK_SEG]]] 

Liema sistema jew komponent qed nimudellaw illum?

[[OCIDECK_SEG]]] 

Dak li huwa espliċitament barra mill-ambitu: …

[[OCIDECK_SEG]]] 

Suppożizzjonijiet li qed naħdmu magħhom:…

[[OCIDECK_SEG]]] 

Riżultat: theddid peżat b'mitigazzjonijiet u sid

[[OCIDECK_SEG]]] 

Skop u għan

[[OCIDECK_SEG]]] 

Immappjar tas-sistema

[[OCIDECK_SEG]]] 

Element

[[OCIDECK_SEG]]] 

Tip

[[OCIDECK_SEG]]] 

Noti

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

Komponent

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

Fluss tad-dejta

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

Partit estern

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

Fejn taqsam id-dejta minn fdati għal mhux fdati?

[[OCIDECK_SEG]]] 

Liema konfini naraw: netwerk, proċess, utent, katina tal-provvista?

[[OCIDECK_SEG]]] 

Fejn iseħħu l-awtentikazzjoni u l-validazzjoni tal-input?

[[OCIDECK_SEG]]] 

Pinġi kull konfini fuq l-iskeċċ tas-sistema:...

[[OCIDECK_SEG]]] 

Konfini tal-fiduċja

[[OCIDECK_SEG]]] 

referenza STRIDE

[[OCIDECK_SEG]]] 

Kategorija

[[OCIDECK_SEG]]] 

Tifsira

[[OCIDECK_SEG]]] 

Spoofing

[[OCIDECK_SEG]]] 

Jippretendu li huwa utent jew servizz ieħor

[[OCIDECK_SEG]]] 

Tbagħbis

[[OCIDECK_SEG]]] 

Modifika mhux awtorizzata ta' data jew kodiċi

[[OCIDECK_SEG]]] 

Ripudju

[[OCIDECK_SEG]]] 

Jiċħad li qatt seħħet azzjoni

[[OCIDECK_SEG]]] 

Żvelar ta' informazzjoni

[[OCIDECK_SEG]]] 

Informazzjoni tasal lil dawk li m'għandhomx permess jarawha

[[OCIDECK_SEG]]] 

Ċaħda ta' servizz

[[OCIDECK_SEG]]] 

Li tagħmel is-sistema ma tistax tintuża jew ma tistax tintlaħaq

[[OCIDECK_SEG]]] 

Elevazzjoni ta' privileġġ

[[OCIDECK_SEG]]] 

Jakkwistaw aktar privileġġi milli mogħtija

[[OCIDECK_SEG]]] 

Il-ġbir tat-theddid

[[OCIDECK_SEG]]] 

Theddida

[[OCIDECK_SEG]]] 

Kategorija STRIDE

[[OCIDECK_SEG]]] 

Komponent

[[OCIDECK_SEG]]] 

Riskju

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

Probabbiltà: kemm hu probabbli l-abbuż (baxx, medju, għoli)?

[[OCIDECK_SEG]]] 

Impatt: kemm ħsara jekk jiġri?

[[OCIDECK_SEG]]] 

Riskju = probabbiltà × impatt; high-high tmur l-ewwel

[[OCIDECK_SEG]]] 

F'dubju: agħżel l-ogħla stima u nnota għaliex

[[OCIDECK_SEG]]] 

Prijoritizzazzjoni: probabbiltà × impatt

[[OCIDECK_SEG]]] 

Mitigazzjonijiet u azzjonijiet

[[OCIDECK_SEG]]] 

Mitigazzjoni

[[OCIDECK_SEG]]] 

Sid

[[OCIDECK_SEG]]] 

Status

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

…

[[OCIDECK_SEG]]] 

Liema theddid ma nindirizzawx apposta:…

[[OCIDECK_SEG]]] 

Għaliex dan huwa ġġustifikat (probabbiltà, spiża, kuntest): …

[[OCIDECK_SEG]]] 

Min għandu din id-deċiżjoni: Rwol

[[OCIDECK_SEG]]] 

Meta nerġgħu nirrevedu dan:...

[[OCIDECK_SEG]]] 

Dak li aħna konxjament naċċettaw

[[OCIDECK_SEG]]] 

Skop u suppożizzjonijiet irreġistrati

[[OCIDECK_SEG]]] 

Komponenti, flussi ta' dejta u partijiet esterni mmappjati

[[OCIDECK_SEG]]] 

Konfini ta' trust imfassla

[[OCIDECK_SEG]]] 

Is-sitt kategoriji STRIDE kollha għaddew

[[OCIDECK_SEG]]] 

Theddid prijoritizzat mill-probabbiltà × impatt

[[OCIDECK_SEG]]] 

Mitigazzjonijiet assenjati lil sid

[[OCIDECK_SEG]]] 

Riskji aċċettati rreġistrati u proprjetà

[[OCIDECK_SEG]]] 

Sessjoni kompluta

[[OCIDECK_SEG]]] 

Sessjoni tal-immudellar tat-theddid
## System · Date · Facilitator · Participants

---

# Scope and goal

- Which system or component are we modeling today?
- What is explicitly out of scope: …
- Assumptions we are working with: …
- Outcome: weighted threats with mitigations and an owner

---

<!-- _class: table table-editable -->

# Mapping the system

| Element | Kind | Notes |
| --- | --- | --- |
| … | Component | … |
| … | Data flow | … |
| … | External party | … |

---

# Trust boundaries

- Where does data cross from trusted to untrusted?
- Which boundaries do we see: network, process, user, supply chain?
- Where do authentication and input validation happen?
- Draw every boundary on the system sketch: …

---

<!-- _class: table -->

# STRIDE reference

| Category | Meaning |
| --- | --- |
| Spoofing | Pretending to be another user or service |
| Tampering | Unauthorised modification of data or code |
| Repudiation | Denying that an action ever took place |
| Information disclosure | Information reaching those not allowed to see it |
| Denial of service | Making the system unusable or unreachable |
| Elevation of privilege | Gaining more privileges than granted |

---

<!-- _class: table table-editable -->

# Collecting threats

| Threat | STRIDE category | Component | Risk |
| --- | --- | --- | --- |
| … | … | … | … |
| … | … | … | … |
| … | … | … | … |

---

# Prioritising: likelihood × impact

- Likelihood: how probable is abuse (low, medium, high)?
- Impact: how much damage if it happens?
- Risk = likelihood × impact; high-high goes first
- In doubt: pick the higher estimate and note why

---

<!-- _class: table table-editable -->

# Mitigations and actions

| Mitigation | Owner | Status |
| --- | --- | --- |
| … | … | … |
| … | … | … |
| … | … | … |

---

# What we knowingly accept

- Which threats do we deliberately not address: …
- Why is that justified (likelihood, cost, context): …
- Who owns this decision: Role
- When do we revisit this: …

---

# Session complete
<!-- ocideck_list_style: checklist -->
<!-- ocideck_checklist_progress: true -->

- [ ] Scope and assumptions recorded
- [ ] Components, data flows and external parties mapped
- [ ] Trust boundaries drawn
- [ ] All six STRIDE categories walked through
- [ ] Threats prioritised by likelihood × impact
- [ ] Mitigations assigned to an owner
- [ ] Accepted risks recorded and owned
