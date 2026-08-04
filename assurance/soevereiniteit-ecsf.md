# Soevereiniteit — OciDeck langs het ECSF

> **Status:** zelfpositionering · opgesteld 2026-08-04 · Stichting LibreKAT
>
> Geen conformiteitsclaim en geen assurance-oordeel. Zie [`README.md`](README.md).
> Dit is een **consultancy-niveau zelfpositionering** in de zin van de ECSF
> Assurance Method: een gestructureerd beeld van waar OciDeck staat, geen
> reproduceerbaar oordeel met bewijsniveaus per vraag. Waar hieronder een niveau
> staat, is dat een eigen inschatting getoetst aan de niveaudefinities van het
> raamwerk, geen vastgestelde score.

## Waarom dit document bestaat

Soevereiniteit is geen schakelaar. Bij het afwegen van distributiekanalen (#1227)
werd "Snap botst met soevereiniteit" als een enkel, zwart-wit oordeel opgeschreven
— en dat is te grof. Het **European Cloud Sovereignty Framework (ECSF)** — acht
doelen, elk op een schaal van vijf niveaus, gebaseerd op het boek *November* —
maakt zichtbaar dat soevereiniteit meerdere assen heeft die onafhankelijk hoog of
laag kunnen staan. Een kanaal kan op de ene as zwak zijn en op de andere geen
verschil maken. Dit document zet OciDeck langs die acht assen, zodat een
kanaalkeuze op de juiste as gewogen wordt in plaats van op een gevoel.

## De mapping-kanttekening (eerst, want ze draagt de rest)

Het ECSF is gebouwd om de positie van een **afnemende organisatie ten opzichte
van een cloud-leverancier** te beoordelen: wie heeft feitelijke zeggenschap over
een afgenomen dienst. OciDeck is geen clouddienst maar een **lokaal-eerst
desktopprogramma zonder backend, account of telemetrie**. De vertaling is dus:

- De **afnemende organisatie** is de gebruiker zelf.
- De **dienst** is OciDeck op de eigen machine.
- De **leveranciers** zijn niet één cloudpartij, maar de *afhankelijkheden* van
  het product: de toolchain (Flutter/Dart), de pakketgraaf, en — het onderwerp
  van #1227 — de **distributiekanalen**.

Het gevolg is structureel: voor een lokaal-eerst product staan de meeste
SOV-doelen **hoog, en niet door inspanning maar door vorm**. Er is geen
leverancier in het kritieke pad die data vasthoudt, dus een hele klasse aan
jurisdictie- en datacontrolerisico's is simpelweg afwezig. De zwakke plekken
zitten niet in de kern maar aan de randen: de toolchain en de kanalen.

## OciDeck langs de acht doelen

| Doel | Min.norm | Inschatting kern | Waarom |
|---|---|---|---|
| **SOV-1** Strategisch | 2 | **4** | EUPL-opensource onder een Nederlandse stichting, **én een open bestandsformaat**. Geen externe eigenaar kan de koers afdwingen; een fork van de code én de vrije voortzetting van de decks (open formaat) zijn de ultieme exit. |
| **SOV-2** Juridisch/rechtsmacht | 2 | **4** | Niet alleen buiten bereik van CLOUD Act/FISA (geen leverancier houdt data), maar breder: **open code (EUPL) en open formaat** betekenen dat geen enkele licentiegever of jurisdictie voorwaarden kan opleggen. De rechtsmacht over de data ligt bij de gebruiker, op zijn machine. |
| **SOV-3** Data & AI | 3 | **3–4** | Data zijn lokale bestanden in een open formaat; sleutels in de OS-sleutelbos; geen telemetrie. AI staat standaard uit én is **wisselbaar** — de gebruiker kiest het endpoint (of geen). Volledige sleutel- en dataregie. |
| **SOV-4** Operationeel | 2 | **4** | Werkt volledig offline; geen dienst die kan uitvallen; bouwbaar uit de bron. Geen operationele afhankelijkheid van enige leverancier. *Meerdere distributieroutes versterken dit — zie onder.* |
| **SOV-5** Keten | 2 | **3** | Zie de verdieping hieronder. Transparante keten (SBOM, ondertekende reproduceerbare updates, eigen build-infra) is 3-niveau; de enige rest is de **niet-EU-oorsprong van een open, forkbare toolchain** — een reële maar niet-intrekbare afhankelijkheid, niet de lock-in die het raamwerk vreest. |
| **SOV-6** Technologisch | 2 | **4** | Markdown-basis = open standaard, volledig exporteerbaar, opensource, geen lock-in — en **meerdere platformen worden ondersteund** (macOS/Windows/Linux/web), wat de vervangbaarheid en onafhankelijkheid vergroot. Rand: Flutter/Dart als ecosysteem (open, forkbaar). |
| **SOV-7** Beveiliging/compliance | 2 | **2, met elementen van 3** | Zie de verdieping. Zelfgetoetst tegen ASVS/CRA/OWASP, met **gedeeltelijke externe review maar nog geen formele, onafhankelijke verificatie** — en dat laatste is per raamwerk bepalend voor niveau 3–4. |
| **SOV-8** Duurzaamheid | 1 | **grotendeels n.v.t.** | Zie de verdieping. De schaal veronderstelt een datacenter; een lokaal product heeft geen cloud-energievoetafdruk. Een formele SOV-8-score is voor dit producttype niet zinvol. |

Twee dingen die deze tabel niet doet. Ze vinkt niets af — de niveaus zijn
inschattingen, getoetst aan de niveaudefinities maar zonder de bewijsverzameling
die een formeel oordeel eist. En ze verbergt de zwakke assen niet: de echte
begrenzers zijn de **niet-EU-oorsprong van de toolchain (SOV-5/6)** en het
**ontbreken van formele externe verificatie (SOV-7)**.

## Verdieping SOV-5 — Ketensoevereiniteit, getoetst aan de definitie

**De definitie.** SOV-5 vraagt hoe afhankelijk we zijn van de internationale
technologie- en toeleveringsketen. De niveauschaal: 0 geen invloed · 1
ondoorzichtig · 2 inzicht mét materiële niet-EU-afhankelijkheden · 3 betekenisvolle
invloed en diversificatie van kritieke schakels · 4 volledige transparantie en
**geen kritieke niet-EU-afhankelijkheden**. De kernvragen gaan over SBOM,
hardware/firmware-herkomst, updatevalidatie, build/signing-infrastructuur en
subleveranciers.

**Wat OciDeck feitelijk heeft.**
- *SBOM (vraag 5.1):* CycloneDX 1.6 + SPDX 2.3 over alle componenten, met een
  verouderingspoort. Technisch bewijs — 3-niveau.
- *Updatevalidatie en terugrol (5.3):* ondertekende releases (minisign),
  `SHA256SUMS`, content-reproduceerbare webbundel, en de gebruiker beheert de
  update zelf (herbouwen/opnieuw downloaden) — geen gedwongen auto-update.
- *Build/signing-locatie (5.4):* de forge is zelf-gehost; de macOS-runner is van
  de maintainer; alleen de Windows-build reist via een GitHub-spiegel (het enige
  niet-EU-ketenelement in de eigen infra).
- *Subleveranciers (5.5):* geen — er is geen clouddienst met subverwerkers. De
  "keten" is de pakketgraaf, niet een serviceketen.
- *Hardware/firmware (5.2):* buiten scope; OciDeck levert geen hardware, het
  draait op de machine die de gebruiker al heeft.

**De kern van de vraag: de toolchain.** Flutter en Dart komen van Google, uit de
VS — dus niet-EU van oorsprong en bestuur. Maar beide zijn **BSD-3-Clause open
source**, publiek ontwikkeld, en "geen enkele partij heeft unilaterale controle
over de code"; er bestaat zelfs een community-fork (**Flock**, "Flutter+", ook
BSD-3) die aantoont dat forken realistisch is. Dart compileert zelfstandig naar
ARM/x64/RISC-V.

Dit dwingt een onderscheid af dat het worst-case-principe van het raamwerk
impliceert maar dat "2-3 zwak" plat sloeg: **intrekkingsrisico versus
overstapkosten.**
- *Intrekkingsrisico — laag.* Geen leverancier kan OciDeck afsluiten van de
  toolchain. Een BSD-licentie is onherroepelijk; de bron staat publiek; een fork
  (Flock) bestaat al. Dit is precies het soort afhankelijkheid dat de ECSF *niet*
  als een kritieke lock-in behandelt, want er is geen partij die zeggenschap kan
  uitoefenen.
- *Overstapkosten — hoog.* OciDeck ís een Dart-codebase. Overstappen naar een
  andere taal is een herschrijving, geen migratie. Dat is een reële technologische
  afhankelijkheid — maar een van *inspanning*, niet van *toestemming*.

**Toetsing tegen de niveaus.** Niveau 4 eist "geen kritieke niet-EU-
afhankelijkheden". De toolchain is niet-EU van oorsprong, dus strikt gelezen haalt
OciDeck de letter van niveau 4 niet. Maar niveau 2 ("inzicht mét materiële
afhankelijkheden") onderschat het: de keten is transparant (SBOM), de updates zijn
beheerst en ondertekend, de build-infra is grotendeels eigen, en de kritieke
afhankelijkheid is *niet intrekbaar*. Dat is de kern van niveau 3 —
betekenisvolle invloed op en beheersing van de eigen keten. **Inschatting: niveau
3**, met de eerlijke kanttekening dat de sprong naar 4 niet aan inspanning ligt
maar aan de niet-EU-*oorsprong* van een open, forkbare toolchain — en dat is een
andere, mildere soort afhankelijkheid dan het raamwerk in het zwaarste geval voor
ogen heeft.

## Verdieping SOV-7 — Beveiliging/compliance, getoetst aan de criteria

**De definitie.** Niveauschaal: 0 afhankelijk (security-ops niet-EU) · 1
beïnvloedbaar compliant · 2 EU-jurisdictie contractueel, audit-/meldplichten
geregeld · 3 EU-gebaseerde security-ops effectief, **onafhankelijke audits
mogelijk** · 4 volledige controle **met onafhankelijke verificatie**. De kritieke
vragen 7.1 (certificering onder EU-toezicht) en 7.3 (NIS2/DORA/AVG/CRA extern
geverifieerd) vereisen minimaal bewijsniveau 3 — technisch of onafhankelijk
bewijs, geen verklaring.

**Wat OciDeck heeft.** Er is geen externe SOC nodig — een lokaal programma
monitort niets op afstand. Patch- en kwetsbaarhedenbeheer voert het project zelf
uit, binnen de EU. Er is een meldroute (`SECURITY.md`, NL-meldadres, eigen
service-normen). Het project is zelfgetoetst tegen ASVS/CRA/OWASP (dit dossier) en
heeft **gedeeltelijke externe review** gehad, maar **geen formele, onafhankelijke
certificering of verificatie**.

**Toetsing.** De SOC-georiënteerde delen van de schaal (7.2 SOC-locatie, monitoring)
zijn voor een lokaal product grotendeels n.v.t. Op de wél toepasselijke delen —
zelf-uitgevoerd EU-patchbeheer en meldroute — zit OciDeck op 2, met elementen van
3. Maar het raamwerk is hier expliciet: **zonder onafhankelijke verificatie op de
kritieke vragen blijft het niveau op 2 begrensd.** Dat "deels extern, nog niet
formeel" precies bepalend is, klopt met het bewijsniveaumodel. **Inschatting:
niveau 2, met elementen van 3**, en de weg naar 3–4 loopt via een formele externe
toets — een bewuste, nog niet gezette stap (zie het assurance-dossier).

## Verdieping SOV-8 — Duurzaamheid, getoetst aan de definitie

**De definitie.** Kernvraag: is de dienst op lange termijn uitvoerbaar binnen
Europese energie-, grondstoffen- en duurzaamheidskaders? De vragen gaan over PUE
van datacenters, energieherkomst, CO2 (scope 1/2/3), circulaire hardware en
CSRD-rapportage. De niveaus lopen van 0 (geen transparantie, dominante niet-EU-
energie/materialen) naar 4 (volledig duurzaam, EU-verankerd, structurele
monitoring).

**Toetsing.** Vrijwel elke vraag veronderstelt een **gehoste dienst met een
datacenter**. OciDeck heeft dat niet: het draait op de bestaande machine van de
gebruiker, zonder cloud-energievoetafdruk en zonder dat het project hardware
levert. De datacenter-as (PUE, energieherkomst, CO2 van de dienst) is dus
**structureel n.v.t.** — niet omdat het slecht scoort, maar omdat de vraag niet
past. Op de marge die wél iets zegt is het beeld gunstig: geen marginaal
cloud-energiegebruik, draait op commodity-hardware die de gebruiker al bezit (geen
gedwongen vervanging), en een compiled-native app is efficiënt. **Een formele
SOV-8-score forceren zou schijnprecisie zijn**; de eerlijke uitkomst is "n.v.t. op
de datacenter-as, gunstig op de eigen-voetafdruk-as."

## Distributieroutes — soevereiniteit als geheel en per route

### Als geheel

De distributiestrategie moet je niet per route beoordelen alsof elke route een
kritieke schakel is, want dat is de denkfout die het worst-case-principe hier zou
misbruiken. De strategie als geheel:

- **Het canonieke kanaal is de directe download uit de eigen forge.** Dat is de
  enige *kritieke* schakel, en die scoort hoog op elke as (van ons, open, geen
  poortwachter).
- **Alle andere routes zijn additief en optioneel.** Ze zitten niet in het
  kritieke pad, dus het worst-case-principe zet de bodem níet op de zwakste route.
  Een gesloten store erbij verlaagt de soevereiniteit van het product niet.
- **Meer routes verhógen SOV-4 (operationeel).** Niet afhankelijk zijn van één
  distributieweg ís soevereiniteit. De strategie-als-geheel scoort daardoor
  **hoog** — juist omdat ze meervoudig is en forge-canoniek blijft.

Kortom: de soevereiniteit van de distributie-als-geheel wordt bepaald door het
canonieke kanaal (hoog) en versterkt door de veelheid aan routes (SOV-4), niet
verlaagd door de zwakste individuele route.

### Per route

Beoordeeld op de drie relevante assen — SOV-1 (leverancier/eigenaar), SOV-5
(keten/poortwachter), SOV-6 (openheid/lock-in) — plus een eerlijk eindoordeel.

| Route | SOV-1 | SOV-5 | SOV-6 | Oordeel |
|---|---|---|---|---|
| **Directe forge-download** (canoniek) | hoog | hoog | hoog | De referentie. Van ons, open, geen poortwachter, geen sandbox. |
| **Homebrew-tap** (forge-canoniek + GitHub-spiegel) | hoog | midden | hoog | Wijst naar ons artefact, verifieert tegen `SHA256SUMS`; Homebrew-tooling open. Enige rand: de GitHub-spiegel is een niet-EU-ketenelement voor de shorthand. |
| **AppImage** (los aan de release) | hoog | hoog | hoog | Ons artefact, één bestand, geen poortwachter, geen sandbox. De Linux-tegenhanger van de directe download. |
| **`.deb` + eigen ondertekende apt-repo** | hoog | hoog | hoog | Van ons; updates lopen mee via onze eigen, ondertekende repo. `.rpm` idem. |
| **Flatpak — eigen remote / `.flatpak`-bundel** | hoog | hoog | midden | Van ons. Flatpak-runtime is open. Sandbox raakt SOV-6 (git-subproces) — opgevangen door de capaciteits-feature-flag. |
| **Flathub** | midden | midden | midden | **Open backend, community-gedragen** (materieel beter dan Snap). Reviewpoortwachter + permissie-review + niet-EU-infra. Bereik en vindbaarheid als tegenwaarde. |
| **Snap Store** | **laag** | **laag** | midden | Canonicals backend is propriëtair, single-vendor, niet zelf te hosten (bouwtooling wél open). Laag op SOV-1/5 — maar als *één van meerdere* routes verdedigbaar (zie inzicht 2). |
| **Apple Mac App Store** | laag | laag | **laag** | Gesloten, reviewpoortwachter, sandbox-amputatie (git breekt). Afgewezen in [`app-store-distributie-positie.md`](app-store-distributie-positie.md). |
| **Microsoft Store** | laag | laag | midden | Poortwachter + voorwaarden, maar full-trust MSIX (geen amputatie). Nevenkanaal, lage prioriteit. |

## De twee inzichten die de kanaalkeuze sturen

**1. Zwakste schakel (SEAL), maar op het juiste object.** Het worst-case-principe
zet het totaal op het laagst scorende *kritische* doel. Voor het product zit die
bodem in de keten/toolchain (SOV-5), niet in de distributie — en een optioneel,
niet-kritiek kanaal verlaagt die bodem niet, want het canonieke pad blijft van
ons.

**2. Meerdere routes verhógen de operationele soevereiniteit (SOV-4).** Daarom
draait het Snap-oordeel om: **Snap als één van meerdere routes voegt operationele
soevereiniteit toe**, ook al scoort Snap-als-kanaal laag op SOV-1/5. De Ubuntu-
gebruiker wordt nergens toe gedwongen en OciDeck wordt er niet afhankelijk van.
Een grote markt deels missen is een reëel nadeel; hem via een laag-soeverein
kanaal alsnog bedienen, zónder het canonieke pad te verlaten, is een nettowinst —
niet een verraad aan de waarde. Snap wordt dus **niet afgewezen op
soevereiniteitsgrond**, maar meegewogen als extra route.

## Gevolg voor de techniek: de capaciteits-feature-flag

De sandbox van Flatpak (strict) en Snap raakt SOV-6: functionaliteit die op een
**git-subproces** leunt (de git-opslag, met de NetGuard-oplegging) draait niet
zomaar in een confined build. In plaats van te breken of stil verkeerd gedrag te
vertonen, hoort OciDeck **transparant te degraderen**: een build-/runtime-
**capaciteits-flag** schakelt de subproces-afhankelijke functies uit en de app
zégt welke mogelijkheden deze build heeft. Zo blijft de technologische
soevereiniteit overeind — de gebruiker weet wat elke verpakking kan, en een
beperkte verpakking is een *bewuste, benoemde* beperking in plaats van een bug.
Dit hoort in het bouwplan van #1227 (zie
[`../docs/design/LINUX_PACKAGING.md`](../docs/design/LINUX_PACKAGING.md)).

## Wanneer dit opnieuw op tafel moet

- De toolchain verandert wezenlijk (een niet-Google-Dart, een andere UI-laag, of
  een overstap naar een EU-forkgovernance zoals Flock) — dat raakt SOV-5/6
  rechtstreeks.
- Er komt een formele externe verificatie (of juist een concrete auditbevinding)
  — dat verschuift SOV-7.
- Er komt een kanaal bij dat het canonieke pad zou *vervangen* in plaats van
  aanvullen — dan geldt inzicht 1 niet meer.
- Het ECSF wordt bijgesteld (nieuwe doelen, andere minimumnormen).
- OciDeck krijgt een backend, account of hostingcomponent — dan verschuift het
  hele mapping-kader én wordt SOV-8 (datacenter) ineens wél van toepassing; de
  kanttekening bovenaan is dan het eerste wat herzien moet worden.
