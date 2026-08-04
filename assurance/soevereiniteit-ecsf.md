# Soevereiniteit — OciDeck langs het ECSF

> **Status:** zelfpositionering · opgesteld 2026-08-04 · Stichting LibreKAT
>
> Geen conformiteitsclaim en geen assurance-oordeel. Zie [`README.md`](README.md).
> Dit is een **consultancy-niveau zelfpositionering** in de zin van de ECSF
> Assurance Method: een gestructureerd beeld van waar OciDeck staat. De niveaus
> hieronder zijn **onze eigen inschatting op grond van de code en documentatie in
> deze repository** — getoetst aan de niveaudefinities, maar **geen audit** en
> geen onafhankelijk geverifieerde score.

## Waarom dit document bestaat

Soevereiniteit is geen schakelaar. Bij het afwegen van distributiekanalen (#1227)
werd "Snap botst met soevereiniteit" als een enkel, zwart-wit oordeel opgeschreven
— en dat is te grof. Het **European Cloud Sovereignty Framework (ECSF)** — acht
doelen, elk op een schaal van vijf niveaus, gebaseerd op het boek *November* —
maakt zichtbaar dat soevereiniteit meerdere assen heeft die onafhankelijk hoog of
laag kunnen staan. Dit document zet OciDeck langs die acht assen, zodat een
kanaalkeuze op de juiste as gewogen wordt in plaats van op een gevoel.

## De methode: van boven naar beneden, en twee dimensies

**Van boven naar beneden.** Per doel beginnen we bij **niveau 4** en toetsen of
OciDeck de definitie van dat niveau waarmaakt. Zo ja, dan is het 4. Zo nee, dan
toetsen we 3, dan 2, enzovoort. We beginnen dus hoog en zakken alleen op een
concrete reden — niet andersom.

**Een inschatting, geen audit.** Wat hieronder staat is onze eigen inschatting
van de volwassenheid — de feitelijke situatie, hoeveel controle er echt is. De
**grondslag** ervan is de code en de documentatie die in deze repository
openligt: inspecteerbaar door iedereen, maar door onszelf aangedragen. Dat is een
reële basis, geen verklaring uit de lucht — maar het is **geen onafhankelijke
audit**. Precies daarom noemen we het inschattingen en geen vastgestelde scores.

Het raamwerk scheidt bewust *volwassenheid* (de situatie) van *bewijsniveau* (hoe
onafhankelijk onderbouwd, 0–4). Wij vullen de volwassenheid in op basis van wat
hier zichtbaar is; het bewijs blijft daarmee op het niveau "documentatie en
technisch aantoonbaar in de eigen bron" (2–3), niet "onafhankelijk geverifieerd"
(4). Dat begrenst niet onze *inschatting* maar wel de *zekerheid* ervan: een
formele externe verificatie zou inschattingen tot geborgde niveaus maken. Zolang
die er niet is, is dit een zelfpositionering met beperkte zekerheid — eerlijk
gelabeld als zodanig.

## De mapping-kanttekening (ze draagt de rest)

Het ECSF beoordeelt de positie van een **afnemende organisatie tegenover een
cloud-leverancier**. OciDeck is geen clouddienst maar een **lokaal-eerst
desktopprogramma zonder backend, account of telemetrie**. De vertaling:

- De **afnemende organisatie** is de gebruiker zelf.
- De **dienst** is OciDeck op de eigen machine.
- De **leveranciers** zijn niet één cloudpartij, maar de *afhankelijkheden* van
  het product: de toolchain (Flutter/Dart), de pakketgraaf en de
  **distributiekanalen** (#1227).

Het gevolg is structureel: voor een lokaal-eerst product staat de kern hoog, niet
door inspanning maar door vorm. Er is geen leverancier in het kritieke pad die
data vasthoudt, dus een hele klasse aan jurisdictie- en datacontrolerisico's is
afwezig — en dat is precies waarom de top-downtoets vaak bij 4 uitkomt.

## Per doel — van niveau 4 naar beneden

### SOV-1 Strategische soevereiniteit → volwassenheid **4**

*Kernvraag: wie kan de strategische richting van deze dienst bepalen of wijzigen?*

- **Niveau 4 — "Strategische autonomie: duurzaam Europees ingebedde aanbieder;
  afhankelijkheid expliciet gewogen in boardbesluit."** De "aanbieder" is
  Stichting LibreKAT (NL) — duurzaam Europees ingebed. De strategische richting
  kan niet extern worden afgedwongen: de code is EUPL-opensource én het
  bestandsformaat is open, dus een fork van de software én de vrije voortzetting
  van de decks zijn beide altijd mogelijk. De afhankelijkheden worden expliciet
  gewogen — dit dossier en de CRA-/rentmeester-analyse zíjn dat besluit.
  **Waargemaakt → 4.**

**Grondslag:** de statuten, de licentie en de gedocumenteerde afwegingen in dit
dossier (inschatting, geen audit).

### SOV-2 Juridische en rechtsmachtsoevereiniteit → volwassenheid **4**

*Kernvraag: onder welke rechtsorde valt de dienst en wie kan juridisch toegang
afdwingen?*

- **Niveau 4 — "Effectieve afdwingbaarheid: rechten effectief afdwingbaar;
  periodieke toets op extraterritoriale risico's."** Dit is breder dan alleen de
  CLOUD Act. Er is geen leverancier die data vasthoudt, dus extraterritoriale
  toegang tot de data is structureel afwezig. De code is open onder de **EUPL**
  (een EU-licentie) en het formaat is open — geen licentiegever of jurisdictie
  kan voorwaarden opleggen of intrekken. De zeggenschap over de data ligt bij de
  gebruiker, op zijn machine. In deze reframe zijn de "rechten" niet contractueel
  maar feitelijk, en absoluut. **Waargemaakt → 4.**

**Grondslag:** de juridische analyse in de CRA-positie en dit dossier
(inschatting, geen audit).

### SOV-3 Data- en AI-soevereiniteit → volwassenheid **4**

*Kernvraag: hebben wij exclusieve en effectieve controle over onze data en
AI-werking?*

- **Niveau 4 — "Volledige controle: volledige controle over data, sleutels,
  AI-modellen en verwerking."** Data zijn lokale bestanden in een open formaat;
  sleutels in de OS-sleutelbos; geen telemetrie; verwerking lokaal. AI staat
  standaard uit én is **wisselbaar** — de gebruiker kiest het endpoint (of geen,
  of een lokaal/EU-model). Alle vier de elementen — data, sleutels, AI-modellen,
  verwerking — liggen bij de gebruiker. **Waargemaakt → 4.** (De enige nuance —
  een gebruiker die zélf een niet-EU-AI kiest — is een keuze van de gebruiker,
  niet een eigenschap van het product, en staat standaard uit.)

**Grondslag:** aantoonbaar in de code en het gedrag van de app (inschatting, geen
audit).

### SOV-4 Operationele soevereiniteit → volwassenheid **4**

*Kernvraag: kunnen wij deze dienst zelfstandig binnen de EU exploiteren, ook als
externe ondersteuning wegvalt?*

- **Niveau 4 — "In control: volledige EU-exploitatie mogelijk zonder kritieke
  niet-EU-afhankelijkheden."** Bij runtime is er geen externe afhankelijkheid: de
  app werkt volledig offline, er is geen dienst die kan uitvallen, en ze is uit de
  bron te bouwen. De enige niet-EU-schakel (de toolchain) speelt bij het *bouwen*,
  niet bij het *exploiteren*. Operationeel is er niets dat kan wegvallen.
  **Waargemaakt → 4.**

**Grondslag:** de app draait offline en is reproduceerbaar uit de bron te bouwen
(inschatting, geen audit).

### SOV-5 Ketensoevereiniteit → volwassenheid **3** (4 op de in-control-lezing)

*Kernvraag: hoe afhankelijk zijn wij van de internationale technologie- en
toeleveringsketen?*

Dit is het enige doel waar een niet-EU-afhankelijkheid *letterlijk* bestaat, dus
hier moet de top-downtoets het scherpst.

- **Niveau 4 — "Transparant en in control: volledige transparantie en geen
  kritieke niet-EU-afhankelijkheden."** Transparantie: waargemaakt (SBOM in
  CycloneDX + SPDX over alle componenten, verouderingspoort). "Geen kritieke
  niet-EU-afhankelijkheden": hier wringt het. Flutter en Dart komen van Google
  (VS) — niet-EU van oorsprong. **Strikt gelezen halen we de letter van 4 niet.**
  Maar de afhankelijkheid is van een bijzondere soort: beide zijn **BSD-3-Clause
  open source**, publiek ontwikkeld ("geen partij heeft unilaterale controle"),
  en er bestáát een community-fork (**Flock**). Het onderscheid dat telt:
  *intrekkingsrisico* (kan iemand ons afsluiten?) is **nul** — een BSD-licentie is
  onherroepelijk, de bron staat publiek, forken is bewezen mogelijk;
  *overstapkosten* (het is een Dart-codebase) zijn **hoog**, maar dat is een
  afhankelijkheid van inspanning, niet van toestemming. Op de "in control"-lezing
  — het niveau-4-label zelf — zijn we ín control: niemand kan de keten tegen ons
  gebruiken.
- **Niveau 3 — "Betekenisvolle invloed: betekenisvolle EU-invloed en
  diversificatie van kritieke schakels."** Betekenisvolle invloed op en
  beheersing van de eigen keten: waargemaakt (SBOM, ondertekende reproduceerbare
  updates, grotendeels eigen build-infra; alleen de Windows-build reist via een
  GitHub-spiegel). **Waargemaakt → 3.**

**Conclusie: 3, en 4 is verdedigbaar** op de lezing dat een open, forkbare,
niet-intrekbare component geen "kritieke afhankelijkheid" in lock-in-zin is. We
houden **3** als de eerlijke, conservatieve uitkomst en benoemen 4 als de
optimistische lezing — de sprong ligt niet aan inspanning maar aan de niet-EU-
*oorsprong* van een open toolchain. **Grondslag:** de SBOM en de ondertekende,
reproduceerbare builds (inschatting, geen audit).

### SOV-6 Technologische soevereiniteit → volwassenheid **4**

*Kernvraag: kunnen wij deze technologie integreren, auditen en aanpassen zonder
afhankelijk te zijn van één gesloten leverancier of niet-EU-ecosysteem?*

- **Niveau 4 — "In control: volledige controle over integratie en standaarden;
  geen kritieke *gesloten* afhankelijkheden."** Let op het woord *gesloten* —
  anders dan SOV-5 (dat naar *niet-EU* vraagt) vraagt SOV-6 naar *closed source*.
  De Markdown-basis is een open standaard, de export is volledig, meerdere
  platformen worden ondersteund (macOS/Windows/Linux/web), en de hele stack —
  inclusief Flutter/Dart — is **open source**. Er is dus **geen enkele kritieke
  gesloten afhankelijkheid**. Precies het criterium van niveau 4. **Waargemaakt →
  4.**

**Grondslag:** het open formaat en de open stack zijn aantoonbaar; vervangbaarheid
op standaardniveau, niet op taalniveau (zie SOV-5) (inschatting, geen audit).

### SOV-7 Beveiligings- en compliancesoevereiniteit → inschatting **3**

*Kernvraag: vindt beveiliging en toezicht plaats binnen de Europese rechtsorde?*

Dit is het doel waar de aard "inschatting, geen audit" het meest telt, want bij
beveiliging is onafhankelijke toetsing juist het punt.

- **Niveau 4 — "In control: volledige controle over monitoring, incidentrespons,
  patching en compliance."** Feitelijk voert het project patch- en
  kwetsbaarhedenbeheer zelf uit, binnen de EU, met een eigen meldroute. Wat 4 hier
  vraagt is niet alleen volledige eigen controle maar ook dat het van buitenaf is
  vastgesteld. Dat laatste is er niet — en dat is precies waar dit een
  zelf-inschatting is en geen audit. **4 spreken we onszelf niet toe.**
- **Niveau 3 — "EU-operaties: EU-gebaseerde security-ops effectief; onafhankelijke
  audits mogelijk."** De security-ops zijn eigen en EU-gebaseerd, en onafhankelijke
  audits zíjn mogelijk — de code is open, iedereen kan meekijken, en er is deels
  externe review geweest. Onze grondslag is het assurance-dossier (ASVS/CRA/OWASP
  zelf-toetsing), de poorten (`make sast`, `make check-secrets`) en de open code.
  **Op basis van wat hier ligt, schatten we dit op 3.**

**Conclusie: inschatting 3.** Het is bewust de zachtste van onze inschattingen —
niet omdat de beveiliging zwak is, maar omdat een oordeel over beveiliging pas
echt hard wordt met een **formele externe verificatie**. Die is er nog niet, en ze
is de duidelijkste openstaande stap: ze zou deze inschatting tot een geborgd
niveau maken. Zolang die er niet is, is 3 wat we op grond van code en documentatie
verantwoord vinden — een inschatting, geen audituitspraak.

### SOV-8 Duurzaamheidssoevereiniteit → **grotendeels niet van toepassing**

*Kernvraag: is deze dienst op lange termijn uitvoerbaar binnen Europese energie-,
grondstoffen- en duurzaamheidskaders?*

De top-downtoets loopt hier stuk op de vorm van de vragen, niet op de prestatie:

- **Niveau 4 — "Duurzaam: volledig duurzaam, transparant en EU-verankerd;
  structurele monitoring geborgd"** en alle lagere niveaus draaien om **PUE van
  datacenters, energieherkomst, CO2 (scope 1/2/3) en circulaire hardware**.
  OciDeck heeft **geen datacenter**: het draait op de bestaande machine van de
  gebruiker en levert geen hardware. Er is dus niets om te monitoren of te
  verankeren — de as is **structureel niet van toepassing**, niet "laag".

Op de marge die wél iets zegt is het beeld gunstig: geen marginaal
cloud-energiegebruik, draait op commodity-hardware die de gebruiker al bezit, en
een compiled-native app is efficiënt. **Een SOV-8-niveau forceren zou
schijnprecisie zijn.**

## Samenvattend

Alle niveaus hieronder zijn **inschattingen op grond van de code en documentatie
in deze repository — geen audit.**

| Doel | Inschatting | Grondslag | Kern |
|---|---|---|---|
| SOV-1 Strategisch | **4** | statuten, licentie, afwegingen | EU-stichting + open code én formaat; niet te kapen |
| SOV-2 Juridisch | **4** | juridische analyse (dossier) | geen leverancier met greep; EUPL; data lokaal |
| SOV-3 Data & AI | **4** | code + gedrag van de app | volledige data-/sleutel-/AI-regie bij de gebruiker |
| SOV-4 Operationeel | **4** | draait offline, reproduceerbaar | volledig offline, niets dat kan uitvallen |
| SOV-5 Keten | **3** (4 mogelijk) | SBOM, ondertekende builds | transparant + niet-intrekbare, maar niet-EU, toolchain |
| SOV-6 Technologisch | **4** | open formaat + open stack | open standaard, open stack, multi-platform |
| SOV-7 Beveiliging | **3** | assurance-dossier, poorten, open code | eigen EU-ops; hard te maken met een externe toets |
| SOV-8 Duurzaamheid | **n.v.t.** | — | schaal veronderstelt een datacenter |

**De uitkomst is hoger dan de eerste ronde**, en eerlijk: op onze inschatting
staat OciDeck op **niveau 4 voor zes van de acht doelen**. De twee die lager
staan zijn benoembaar en liftbaar: SOV-5 zit op 3 door de niet-EU-*oorsprong* van
een open, forkbare toolchain (geen intrekkingsrisico), en SOV-7 is de zachtste
inschatting — niet omdat de beveiliging zwak is, maar omdat een beveiligingsoordeel
pas hard wordt met een **formele externe verificatie**. Volgens het
worst-case-principe (SEAL) is het totaal de zwakste kritische schakel; die zit dus
in SOV-5/SOV-7. Beide zijn inschattingen op basis van wat hier openligt, geen
geborgde scores — en beide hebben een bekende route omhoog.

## Distributieroutes — soevereiniteit als geheel en per route

### Als geheel

Beoordeel de strategie niet alsof elke route een kritieke schakel is — dat zou het
worst-case-principe misbruiken.

- **Het canonieke kanaal is de directe download uit de eigen forge.** Dat is de
  énige kritieke schakel, en die scoort hoog op elke as.
- **Alle andere routes zijn additief en optioneel** — niet in het kritieke pad,
  dus ze zetten de bodem niet. Een gesloten store erbij verlaagt de
  soevereiniteit van het product niet.
- **Meer routes verhógen SOV-4 (operationeel).** Niet afhankelijk zijn van één
  distributieweg ís soevereiniteit.

De distributie-als-geheel scoort daardoor **hoog** — bepaald door het canonieke
kanaal en versterkt door de veelheid aan routes.

### Per route

Op de drie relevante assen — SOV-1 (leverancier/eigenaar), SOV-5 (keten/
poortwachter), SOV-6 (openheid/lock-in):

| Route | SOV-1 | SOV-5 | SOV-6 | Oordeel |
|---|---|---|---|---|
| **Directe forge-download** (canoniek) | hoog | hoog | hoog | De referentie. Van ons, open, geen poortwachter, geen sandbox. |
| **Homebrew-tap** (forge-canoniek + GitHub-spiegel) | hoog | midden | hoog | Wijst naar ons artefact, verifieert tegen `SHA256SUMS`. Rand: de GitHub-spiegel voor de shorthand. |
| **AppImage** (los aan de release) | hoog | hoog | hoog | Ons artefact, één bestand, geen poortwachter, geen sandbox. |
| **`.deb` + eigen ondertekende apt-repo** | hoog | hoog | hoog | Van ons; updates lopen mee via onze eigen repo. `.rpm` idem. |
| **Flatpak — eigen remote / `.flatpak`-bundel** | hoog | hoog | midden | Van ons; Flatpak-runtime open. Sandbox raakt SOV-6 (git) — opgevangen door de feature-flag. |
| **Flathub** | midden | midden | midden | Open backend, community-gedragen (beter dan Snap). Reviewpoortwachter + permissie-review. Bereik als tegenwaarde. |
| **Snap Store** | **laag** | **laag** | midden | Propriëtaire, single-vendor backend (bouwtooling wél open). Laag — maar als één-van-velen verdedigbaar (inzicht 2). |
| **Apple Mac App Store** | laag | laag | **laag** | Gesloten, reviewpoortwachter, sandbox-amputatie. Afgewezen in [`app-store-distributie-positie.md`](app-store-distributie-positie.md). |
| **Microsoft Store** | laag | laag | midden | Poortwachter + voorwaarden, maar full-trust MSIX. Nevenkanaal. |

## De twee inzichten die de kanaalkeuze sturen

**1. Zwakste schakel (SEAL), maar op het juiste object.** Het worst-case-principe
zet het totaal op het laagst scorende *kritische* doel. Voor het product zit die
bodem in SOV-5/SOV-7, niet in de distributie — en een optioneel, niet-kritiek
kanaal verlaagt die bodem niet, want het canonieke pad blijft van ons.

**2. Meerdere routes verhógen de operationele soevereiniteit (SOV-4).** Daarom
draait het Snap-oordeel om: **Snap als één van meerdere routes voegt operationele
soevereiniteit toe**, ook al scoort Snap-als-kanaal laag op SOV-1/5. De Ubuntu-
gebruiker wordt nergens toe gedwongen en OciDeck wordt er niet afhankelijk van.
Een grote markt deels missen is een reëel nadeel; hem via een laag-soeverein
kanaal alsnog bedienen, zónder het canonieke pad te verlaten, is een nettowinst.

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
  een overstap naar een EU-forkgovernance zoals Flock) — dat raakt SOV-5/6.
- **Er komt een formele externe verificatie** — dat maakt de SOV-7-inschatting
  hard (van zelf-ingeschat naar geborgd) en mogelijk 4; de belangrijkste
  openstaande stap.
- Er komt een kanaal bij dat het canonieke pad zou *vervangen* in plaats van
  aanvullen — dan geldt inzicht 1 niet meer.
- Het ECSF wordt bijgesteld (nieuwe doelen, andere minimumnormen).
- OciDeck krijgt een backend, account of hostingcomponent — dan verschuift het
  hele mapping-kader én wordt SOV-8 (datacenter) ineens wél van toepassing.
