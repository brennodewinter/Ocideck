# Soevereiniteit — OciDeck langs het ECSF

> **Status:** zelfpositionering · opgesteld 2026-08-04 · Stichting LibreKAT
>
> Geen conformiteitsclaim en geen assurance-oordeel. Zie [`README.md`](README.md).
> Dit is een **consultancy-niveau zelfpositionering** in de zin van de ECSF
> Assurance Method: een gestructureerd beeld van waar OciDeck staat, geen
> reproduceerbaar oordeel met bewijsniveaus per vraag. Waar hieronder een niveau
> staat, is dat een eigen inschatting, geen vastgestelde score.

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
| **SOV-1** Strategisch | 2 | **3–4** | EUPL-opensource onder een Nederlandse stichting; geen externe eigenaar kan de koers afdwingen, en een fork is de ultieme exit. Rand: de toolchain is niet EU-bestuurd. |
| **SOV-2** Juridisch/rechtsmacht | 2 | **3–4** | Geen cloudverwerking → CLOUD Act/FISA raken de data van de gebruiker niet, want geen leverancier houdt ze vast. Data lokaal, stichting NL, licentie EU (EUPL). |
| **SOV-3** Data & AI | 3 | **3–4** | Data zijn lokale bestanden in een open formaat; sleutels in de OS-sleutelbos; geen telemetrie; AI staat standaard uit en wijst naar een door de gebruiker gekozen endpoint. Volledige sleutelcontrole. |
| **SOV-4** Operationeel | 2 | **4** (kern) | Werkt volledig offline; er is geen dienst die kan uitvallen; bouwbaar uit de bron. Geen operationele afhankelijkheid van enige leverancier. *Hier telt het aantal kanalen — zie onder.* |
| **SOV-5** Keten | 2 | **2–3** | SBOM (CycloneDX + SPDX), reproduceerbare webbundel, ondertekende releases, beheerste updates. Rand: de pakketgraaf en de toolchain bevatten niet-EU-componenten (Flutter/Dart, Google). Eerlijk de zwakkere as. |
| **SOV-6** Technologisch | 2 | **4** (interop) | Markdown-basis = open standaard, volledig exporteerbaar, opensource, geen lock-in — de kern van het product. Rand: Flutter/Dart is een Google-ecosysteem (begrensd: opensource, forkbaar). |
| **SOV-7** Beveiliging/compliance | 2 | **2–3** | Zelfgetoetst tegen ASVS/CRA/OWASP (dit dossier), NL-meldadres, geen externe SOC nodig (lokaal). Het raamwerk begrenst dit bewust op 2–3 zonder onafhankelijke verificatie — dat klopt met onze eigen disclaimer. |
| **SOV-8** Duurzaamheid | 1 | **n.v.t.–1** | Weinig van toepassing: geen datacenter, draait op de bestaande hardware van de gebruiker. De minimumnorm is triviaal gehaald; diepere CSRD-rapportage valt buiten scope. Lage relevantie, geen prestatie. |

Twee dingen die deze tabel niet doet. Ze vinkt niets af — de niveaus zijn
inschattingen zonder de bewijsverzameling die een formeel oordeel eist. En ze
verbergt de zwakke assen niet: de **keten (SOV-5)** en het **Google-deel van de
technologische as (SOV-6)** zijn de echte begrenzers, niet de distributie.

## Distributiekanalen langs de soevereiniteitsassen

Dit is waar #1227 baat bij heeft. Kanalen verschillen niet "wel/niet soeverein"
maar per as. De relevante assen zijn SOV-1 (leverancier/eigenaar), SOV-5 (keten/
poortwachter) en SOV-6 (openheid/lock-in).

| Kanaal | SOV-1 | SOV-5 | SOV-6 | Kernpunt |
|---|---|---|---|---|
| **Directe forge-download** | hoog | hoog | hoog | Van ons, open, geen poortwachter. De canonieke bodem. |
| **Homebrew-tap** (forge-canoniek + GH-spiegel) | hoog | midden | hoog | Wijst naar ons artefact; Homebrew-tooling open; de GitHub-spiegel is een mild niet-EU-ketenelement. |
| **AppImage** (los aan de release) | hoog | hoog | hoog | Ons artefact, geen poortwachter, geen sandbox. |
| **`.deb` + eigen ondertekende apt-repo** | hoog | hoog | hoog | Van ons, updates lopen mee. |
| **Flatpak — eigen remote / `.flatpak`-bundel** | hoog | hoog | midden | Van ons; Flatpak-runtime is open. Sandbox raakt SOV-6 licht (zie feature-flag). |
| **Flathub** | midden | midden | midden | **Open backend, community-gedragen** — beter dan Snap; maar een reviewpoortwachter en niet-EU-infra. |
| **Snap Store** | **laag** | **laag** | midden | Canonicals backend is propriëtair en single-vendor, niet zelf te hosten. Bouwtooling wel open. |
| **Apple App Store / MS Store** | laag | laag | laag | Gesloten, reviewpoortwachter, sandbox-amputatie. Al afgewogen in [`app-store-distributie-positie.md`](app-store-distributie-positie.md). |

## De twee inzichten die de kanaalkeuze sturen

**1. Zwakste schakel (SEAL), maar op het juiste object.** Het worst-case-principe
zegt: het totaal is het laagst scorende kritische doel. Voor het *product* zit die
bodem in de **keten/toolchain** (SOV-5/6, Google's Flutter), niet in de
distributie. En cruciaal: **een kanaal verlaagt de bodem van het product niet**,
want kanalen zijn *additief* en het canonieke kanaal (directe forge-download)
blijft van ons. Een gesloten store erbij zetten maakt de directe download niet
minder soeverein.

**2. Meerdere routes verhógen de operationele soevereiniteit (SOV-4).** Niet
afhankelijk zijn van één kanaal ís soevereiniteit. Daarom draait het Snap-oordeel
om: **Snap als één van meerdere routes voegt operationele soevereiniteit toe**,
ook al scoort Snap-als-kanaal laag op SOV-1/5/6. De Ubuntu-gebruiker wordt er niet
toe gedwongen (hij heeft AppImage, `.deb`, Flatpak) en OciDeck wordt er niet
afhankelijk van (de release komt uit onze forge). Een grote markt deels missen is
een reëel nadeel; het via een laag-soeverein kanaal alsnog bedienen, zónder het
canonieke pad te verlaten, is een nettowinst — niet een verraad aan de waarde.

Dit is de correctie op het eerdere te grove oordeel: Snap wordt **niet afgewezen
op soevereiniteitsgrond**, maar meegenomen als extra route, met open ogen over
waar het laag scoort en waarom dat er als *één van velen* minder toe doet.

## Gevolg voor de techniek: de capaciteits-feature-flag

De sandbox van Flatpak (strict) en Snap raakt SOV-6: functionaliteit die op een
**git-subproces** leunt (de git-opslag, met de NetGuard-oplegging) draait niet
zomaar in een confined build. In plaats van te breken of stil verkeerd gedrag te
vertonen, hoort OciDeck **transparant te degraderen**: een build-/runtime-
**capaciteits-flag** schakelt de subproces-afhankelijke functies uit en de app
zégt welke mogelijkheden deze build heeft. Zo blijft de technologische
soevereiniteit overeind — de gebruiker weet wat elke verpakking kan, en een
beperkte verpakking is een *bewuste, benoemde* beperking in plaats van een bug.
Dit hoort in het bouwplan van #1227 (zie [`../docs/design/LINUX_PACKAGING.md`](../docs/design/LINUX_PACKAGING.md)).

## Wanneer dit opnieuw op tafel moet

- De toolchain verandert wezenlijk (een niet-Google-Dart, of een andere
  UI-laag) — dat raakt de echte bodem (SOV-5/6).
- Er komt een kanaal bij dat het canonieke pad zou *vervangen* in plaats van
  aanvullen — dan geldt inzicht 1 niet meer.
- Het ECSF wordt bijgesteld (nieuwe doelen, andere minimumnormen).
- OciDeck krijgt een backend, account of hostingcomponent — dan verschuift het
  hele mapping-kader en moet de kanttekening bovenaan als eerste worden herzien.
