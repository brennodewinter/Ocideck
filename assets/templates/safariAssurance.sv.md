---
marp: true
ocideck_format: 1
theme: ocideck
paginate: true
title: SAFARI-bedömning av digital suveränitet
language: sv
standards: SAFARI@0.9, ECSF
---

<!-- _class: title -->

# SAFARI-bedömning av digital suveränitet

---
# Så här används detta arbetsark

- Definiera först omfattning, påstående, önskade nivåer och den avsedda graden av säkerhet.
- Fyll i varje frågeställning med fynd, en spårlösande källreferens och bevisnivå.
- Hantera saknat eller nekad bevis som en fynd med bevisnivå 0.
- Tillämpa de sex bedömningsreglerna innan du fastställer nivån för varje SOV-mål.
- Formulera assurancebedömningen först efter att kvalitetskontrollen och händelserna efter referensdatum har utvärderats.
---

<!-- _class: table table-editable -->

# Dokumenthantering och uppdragsteam

| Fält | Completion |
| --- | --- |
| Organisation | … |
| Service eller system | … |
| Leliver | … |
| Client | … |
| Ansvarig för reklamationen | … |
| Exekutiv revisor eller konsult | … |
| Oberoende granskare | … |
| Referensdatum och bedömningsperiod | … |
| Rapportera version och datum | … |
| TLP klassificering och distributionslista | … |

---
<!-- _class: table table-editable -->

# Objekt och omfattning

| Områdesdel | Fyllning |
| --- | --- |
| Bedömt applikationer, plattformar och infrastruktur | … |
| Direkta leverantörer | … |
| Relevanta underleverantörer och kedjeledare | … |
| Datatyper | Personuppgifter / företagsuppgifter / myndighetsuppgifter / kodade information |
| Juridiska bestämmelser per berörd part | … |
| Hanterings-, support-, bygg- och signeringsplatser | … |
| Explicita undantag med motivering | … |
| Versionsnormativ ram | SAFARI v0.9 (koncept; frivillig metodik) |
---
<!-- _class: table table-editable -->

# Organisationens påstående

| Del | Fyllning |
| --- | --- |
| Objekt | [Organisation] har bedömt suveränitetspositionen med avseende på [tjänst], levererad av [leverantör], |
| Tidsperiod | Bedömningen avser situationen per [datum] inom omfattningen som fastställts på [datum]. |
| Ramverk | Bedömningen har genomförts enligt SAFARI v0.9, en frivillig konceptmetodik kopplad till ISO 27001:2022 och de åtta målen för ECSF. |
| Utfall | Organisationen uppställer att den uppfyller det valda nivån [0-4] för [SOV-kod eller alla mål]. |
| Förbehåll | Resultatet är baserat på det tillgängliga beviset per referensdatum; förändringar kan påverka resultatet. |
| Ägare och formell fastställning | … |
---
<!-- _class: table table-editable -->

# Önskade nivåer och kärnmål

| Kod | Mål | Kärnmål | Rekommenderad minimum | Önskat | Motivering vid avvikelse |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | Strategisk | Ja | 2 | … | … |
| SOV-2 | Juridisk och rättslig | Ja | 2 | … | … |
| SOV-3 | Data och AI | Ja | 3 (2 endast låg känslighet och utan personuppgifter) | … | … |
| SOV-4 | Operativ | Ja | 3 (2 endast låg känslighet, ersättbart och utan personuppgifter) | … | … |
| SOV-5 | Kjede | Ja | 3 (2 endast låg känslighet och utan personuppgifter) | … | … |
| SOV-6 | Teknik | Ja | 3 (2 endast låg känslighet och utan personuppgifter) | … | … |
| SOV-7 | Säkerhet och efterlevnad | Ja | 2 | … | … |
| SOV-8 | Hållbarhet | Ja | 1 | … | … |
---

<!-- _class: table table-editable -->

# Aförsäkran

| Part | Val och belägg |
| --- | --- |
|  Kommandotyp | Rådgivning / begränsad säkerhet / rimlig säkerhet |
| Mål inom försäkran | … |
| Materialitet och riskorienterat urval | … |
| Aktiviteter per typ av bevis | Inspektion / observation / återutförande / bekräftelse / analys |
| Samplingsmetod och populationer | … |
| Experter utplacerade | Juridisk / teknisk / hållbarhet / övrigt: … |
| Oberoende och intressekonflikter | … |
| Begränsningar för åtkomst eller aktiviteter | … |

---
<!-- _class: table table-editable -->

# Formell assurance-godkännande

| Godkännandekriterium | Bedömning och källa | Utfall |
| --- | --- | --- |
| SAFARI är lämplig som kriterium för påståendet och den avsedda användaren | … | Ja / nej |
| Den ansvariga parten erkänner sitt ansvar för påståendet | … | Ja / nej |
| Rationellt mål, den avsedda användaren och den spridda kretsen är fastställd | … | Ja / nej |
| Oberoende, etik, expertis och nödvändiga experter är garanterade | … | Ja / nej |
| Uppdragsförhållanden och önskad säkerhetsnivå är överenskomna | … | Ja / nej |
| Tillräckligt lämpligt bevis förväntas vara tillgängligt | … | Ja / nej |
| Godkännandebeslut | Endast fortsättning om alla kriterier är "ja" | Acceptera / inte acceptera |
---

<!-- _class: table -->

#  Bevisnivåer

| Nivå |  Namn | Ansökan |
| --- | --- | --- |
| 0 | Inga bevis | Ingen bevisning eller bevis saknas eller vägras |
| 1 | Uttalande | Muntligt eller skriftligt uttalande utan ytterligare belägg |
| 2 | Dokumentation |  Avtal, policy, procedur eller rapport utan oberoende verifiering |
| 3 | Tekniskt bevis | Konfiguration, logg, test eller extern juridisk rådgivning som kunden har inhämtat |
| 4 | Oberoende bevis |  Samlas in eller verifieras av en oberoende testpart |

---

<!-- _class: table table-editable -->

# Centralt bevisregister

| Käll-ID | Dokument eller registrering | Ägare | Datum och version |  Ursprung | Integritet och lagringsplats |
| --- | --- | --- | --- | --- | --- |
| B-001 | … | … | … | Intern / leverantör / extern | … |
| B-002 | … | … | … | … | … |
| B-003 | … | … | … | … | … |
| B-004 | … | … | … | … | … |

---
<!-- _class: table -->

# Bindande bedömningsregler

| Regel | Konsekvens för bedömningen |
| --- | --- |
| 0 · Laglighet | En laglighetrisk gör att det berörda målet alltid är ett gap; rekommendera en juridisk granskning. |
| 1 · Kritiska frågor | Bevisnivå 0 på en kritisk fråga begränsar målet till högst nivå 1. |
| 2 · Bevis bär nivån | Bevis under det minsta av en fråga räknas som 0. Målbeviset är det lägsta beviset på kritiska frågor; nivå 2, 3 och 4 kräver minst samma bevisnivå. |
| 3 · Svagaste länk | SEAL-totalt är det lägsta fastställda nivån för kärnmålen. |
| 4 · Fungerande lagordning | Vid avdrivbar utomlandsåtkomst skyddar endast den fullständiga tekniska rutten; det förändrar inte SOV-2 och SEAL-totalt. En tjänst som måste bearbeta läsbar data har inte denna rutt. |
| 5 · Teknisk rutt | Vid avdrivbar utomlandsåtkomst skyddar endast den fullständiga tekniska rutten; det förändrar inte SOV-2 och SEAL-totalt. En tjänst som måste bearbeta läsbar data har inte denna rutt. |
---

<!-- _class: section -->

# SOV-1 · Strategisk suveränitet

---
<!-- _class: table -->

# SOV-1 · Frågor

| Fråga · typ/min. | Fråga | Krävt bevis |
| --- | --- | --- |
| 1.1 · K·2+ | Vem är de slutliga aktieägarna och under vilken rättslig ordning är de registrerade? | UBO-register, årsredovisning, aktieägarskapskatalog |
| 1.2 · K·2+ | Kan en moderföretag utanför EU tvinga fram en strategisk kursändring? | Gruppstrukturdiagram, stadgar, styrelsesätt |
| 1.3 · Change-of-control (K·2+) | Innehåller avtalet klausuler om förändring av kontroll? | Kontraktstext |
| 1.4 · Placering av teknik och IP (O·1+) | Är teknik och IP placerade i EU-företaget eller i ett utländskt moderföretag? | IP-registrering, licensavtal |
| 1.5 · Beroende på styrelsen (O·2+) | Diskuteras och fastställs beroendet explicit på styrelsenivå? | Styrelseprotokoll, riskregister |
| 1.6 · Exit vid ägandeförändring (O·2+) | Finns det en exit- eller kontinuitetsscenario för en ägandeförändring? | Kontinuitetsplan, exitstrategi |
---
<!-- _class: table table-editable -->

# SOV-1 · Fynd och bevis |
| Fråga · typ/min. | Faktisk fynd | Källa-ID | Bevis 0-4 | Inverkan / risk |
| --- | --- | --- | --- | --- |
| 1.1 · UBO:er och rättslig ordning (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.2 · Moder utanför EU kan tvinga fram kurs (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.3 · Change-of-control (K·2+) | … | … | … | L/M/H · J/O/S |
| 1.4 · Placering av teknik och IP (O·1+) | … | … | … | L/M/H · J/O/S |
| 1.5 · Beroende på styrelsen (O·2+) | … | … | … | L/M/H · J/O/S |
| 1.6 · Exit vid ägandeförändring (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-1 · Nivåbestämning

| Nivå | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Ingen insikt | Ingen insikt i ägande eller maktstruktur | Ingen |
| 1 | Insikt | Insikt tillgänglig, men ingen garanti vid ägarbyte | 1 |
| 2 |  Avtalsgaranti | Change-of-control och transparens är avtalade | 2 |
| 3 | kontroll | EU styrning är separat och verkställbar; inflytande utanför EU är starkt begränsat | 3 |
| 4 | Strategisk autonomi |  Hållbart europeiskt inbäddat; beroende vägs uttryckligen in i ett styrelsebeslut | 4 |

---
<!-- _class: table table-editable -->

# SOV-1 · Slutsatsedomen

| Underbyggande för centrala scorekort | Infyllning |
| --- | --- |
| Faktiskt läge och lämpligt kännetecken från nivåskalan | … |
| Lägsta bevis på kritiska frågor, med käll-ID:n | … |
| Tillämpade regler och eventuell begränsning | … |
| Viktigaste anledning, risk och fynd-ID | … |
---

<!-- _class: section -->

# SOV-2 · Juridisk suveränitet och jurisdiktion

---
<!-- _class: table -->

# SOV-2 · Kritiska granskningsfrågor

| Fråga · typ/min. | Granskningsfråga | Krävt bevis |
| --- | --- | --- |
| 2.1 · K·2+ | Vilket rätt gäller för avtalet och vilken domstol är behörig? | Avtalsutkast med rätts- och domstolsval |
| 2.2 · K·3+ | Kan en regering utanför EU kräva tillträde eller samarbete och finns oberoende rättssäkerhet? | Juridisk rådgivning, gruppstruktur och analys per rättssystem |
| 2.3 · K·2+ | Gäller en rapporteringsskyldighet vid ett myndighetsförfrågan om datainsikt? | Avtalsklausul, transparensrapport |
| 2.6 · K·2+ | Finns det rutiner för att bestrida utländska juridiska förfrågningar om data i avtalet? | Avtalsklausul, leverantörs policy |
| 2.7 · K·2+ | Är lagligheten av data underbyggd med tanke på alla relevanta rättssystem? | DPIA, överföringskontroll, Data Act-åtgärder, rubricerings- och sektorrättsliga regler |
---
<!-- _class: table -->

# SOV-2 · Stödjande granskningsfrågor

| Fråga · typ/min. | Granskningsfråga | Krävt bevis |
| --- | --- | --- |
| 2.4 · O·2+ | Finns det en källkod-eskrow och under vilka villkor är den tillgänglig? | Eskrowavtal, notarialt intyg |
| 2.5 · O·2+ | Kan avtalsrättigheter effektivt gäldas vid en EU-domstol? | Juridisk rådgivning, avtalsanalys |
---
<!-- _class: table table-editable -->

# SOV-2 · Fynd och bevis |

| Fråga · typ/min. | Faktisk fynd | Käll-ID | Bevis 0-4 | Inverkan / risk |
| --- | --- | --- | --- | --- |
| 2.1 · Rätt och behörig domstol (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.2 · Utländigt tvång och rättssäkerhet (K·3+) | … | … | … | L/M/H · J/O/S |
| 2.3 · Rapporteringsskyldighet (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.4 · Källkod-eskrow (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.5 · Gällande vid EU-domstol (O·2+) | … | … | … | L/M/H · J/O/S |
| 2.6 · Bestrid utländsk förfrågan (K·2+) | … | … | … | L/M/H · J/O/S |
| 2.7 · Lagligheten av data (K·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-2 · Nivåbestämning

| Nivå | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Ingen insikt | Tillämplig lag och jurisdiktion är oklar | Ingen |
| 1 | Medvetande | Juridisk analys utan avtalsgaranti | 1 |
| 2 | Kontraktsförankring |  Lagval, val av forum och rapporteringsskyldigheter fastställda; återstående exponering analyserades | 2 |
| 3 | Praktisk kontroll | Tvisteförfaranden och deposition har upprättats och bevisligen genomförbara | 3 |
| 4 | Effektiv verkställbarhet | Rättigheter är effektivt verkställbara och extraterritoriella risker utvärderas regelbundet | 4 |

---
<!-- _class: table table-editable -->

# SOV-2 · Slutsatsdomen |

| Underbyggande för centrala scorekort | Infyllning |
| --- | --- |
| Faktiskt läge och lämpligt kännetecken från nivåskalan | … |
| Lägsta bevis på kritiska frågor, med käll-ID:n | … |
| Tillämpning av regler 0 och 4 och eventuell begränsning | … |
| Viktigaste anledning, risk och fynd-ID | … |
---

<!-- _class: section -->

# SOV-3 · Data- och AI-suveränitet

---
<!-- _class: table -->

# SOV-3 · Testfrågor

| Fråga · typ/min. | Testfråga | Krävs bevis |
| --- | --- | --- |
| 3.1 · K·3+ | Vem ansvarar för krypteringsnycklarna: kund, leverantör eller tredje part? | Arkitektur, nyckelpolicy, BYOK- eller HYOK-konfiguration |
| 3.2 · K·3+ | Är det bevisbart vem, när och från vilken plats data har tillgängnats? | Loggar, revisionsspår, SIEM-rapportering |
| 3.3 · K·2+ | Fortsatt lagring och bearbetning, inklusive säkerhetskopior, telemetri och support, bevisbart i EU? | DPIA, arkitektur, underleverantörer, datacenterplatser |
| 3.4 · O·2+ | Är användning av data för AI-träning eller modellförbättring avtalsmässigt förbjuden? | Avtal, processavtal |
| 3.5 · O·2+ | Kan data bevisligen permanent raderas, inklusive säkerhetskopior och härledda dataset? | Lömskedigtcertifikat, procedur, avtal |
| 3.6 · O·2+ | Är supportåtkomst reglerad och loggas? | Supportpolicy, loggar, avtal |
---
<!-- _class: table table-editable -->

# SOV-3 · Fynd och bevis |

| Fråga · typ/min. | Faktisk fynd | Käll-ID | Bevis 0-4 | Inverkan / risk |
| --- | --- | --- | --- | --- |
| 3.1 · Hantering av krypteringsnycklar (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.2 · Återspårbar datatillgång (K·3+) | … | … | … | L/M/H · J/O/S |
| 3.3 · Lagring och bearbetning i EU (K·2+) | … | … | … | L/M/H · J/O/S |
| 3.4 · Ingen AI-träning med data (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.5 · Definitiv radering (O·2+) | … | … | … | L/M/H · J/O/S |
| 3.6 · Hanterad supportåtkomst (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-3 · Nivåbestämning

| Nivå | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Ingen kontroll | A-leverantören har faktisk åtkomst och nyckelkontroll | Ingen |
| 1 | EU lagring | EU lagring överenskommen; åtkomst eller nyckelkontroll är delad eller otydlig | 1 |
| 2 | Tekniskt förstärkt | Kunddriven nyckelhantering och åtkomstbegränsningar; leverantören kan fortfarande komma åt nycklar eller läsbar data | 2 |
| 3 | ASskärmad kontroll | Endast kunden hanterar nycklar; leverantören ser inga läsbara data; bearbetningen kvarstår inom EU | 3 |
| 4 | Full kontroll | Full kontroll över data, nycklar, AI-modeller och bearbetning | 4 |

---
<!-- _class: table table-editable -->

# SOV-3 · Slutsatsdomen |

| Underbyggande för centrala scorekort | Infyllning |
| --- | --- |
| Faktiskt läge och lämpligt kännetecken från nivåskalan | … |
| Lägsta bevis på kritiska frågor, med käll-ID:n | … |
| Tillämpning av regler 0 och 5 och eventuell begränsning | … |
| Viktigaste anledning, risk och fynd-ID | … |

Here's the translated Markdown slide blocks from Dutch to professional Swedish, preserving all markers and identifiers as requested:
---

<!-- _class: section -->

# SOV-4 · Operativ suveränitet

---
<!-- _class: table -->

# SOV-4 · Frågor

| Fråga · typ/min. | Fråga | Krävd bevis |
| --- | --- | --- |
| 4.1 · K·2+ | Dokumenterad och testad migrering? Är data och konfigurationer fullständigt exporterbara? | Migreringsdokumentation, exporttest, Data Akt-klausuler |
| 4.2 · K·2+ | Kan incidenthantering och daglig drift utföras fullt ut av EU-personal? | Personalöversikt, supportplats, SLA |
| 4.3 · O·2+ | Överförs exploateringkunskap och finns den inte enbart hos leverantören? | Utbildningsplan, kunskapsverifiering, dokumentation |
| 4.4 · O·2+ | Har organisationen fullständig teknisk dokumentation och runbooks? | Dokumentationsinventering, runbooks |
| 4.5 · O·1+ | Är kritiska underleverantörer kända och realistiskt ersättningsbara? | Underleverantörslista, alternativa analyser |
| 4.6 · O·2+ | Finns ett utfasningsscenario med realistisk övergångstid och kostnader? | Utfasningsstrategi, migrationsaffärsfall |
---
<!-- _class: table table-editable -->

# SOV-4 · Funn och bevis

| Fråga · typ/min. | Faktisk funn | Brå-ID | Bevis 0-4 | Inverkan / risk |
| --- | --- | --- | --- | --- |
| 4.1 · Testad migrering och export (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.2 · Drift utförs av EU-personal (K·2+) | … | … | … | L/M/H · J/O/S |
| 4.3 · Överförbar exploateringkunskap (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.4 · Dokumentation och runbooks (O·2+) | … | … | … | L/M/H · J/O/S |
| 4.5 · Ersättningsbara underleverantörer (O·1+) | … | … | … | L/M/H · J/O/S |
| 4.6 · Realistisk utfasning (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-4 · Nivåbestämning

| Nivå | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Aberoende | Driften är helt beroende av leverantör eller personal utanför EU | Ingen |
| 1 | Impressionable | EU drift på papper; kritiska handlingar utanför EU kan påverkas | 1 |
| 2 | Exploaterbar med beroenden | EU utnyttjande möjligt; viktiga beroenden eller inlåsning kvarstår | 2 |
| 3 | Meningsfull kontroll | EU aktörer kontrollerar operationen; supportåtkomst är EU-bunden, loggad och tillåten; exit är realistiskt | 3 |
| 4 | In kontroll | Fullständig EU-drift utan kritiska beroenden utanför EU | 4 |

---
<!-- _class: table table-editable -->

# SOV-4 · Målsättning

| Underlag för centrala scorekort | Genomförande |
| --- | --- |
| Faktisk situation och lämplig egenskap från nivåskalan | … |
| Lägsta bevis på kritiska frågor, med brå-ID:n | … |
| Användning av regel 5 och eventuell begränsning | … |
| Viktigaste anledningen, risk och funn-ID | … |
---

<!-- _class: section -->

# SOV-5 · Kedjesuveränitet

---
<!-- _class: table -->

# SOV-5 · Frågor

| Fråga · typ/min. | Fråga | Krävd bevis |
| --- | --- | --- |
| 5.1 · K·2+ | Finns en aktuell SBOM tillgänglig för mjukvaran i tjänsten? | SBOM, leverantörsdeklaration |
| 5.2 · O·1+ | Kända ursprung för hårdvara och firmware och icke-EU-beroenden? | Hårdvaruinventering, firmwareöversikt, deklaration |
| 5.3 · K·2+ | Kan uppdateringar genomföras fasvis, valideras och återdras före bred utrullning? | Uppdateringspolicy, konfiguration, testrapport |
| 5.4 · O·1+ | Kända plats och jurisdiktion för build- och signinfrastruktur? | Teknisk dokumentation, arkitekturschema |
| 5.5 · K·2+ | Är alla underleverantörer kända och är en ändringsmeddelande reglerat i kontrakt? | Underleverantörslista, kontraktsbestämmelser |
| 5.6 · O·2+ | Är revisionsrättigheter för underleverantörer reglerade i kontrakt? | Kontraktsbestämmelser, revisionsrapporter |
---
<!-- _class: table table-editable -->

# SOV-5 · Funn och bevis

| Fråga · typ/min. | Faktisk funn | Brå-ID | Bevis 0-4 | Inverkan / risk |
| --- | --- | --- | --- | --- |
| 5.1 · Aktuell SBOM (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.2 · Ursprung hårdvara och firmware (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.3 · Uppdateringar valideras och återdras (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.4 · Build- och signinfrastruktur (O·1+) | … | … | … | L/M/H · J/O/S |
| 5.5 · Underleverantörer och ändringsmeddelande (K·2+) | … | … | … | L/M/H · J/O/S |
| 5.6 · Revisionsrättigheter underleverantörer (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-5 · Nivåbestämning

| Nivå | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Inget inflytande | Kritisk kedja helt utanför EU:s inflytande | Ingen |
| 1 | Ogenomskinlig | EU-lagen gäller formellt, men kedjan är ogenomskinlig | 1 |
| 2 | Insikt med beroenden | Chain insiktsfull; materiella beroenden utanför EU kvarstår | 2 |
| 3 | Meningsfull påverkan | Kritiska länkar är diversifierade; uppdateringar är verifierbara; bygga och signera kedjan är känd | 3 |
| 4 | Transparent och under kontroll | Full transparens utan kritiska beroenden utanför EU | 4 |

---
<!-- _class: table table-editable -->

# SOV-5 · Målsättning

| Underlag för centrala scorekort | Genomförande |
| --- | --- |
| Faktisk situation och lämplig egenskap från nivåskalan | … |
| Lägsta bevis på kritiska frågor, med brå-ID:n | … |
| Användning av regel 5 och eventuell begränsning | … |
| Viktigaste anledningen, risk och funn-ID | … |
---

<!-- _class: section -->

# SOV-6 · Teknisk suveränitet

---
<!-- _class: table -->

# SOV-6 · Frågor

| Fråga · typ/min. | Fråga | Krävd bevis |
| --- | --- | --- |
| 6.1 · K·2+ | Är alla API:er baserade på öppna och publicerat dokumenterade standarder? | API-dokumentation, standardregister |
| 6.2 · K·2+ | Kan all data exporteras utan förlust av kärnfunktionalitet? | Exporttest, teknisk dokumentation |
| 6.3 · O·2+ | Vilka programvarulicenser och begränsningar för anpassning eller återanvändning gäller? | Licenstext, juridisk analys |
| 6.4 · O·2+ | Är en källkodsuppgiftsrätt eller escrow avtalat? | Escrowavtal, revisionsrapport |
| 6.5 · O·1+ | Är hela stacken dokumenterad, inklusive stängda komponenter och alternativ? | Arkitektur, komponentregister |
| 6.6 · O·2+ | Är migrering till ett alternativ realistisk och testad? | Migreringstest, utfasningsstrategi, alternativa analyser |
---
<!-- _class: table table-editable -->

# SOV-6 · Funn och bevis

| Fråga · typ/min. | Faktisk funn | Brå-ID | Bevis 0-4 | Inverkan / risk |
| --- | --- | --- | --- | --- |
| 6.1 · Öppna och dokumenterade API:er (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.2 · Förlustfri öppen dataexport (K·2+) | … | … | … | L/M/H · J/O/S |
| 6.3 · Licenser och återanvändning (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.4 · Källkodsuppgift eller escrow (O·2+) | … | … | … | L/M/H · J/O/S |
| 6.5 · Dokumenterad stack (O·1+) | … | … | … | L/M/H · J/O/S |
| 6.6 · Testad migrering till alternativ (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-6 · Nivåbestämning

| Nivå | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Stängd | Stängt ekosystem; migration är praktiskt taget omöjligt | Ingen |
| 1 | Lås in | Vissa länkbarhet; inlåsning förblir dominerande | 1 |
| 2 | Migrerbar | Interoperabilitet och export är ordnade; revisions- och depositionsalternativ finns | 2 |
| 3 | Betydande autonom |  Utbytbarhet är testad och kritisk programvara kan verifieras via revision eller öppen källkod | 3 |
| 4 | In kontroll | Full kontroll över integration och standarder utan kritiska slutna beroenden | 4 |

---
<!-- _class: table table-editable -->

# SOV-6 · Målbedömning

| Underlag för centrala scorecard | Ansats |
| --- | --- |
| Faktisk situation och lämpligt kännetecken från prestationsskalan | … |
| Lägsta bevis på kritiska frågor, med käll-ID:n | … |
| Tillämpning av regel 5 och eventuell begränsning | … |
| Viktigaste anledning, risk och fynd-ID | … |
---

<!-- _class: section -->

# SOV-7 · Säkerhet och efterlevnadssuveränitet

---
<!-- _class: table -->

# SOV-7 · Beslutande frågor

| Fråga · typ/min. | Beslutande fråga | Krävt bevis |
| --- | --- | --- |
| 7.1 · K·3+ | Är leverantören certifierad enligt en erkänd standard och omfattas granskningen av EU:s tillsyn? | Certifikat, granskningsrapport, omfattning |
| 7.2 · K·2+ | Är SOC i EU baserad och operativ under EU:s jurisdiktion? | SOC-plats, avtal, SLA |
| 7.3 · O·3+ | Är efterlevnad av NIS2, DORA, GDPR och CRA bevisats och oberoende verifierat? | Efterlevnadsuppgift, tillsynsmyndighet, granskning |
| 7.4 · K·2+ | Vem utför sårbarhetshantering och patchning och kan detta oberoende i EU? | Patchpolicy, SLA, teknisk dokumentation |
| 7.5 · K·2+ | Är revisionsrättigheter praktiskt genomförbara, inklusive system- och logginlogering? | Avtalsmässig revisionsrätt, genomförd granskningsrapport |
| 7.6 · O·2+ | Är incidentrapporteringsprocessen för dataintrång och incidenter GDPR-kompatibel och bevisats etablerad? | Incidentplan, entreprenörsavtal, rapporteringsregister |
---
<!-- _class: table table-editable -->

# SOV-7 · Fynd och bevis

| Fråga · typ/min. | Faktisk fynd | Käll-ID | Bevis 0-4 | Inverkan / risk |
| --- | --- | --- | --- | --- |
| 7.1 · Certifiering under EU-tillsyn (K·3+) | … | … | … | L/M/H · J/O/S |
| 7.2 · SOC i EU under EU-lagstiftning (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.3 · Oberoende verifierad efterlevnad (O·3+) | … | … | … | L/M/H · J/O/S |
| 7.4 · EU-sårbarhetshantering (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.5 · Praktiskt genomförbara revisionsrättigheter (K·2+) | … | … | … | L/M/H · J/O/S |
| 7.6 · GDPR-kompatibel rapporteringsprocess (O·2+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-7 · Nivåbestämning

| Nivå | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Aberoende |  Säkerhetsverksamhet helt under kontroll utanför EU | Ingen |
| 1 | Impressionable kompatibel | Formell efterlevnad; genomförande utanför EU förblir föremål för påverkan | 1 |
| 2 | Kontraktsmässigt garanterad | EU jurisdiktion, revision och rapporteringsskyldigheter är avtalsreglerade | 2 |
| 3 | EU verksamhet | EU säkerhetsoperationer är effektiva och oberoende granskningar är möjliga | 3 |
| 4 | In kontroll | Full kontroll över övervakning, incidentrespons, patchning och efterlevnad | 4 |

---
<!-- _class: table table-editable -->

# SOV-7 · Målbedömning

| Underlag för centrala scorecard | Ansats |
| --- | --- |
| Faktisk situation och lämpligt kännetecken från prestationsskalan | … |
| Lägsta bevis på kritiska frågor, med käll-ID:n | … |
| Tillämpade regler och eventuell begränsning | … |
| Viktigaste anledning, risk och fynd-ID | … |
---

<!-- _class: section -->

# SOV-8 · Suveränitet för hållbarhet

---
<!-- _class: table -->

# SOV-8 · Beslutande frågor

| Fråga · typ/min. | Beslutande fråga | Krävt bevis |
| --- | --- | --- |
| 8.1 · K·2+ | Vad är den mätta PUE per datacenterplats? | Datacenterrapportering, oberoende mätning |
| 8.2 · O·2+ | Är energi bevisat förnybar och är certifikat oberoende verifierat? | Energicertifikat, oberoende rapport |
| 8.3 · O·2+ | Är CO2-utsläpp och vattenförbrukning transparent och externt verifierat? | ESG-rapport, revisorutlåtande, GRI |
| 8.4 · O·1+ | Är hårdvaruleveranscykel- och e-avfallspolitik dokumenterad och kontrollerbar? | Policy, ISO 14001-certifikat |
| 8.5 · O·1+ | Är beroende av kritiska råvaror bedömt? | Riskanalys, leverantörsdeklaration |
| 8.6 · O·1+ | Är leverantören under CSRD och är rapporteringar offentliga; om inte, rapporterar den frivilligt? | Årsredovisning, CSRD eller frivillig rapportering |
---
<!-- _class: table table-editable -->

# SOV-8 · Fynd och bevis

| Fråga · typ/min. | Faktisk fynd | Käll-ID | Bevis 0-4 | Inverkan / risk |
| --- | --- | --- | --- | --- |
| 8.1 · Mätt PUE per plats (K·2+) | … | … | … | L/M/H · J/O/S |
| 8.2 · Oberoende verifierad förnybar energi (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.3 · Extern verifierat CO2 och vatten (O·2+) | … | … | … | L/M/H · J/O/S |
| 8.4 · Hårdvaruleverans- och e-avfallspolitik (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.5 · Bedömt kritiska råvaror (O·1+) | … | … | … | L/M/H · J/O/S |
| 8.6 · CSRD eller frivillig rapportering (O·1+) | … | … | … | L/M/H · J/O/S |
---

<!-- _class: table table-editable -->

# SOV-8 · Nivåbestämning

| Nivå | Label | Attribut | Min. bevis |
| --- | --- | --- | --- |
| 0 | Ogenomskinlig | Ingen transparens; dominerande icke-EU-beroende av energi eller material | Ingen |
| 1 | Grundläggande rapportering | Grundläggande rapportering tillgänglig; stora strukturella beroenden kvarstår | 1 |
| 2 | Transparent med beroenden | Transparens och kontraktskrav tillgängliga; materiella beroenden kvarstår | 2 |
| 3 | Inflytande | Betydande EU-inflytande på energikälla och cirkulär kedja | 3 |
| 4 | Hållbar | Helt hållbar, transparent och EU-förankrad med strukturövervakning | 4 |

---
<!-- _class: table table-editable -->

# SOV-8 · Målbedömning

| Underlag för centrala scorecard | Ansats |
| --- | --- |
| Faktisk situation och lämpligt kännetecken från prestationsskalan | … |
| Lägsta bevis på kritiska frågor, med käll-ID:n | … |
| Tillämpade regler och eventuell begränsning | … |
| Viktigaste anledning, risk och fynd-ID | … |
---

<!-- _class: section -->

#  Slutsats och bekräftelseutlåtande

---

<!-- _class: table table-editable -->

#  Legitimitet per datatyp · Rad 0

| Datatyp | Testramverk | Bekräftelse och käll-ID | Utfall | Påverkat SOV-mål |
| --- | --- | --- | --- | --- |
| Personliga data | AVG, inklusive överföring och lämpliga åtgärder | … |  Underbyggd / risk | … |
| Icke-personlig företagsinformation | Datalagen artikel 32 | … |  Underbyggd / risk | … |
|  Statlig eller sekretessbelagd information | Gällande nationella och EU-regler | … |  Underbyggd / risk | … |
| Reglade sektordata | NIS2, DORA eller sektorspecifika regler | … | Bestyrkt / risk | … |

---

<!-- _class: table table-editable -->

# Exponering för juridiska order · Regel 4

| Parti och rättsordning | Kan regeringen tvinga? | Oberoende juridisk process? | Får meddelande göras till kunden? | Konsekvens för bevis och nivå |
| --- | --- | --- | --- | --- |
| … | Ja / nej / osäker | Ja / nej / osäkert | Ja / nej / osäkert | … |
| … | … | … | … | … |
| … | … | … | … | … |

---
<!-- _class: table table-editable -->

# Regel 4 · Obligatorisk Utfall

| Villkor eller Konsekvens | Fastställande och Käll-ID |
| --- | --- |
| En myndighet kan tvinga till åtkomst eller samarbete | Ja / nej / osäker: … |
| Oberoende rättslig prövning saknas eller meddelande till avnämaren är förbjudet | Ja / nej / osäker: … |
| Om båda gäller: frågor 2.3, 2.5 och 2.6 räknas som bevisnivå 0 | Tillämpat / ej tillämpat: … |
| Om båda gäller: SOV-2 är maximal nivå 1 | Tillämpat / ej tillämpat: … |
| Finns förtroendet i den rättsliga ordningen, då är även SOV-1 maximal nivå 1 | Tillämpat / ej tillämpat: … |
| Övrig Exponering | … |
---
<!-- _class: table table-editable -->

# Teknisk väg · Regel 5

| Villkor | Utfall och källa-ID |
| --- | --- |
| SOV-3 är minst nivå 3: nycklar enbart hos kund; leverantör ser ingen läsbar data | … |
| Ingen administration eller supportåtkomst till läsbar data | … |
| SOV-5 är minst nivå 3: uppdateringar validerade och återvändbara; build- och signerkedja känd | … |
| SOV-6 är minst nivå 3: drift av kritisk programvara kontrollerbar | … |
| Tjänsten behöver inte bearbeta data i läsbart format | Ja / nej |
| Alla villkor uppfyllda | Endast "ja" om alla föregående resultat är positiva: … |
| Utfall | Kan stödja Regel 0; ändrar inte SOV-2 och det totala SEAL-nivån |
---
<!-- _class: table table-editable -->

# SAFARI-Scorekort

| Kod | Vikt | Fastställt 0-4 | Bevis 0-4 | Bedömning mot vald norm | Källmålsresultat |
| --- | --- | --- | --- | --- | --- |
| SOV-1 | 15% | … | … | Möjligt / lucka / ej tillämpligt | … |
| SOV-2 | 10% | … | … | Möjligt / lucka / ej tillämpligt | … |
| SOV-3 | 10% | … | … | Möjligt / lucka / ej tillämpligt | … |
| SOV-4 | 15% | … | … | Möjligt / lucka / ej tillämpligt | … |
| SOV-5 | 20% | … | … | Möjligt / lucka / ej tillämpligt | … |
| SOV-6 | 15% | … | … | Möjligt / lucka / ej tillämpligt | … |
| SOV-7 | 10% | … | … | Möjligt / lucka / ej tillämpligt | … |
| SOV-8 | 5% | … | … | Möjligt / lucka / ej tillämpligt | … |
---
<!-- _class: table table-editable -->

# Total Utfall

| Del | Utfall och motivering |
| --- | --- |
| SEAL-totalnivå · lägsta kärnobjekt | … |
| Viktad ECSF-poäng · Σ (fastställt nivå / 4 × vikt) | …% |
| Största luckor | … |
| Kritisk beroende | … |
| Önskade nivåer under rekommendationen | … |
| Lagringskonsekvensrisker | … |
| Intern löslighet | … |
| Leverantörs samarbete krävs | … |
---

<!-- _class: table table-editable -->

# Indikativ CADA-position

| Part | Resultat och käll-ID |
| --- | --- |
| Relevans | Offentlig sektor / kritisk aktivitet / NIS2-sektor / n.a. |
| Mål CADA-nivå | 1 / 2 / 3 / 4 / n.a. |
| Indikativ uppnåbar nivå | 1 / 2 / 3 / 4 / ingen |
| Krav inte uppfyllda | … |
| Bevisbegränsning | … |
| Obligatorisk formulering | Indikation baserad på förslaget; ingen bedömning av överensstämmelse. |

---

<!-- _class: table table-editable -->

# Assurancebedömning per mål

| Mål | Prova kritiska frågor | Legalitär risk |  Typ av bedömning | Formulering och varningar |
| --- | --- | --- | --- | --- |
| SOV-… | Lästa nivå: … | Ja / nej | Ingen / begränsad / rimlig | … |
| SOV-… | … | … | … | … |
| SOV-… | … | … | … | … |

---
<!-- _class: table -->

# Formuleringshjälp Assurance

| Typ | Villkor | Standardformulering |
| --- | --- | --- |
| Inga bedömningar | En kritisk fråga har bevisnivå 0 eller 1 | Baserat på den tillgängliga bevisningen är ingen bedömning möjlig över [mål] med avseende på [tjänst]. |
| Begränsad säkerhet | Alla kritiska frågor minst 2; inte alla minst 3 | Baserat på våra aktiviteter har vi inget som tyder på att [påstående] inte skulle vara sant. Vi ger en begränsad grad av säkerhet. |
| Rimlig säkerhet | Alla kritiska frågor minst 3 | Baserat på våra aktiviteter anser vi att [påstående]. Vi ger en rimlig grad av säkerhet. |
---

<!-- _class: table table-editable -->

# Fynd och rekommendationer

| ID | SOV | Find | Impact | Rekommendation | Ägare | Term |
| --- | --- | --- | --- | --- | --- | --- |
| F-01 | … | … | Hög / mellan / låg | … | … | … |
| F-02 | … | … | … | … | … | … |
| F-03 | … | … | … | … | … | … |

---

<!-- _class: table table-editable -->

# Kvalitetskontroll och händelser efter referensdatum

| Kontroll | Resultat och granskare referens |
| --- | --- |
|  Omfattning och påstående fastställd före exekvering | … |
| Alla kritiska frågor har täckts eller rapporterats som begränsningar | … |
| Källreferenser är spårbara och bevisnivåer är spårbara | … |
| Poängreglerna 0 till 5 har bevisligen tillämpats | … |
| Aritmetisk och textmässig överensstämmelse har kontrollerats | … |
| Oberoende granskning har slutförts | … |
| Händelser efter referensdatumet har utvärderats | … |
| Enastående meningsskiljaktigheter har behandlats | … |

---
<!-- _class: table table-editable -->

# Fastställande av påstående av organisation

| Fastställande | Fyllning |
| --- | --- |
| Namn och funktion ansvarig part | … |
| Förklaring | Påståendet, omfattningen och de valda normerna är fullständigt och ärligt fastställda. |
| Datum | … |
| Godkännande | Ja / nej |
---
<!-- _class: table table-editable -->

# Oberoende kvalitetsgranskning

| Granskning | Fyllning |
| --- | --- |
| Namn och funktion granskare | … |
| Oberoende av utförande | Ja / nej |
| Granskningsresultat och eventuella öppna punkter | … |
| Datum | … |
| Godkännande för signering | Ja / nej |
---
<!-- _class: sign-off -->

# Underteckning Assurance-bedömning
---
# Källor och licens

- Metod: SAFARI v0.9 (koncept), Brenno de Winter och Stichting LibreKAT.
- Status: frivillig metod. De minsta normerna är rekommendationer; regler 0 till och med 5 är bindande för den som ställer SAFARI tillgänglig.
- Utgångspunkt: European Cloud Sovereignty Framework, kompletterat med ISO 27001:2022 och en ISAE 3000-assuransstruktur.
- Fullständig metod: https://pawprint.vigilis.online/LibreKAT/Safari
- Denna mallinnehåll är en bearbetning av SAFARI och faller under CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/
- Fyll alltid in den aktuella versionen, peildatum, professionella standarder och lokala lagkrav.
