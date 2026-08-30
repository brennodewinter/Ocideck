> 🤖 Machinevertaling — het Engelse bronbestand is leidend.
>
> _Machine translation — the English source document is authoritative. _

# OciDeck — Documentation

> **Status:** index van deze map, actueel · **Status laatst nagekeken:** 2026-08-30 · **Uitgegeven door:** Stichting LibreKAT

OciDeck is een privacy-eerst Marp-presentatiebouwer voor desktop en web, zonder
applicatie-backend — alles draait lokaal. Deze map bevat de projectdocumentatie.
Begin hier en spring naar wat je nodig hebt.

> **Status:** alpha — releases worden getagd (laatste `0.1.1`, 2026-07-27). Zie
> [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) en
> [`../SECURITY.md`](../SECURITY.md) onder *Supported versions*.
>
> *(Gecorrigeerd 2026-07-28: hier stond "unreleased. No release has ever been
> tagged" — waar tot `0.1.0` op 2026-07-25, sindsdien verouderd.)*
>
> *(Gecorrigeerd 2026-07-22: deze regel luidde "pre-release (currently 0.1.0)", wat
> als een versieclaim leest en beide hierboven genoemde documenten tegensprak.)*

## Voor gebruikers

| Document | Waar het over gaat |
|---|---|
| [USER_GUIDE.md](USER_GUIDE.md) | Volledige gebruikershandleiding — elke functie, workflow en slidetype. |
| [SHORTCUTS.md](SHORTCUTS.md) | Sneltoetsen. |
| [FAQ.md](FAQ.md) | Veelgestelde vragen over functies, beveiliging en privacy. |
| [PRIVACY.md](PRIVACY.md) | Welke data lokaal blijft, wat alleen op jouw actie vertrekt, en hoe. |
| [ACCESSIBILITY.md](ACCESSIBILITY.md) | Wat toegankelijk is, en — de langere helft — wat niet. |
| [TROUBLESHOOTING_GUIDE.md](TROUBLESHOOTING_GUIDE.md) | Oplossingen voor veelvoorkomende problemen. |
| [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) | Wat er nog niet is, in één lijst, zodat je het niet één verrassing per keer tegenkomt. |
| [FILE_FORMAT.md](FILE_FORMAT.md) | Het Markdown/Marp-formaat op schijf — het stabiele contract. |

## Voor bijdragers en ontwikkelaars

| Document | Waar het over gaat |
|---|---|
| [CONTRIBUTING_GUIDELINES.md](CONTRIBUTING_GUIDELINES.md) | Hoe je bijdraagt: workflow, codestijl, testen. |
| [DEVELOPMENT_SETUP_GUIDE.md](DEVELOPMENT_SETUP_GUIDE.md) | Een ontwikkelomgeving opzetten per platform. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Systeemarchitectuur en gelaagdheid. |
| [SOURCE_MAP.md](SOURCE_MAP.md) | Waar dingen leven in `lib/`. |
| [API_DOCUMENTATION.md](API_DOCUMENTATION.md) | Belangrijke interne API's, modellen, services en providers. |
| [BUILD.md](BUILD.md) | Bouwdoelen en de versiepin. |
| [CHECKS.md](CHECKS.md) | De kwaliteitspoorten (`make check`) en wat elke afdwingt. |
| [PERFORMANCE_GUIDE.md](PERFORMANCE_GUIDE.md) | Afgedwongen grenzen, gemeten omvang en optimalisatietips. |
| [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) | Wat de app zelf migreert (instellingen), en de regels voor het toevoegen van de volgende. |

## Voor beheerders en compliance

| Document | Waar het over gaat |
|---|---|
| [HOSTING.md](HOSTING.md) | De webbuild veilig serveren (statische host, CSP-headers, fetch-proxy). |
| [SECURITY_DESIGN.md](SECURITY_DESIGN.md) | Beveiligingsprincipes en de concrete mechanismen die ze afdwingen. |
| [LICENSE_COMPLIANCE.md](LICENSE_COMPLIANCE.md) | Licentiecompliance van afhankelijkheden. |
| [SBOM.md](SBOM.md) | De Software Bill of Materials (EU CRA). |
| [SECURITY_REVIEW_APT.md](SECURITY_REVIEW_APT.md) | Een toetsing van de app tegen een gericht-aanvallersdreigingsmodel, en wat die opleverde. |
| [GLOSSARY.md](GLOSSARY.md) | OciDeck-specifieke termen op één plek. |

*(Gecorrigeerd 2026-08-30: twee documenten in deze map hadden geen regel in deze
index — `KNOWN_LIMITATIONS.md`, dat in de app is gebundeld, naar het Nederlands is
vertaald en vanaf vier andere pagina's wordt aangehaald, en `SECURITY_REVIEW_APT.md`.
Een index die stilzwijgend onvolledig is, stuurt een lezer op zoek naar iets dat er
gewoon staat.)*

## Ontwerpnotities (`design/`)

Ontwerpvoorstellen, onderbouwing en openstaand werk — historisch of vooruitkijkend, **geen**
referenties voor de huidige stand. Waar een notitie de code tegenspreekt, wint de code. Elk
van deze draagt een eigen statusbanner die zegt hoever het is ingehaald;
lees die banner eerst. Geen van deze wordt met de app meegeleverd: `docs/design/**`
staat alleen in de repo, bereikbaar via de repository-voettekst van de lezer in plaats van meegebundeld.

*(Gecorrigeerd 2026-07-31: hier stond "All eleven ship with the app". Sinds de in-app-
lezer is teruggebracht tot de gebruikers-, licentie/compliance- en gebruiksrelevante technische
documenten, worden de ontwerpnotities — en de ontwikkelaar-interne documenten — niet langer meegebundeld;
ze leven in de repository. Zie [Hoe deze documenten worden onderhouden](#hoe-deze-documenten-worden-onderhouden).)*

| Document | Wat het is |
|---|---|
| [COLLABORATION.md](design/COLLABORATION.md) | Ontwerpvoorstel, ongebouwd: realtime samenwerking, presenteren, gesprekken en een register van provider-adapters dat grote, kleinere en zelf-gehoste vergadersystemen omspant. |
| [SELF_ENCRYPTED_RELAY.md](design/SELF_ENCRYPTED_RELAY.md) | Ontwerpvoorstel, ongebouwd: de gekozen pure-Dart-route voor realtime samenwerking (COLLABORATION Fase 1) — de homeserver als versleutelde relay met OciDecks eigen minimale E2EE, geen AGPL, geen Rust, EUPL-1.2 intact. Vervangt het Matrix-SDK-mechanisme in COLLABORATION §6/§9. |
| [TEAMS_GUEST_CLIENT.md](design/TEAMS_GUEST_CLIENT.md) | Ontwerpvoorstel, ongebouwd: deelnemen aan ondersteunde Teams-werk/school-vergaderingen via een OciDeck-web/PWA-gastclient zonder een Microsoft-account. |
| [GIT_STORAGE.md](design/GIT_STORAGE.md) | Ontwerp van het git-opslagvlak; fasen 0–6 zijn geland, wat rest is verificatie. |
| [PENTEST_MIAUW.md](design/PENTEST_MIAUW.md) | Het oorspronkelijke ontwerp voor de MIAUW-pentestmodule, die wordt meegeleverd. Delen worden door de code tegengesproken. |
| [AI_ASSIST.md](design/AI_ASSIST.md) | Het optionele AI-assistentieontwerp; fasen 0–3 zijn gebouwd, fase 4 (MCP) niet. |
| [OCIWACHT.md](design/OCIWACHT.md) | Het ontwerp van de privacyscanner, **in het Nederlands**, met bovenaan een tabel per sectie van geleverd/open. Met 2.668 regels is het het grootste van de drie Nederlandse documenten. |
| [AGENTIC_BUILD_PLAN.md](design/AGENTIC_BUILD_PLAN.md) | Historisch: het agentische bouwplan voor het pentest/AI-werk. Uitgevoerd; bewaard als uitgewerkt voorbeeld, niet als wachtrij. |
| [PROCESS_IMPROVEMENT.md](design/PROCESS_IMPROVEMENT.md) | Ontwerpvoorstel, ongebouwd: een Lean Six Sigma-auteursmodule. Ondanks de naam is het een productontwerp, geen rapport over ons proces. |
| [VERIFICATION.md](design/VERIFICATION.md) | Een werklijst, in het Nederlands: wat is gebouwd en zijn eigen tests doorstaat maar nooit een echte server, een tweede besturingssysteem of een echt rapport heeft ontmoet. |
| [LEXICON_LICENTIENAVRAAG.md](design/LEXICON_LICENTIENAVRAAG.md) | Een licentiedossier, in het Nederlands: drie lexiconbronnen die de privacycontrole zouden verrijken, en waarom geen ervan al kan worden meegebundeld. |
| [OPENKAT_DISTRIBUTIE.md](design/OPENKAT_DISTRIBUTIE.md) | Ontwerpvoorstel, ongebouwd: versleutelde rapportdistributie naar een ontvanger met minimale wrijving — dubbelklikken en bekijken. De distributiekant van de OpenKAT-integratie. |

*(Gecorrigeerd 2026-07-22: deze lijst noemde zeven van de toen negen documenten in
`design/`; `VERIFICATION.md` en `LEXICON_LICENTIENAVRAAG.md` ontbraken terwijl
beide als assets in `pubspec.yaml` zijn meegebundeld en in de app leesbaar zijn. Geen test
vergelijkt de twee lijsten, dus niets ving het.)*

*(Vervolg 2026-07-31: sindsdien is de in-app-lezer teruggebracht en wordt `docs/design/**`
niet langer meegebundeld — de "in de app leesbaar"-helft van de notitie hierboven is verouderd;
deze ontwerpnotities staan nu alleen in de repo. `test/docs_registration_test.dart` bewaakt
dat ze buiten de bundel blijven.)*

## Nieuw hier?

- **Ik wil OciDeck gebruiken** → [USER_GUIDE.md](USER_GUIDE.md), daarna [FAQ.md](FAQ.md).
- **Ik wil eraan bouwen/sleutelen** → [DEVELOPMENT_SETUP_GUIDE.md](DEVELOPMENT_SETUP_GUIDE.md), daarna [ARCHITECTURE.md](ARCHITECTURE.md).
- **Ik wil de webbuild hosten** → [HOSTING.md](HOSTING.md).
- **Ik moet de beveiliging/privacy beoordelen** → [SECURITY_DESIGN.md](SECURITY_DESIGN.md) en [PRIVACY.md](PRIVACY.md).
- **Ik ben afhankelijk van hulptechnologie** → [ACCESSIBILITY.md](ACCESSIBILITY.md).
- **Ik stuit op een term die ik niet ken** → [GLOSSARY.md](GLOSSARY.md).

## Hoe deze documenten worden onderhouden

*Toegevoegd 2026-07-22.* Deze regels werden allemaal ergens gevolgd en nergens
opgeschreven, en daarom volgde slechts een minderheid van de bestanden ze. Ze staan
er nu zodat een nieuw document meteen de eerste keer goed kan.

**De code wint.** Elk document in deze map beschrijft software die sneller
verandert dan proza. Waar een document en de code het oneens zijn, heeft de code
gelijk en is het document een defect. Een bewering die je niet tegen de code kunt
toetsen hoort niet in een document — de reeks gidsen die op 2026-07-19 werd verwijderd
was overtuigend, leesbaar en beschreef niets dat bestond, en dat is de faalmodus die
deze regel probeert te voorkomen.

**De titel.** Eén `# OciDeck — <Name>`-kop, eerste regel, niets erboven.

**De masthead.** Direct onder de titel, één blockquote-regel:

```
> **Status:** … · **Status last reviewed:** YYYY-MM-DD · **Published by:** Stichting LibreKAT
```

Lees die datum nauw: hij zegt wanneer iemand voor het laatst besloot wat voor
*soort* document dit is en of die beschrijving nog klopt — een ontwerpvoorstel, een
beschrijving van de huidige stand, een procedure, een rapport, een uitgevoerd plan. Het is
bewust **niet** een claim dat elke zin op die datum opnieuw is geverifieerd. Een
document dat regel voor regel is nagelopen zegt dat in zijn eigen woorden, zoals
`design/PENTEST_MIAUW.md` en `design/AI_ASSIST.md` dat doen voor de delen ervan die
zijn nagelopen.

De uitgever is **Stichting LibreKAT**, die het auteursrecht houdt. Er is een
beveiligingscontact; het staat in [`../SECURITY.md`](../SECURITY.md) en het wordt
bewust niet in deze map herhaald — zie *Voorbeelden* hieronder.

**Correcties dragen een datum, in de tekst.** Wanneer je een bewering die fout was
herstelt, zeg dat dan waar hij fout was in plaats van alleen in de commitboodschap:

```
*(Corrected 2026-07-22: this said X. It says Y because …)*
```

Een lezer die de oude bewoording onthoudt moet weten dat die veranderde en waarom; een
reviewer moet zien dat iemand heeft gekeken. Samen vormen deze notities de
wijzigingsgeschiedenis van deze map, dus laat de oude staan.

**Verwijs naar symbolen, niet naar regelnummers.** Citeer `maxPackageBytes` of
`resolveSlideAssetPath`, nooit "regel 412" — de naam overleeft een refactor en het
nummer niet.

**Een getal heeft een datum nodig of het moet weg.** Elke telling die met de
codebase meegroeit — tests, bronbestanden, packages, catalogus-items — is een meting.
Geef het de dag waarop het is gemeten, zoals [CHECKS.md](CHECKS.md) en
[LICENSE_COMPLIANCE.md](LICENSE_COMPLIANCE.md) doen, of laat het weg. Een ongedateerd
getal is er een waarvan niemand kan zien dat het is verouderd.

**Een nieuw document registreren.** De app bundelt een *gecureerde* subset van `docs/`,
niet alles eronder: de gebruikersdocumenten, licentie/compliance, en de technische
documenten die van belang zijn voor het gebruiken en draaien van OciDeck. De ontwikkelaar-interne
documenten (architectuur, build, checks, source map, API, bijdragen, dev-setup) en elke
`docs/design/**`-spec staan alleen in de repo. `test/docs_registration_test.dart` laat
`make check` falen tenzij een nieuw `docs/*.md` netjes aan één kant van die scheiding landt.

Een nieuw `docs/*.md` **staat standaard in de bundel**, dus een gebundeld document moet
op drie plekken bekend zijn:

1. de assetlijst in `pubspec.yaml`;
2. een lezer-tegel in `lib/widgets/dialogs/parts/settings_dialog_docs.dart`;
3. een titel vertaald naar **elke** ondersteunde taal.

Dat derde is echt werk, dus denk twee keer na voor je een bestand toevoegt: in de meeste gevallen
hoort het materiaal in een document dat al bestaat. Als het document
ontwikkelaar-intern is in plaats van iets waar een gebruiker naar grijpt, maak het dan repo-only
— voeg het toe aan `repoOnlyDocs` in de test (en laat het weg uit de assetlijst
en de lezer), of zet het onder `docs/design/`, dat integraal repo-only is
en geen testwijziging nodig heeft. Een `NAME.<lang>.md`-vertaling van een bestaand
document is de uitzondering — die wordt automatisch opgepikt en mag *geen* eigen
assetregel of tegel krijgen.

**Voorbeelden moeten onmiskenbaar verzonnen zijn.** Deze documenten worden met de app
meegeleverd, en de privacyscanner leest de hele map als één document. Eén enkele
echt ogende waarde — een burgerservicenummer, een IBAN, een werkend e-mailadres,
een aannemelijk telefoonnummer — escaleert elke bijzondere-categoriebevinding in
dat bestand, ook in tekst die er al jaren staat. Gebruik waarden die
overduidelijk fictief zijn, en houd werkende contactadressen in de root-documenten,
die niet worden meegebundeld.

## Licentie

OciDeck wordt uitgebracht onder de **EUPL-1.2**. Bijdragen worden onder dezelfde
licentie aanvaard.
