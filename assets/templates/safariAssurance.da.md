---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: SAFARI-vurdering af digital suverænitet
language: da
standards: SAFARI@0.9, ECSF
---

<!-- _class: title -->

# SAFARI-vurdering af digital suverænitet

---
# Sådan bruges dette arbejdsark

- Fastlæg først omfang, påstand, ønskede niveauer og den tilsigtede grad af sikkerhed.
- Udfyld hver spørgsmål med fund, en sporbar kildehenvisning og bevisniveauet.
- Behandle manglende eller afvist bevis som en fund med bevisniveau 0.
- Anvend de seks rangeringsregler, før du fastlægger niveauet for hvert SOV-mål.
- Formulér assurancevurderingen først efter at kvalitetskontrollen og begivenhederne efter referencepunktet er vurderet.
---

<!-- _class: table table-editable -->

# Dokumenthåndterings- og opgaveteam

|  Felt | Fuldførelse |
| --- | --- |
| Organisation | … |
| Service eller system | … |
| Leliver | … |
| Client | … |
| Ansvarlig for kravet | … |
| Executive revisor eller konsulent | … |
| Uafhængig anmelder | … |
| Referencedato og vurderingsperiode | … |
| Rapportversion og dato | … |
| TLP klassificering og distributionsliste | … |

---
<!-- _class: table table-editable -->

# Objekt og omfang

| Områdeelement | Udfyldning |
| --- | --- |
| Vurderede applikationer, platforme og infrastruktur | … |
| Direkte leverandører | … |
| Relevante underleverandører og kædepartnere | … |
| Datatyper | Personoplysninger / virksomhedsdata / offentlige data / klassificerede oplysninger |
| Juridiske bestemmelser pr. involverede parter | … |
| Styrings-, support-, build- og signeringplaceringer | … |
| Eksplicitte undtagelser med begrundelse | … |
| Versionsnormativt rammeværk | SAFARI v0.9 (koncept; frivillig metode) |
---
<!-- _class: table table-editable -->

# Organisationens påstand

| Element | Udfyld tekst |
| --- | --- |
| Objekt | [Organisation] har vurderet suverænitetspositionen i forhold til [service], leveret af [leverandør]. |
| Tidsperiode | Vurderingen vedrører situationen pr. [dato] inden for omfang, der er fastlagt på [dato]. |
| Ramme | Vurderingen er udført i overensstemmelse med SAFARI v0.9, en frivillig konceptmetode knyttet til ISO 27001:2022 og de otte mål for ECSF. |
| Resultat | Organisationen påberåber sig, at den opfylder det valgte niveau [0-4] for [SOV-kode eller alle mål]. |
| Forbehold | Resultatet er baseret på det tilgængelige bevis pr. referencepunkt; ændringer kan påvirke resultatet. |
| Ejer og formel godkendelse | … |
---
<!-- _class: table table-editable -->

# Ønskede niveauer og kerne mål

| Kode | Mål | Kerne mål | Anbefalet minimum | Ønsket | Begrundelse ved afvigelse |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | Strategisk | Ja | 2 | … | … |
| SOV-2 | Juridisk og lovmæssigt | Ja | 2 | … | … |
| SOV-3 | Data og AI | Ja | 3 (2 kun lav-følsomt og uden personoplysninger) | … | … |
| SOV-4 | Operationelt | Ja | 3 (2 kun lav-følsomt, udskifteligt og uden personoplysninger) | … | … |
| SOV-5 | Kæde | Ja | 3 (2 kun lav-følsomt og uden personoplysninger) | … | … |
| SOV-6 | Teknologi | Ja | 3 (2 kun lav-følsomt og uden personoplysninger) | … | … |
| SOV-7 | Sikkerhed og overholdelse | Ja | 2 | … | … |
| SOV-8 | Bæredygtighed | Ja | 1 | … | … |
---

<!-- _class: table table-editable -->

# Aassurance tilgang

| Part | Valg og begrundelse |
| --- | --- |
|  Kommandotype | Rådgivning / begrænset sikkerhed / rimelig sikkerhed |
|  Mål inden for forsikringspåstanden | … |
| Væsentlighed og risikoorienteret udvælgelse | … |
| Aktiviteter pr. type bevis | Inspektion / observation / genudførelse / bekræftelse / analyse |
| Sampling tilgang og populationer | … |
|  Eksperter installeret | Juridisk / teknisk / bæredygtighed / andet: … |
| Uafhængighed og interessekonflikter | … |
| Begrænsninger for adgang eller aktiviteter | … |

---
<!-- _class: table table-editable -->

# Assurance-acceptation formel

| Acceptationskriterium | Vurdering og kilde | Resultat |
| --- | --- | --- |
| SAFARI er egnet som kriterium for påstanden og den tilsigtede brugere | … | Ja / nej |
| Den ansvarlige part anerkender sit ansvar for påstanden | … | Ja / nej |
| Rationel mål, den tilsigtede brugere og spredningscirkel er fastlagt | … | Ja / nej |
| Uafhængighed, etik, ekspertise og nødvendige eksperter er sikret | … | Ja / nej |
| Opdragsbetingelser og ønsket grad af sikkerhed er aftalt | … | Ja / nej |
| Tilstrækkeligt egnet bevis er forventeligt tilgængeligt | … | Ja / nej |
| Acceptationsbeslutning | Kun fortsætte ved alle kriterier 'ja' | Acceptere / ikke acceptere |
---

<!-- _class: table -->

#  Bevisniveauer

| Niveau |  Navn | Ansøgning |
| --- | --- | --- |
| 0 | Ingen bevis | Ingen dokumentation, eller bevis mangler eller afvist |
| 1 |  Erklæring |  Mundtlig eller skriftlig erklæring uden yderligere begrundelse |
| 2 | Dokumentation |  Kontrakt, politik, procedure eller rapport uden uafhængig verifikation |
| 3 | Teknisk bevis | Konfiguration, log, test eller ekstern juridisk rådgivning, som kunden har indhentet |
| 4 | Uafhængige beviser |  Indsamlet eller verificeret af en uafhængig testpart |

---

<!-- _class: table table-editable -->

# Centralt bevisregister

|  Kilde-id | Dokument eller registrering | Ejer | Dato og version | Oprindelse | Integritet og opbevaringsplacering |
| --- | --- | --- | --- | --- | --- |
| B-001 | … | … | … | Intern / leverandør / ekstern | … |
| B-002 | … | … | … | … | … |
| B-003 | … | … | … | … | … |
| B-004 | … | … | … | … | … |

---
<!-- _class: table -->

# Bindende rangeringsregler

| Regel | Konsekvens for vurderingen |
| --- | --- |
| 0 · Lovlighed | En lovlighedsrisiko gør det involverede mål altid et hul; anbefal en juridisk vurdering. |
| 1 · Kritisk spørgsmål | Bevisniveau 0 på et kritisk spørgsmål begrænser målet til maksimalt niveau 1. |
| 2 · Bevis bærer niveauet | Bevis under minimum af et spørgsmål tæller som 0. Målbevis er det laveste bevis på kritiske spørgsmål; niveau 2, 3 og 4 kræver der mindst det samme bevisniveau. |
| 3 · Svageste led | SEAL-totalniveauet er det laveste fastsatte niveau af kerne målene. |
| 4 · Fungerende lovmæssighed | Ved håndhævelig udenlandsk adgang beskytter kun den fulde tekniske rute; det ændrer ikke SOV-2 og SEAL-totalet. En tjeneste, der skal behandle læsbare data, har ikke denne rute. |
| 5 · Teknisk rute | Ved håndhævelig udenlandsk adgang beskytter kun den fulde tekniske rute; det ændrer ikke SOV-2 og SEAL-totalet. |
---

<!-- _class: section -->

# SOV-1 · Strategisk suverænitet

---
<!-- _class: table -->

# SOV-1 · Spørgsmål

| Spørgsmål · type/min. | Spørgsmål | Krævet bevis |
| --- | --- | --- |
| 1.1 · K·2+ | Hvem er de endelige aktionærer og under hvilken lovgivning er de registreret? | UBO-register, årsregnskab, aktionærregister |
| 1.2 · K·2+ | Kan en modervirksomhed uden for EU påtvinge en strategisk kursændring? | Gruppestrukturdiagram, vedtægter, bestyrelsesreglement |
| 1.3 · Change-of-control (K·2+) | Indeholder kontrakten change-of-control-klausuler? | Kontrakttekst |
| 1.4 · Lokation teknologi og IP (O·1+) | Er teknologi og IP underlagt EU'en eller en udenlandsk modervirksomhed? | IP-registrering, licenstagning |
| 1.5 · Afhængighed på bestyrelsesniveau (O·2+) | Er leverandørafhængighed eksplicit diskuteret og fastlagt på bestyrelsesniveau? | Bestyrelsesprotokoller, risikoregister |
| 1.6 · Exit ved ejendomsændring (O·2+) | Er der en exit- eller kontinuitetsplan for en ejendomsændring? | Kontinuitetsplan, exitstrategi |
---
<!-- _class: table table-editable -->

# SOV-1 · Fund og bevis |

| Spørgsmål · type/min. | Faktisk fund | Kilde-ID | Bevis 0-4 | Impact / risiko |
| --- | --- | --- | --- | --- |
| 1.1 · UBO'er og lovgivning (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.2 · Modervirksomhed uden for EU kan påtvinge kursændring (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.3 · Change-of-control (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.4 · Lokation teknologi og IP (O·1+) | … | … | … | L/M/H · J/O/S |
| 1.5 · Afhængighed på bestyrelsesniveau (O·2+) | … | … | … | L/M/H · J/O/S |
| 1.6 · Exit ved ejendomsændring (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-1 · Niveaubestemmelse

| Niveau | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Ingen indsigt | Ingen indsigt i ejerskab eller magtstruktur | Ingen |
| 1 | Indsigt | Indsigt tilgængelig, men ingen garanti i tilfælde af ejerskifte | 1 |
| 2 | Kontraktgaranti |  Ændring af kontrol og gennemsigtighed er kontraktligt aftalt | 2 |
| 3 |  Kontrol | EU-styring er adskilt og håndhæves; indflydelse uden for EU er stærkt begrænset | 3 |
| 4 | Strategisk autonomi | Bæredygtig europæisk indlejret; afhængighed afvejes eksplicit i en bestyrelsesbeslutning | 4 |

---
<!-- _class: table table-editable -->

# Målkonklusion

| Begrundelse for hovedscorekort | Implementering |
| --- | --- |
| Faktuel situation og passende karakteristik fra skalaen | … |
| Laveste bevis på kritiske spørgsmål, med kilde-ID'er | … |
| Anvendte regler og eventuel begrænsning | … |
| Vigtigste årsag, risiko og fund-ID | … |
---

<!-- _class: section -->

# SOV-2 · Juridisk suverænitet og jurisdiktion

---
<!-- _class: table -->

# SOV-2 · Kritisk testspørgsmål

| Spørgsmål · type/min. | Testspørgsmål | Krævet bevis |
| --- | --- | --- |
| 2.1 · K·2+ | Hvilke rettigheder gælder for kontrakten og hvilken domstol er bemyndiget? | Kontrakttekst med ret- og forretningsmandatvalg |
| 2.2 · K·3+ | Kan en regering uden for EU påtvinge adgang eller samarbejde og eksisterer uafhængig retssikkerhed? | Juridisk rådgivning, gruppe struktur og analyse pr. retssystem |
| 2.3 · K·2+ | Er der en rapporteringspligt ved et offentligt anmodning om dataadgang? | Kontraktklausul, gennemsigtighedsrapport |
| 2.6 · K·2+ | Er der procedurer for at bestride udenlandske juridiske anmodninger kontraktuelt fastlagt? | Kontraktklausul, leverandørens politik |
| 2.7 · K·2+ | Er lovligheden af data understøttet i forhold til alle relevante retssystemer? | DPIA, dataoverførselstest, Data Act-foranstaltninger, klassificerings- og sektorregler |
---
<!-- _class: table -->

# SOV-2 · Støttende testspørgsmål

| Spørgsmål · type/min. | Testspørgsmål | Krævet bevis |
| --- | --- | --- |
| 2.4 · O·2+ | Er der en kildekode escrow og under hvilke betingelser er den tilgængelig? | Escrow-aftale, notarbekræftelse |
| 2.5 · O·2+ | Kan kontraktrettigheder effektivt håndhæves ved en EU-domstol? | Juridisk rådgivning, kontraktanalyse |
---
<!-- _class: table table-editable -->

# SOV-2 · Fund og bevis |
| Spørgsmål · type/min. | Faktisk fund | Kilde-ID | Bevis 0-4 | Risiko / Impact |
| --- | --- | --- | --- | --- |
| 2.1 · Ret og bemyndiget domstol (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.2 · Udenlandske tvangsforanstaltninger og retssikkerhed (K·3+) | … | … | … | L/M/H · J/O/S |
| 2.3 · Rapporteringspligt ved offentlig anmodning (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.4 · Kildekode escrow (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.5 · Håndhævelig ved EU-domstol (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.6 · Bestridelse af udenlandske anmodninger (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.7 · Lovlighed af dataarter (K·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-2 · Niveaubestemmelse

| Niveau | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Ingen indsigt | Gældende lov og jurisdiktion er uklar | Ingen |
| 1 |  Bevidsthed | Juridisk analyse uden kontraktlig garanti | 1 |
| 2 | Kontraktmæssig forankring |  Lovvalg, valg af forum og indberetningsforpligtelser etableret; resterende eksponering blev analyseret | 2 |
| 3 | Praktisk kontrol | Tvisteprocedurer og deponering er blevet oprettet og påviselig muligt | 3 |
| 4 | Effektiv håndhævelse | Rights kan håndhæves effektivt, og ekstraterritoriale risici vurderes med jævne mellemrum | 4 |

---
<!-- _class: table table-editable -->

# SOV-2 · Konklusion

| Begrundelse for den centrale scorekort | Implementering |
| --- | --- |
| Faktuelt scenarie og passende karakteristik fra niveaubanen | … |
| Laveste bevis på kritiske spørgsmål, med kilde-ID'er | … |
| Anvendelse af regler 0 og 4 samt eventuel begrænsning | … |
| Vigtigste årsag, risiko og fund-ID | … |
---

<!-- _class: section -->

# SOV-3 · Data- og AI-suverænitet

---
<!-- _class: table -->

# SOV-3 · Testspørgsmål

| Spørgsmål · type/min. | Testspørgsmål | Krævet bevis |
| --- | --- | --- |
| 3.1 · K·3+ | Hvem administrerer krypteringsnøglerne: abonnent, leverandør eller en tredjepart? | Arkitektur, nøglepolitik, BYOK- eller HYOK-konfiguration |
| 3.2 · K·3+ | Er der spor af, hvem, hvornår og fra hvilken placering data er blevet tilgået? | Logs, audit trail, SIEM-rapporter |
| 3.3 · K·2+ | Forblive opbevaring og behandling, inklusive backups, telemetri og support, bekræftet i EU? | DPIA, arkitektur, underleverandører, datacenter placeringer |
| 3.4 · O·2+ | Bruges data til AI-træning eller modelforbedring kontraktuelt udelukket? | Kontrakt, processor aftale |
| 3.5 · O·2+ | Kan data beviseligt slettes, inklusive backups og afledte datasæt? | Sletningscertifikat, procedure, kontrakt |
| 3.6 · O·2+ | Er supportadgang reguleret og logges den? | Supportpolitik, logs, kontrakt |
---
<!-- _class: table table-editable -->

# SOV-3 · Fund og bevis |
| Spørgsmål · type/min. | Faktisk fund | Kilde-ID | Bevis 0-4 | Risiko / Impact |
| --- | --- | --- | --- | --- |
| 3.1 · Administrering af krypteringsnøgler (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.2 · Sporbar datatilgang (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.3 · Opbevaring og behandling i EU (K·2+) | … | … | … | L/M/H · J/O/S |
| 3.4 · Ingen AI-træning med data (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.5 · Definitiv sletning (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.6 · Reguleret supportadgang (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-3 · Niveaubestemmelse

| Niveau | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Ingen kontrol | A-udbyderen har faktisk adgang og nøglekontrol | Ingen |
| 1 | EU opbevaring | EU lagring aftalt; adgang eller nøglekontrol er delt eller uklar | 1 |
| 2 | Teknisk forstærket | Kundedrevet nøglestyring og adgangsbegrænsninger; udbyder kan stadig få adgang til nøgler eller læsbare data | 2 |
| 3 | ASafskærmet kontrol | Kun kunden administrerer nøgler; udbyderen kan ikke se nogen læsbare data; behandlingen forbliver i EU | 3 |
| 4 | Fuld kontrol | Fuld kontrol over data, nøgler, AI-modeller og behandling | 4 |

---
<!-- _class: table table-editable -->

# SOV-3 · Formålsvurdering

| Begrundelse for hovedscorekortet | Implementering |
| --- | --- |
| Faktuel situation og passende karakteristik fra niveaubanen | … |
| Laveste bevis på kritiske spørgsmål, med kilde-ID'er | … |
| Anvendelse af regler 0 og 5 samt eventuel begrænsning | … |
| Vigtigste årsag, risiko og fund-ID | … |
---

<!-- _class: section -->

# SOV-4 · Operationel suverænitet

---
<!-- _class: table -->

# SOV-4 · Testspørgsmål

| Spørgsmål · type/min. | Testspørgsmål | Krævet bevis |
| --- | --- | --- |
| 4.1 · K·2+ | Er migrering dokumenteret og testet, og er data og konfigurationer fuldt ud eksporterbare? | Migreringsprocedure, eksporttest, Data Akt klausuler |
| 4.2 · K·2+ | Kan hændelsesbehandling og daglig drift fuldt ud udføres af EU-personale? | Personalekort, supportlokation, SLA |
| 4.3 · O·2+ | Er driftsviden overdraget og ikke udelukkende til stede hos leverandøren? | Træningsplan, videnborgning, dokumentation |
| 4.4 · O·2+ | Har den egen organisation fuld teknisk dokumentation og runbooks? | Dokumentationsinventar, runbooks |
| 4.5 · O·1+ | Er kritiske underleverandører kendt og realistisk udskiftelige? | Subprocesorliste, alternativeranalyse |
| 4.6 · O·2+ | Er der et exit-scenarie med realistisk overgangstid og omkostninger? | Exitstrategi, migrationsforretningscase |
---
<!-- _class: table table-editable -->

# SOV-4 · Fund og beviser

| Spørgsmål · type/min. | Faktisk fund | Kilde-ID | Bevis 0-4 | Impact / risiko |
| --- | --- | --- | --- | --- |
| 4.1 · Testet migrering og eksport (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.2 · Drift udført af EU-personale (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.3 · Overdraget driftsviden (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.4 · Dokumentation og runbooks (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.5 · Udskiftelige underleverandører (O·1+) | … | … | … | L/M/H · J/O/S |
| 4.6 · Realistisk exit (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-4 · Niveaubestemmelse

| Niveau | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Aafhængig | Drift er fuldstændig afhængig af ikke-EU leverandør eller personale | Ingen |
| 1 | Impressionsdygtig | EU operation på papir; kritiske handlinger uden for EU kan påvirkes | 1 |
| 2 | Udnyttes med afhængigheder | EU udnyttelse mulig; vigtige afhængigheder eller lock-in forbliver | 2 |
| 3 | Meningsfuld kontrol | EU aktører kontrol drift; supportadgang er EU-bundet, logget og tilladt; exit er realistisk | 3 |
| 4 | In kontrol | Fuld EU-drift uden kritiske ikke-EU-afhængigheder | 4 |

---
<!-- _class: table table-editable -->

# SOV-4 · Målkonklusion

| Begrundelse for den centrale scorekort | Indhold |
| --- | --- |
| Faktisk situation og passende karakteristika fra niveauskalaen | … |
| Laveste bevis på kritiske spørgsmål, med kilde-ID'er | … |
| Anvendte regler og eventuel begrænsning | … |
| Vigtigste årsag, risiko og fund-ID | … |
---

<!-- _class: section -->

# SOV-5 · Kædesuverænitet

---
<!-- _class: table -->

# SOV-5 · Testspørgsmål

| Spørgsmål · type/min. | Testspørgsmål | Krævet bevis |
| --- | --- | --- |
| 5.1 · K·2+ | Er en aktuel SBOM tilgængelig for softwaren i tjenesten? | SBOM, leverandørdeklaration |
| 5.2 · O·1+ | Er oprindelse af hardware og firmware og ikke-EU-afhængigheder kendt? | Hardware inventar, firmwareoversigt, erklæring |
| 5.3 · K·2+ | Kan opdateringer før bred udrulning fases, valideres og rulles tilbage? | Opdateringspolitik, konfiguration, testrapport |
| 5.4 · O·1+ | Er placering og jurisdiktion af build- og signering-infrastruktur kendt? | Teknisk dokumentation, arkitekturdiagram |
| 5.5 · K·2+ | Er alle underleverandører kendt og er der en ændringsmeddelelse kontraktligt ordnet? | Subprocesorliste, klausul i kontrakten |
| 5.6 · O·2+ | Er auditrettigheder for underleverandører kontraktligt fastlagt? | Klausuler i kontrakten, auditrapporter |
---
<!-- _class: table table-editable -->

# SOV-5 · Fund og beviser

| Spørgsmål · type/min. | Faktisk fund | Kilde-ID | Bevis 0-4 | Impact / risiko |
| --- | --- | --- | --- | --- |
| 5.1 · Aktuel SBOM (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.2 · Oprindelse hardware og firmware (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.3 · Opdateringer valideres og rulles tilbage (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.4 · Build- og signeringrettigheder (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.5 · Underleverandører og ændringsmeddelelse (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.6 · Auditrettigheder underleverandører (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-5 · Niveaubestemmelse

| Niveau | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Ingen indflydelse | Kritisk kæde helt uden for EU's indflydelse | Ingen |
| 1 | Igennemsigtig | EU-lovgivningen gælder formelt, men kæden er uigennemsigtig | 1 |
| 2 | Indsigt med afhængigheder | Chain indsigtsfuld; materielle ikke-EU-afhængigheder forbliver | 2 |
| 3 | Meningsfuld indflydelse | Kritiske links er diversificerede; opdateringer kan verificeres; bygge- og signeringskæde er kendt | 3 |
| 4 | Transparent og i kontrol | Fuld gennemsigtighed uden kritiske ikke-EU-afhængigheder | 4 |

---
<!-- _class: table table-editable -->

# SOV-5 · Målkonklusion

| Begrundelse for den centrale scorekort | Indhold |
| --- | --- |
| Faktisk situation og passende karakteristika fra niveauskalaen | … |
| Laveste bevis på kritiske spørgsmål, med kilde-ID'er | … |
| Anvendelse af regel 5 og eventuel begrænsning | … |
| Vigtigste årsag, risiko og fund-ID | … |
---

<!-- _class: section -->

# SOV-6 · Teknologisk suverænitet

---
<!-- _class: table -->

# SOV-6 · Testspørgsmål

| Spørgsmål · type/min. | Testspørgsmål | Krævet bevis |
| --- | --- | --- |
| 6.1 · K·2+ | Er alle API'er baseret på åbne og offentligt dokumenterede standarder? | API-dokumentation, standardregister |
| 6.2 · K·2+ | Kan alle data uden tab af kernefunktionalitet eksporteres til et åbent format? | Eksporttest, teknisk dokumentation |
| 6.3 · O·2+ | Hvilke softwarelicenser og begrænsninger for tilpasning eller genbrug gælder? | Licenstekst, juridisk analyse |
| 6.4 · O·2+ | Er der en kildekode-auditret eller escrow aftalt? | Escrow-aftale, auditrapport |
| 6.5 · O·1+ | Er hele stacken dokumenteret, inklusive lukkede komponenter og alternativer? | Arkitektur, komponentregister |
| 6.6 · O·2+ | Er migration til et alternativ realistisk og testet? | Migrerings test, exitstrategi, alternativeranalyse |
---
<!-- _class: table table-editable -->

# SOV-6 · Fund og beviser

| Spørgsmål · type/min. | Faktisk fund | Kilde-ID | Bevis 0-4 | Impact / risiko |
| --- | --- | --- | --- | --- |
| 6.1 · Åbne og dokumenterede API'er (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.2 · Tab af data ved åben eksport (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.3 · Licenser og genbrug (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.4 · Kildekode-audit eller escrow (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.5 · Dokumenteret stack (O·1+) | … | … | … | L/M/H · J/O/S |
| 6.6 · Testet migration til alternativ (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-6 · Niveaubestemmelse

| Niveau | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Lukket | Lukket økosystem; migration er praktisk talt umulig | Ingen |
| 1 | Lås ind | Nogle linkbarhed; lock-in forbliver dominerende | 1 |
| 2 | Migrerbar | Interoperabilitet og eksport er arrangeret; revision og deponeringsmuligheder findes | 2 |
| 3 | Meningsfuldt autonom | Udskiftelighed er testet, og kritisk software kan verificeres via revision eller open source | 3 |
| 4 | In kontrol | Fuld kontrol over integration og standarder uden kritiske lukkede afhængigheder | 4 |

---
<!-- _class: table table-editable -->

# SOV-6 · Målkonklusion

| Begrundelse for den centrale scorekort | Indhold |
| --- | --- |
| Faktuel situation og passende karakteristika fra niveaubanen | … |
| Laveste bevis på kritiske spørgsmål, med kilde-ID'er | … |
| Anvendelse af regel 5 og eventuel begrænsning | … |
| Vigtigste årsag, risiko og fund-ID | … |
---

<!-- _class: section -->

# SOV-7 · Sikkerheds- og overholdelsessuverænitet

---
<!-- _class: table -->

# SOV-7 · Centrale spørgsmål

| Spørgsmål · type/min. | Centralt spørgsmål | Krævet bevis |
| --- | --- | --- |
| 7.1 · K·3+ | Er leverandøren certificeret mod en anerkendt standard og er audittet under EU-overvågning? | Certifikat, auditrapport, scope |
| 7.2 · K·2+ | Er SOC'en beliggende i EU og opererer under EU-jurisdiktion? | SOC-lokation, kontrakt, SLA |
| 7.3 · O·3+ | Er overholdelse af NIS2, DORA, GDPR og CRA dokumenteret og eksternt verificeret? | Overholdelsesrapport, tilsynsmyndighed, audit |
| 7.4 · K·2+ | Hvem udfører sårbarhedsstyring og patching, og kan det selvstændigt i EU? | Patchpolitik, SLA, teknisk dokumentation |
| 7.5 · K·2+ | Er auditrettigheder praktisk gennemførlige, inklusive system- og logadgang? | Kontraktuel auditret, udført auditrapport |
| 7.6 · O·2+ | Er der en rapporteringsprocedure for datalækager og hændelser i overensstemmelse med GDPR og dokumenteret? | Incidentplan, underleverandørakta, rapporteringslog |
---
<!-- _class: table table-editable -->

# SOV-7 · Fund og beviser

| Spørgsmål · type/min. | Faktisk fund | Kilde-ID | Bevis 0-4 | Impact / risiko |
| --- | --- | --- | --- | --- |
| 7.1 · Certificering under EU-overvågning (K·3+) | … | … | … | L/M/H · J/O/S |
| 7.2 · SOC i EU under EU-ret (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.3 · Eksternt verificeret overholdelse (O·3+) | … | … | … | L/M/H · J/O/S |
| 7.4 · EU-sårbarhedsstyring (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.5 · Praktisk gennemførlige auditrettigheder (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.6 · GDPR-overensstemmende rapporteringsprocedure (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-7 · Niveaubestemmelse

| Niveau | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Aafhængig | Sikkerhedsoperationer helt under ikke-EU-kontrol | Ingen |
| 1 | Impressionable kompatibel | Formel overholdelse; implementering uden for EU er fortsat underlagt indflydelse | 1 |
| 2 | Kontraktmæssigt garanteret | EU jurisdiktion, revision og rapporteringsforpligtelser er kontraktligt reguleret | 2 |
| 3 | EU operationer | EU sikkerhedsoperationer er effektive, og uafhængige revisioner er mulige | 3 |
| 4 | In kontrol | Fuld kontrol over overvågning, hændelsesrespons, patching og overholdelse | 4 |

---
<!-- _class: table table-editable -->

# SOV-7 · Målkonklusion

| Begrundelse for den centrale scorekort | Indhold |
| --- | --- |
| Faktuel situation og passende karakteristika fra niveaubanen | … |
| Laveste bevis på kritiske spørgsmål, med kilde-ID'er | … |
| Anvendte regler og eventuel begrænsning | … |
| Vigtigste årsag, risiko og fund-ID | … |
---

<!-- _class: section -->

# SOV-8 · Suverænitet for bæredygtighed

---
<!-- _class: table -->

# SOV-8 · Centrale spørgsmål

| Spørgsmål · type/min. | Centralt spørgsmål | Krævet bevis |
| --- | --- | --- |
| 8.1 · K·2+ | Hvad er den målte PUE per datacenterlokation? | Datacenterrapportering, uafhængig måling |
| 8.2 · O·2+ | Er energiforbruget dokumenteret som vedvarende og er certificeringer uafhængigt verificeret? | Energicertifikater, uafhængig rapport |
| 8.3 · O·2+ | Er CO2-udledning og vandforbrug transparent og eksternt verificeret? | ESG-rapport, revisionserklæring, GRI |
| 8.4 · O·1+ | Er hardwarelevetids- og e-wastepolitik dokumenteret og kontrollerbar? | Politik, ISO 14001-certifikat |
| 8.5 · O·1+ | Er afhængighed af kritiske råstoffer vurderet? | Risikovurdering, leverandørapportering |
| 8.6 · O·1+ | Er leverandøren underlagt CSRD og er rapporteringer offentligt tilgængelige; hvis ikke, udarbejder den frivillige rapporteringer? | Årsrapport, CSRD- eller frivillig rapport |
---
<!-- _class: table table-editable -->

# SOV-8 · Fund og beviser

| Spørgsmål · type/min. | Faktisk fund | Kilde-ID | Bevis 0-4 | Impact / risiko |
| --- | --- | --- | --- | --- |
| 8.1 · Målt PUE per lokation (K·2+) | … | … | … | L/M/H · J/O/S |
| 8.2 · Verificeret vedvarende energi (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.3 · Verificeret CO2 og vand (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.4 · Levetids- og e-wastepolitik (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.5 · Råstofafhængighed vurderet (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.6 · CSRD eller frivillig rapportering (O·1+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-8 · Niveaubestemmelse

| Niveau | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Igennemsigtig | Ingen gennemsigtighed; dominerende ikke-EU-afhængighed af energi eller materialer | Ingen |
| 1 | Grundlæggende rapportering | Grundlæggende rapportering tilgængelig; stadig store strukturelle afhængigheder | 1 |
| 2 | Transparent med afhængigheder | Gennemsigtighed og kontraktkrav tilgængelige; materielle afhængigheder forbliver | 2 |
| 3 |  Indflydelse | Væsentlig EU-indflydelse på energikilde og cirkulær kæde | 3 |
| 4 | Bæredygtig | Fuldstændig bæredygtig, gennemsigtig og EU-forankret med strukturel overvågning | 4 |

---
<!-- _class: table table-editable -->

# SOV-8 · Målkonklusion

| Begrundelse for den centrale scorekort | Indhold |
| --- | --- |
| Faktuel situation og passende karakteristika fra niveaubanen | … |
| Laveste bevis på kritiske spørgsmål, med kilde-ID'er | … |
| Anvendte regler og eventuel begrænsning | … |
| Vigtigste årsag, risiko og fund-ID | … |
---

<!-- _class: section -->

#  Konklusion og erklæring om sikkerhed

---

<!-- _class: table table-editable -->

#  Legitimitet pr. datatype · Linje 0

| Datatype | Testramme |  Begrundelse og kilde-id | Resultat | Berørt SOV-mål |
| --- | --- | --- | --- | --- |
| Personlige data | AVG, inklusive overførsel og passende foranstaltninger | … | Begrundet / risiko | … |
| Ikke-personlige virksomhedsoplysninger | Data Act artikel 32 | … | Begrundet / risiko | … |
|  Offentlig eller klassificeret information | Gældende nationale og EU-regler | … | Begrundet / risiko | … |
| Regulerede sektordata | NIS2, DORA eller sektorspecifikke regler | … | Begrundet / risiko | … |

---

<!-- _class: table table-editable -->

# Eksponering for juridiske ordrer · Regel 4

| Part og juridisk orden | Kan regeringen magte? | Uafhængig juridisk proces? | Må der gives besked til kunden? | Konsekvens for bevis og niveau |
| --- | --- | --- | --- | --- |
| … | Ja / nej / usikker | Ja / nej / usikker | Ja / nej / usikker | … |
| … | … | … | … | … |
| … | … | … | … | … |

---
<!-- _class: table table-editable -->

# Regel 4 · Obligatorisk Konklusion

| Beting eller Konsekvens | Fastlæggelse og Kilde-ID |
| --- | --- |
| En myndighed kan pålægge adgang eller samarbejde | Ja / nej / usikker: … |
| Uafhængig retsgang mangler eller meddelelse til modtager er forbudt | Ja / nej / usikker: … |
| Hvis begge gælder: Spørgsmål 2.3, 2.5 og 2.6 tæller som bevisniveau 0 | Anvendt / n.v.t.: … |
| Hvis begge gælder: SOV-2 er maksimalt niveau 1 | Anvendt / n.v.t.: … |
| Ligger ejerskabsretten i den pågældende ret, så er SOV-1 også maksimalt niveau 1 | Anvendt / n.v.t.: … |
| Resterende eksponering | … |
---
<!-- _class: table table-editable -->

# Teknisk rute · Regel 5

| Betingelse | Resultat og kilde-ID |
| --- | --- |
| SOV-3 er mindst niveau 3: nøgler udelukkende hos kunden; leverandøren ser ingen læsbare data | … |
| Ingen administration eller supportadgang til læsbare data | … |
| SOV-5 er mindst niveau 3: opdateringer forudvalideret og kan tilbagestilles; build- og signekæde kendt | … |
| SOV-6 er mindst niveau 3: drift af kritisk software kontrollerbar | … |
| Tjenesten behøver ikke at behandle data i læselig form | Ja / nej |
| Alle betingelser opfyldt | Kun "ja" hvis alle foregående resultater er positive: … |
| Konsekvens | Kan understøtte Regel 0; ændrer ikke SOV-2 og det samlede SEAL-niveau. |
---
<!-- _class: table table-editable -->

# SAFARI-scorekort

| Kode | Vægt | Fastlagt 0-4 | Bevis 0-4 | Dom over valgt standard | Kilde målkonklusion |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | 15% | … | … | Vurderer / kløe / n.v.t. | … |
| SOV-2 | 10% | … | … | Vurderer / kløe / n.v.t. | … |
| SOV-3 | 10% | … | … | Vurderer / kløe / n.v.t. | … |
| SOV-4 | 15% | … | … | Vurderer / kløe / n.v.t. | … |
| SOV-5 | 20% | … | … | Vurderer / kløe / n.v.t. | … |
| SOV-6 | 15% | … | … | Vurderer / kløe / n.v.t. | … |
| SOV-7 | 10% | … | … | Vurderer / kløe / n.v.t. | … |
| SOV-8 | 5% | … | … | Vurderer / kløe / n.v.t. | … |
---
<!-- _class: table table-editable -->

# Samlet resultat

| Komponent | Resultat og begrundelse |
| --- | --- |
| SEAL-samlet niveau · laveste kerne mål | … |
| Vægtet ECSF-score · Σ (fastlagt niveau / 4 × vægt) | …% |
| Største kløer | … |
| Kritisk afhængigheder | … |
| Ønskede niveauer under anbefaling | … |
| Lovlighedsrisici | … |
| Intern løseligt | … |
| Leverandørens samarbejde kræves | … |
---

<!-- _class: table table-editable -->

# Vejledende CADA-stilling

| Part | Resultat og kilde-id |
| --- | --- |
| Relevans | Offentlig sektor / kritisk aktivitet / NIS2-sektor / n.a. |
| Mål CADA-niveau | 1 / 2 / 3 / 4 / n.a. |
| Vejledende opnåeligt niveau | 1 / 2 / 3 / 4 / ingen |
| Krav ikke opfyldt | … |
| Bevisbegrænsning | … |
| Obligatorisk formulering | Indikation baseret på forslaget; ingen bedømmelse af overensstemmelse. |

---

<!-- _class: table table-editable -->

# Sikkerhedsvurdering pr. mål

| Mål | Bevis kritiske spørgsmål | Legalitær risiko |  Type bedømmelse | Formulering og forbehold |
| --- | --- | --- | --- | --- |
| SOV-… | Leste niveau: … | Ja / nej | Ingen / begrænset / rimelig | … |
| SOV-… | … | … | … | … |
| SOV-… | … | … | … | … |

---
<!-- _class: table -->

# Formuleringshjælp til assurance

| Type | Betingelse | Standardformulering |
| --- | --- | --- |
| Ingen dom | En kritisk spørgsmål har bevisniveau 0 eller 1 | Baseret på de tilgængelige beviser er der ikke en dom over [mål] i forhold til [tjeneste]. |
| Begrænset sikkerhed | Alle kritiske spørgsmål mindst 2; ikke alle mindst 3 | Baseret på vores arbejde er der intet, der tyder på, at [påstand] ikke kunne være ukorrekt. Vi giver en begrænset grad af sikkerhed. |
| Rimelig sikkerhed | Alle kritiske spørgsmål mindst 3 | Baseret på vores arbejde er vi af opfattelse af, at [påstand]. Vi giver en rimelig grad af sikkerhed. |
---

<!-- _class: table table-editable -->

# Fund og anbefalinger

| ID | SOV | Find | Impact | Anbefaling | Ejer | Term |
| --- | --- | --- | --- | --- | --- | --- |
| F-01 | … | … | Høj / mellem / lav | … | … | … |
| F-02 | … | … | … | … | … | … |
| F-03 | … | … | … | … | … | … |

---

<!-- _class: table table-editable -->

# Kvalitetskontrol og hændelser efter referencedato

|  Kontrol | Resultat og anmelderreference |
| --- | --- |
|  Omfang og påstand etableret før udførelse | … |
| Alle kritiske spørgsmål er blevet dækket eller rapporteret som begrænsninger | … |
|  Kildereferencer kan spores, og bevisniveauer kan spores | … |
| Scoringsregler 0 til 5 er beviseligt blevet anvendt | … |
| Aritmetisk og tekstmæssig konsistens er blevet kontrolleret | … |
| Uafhængig gennemgang er afsluttet | … |
| Hændelser efter referencedatoen er blevet vurderet | … |
| Enestående meningsforskelle er blevet behandlet | … |

---
<!-- _class: table table-editable -->

# Fastlæggelse af påstand af organisation

| Fastlæggelse | Indhold |
| --- | --- |
| Navn og funktion ansvarlig part | … |
| Forklaring | Påstanden, omfanget og de valgte standarder er fuldt ud og sandfærdigt fastlagt. |
| Dato | … |
| Godkendelse | Ja / nej |
---
<!-- _class: table table-editable -->

# Uafhængig kvalitetsgennemgang

| Gennemgang | Indhold |
| --- | --- |
| Navn og funktion gennemgåer | … |
| Uafhængig af udførelse | Ja / nej |
| Gennemgangskonklusion og eventuelle åbne punkter | … |
| Dato | … |
| Godkendelse til underskrivelse | Ja / nej |
---
<!-- _class: sign-off -->

# Underskrivelse af assurance-vurdering
---
# Kilder og licens

- Metodik: SAFARI v0.9 (koncept), Brenno de Winter og Stichting LibreKAT.
- Status: frivillig metode. De minimale standarder er rådgivende; regler 0 til og med 5 er bindende for dem, der fastsætter SAFARI.
- Udgangspunkt: European Cloud Sovereignty Framework, suppleret med ISO 27001:2022 og en ISAE 3000-assurancestruktur.
- Fuldt ud metodik: https://pawprint.vigilis.online/LibreKAT/Safari
- Denne skabelonindhold er en bearbejdning af SAFARI og falder under CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
- Udfyld altid den aktuelle version, pejlingsdato, professionelle standarder og lokale juridiske krav.
