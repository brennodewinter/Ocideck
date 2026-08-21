# App-storedistributie — positie en leidraad

> **Status:** vastgesteld 2026-08-04 · Stichting LibreKAT · intern werkdocument
>
> Geen conformiteitsclaim en geen auditrapport. Zie [`README.md`](README.md).
>
> Dit is een kernwaardentoets (de `bewaker`-lijn), geen ketenkeuring van een
> afhankelijkheid. De vraag is niet "kunnen we dit veilig bouwen" maar "past dit
> bij waar OciDeck voor bestaat".

## De aanleiding

Terugkerende vraag van gebruikers: **"hoe krijg ik OciDeck in de app-store?"** —
zowel de Apple Mac App Store als de Microsoft Store (Windows). Dit document legt
het oordeel vast zodat er een eerlijk, herbruikbaar antwoord op te geven is,
inclusief de afwegingen eronder en de condities waaronder het besluit kantelt.

## Het besluit

**De canonieke distributie blijft de directe download uit de eigen forge —
notarized DMG (macOS) en MSIX/installer (Windows). Een app-store is nooit het
enige kanaal, hooguit een extra.**

Per store:

- **Apple Mac App Store — niet doen** als primaire route, en zelfs als gelabelde
  nevenroute zwaar ontraden. De verplichte App Sandbox breekt een productpijler
  (git-opslag via subproces) en levert daarmee een tweederangs OciDeck; de
  codereview wordt een externe partij met vetorecht op het releasetempo van
  beveiligingsfixes.
- **Microsoft Store — mag, lage prioriteit.** Full-trust MSIX vraagt geen
  functie-amputatie, dus de zwaarste botsing valt weg. Wat overblijft is
  Microsoft als poortwachter (certificering + voorwaarden), dezelfde soort
  afhankelijkheid die ook de bewuste keuze tegen Windows Authenticode ingaf
  (#1013). Aanvaardbaar als nevenkanaal, geen doel op zich.

## Waarom de kerntoets hier niet de doorslag geeft

De scherpste bewakervraag is: *als OciDeck morgen ophoudt te bestaan, kan de
gebruiker dan verder met zijn decks?* Een app-store distribueert de **binary**,
niet de **data**. De decks blijven gewone `.md`-bestanden op de door de gebruiker
gekozen plek, ongeacht hoe de app is geïnstalleerd. Op de data-as — de as waar de
kerntoets over gaat — is een app-store dus **geen slot**.

Dit is bewust vooropgezet, want het is de meest gemaakte denkfout: een app-store
raakt niet het bestandsformaat en niet de informatiesoevereiniteit over de
inhoud. De wrijving zit op een andere as — **wie je moet vertrouwen om de app te
krijgen en te draaien, en of de gebruiker een volwaardige app krijgt.** Daar
worden de tien kernwaarden geraakt.

## Apple Mac App Store — de drie botsingen, benoemd

**1. Sandbox dwingt functie-amputatie (waarden 7, 8, 4).** De verplichte App
Sandbox staat geen willekeurige subprocessen toe. De git-opslag draait op een
`git`-subproces (met de NetGuard-oplegging via git-config); dat komt de sandbox
niet door. Twee uitkomsten, beide slecht:

- *Store-build gelijk aan de directe build:* alle gebruikers worden gedegradeerd
  om Apple te plezieren. Onaanvaardbaar.
- *Store-build als aparte, uitgeklede variant:* de store levert stilzwijgend een
  OciDeck zonder git-opslag. De gebruiker die niet weet waarom zijn opslag
  ontbreekt, is precies de mens uit waarde 8 die je niet mag wegredeneren — en
  je onderhoudt voortaan twee producten.

**2. Reviewpoortwachter botst met veiligheid-op-1 (waarde 1).** Fail-closed
betekent dat *wij* bepalen wanneer een beveiligingsfix uitgaat. In de store zit
Apples review tussen ontwikkelaar en gebruiker; een reviewer kan een security-
patch dagen ophouden. Voor een product dat veiligheid expliciet op 1 zet, is een
externe partij met remkracht op het patchtempo een reëel risico, geen
formaliteit.

**3. Nieuwe partij in het pad + jaarlijkse afhankelijkheid (waarden 3, 4).**
Apple wordt een gesloten, buitenlands platform tussen product en gebruiker,
plus een terugkerende accountverplichting. Aanvaardbaar zolang het strikt een
*extra* kanaal is naast de canonieke directe download — nooit als het het enige
kanaal wordt, want dan is het alsnog een slot op de distributie.

**Oordeel:** niet doen, of pas veel later met de amputatie expliciet
gedocumenteerd en de store-build zichtbaar gelabeld als beperkt.

**Waaronder dit kantelt:** als Apple een entitlement voor het benodigde
subproces toestaat, óf de git-laag naar pure-Dart gaat zodat de store-build
volwaardig is, vervalt botsing 1. Dan resteert alleen de reviewpoortwachter, en
wordt het een gewone afweging in plaats van een principiële afwijzing.

## Microsoft Store — de lichtere botsing

Wezenlijk milder, want de Microsoft Store accepteert **full-trust Win32-apps via
MSIX** — geen verplichte AppContainer-sandbox. Daarmee vervalt de functie-
amputatie: git en netwerk blijven intact. Wat resteert is Microsoft als
poortwachter (certificering, storevoorwaarden, account), maar zonder de
release-remmende codereview en zonder een tweederangs-build.

Dit rijmt met een besluit dat al genomen is: **Windows Authenticode bewust niet**
(#1013). Dezelfde logica — geen gatekeeper-mechanisme in het kritieke pad —
pleit ervoor de Microsoft Store hoogstens als optioneel gemakskanaal te zien.

**Oordeel:** waardenneutraal genoeg om te mogen, mits de directe download het
canonieke kanaal blijft en de store-build in capaciteit identiek is. Geen
prioriteit.

## Samengevat

| Kanaal | Data-slot? | Functie-amputatie? | Poortwachter | Verdict |
|---|---|---|---|---|
| Directe download (notarized DMG / MSIX) | nee | nee | geen | canoniek, blijft de norm |
| Apple Mac App Store | nee | **ja — git-opslag breekt** | review blokkeert patches | niet, of zwaar gelabelde nevenroute |
| Microsoft Store | nee | nee (full-trust MSIX) | certificering + voorwaarden | mag als nevenkanaal, lage prioriteit |

De rode draad: **een store is nooit het canonieke kanaal, altijd hooguit een
extra.** Het eerlijke antwoord op "hoe krijg ik OciDeck in de app-store" is dus:
de canonieke route ís de directe notarized/MSIX-download; de stores zijn
optioneel en kosten bij Apple een uitgeklede app.

## Samenhang met de CRA-positie

Dit raakt [`CRA-2024-2847-positie.md`](CRA-2024-2847-positie.md) direct. Dat
document noemt als een van de zes condities om de "geen fabrikant"-positie te
heroverwegen: *"Distributie loopt via een kanaal dat niet de eigen forge is, met
binaries."* Een app-store ís precies zo'n kanaal.

Zolang een store een nevenkanaal blijft dat dezelfde uit-de-bron-gebouwde,
ondertekende binary aanbiedt en de stichting niet monetiseert, verandert de
CRA-conclusie niet — maar de conditie stáát er niet voor niets. Wordt een store
ooit serieus opgetuigd, dan is de CRA-positie het eerste wat opnieuw gewogen
moet worden, vóór de eerste upload.

## Package managers (Homebrew, Linux) — een ander geval dan een store

*Toegevoegd 2026-08-04, n.a.v. #1222/#1227.* Een package manager is geen store,
en de toets valt dan ook anders uit. Een Homebrew-**cask** herbergt de app niet:
hij is een *verwijzing* die `brew` naar ons eigen release-artefact stuurt en de
download tegen onze gepubliceerde `SHA256SUMS` verifieert. Geen sandbox, geen
review-poortwachter op de binary, geen re-hosting — de gebruiker krijgt exact de
`.app` die wij uitbrachten. Dat staat qua waarden **dicht tegen de canonieke
directe download**, en veel dichterbij dan een app-store.

Twee dingen bewaken we daarbij, zodat het een nevenkanaal blijft en geen slot:

- **De tap is van ons.** De cask-formule leeft in een eigen tap-repo op de
  **eigen forge** (canoniek), met een GitHub-spiegel als reservekopie. De
  gedocumenteerde installatieroute tapt de forge rechtstreeks
  (`brew tap librekat/ocideck https://pawprint.vigilis.online/LibreKAT/homebrew-ocideck.git`),
  zodat zowel de formule als het artefact van ons komt; de shorthand
  `brew install --cask brennodewinter/ocideck/ocideck` blijft staan als
  terugvaloptie, want die lost per definitie naar GitHub op. Zo is de bron
  inspecteerbaar en van ons; de officiële `homebrew-cask` (met eigen reviewers
  en notability-criteria) wordt bewust niet gebruikt.
- **Homebrew Cask is macOS-only.** Er bestaan geen Linux-casks. Linux krijgt dus
  een *eigen* installatieroute die op zo veel mogelijk distributies werkt
  (AppImage/Flatpak-spoor, #1227) — nooit een uitgeklede cask die alleen op
  papier bestaat.

Dit trekt de heroverwegingsconditie in [`CRA-2024-2847-positie.md`](CRA-2024-2847-positie.md)
licht ("distributie via een kanaal dat niet de eigen forge is, met binaries"),
maar mild: de binary komt uit onze forge; de tap is enkel een index die ernaar
wijst. Genoteerd, geen blokker.

**Voorbehoud (eerlijk).** De cask is pas een gladde installatie zodra de
macOS-release genotariseerd is; is een release ongetekend uitgebracht (zie
`README.md` en `docs/BUILD.md`), dan blokkeert Gatekeeper de app bij eerste
start net als bij een directe download. De cask maakt de distributie makkelijker,
niet de ondertekening — die staat los.

## Wanneer dit besluit opnieuw op tafel moet

- De git-opslag verhuist naar een pure-Dart-implementatie (Apple-botsing 1
  vervalt).
- Apple wijzigt het sandboxbeleid zó dat het benodigde subproces met een
  entitlement is toegestaan.
- Er ontstaat een concrete reden dat de directe download onvoldoende bereik
  geeft (vindbaarheid, een vertrouwenssignaal dat gebruikers echt missen).
- Er komt geld aan OciDeck vast te zitten — dan speelt óók de CRA-/rentmeester-
  vraag mee, niet alleen deze afweging.
- De Microsoft Store of Apple wijzigt de verpakkings- of ondertekeningseisen
  wezenlijk.

Bij elk van deze is de vraag niet "mag het nu wel", maar: **wat verandert er
feitelijk aan de drie botsingen hierboven, en klopt het oordeel per store dan
nog.**
