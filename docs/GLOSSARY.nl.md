> 🤖 Machinevertaling — het Engelse bronbestand is leidend.
>
> _Machine translation — the English source document is authoritative. _

# OciDeck — Woordenlijst

> **Status:** reference, current · **Status laatst nagekeken:** 2026-07-22 · **Uitgegeven door:** Stichting LibreKAT

OciDeck-specifieke termen en de afkortingen die steeds terugkomen in de codebase en
docs. Voor waar dingen leven in `lib/`, zie [SOURCE_MAP.md](SOURCE_MAP.md).

## Kernbegrippen

**OciDeck** — een privacy-eerst Marp-presentatiebouwer voor desktop en web, zonder
applicatie-backend; alle verwerking gebeurt lokaal.

**Deck** — een volledige presentatie: metadata, een geordende lijst van slides, een
themaprofiel en een TLP-classificatie. Onveranderlijk model (`lib/models/deck.dart`).

**Slide** — één onveranderlijke, sterk getypeerde slide. Zijn `SlideType` (31 waarden)
kiest de layout: `title`, `section`, `bullets`, `twoBullets`, `bulletsImage`,
`twoImages`, `image`, `video`, `quote`, `table`, `freeMarkdown`, `code`, `chart`,
`cockpit`, `question`, `timeline`, `scorecard`, `menu` (niet-lineair keuzemenu, #1162), de pentest-layouts (`assets`,
`discoveries`, `finding`, `findingsSummary`, `checklist`, `scopeMatrix`,
`signOff`), de Procesverbetering-layouts (`matrix`, `canvas`, `tree`,
`flow`, `phaseGate`) en de Managementsysteem-layout (`controlStatus`). De zeven
informatiebeveiligings-layouts blijven verborgen totdat die module is ingeschakeld; `matrix`,
`canvas`, `tree`, `flow` en `phaseGate` volgen dezelfde auteurspoort voor
Procesverbetering, en `controlStatus` voor de Managementsysteem-module. *(Gecorrigeerd
2026-07-29: Fase 7 voegt `phaseGate` toe; 2026-08-02: de Managementsysteem-module
voegt `controlStatus` toe; aantal bewaakt door `test/docs_enum_counts_test.dart`.)*

**Marp** — het open Markdown-voor-presentaties-formaat dat OciDeck leest en schrijft.
Decks blijven dicht bij gewone Marp-Markdown, zodat ze samenwerken met andere Marp-
tools. Zie [FILE_FORMAT.md](FILE_FORMAT.md).

**Themaprofiel** — kleuren, lettertypen, logo en voettekstinstellingen voor een deck. Gedeeld
als een `.ocideckstyle`-bestand. Visuele overrides per slide leven op de slide zelf.

**Cockpit** — een dashboardachtige slide met maximaal zes vlieginstrumenten. Zijn
authentieke uiterlijk is de standaard; de eerdere klassieke kaarten blijven selecteerbaar in
de app-instellingen. Het deck bewaart de meterstanden en het activeringsgedrag per slide,
niet het globaal gekozen uiterlijk of het semantische kleurenschema.

**Presentatormodus** — de presentatieweergave met twee schermen: presentatornotities, timer
en bediening op het ene scherm; de volledige slide op het andere (desktop).

**Vraagsoort** — welke van de zes vormen een `question`-slide aanneemt:
meerkeuze, waar/onwaar, meerdere-juist, ordenen, beeldpaar (twee afbeeldingen,
kies er één) of open tekst (de kijker typt). Opgeslagen als `kind` in het `question`-
blok van de slide binnen de hekken.

**Jaro-Winkler** — de maat voor tekstovereenkomst (`lib/utils/jaro_winkler.dart`)
achter de open-tekst-vraagsoort: hij scoort hoe dicht een getypt antwoord bij een
geaccepteerd antwoord ligt, zodat een typefout niet fout wordt gerekend terwijl een ander woord dat wel is. De
auteur stelt de drempel per vraag in.

**Repetitieronde** — één gemeten doorloop door een deck in de presentator: totale tijd
tegenover een optioneel doel, tijd per slide en elke beantwoorde vraagpoging.
Alleen voor de sessie; er wordt niets naar schijf of in de `.md` geschreven.

## Bestanden & opslag

**`.ocideck`** — een enkelbestandspakket (zip) dat een deck en zijn assets bundelt; kan
met een wachtwoord versleuteld worden.

**`.ocideckstyle`** — een deelbaar thema-/stijlprofielbestand.

**Forge** — een git-hostingdienst waarmee OciDeck via REST kan praten (Gitea/Forgejo,
GitHub, GitLab). De git-backend is "WebDAV met versiegeschiedenis" — dezelfde bronvorm
plus commits, tags en een versiekiezer.

**Fetch-proxy** — een klein optioneel serverzijdig eindpunt (`fetch-proxy?url=…`) dat de
**web**-build gebruikt om URL's op te halen die browser-CORS anders zou blokkeren. Het
past dezelfde SSRF-regels toe als NetGuard. Zie [HOSTING.md](HOSTING.md).

## Privacy & classificatie

**OciWacht** — de ingebouwde privacyscanner van OciDeck. Hij detecteert persoonsgegevens
(e-mail, telefoon, IBAN, BSN en nationale identificatienummers die alle 27 EU-lidstaten
dekken — sommige via een gedeelde regel, omdat Tsjechië en Slowakije en Estland en
Litouwen elk een nummerformaat delen — plus IJsland, Liechtenstein, Noorwegen,
Zwitserland en twee VK-nummers, adressen, namen, geheimen) en
kan het markeren of redigeren. Naamdetectie is bewust geen NER (zie
[design/OCIWACHT.md](design/OCIWACHT.md)). *Gecorrigeerd 2026-07-22: hier stond 13
lidstaten, wat de stand was voordat de latere Europese batches landden;
[PRIVACY.md](PRIVACY.md) draagt dezelfde correctie.*

**TLP (Traffic Light Protocol)** — het classificatieschema voor delen: `CLEAR`,
`GREEN`, `AMBER`, `AMBER+STRICT`, `RED` (plus een niet-ingesteld `none`). OciDeck kan
bij export een vrijgaveplafond afdwingen.

**Achtergehouden (withheld)** — een slide waarvan het eigen TLP-niveau strenger is dan dat
van het deck, zodat hij het publiek niet bereikt wanneer je presenteert, exporteert of inpakt
(`slideWithheldByTlp`). Niet hetzelfde als **overgeslagen**: overslaan is een keuze die de
auteur op die slide maakte, achterhouden volgt uit de classificatie. De
editor markeert de twee juist daarom verschillend.

**Dispositie** — een privacybeslissing per slide voor een scannerbevinding
(`warn`, `accept`, `shield`, `redact`).

**Projectie** — de transformatie die een bron-`Deck` omzet in een
**AudienceDeck** voor een specifiek publiek, met toepassing van redactie. `forAudience`
respecteert disposities per slide; `forExternalProcessing` is strenger (redigeert
alles wat gevonden is).

**AudienceDeck** — een deck dat door een privacyprojectie is gegaan. Zijn
constructor is privé, zodat alleen de projectie er een kan produceren; exportoppervlakken
moeten een `AudienceDeck` accepteren, nooit een kaal `Deck` — een grens die tijdens
het compileren wordt afgedwongen.

**Redactiemanifest** — het register van wat er uit een verzegeld deck is geredigeerd, zodat een
geredigeerde export tegen zijn bron kan worden geverifieerd zonder een vals sabotage-alarm.
Het wordt weggeschreven als twee bestanden naast de export: `<name>-redactions.json`, dat mee
mag reizen met het rapport, en `<name>-redaction-keys.json`, dat de zouten bevat
en bij de bron blijft — de scheiding daartussen is wat een
commitment onomkeerbaar houdt. Zie FILE_FORMAT.md §12.

**Documentzegel** — een SHA-512-hash over de **bytes van het `.md`-bestand van een deck**,
ernaast vastgelegd in `<name>.seal.json` samen met de zichtbare handtekening.
Geeft sabotage-bewijs voor afgeronde documenten, en — omdat het zegel buiten
het bestand zit dat het dekt — laat een ontvanger het herberekenen met alleen `sha512sum`.
Zie FILE_FORMAT.md §6.6.

## Beveiligingsmechanismen

**NetGuard** — de SSRF-bewaker (`lib/utils/net_guard.dart`): wijst interne/
private/metadata-adressen af, pakt IPv4-in-IPv6 uit en resolvet-dan-pint om
DNS-rebinding te verslaan.

**SecretStore** — opslag van geheimen in de OS-sleutelbos (WebDAV-wachtwoord, S3 secret
access key, AI API-sleutel, git-token) via `flutter_secure_storage`. Het S3-access-
key-*ID* is hier geen geheim — het blijft in het prefs-domein bij het eindpunt
en de bucketnaam.

**trustedInternal** — een expliciete opt-in per verbinding waarmee een door de gebruiker gekozen
interne server de private-range-blokkade omzeilt (en gewoon `http` mag gebruiken). Nooit
van toepassing op URL's die het deck aanlevert.

**SBOM** — Software Bill of Materials (CycloneDX + SPDX), de afhankelijkhedeninventaris
zoals beschreven in de EU-CRA — vrijwillig aangehouden, niet als verplichting. Zie
[SBOM.md](SBOM.md).

**CRA** — de EU **Cyber Resilience Act** (Verord. (EU) 2024/2847). Hier gebruikt als
richtlijn voor hoe goede praktijk eruitziet, niet als nalevingsclaim; zie
`assurance/CRA-2024-2847-positie.md`.

## Pentestmodule (MIAUW)

**MIAUW** — *Methodiek voor Informatiebeveiligingsonderzoek met Auditwaarde*, de
Nederlandse methodiek voor beveiligingstesten met auditwaarde. De opt-in-module
"Informatieveiligheid" van OciDeck ondersteunt het opstellen van pentestrapporten daarnaar. Zie
[design/PENTEST_MIAUW.md](design/PENTEST_MIAUW.md).

**Finding** — een slidegroep voor een beveiligingskwestie (kop + detail + bewijs) die
één finding-id deelt.

**Scope matrix / Sign-off** — pentestrapport-layouts: de geteste scope, en de
formele aanvaardings-/sign-off-pagina.

**CWE** — MITRE's *Common Weakness Enumeration*. OciDeck bundelt de volledige CWE-lijst
offline voor de kiezer van de finding-editor.

**CVE** — *Common Vulnerabilities and Exposures*. OciDeck kan een lokale,
offline CVE-database bouwen (desktop) en erin zoeken.

**CVSS** — *Common Vulnerability Scoring System* (v4), gebruikt om findings te scoren.

**WSTG** — de OWASP *Web Security Testing Guide*, gebundeld als referentiecatalogus.

## Bouw & kwaliteit

**`make check`** — de vereiste lokale poort: format, statische analyse, conventies,
methodelengte, dode code, en de testsuite met de dekkingsvloer. Zie
[CHECKS.md](CHECKS.md).

**Ratchet** — een basislijn die alleen omlaag kan (bijv. maximale bestandslengte 1000, maximale methode-
lengte 150): bestaande plekken boven de limiet zijn onder overgangsrecht toegestaan maar mogen alleen krimpen, en
er zijn geen nieuwe overtredingen toegestaan.

**Dekkingsvloer** — de minimaal afgedwongen regeldekking (momenteel **80 %**).
