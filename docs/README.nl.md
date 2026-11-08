> 🤖 Machinevertaling — het Engelse bronbestand is leidend.
>
> _Machine translation — the English source document is authoritative. _

# OciDeck — Documentation

> **Status:** index van deze map, actueel · **Status laatst nagekeken:** 2026-11-08 · **Uitgegeven door:** Stichting LibreKAT

OciDeck is een privacy-eerst Marp-presentatiebouwer voor desktop en web, zonder
verplichte bewerkingsbackend. Optionele integraties benaderen gekozen diensten. Deze map bevat de projectdocumentatie.
Begin hier en spring naar wat je nodig hebt.

> **Status:** alpha — releases worden getagd; de releases-feed op de forge
> draagt de nieuwste. Zie
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
| [TRANSCRIPTION_SETUP.md](TRANSCRIPTION_SETUP.md) | Opname en transcriptie per platform: rechten, modellen, serverroutes en het bewijs achter elke claim. |
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
| [RELEASE_OPERATIONS.md](RELEASE_OPERATIONS.md) | Releasekanalen afzonderlijk bedienen, stoppen en hervatten; publicatiebewijs. |
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

| Document | Wat het beschrijft |
|---|---|
| [AGENTIC_BUILD_PLAN.md](design/AGENTIC_BUILD_PLAN.md) | Historisch uitgevoerd bouwplan voor pentest- en AI-werk. |
| [AI_ASSIST.md](design/AI_ASSIST.md) | AI-ontwerp: fasen 0–3 gebouwd; MCP-fase 4 niet gebouwd. |
| [COCKPIT_LAYOUT.md](design/COCKPIT_LAYOUT.md) | Geïmplementeerde ontwerprationale voor meters, uitlezingen en labels. |
| [COLLABORATION.md](design/COLLABORATION.md) | Deels gebouwd: samenwerkingskern en WebDAV-transport; dit transport is niet eind-tot-eind versleuteld. Versleutelde relay en andere adapters blijven ontwerp. |
| [DOCUMENT_MODE.md](design/DOCUMENT_MODE.md) | Ontwerp en implementatierecord van documentmodus; actuele werking staat in de gebruikersgids. |
| [ELEARNING_MODEL.md](design/ELEARNING_MODEL.md) | eLearning-domeinmodel en OciServe-contract; ontwerpen en serverintegratie zijn afzonderlijk. |
| [FORM_INTAKE.md](design/FORM_INTAKE.md) | Deels gebouwd: fasen 1–3, de bestands- en age-route. Managed Intake heeft een afzonderlijk providercontract; de eerdere blinde server is teruggedraaid. |
| [FORM_INTAKE_REVIEW.md](design/FORM_INTAKE_REVIEW.md) | Dossier voor externe cryptografische review; geen verklaring dat die review al is afgerond. |
| [GANTT_SLIDETYPE.md](design/GANTT_SLIDETYPE.md) | Geïmplementeerd Gantt-diatype met een Markdown-tabel en gegenereerde Mermaid. |
| [GIT_STORAGE.md](design/GIT_STORAGE.md) | Git-opslagontwerp: fasen 0–6 gebouwd, met resterende verificatie. |
| [IMAGE_CALLOUTS.md](design/IMAGE_CALLOUTS.md) | Geïmplementeerde afbeeldingsaanwijzingen; formaatcontract en gedeelde geometrie. |
| [IMAGE_ROTATION.md](design/IMAGE_ROTATION.md) | Gebouwde kopieer-bij-roteren aanpak die het oorspronkelijke bestand behoudt. |
| [ISO_MANAGEMENTSYSTEEM.md](design/ISO_MANAGEMENTSYSTEEM.md) | Gebouwde blokken A–C voor ISO 27001/9001/42001-voortgang. |
| [LEXICON_LICENTIENAVRAAG.md](design/LEXICON_LICENTIENAVRAAG.md) | Licentiedossier van lexiconbronnen; geen toestemming om ze te bundelen. |
| [LINUX_PACKAGING.md](design/LINUX_PACKAGING.md) | Gebouwde fase 1: AppImage-, deb- en rpm-installatieroutes. |
| [NATIVE_CALLS.md](design/NATIVE_CALLS.md) | Deels gebouwd: tweepersoonsgesprekken bewezen op macOS en web; Windows en Linux niet getest. |
| [OCIWACHT.md](design/OCIWACHT.md) | Privacyscannerontwerp met tabel van geleverd en open werk. |
| [OPENKAT_DISTRIBUTIE.md](design/OPENKAT_DISTRIBUTIE.md) | Nog niet gebouwd ontwerp voor versleutelde rapportdistributie. |
| [OPENKAT_LIVE_UX.md](design/OPENKAT_LIVE_UX.md) | Ontwerpbijlage over de gebruikerskant van de live OpenKAT-integratie. |
| [OPENKAT_ROCKY_REPORT_API.md](design/OPENKAT_ROCKY_REPORT_API.md) | Onderzoek en ontwerpcontract voor Rocky-rapporten via API en JSON-export. |
| [OPENKAT_ROCKY_REPORT_API.nl.md](design/OPENKAT_ROCKY_REPORT_API.nl.md) | Nederlandse versie van het Rocky-API-onderzoek en ontwerpcontract. |
| [PENTEST_DOCUMENT.md](design/PENTEST_DOCUMENT.md) | Nog niet gebouwd ontwerp voor pentestrapporten als document en afgeleide presentaties. |
| [PENTEST_MIAUW.md](design/PENTEST_MIAUW.md) | Oorspronkelijk ontwerp van de geleverde MIAUW-module; deels door code achterhaald. |
| [PROCESS_IMPROVEMENT.md](design/PROCESS_IMPROVEMENT.md) | Geïmplementeerde Lean Six Sigma-module, met beperkingen per fase. |
| [PROVENANCE_SIGNATURE.md](design/PROVENANCE_SIGNATURE.md) | Deels gebouwd: formaat, cryptografie en service; de ondertekeningsinterface is nog niet gebouwd. |
| [RISK_FORMAT.md](design/RISK_FORMAT.md) | Formaatcontract en ontwerprationale voor risicoregisters. |
| [SELF_ENCRYPTED_RELAY.md](design/SELF_ENCRYPTED_RELAY.md) | Nog niet gebouwde eind-tot-eind versleutelde relay; huidige WebDAV-samenwerking heeft deze bescherming niet. |
| [TEAMS_GUEST_CLIENT.md](design/TEAMS_GUEST_CLIENT.md) | Nog niet gebouwd ontwerp voor een Teams-gastclient. |
| [TRANSCRIPTION.md](design/TRANSCRIPTION.md) | Ontwerpcontract met geleverde implementatie; actuele inrichting en bewijsgrenzen staan in TRANSCRIPTION_SETUP.md. |
| [VERIFICATION.md](design/VERIFICATION.md) | Werklijst van gebouwd gedrag waarvoor praktijkverificatie nog ontbreekt. |
| [XMPP_COLLAB_TRANSPORT.md](design/XMPP_COLLAB_TRANSPORT.md) | Nog niet gebouwd XMPP-datatransport voor samenwerking; afzonderlijk van gesprekken. |

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

*(Documentatieronde 2026-11-08: links, registratie, versieclaims, platformopslag,
toestemming, DLP en ontwerpstatus zijn naast de huidige code gelegd. Historische
metingen en beoordelingen blijven gedateerde verslagen; deze ronde is geen
nieuwe externe veiligheids- of compliancebeoordeling.)*

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
