# ENISA Secure by Design & Default — afbeelding op de poorten

> **Status:** vastgesteld 2026-07-31 · Stichting LibreKAT · intern werkdocument
>
> Geen conformiteitsclaim en geen auditrapport. Zie [`README.md`](README.md) voor
> waarom dit niet in `docs/` staat.

## Waarom dit dossier bestaat

De [ENISA Secure by Design and Default Playbook](https://github.com/enisaeu/enisa-sbd-playbook)
(v0.4, consultatieversie) is geen leesstuk maar een werkinstrument: 22 playbooks,
elk met een principe, een checklist, een **minimum evidence**-set en een
**release gate** — een afvinklijst die je in je pre-release-review plakt. Dat is
precies de vorm die dit project zelf hanteert: **gedrag dat een poort afdwingt,
niet een belofte die je opschrijft.** Een ENISA-release-gate is conceptueel een
`make check`-deelpoort.

Daarom is de nuttige gebruiksvorm hier niet "een document dat claimt dat we
Secure by Design doen" — dat botst met de vaste lijn uit [`README.md`](README.md)
en met de [CRA-positie](CRA-2024-2847-positie.md). De nuttige vorm is: **de 22
release gates als toetslijst tegen de bestaande poorten leggen.** Waar een poort
het al afdwingt, is dat het antwoord. Waar niet, is er ofwel een reden dat het
hier geen onderwerp heeft, ofwel een open gat. Zoals overal in dit dossier is de
**motivering het waardevolle deel**, niet de telling.

## Verhouding tot de CRA-positie

ENISA mapt de 22 principes zelf op CRA Annex I. Dit project heeft die CRA-map al:
[`CRA-2024-2847-positie.md`](CRA-2024-2847-positie.md) meet tegen Annex I deel I
(producteisen) en deel II (kwetsbaarhedenbeheer). **Dit dossier vervangt dat niet
en herhaalt het niet** — het is de fijnmazige laag eronder: waar de CRA-tabellen
één regel per producteis geven, geven de 22 playbooks een engineeringpraktijk met
een afvinkbare gate. Waar beide hetzelfde punt raken, wordt naar de CRA-positie
of het ASVS-dossier verwezen in plaats van het argument over te schrijven.

## De twee poorten waar dit op landt

Een ENISA-release-gate veronderstelt één moment vóór uitgifte. OciDeck kent er
twee, en trekt het meeste naar het eerste:

- **Samenvoegpoort — `make check`** (elke commit/PR). `STATIC_GATES` +
  `coverage` + `coverage-per-file`. De altijd-aan-vloer: opmaak, `analyze
  --fatal-infos`, toolchain, conventies, de compileertijd-privacygrens,
  methodelengte, dode code, hardgecodeerde tekst, dekkingsvloer.
- **Uitbreide poort — `make check-full`** en per-PR op de forge
  (`.forgejo/workflows/scans.yml`). `check-secrets`, `sast`, `licenses`,
  `sbom-verify`, `deps-check`, `check-web`.
- **Uitbrengpoort — `make check-release`** (met de hand vóór een `v*`-tag).
  `check-full` plus de adviserende `dast` (OWASP ZAP).

Het punt om te onthouden: het meeste dat ENISA pas bij *release* toetst, staat
hier al op de *samenvoeg*poort. De afbeelding hieronder noemt per regel de poort
of het bestand dat hem draagt.

## Legenda voor het oordeel

| Oordeel | Betekenis |
|---|---|
| **Afgedwongen** | Een poort of test faalt de bouw als het niet klopt. |
| **Sterk (niet-poort)** | Aanwezig en streng, maar geborgd door ontwerp/documentatie, niet door een falende bouw. |
| **Deels** | Kern is er; één afvinkregel uit de gate mist of is n.v.t. |
| **Buiten scope** | Heeft in een lokaal-eerste editor zonder accounts/server geen onderwerp; mét reden. |
| **Open** | Een echt gat. Verzameld onder [De open punten](#de-open-punten). |

Verwijzingen zijn naar **bestandsnaam plus symbool**, nooit naar een regelnummer
(huisregel uit [`README.md`](README.md)).

---

## Secure by Design — Architectural Foundations (01–06)

| # | Playbook | Oordeel | Anker in OciDeck | Motivering / open |
|---|---|---|---|---|
| 01 | Trust boundaries & threat modelling | **Sterk (niet-poort)** | `docs/SECURITY_DESIGN.md` §Threat model (7 rijen, elk met restrisico + aanvaardingsdatum); `assurance/risicoafweging.md` (R1–R10); vertrouwensgrenzen ook in `docs/design/GIT_STORAGE.md`, `AI_ASSIST.md` | Model bestaat, gebruikt "trust boundary" expliciet en is per grens getoetst (`network_sink_guard_test`, `git_network_guard_test`, `privacy_scan_redact_parity_test`, de SSRF-serie in `AUDIT_RESPONSE.md`). Wat mist is de **verversingstrigger** uit de gate: er is geen automatische prikkel die bij een nieuwe interface om herziening vraagt. Zie [open punt O2](#de-open-punten) (#1015). |
| 02 | Least privilege | **Deels** | OS-sleutelbos voor geheimen (`SECURITY_DESIGN.md` §13); git-subproces met `includeParentEnvironment:false`, lege `HOME`, `GIT_CONFIG_NOSYSTEM=1` (`GitCliIo`); default-deny netwerk (`NetGuard`) | Geen serverrollen, geen gedeelde productie-adminsleutels — omdat er geen server en geen accounts zijn. De gate-regel "geautomatiseerde autorisatietests" heeft geen onderwerp: `ClassificationEnforcementPolicy` is datagovernance, geen autorisatie (zie [`ASVS-5.0.0-scope.md`](ASVS-5.0.0-scope.md) V8). Wat wél geldt — geheimen, subproces, default-deny — is streng. |
| 03 | Strong identity & authentication | **Buiten scope** | — | Geen accounts, geen inlog, geen sessie, geen identity provider (zie `ASVS-5.0.0-scope.md` V6/V7). De enige credential is een door de gebruiker geplakt git-token, in de OS-sleutelbos. Er is geen identiteitsdomein om te harden. |
| 04 | Attack surface minimisation | **Afgedwongen** | `make check-web` (`tool/check_web_hardening.dart`); `check-dead-code`; `check-conventions` (verbiedt `print()`); de beveiligingsmodule is een schakelaar over ingebakken catalogi zonder netwerkuitgang | Productiebouw is minimaal; wees interfaces zijn de webbundel (gehard) en niets meer. Geen diagnostische gereedschappen in release. |
| 05 | Defence in depth | **Afgedwongen** | `NetGuard` (SSRF-classificatie → resolve-then-pin → certificaatpin → poort-allowlist), `MarkdownSafetyScanner` (fail-closed vóór het parsen), `PrivacyProjection` + compileertijdgrens (`check-audience-boundary`) | Kritieke activa hebben meer dan één onafhankelijke laag. De gate-regels over "logging op meerdere lagen" en "alerts" hebben geen onderwerp: één logafvoer, geen SIEM (zie [`ASVS-5.0.0-afwijkingen.md`](ASVS-5.0.0-afwijkingen.md) V16). |
| 06 | Open design | **Afgedwongen** | Volledig openbaar; `semgrep/ocideck.yaml` verbiedt een eigen `badCertificateCallback` buiten `net_guard.dart`; geen eigen crypto (SHA-512-zegel op standaardprimitieven); `make sbom-verify`; meldkanaal `security.txt` + `tool/check_service_norms.dart` | Geen beveiliging-door-onbekendheid; dat is een kernwaarde, niet een maatregel. |

De scope-out bij **03** is de scherpste van de zes en volgt rechtstreeks uit het
ASVS-dossier: zonder sessie, token of inlogstaat missen álle
identiteits-playbooks hun onderwerp. Datzelfde argument keert terug bij 16, 18 en
19 hieronder — het is telkens dezelfde afwezigheid.

## Secure by Design — Operational Integrity (07–14)

| # | Playbook | Oordeel | Anker in OciDeck | Motivering / open |
|---|---|---|---|---|
| 07 | Life-cycle management | **Deels** | EOL-beleid in `SECURITY.md` (≥3 maanden aanzegging); `make deps-check` (OSV) + `make sbom`; `DiskTraces` voor buitenbedrijfstelling; aanvaarde restrisico's met eigenaar in `risicoafweging.md` + `AUDIT_RESPONSE.md` | Sterk op EOL, SBOM en restrisico. De gate-regel "secure update path" is **bewust afwezig** — zie 20. |
| 08 | User-centric design | **Deels** | Veilige standaard (netwerk uit, module uit); `certificate_trust_dialog.dart`; OciWacht-bevindingen gemaskeerd getoond; `check-hardcoded-text` (elke zichtbare tekst via `l10n.d()`, dus vertaalbaar en te herschrijven); toetsing via de `gebruikerstest`-agent | Geen standaard-adminwachtwoord (n.v.t.). Beveiligingswaarschuwingen zijn handelingsgericht. |
| 09 | Secure coding & verification | **Afgedwongen** | `make sast` (semgrep, per-PR), `make check-secrets` (gitleaks + trufflehog `--no-verification`, per-PR), `make sbom`, `analyze --fatal-infos`, dekkingsvloer, rood-één-keer-conventie (`PULL_REQUEST_TEMPLATE.md`) | Bijna 1:1 met de gate. Twee kanttekeningen, geen van beide een openstaand gat: **CODEOWNERS ontbreekt**, maar de peer-review op de gevoelige modules is al belegd bij de enige onderhouder (`CONTRIBUTING.md` benoemt de busfactor-één) en wordt geschraagd door de semgrep-grendels rond `net_guard`, `Process.run`-inperking en secret-RNG; een `CODEOWNERS`-bestand formaliseert dat pas zinvol zodra een tweede onderhouder toetreedt (waar CONTRIBUTING de "self-merge stopt"-regel al aan hangt). En het mutatietesten is smal en handmatig (`make mutate`, één operator, niet in `check`) — al gevolgd in de CRA-positie. |
| 10 | Logging, monitoring & alerting | **Buiten scope** | `lib/utils/log.dart` (één afvoer, `dart:developer`); `_safeError` houdt deckinhoud uit de log; weigeringen van `TabsProvider`/`GitCliIo`/`ExportService` laten een spoor zónder inhoud | Geen logverwerker, geen SIEM, geen tweede machine — centralisatie en alerting missen hun onderwerp (zie `ASVS-5.0.0-afwijkingen.md` V16.2.4/16.4.2/16.4.3). De **privacy**kant van logging is juist streng: bijzondere persoonsgegevens mogen niet in een log echoën. |
| 11 | Configuration & change management | **Afgedwongen** | Alles in git + DCO (`dco.txt`, `PULL_REQUEST_TEMPLATE.md`); `test/pinned_versions_manifest_test.dart` (harde pin-poort) + `.github/pinned-ci-versions.json`; `make check-toolchain` | Sterk op versiebeheer, pins en toolchain-basislijn. De gate-regel "dev/test/prod gescheiden" heeft geen onderwerp: er is geen IaC en geen productieomgeving. |
| 12 | Incident response & recovery | **Deels** | `SECURITY.md` (rollen, escalatieadres `security@librekat.nl`, runbook detect→reproduce→tracker); SLA gemeten door `tool/check_service_norms.dart` (5/10/90 werkdagen); herstel via git-opslag + crash-recovery-snapshot | Intern proces bestaat en wordt gemeten. De **externe meldroute** (CSIRT/ENISA) is géén openstaand gat: die hoort bij een fabrikants- of rentmeestersplicht, en [`CRA-2024-2847-positie.md`](CRA-2024-2847-positie.md) §artikel 24 concludeert dat geen van beide op LibreKAT rust. Komt die rol ooit alsnog, dan is het een adres en een afspraak — zie daar. |
| 13 | Vulnerability & patch management | **Deels** | `make deps-check` (OSV over de gebundelde JS), `make sbom`, `make sast`, `make check-secrets`; triage vastgelegd in `risicoafweging.md`, `AUDIT_RESPONSE.md`, CHANGELOG; fix staat op `main` zodra gemerged | Proces en JS-graaf gedekt. Open: de **Dart-afhankelijkheidsgraaf** wordt niet automatisch afgezocht — Trivy draait adviserend, niet als poort (#517). |
| 14 | Supply chain controls | **Afgedwongen** | `make sbom` (CycloneDX 1.6 + SPDX 2.3) + `sbom-verify`-poort + `test/sbom_test.dart`; leveranciersweging in `ketenkeuring-matrix-sdk.md` / `-rust-sdk.md` (GO/NO-GO); build-secrets minimaal in de workflows | Een uitschieter. **Artefactondertekening is asymmetrisch** — macOS is Developer-ID-getekend + genotariseerd (`scripts/notarize_macos.sh`), Windows en Linux leunen op `SHA256SUMS` (geen handtekening; `SECURITY.md` §"Release artifact integrity and signing", `docs/BUILD.md`). Windows is na weging **bewust zo gelaten** (#1013, gesloten — SmartScreen-reputatie is sinds maart 2024 certtype-onafhankelijk en downloadvolume-gebonden, en elke betaalde route kost óf een hardware-token óf een secret in de release-runner); Linux blijft open (#1014). Provenance/SLSA is niet geformaliseerd. Zie [open punt O1](#de-open-punten). |

## Secure by Default — Default Hardening (15–18)

| # | Playbook | Oordeel | Anker in OciDeck | Motivering / open |
|---|---|---|---|---|
| 15 | Minimisation of default services | **Afgedwongen** | Netwerk staat standaard uit (`NetGuard`, `SECURITY_DESIGN.md` §3); de beveiligingsmodule is een uit-standaard schakelaar over ingebakken catalogi | Alleen kernfunctionaliteit staat standaard aan; optionele diensten zijn uit tot de gebruiker ze aanzet. |
| 16 | Restrictive initial access | **Buiten scope** | — | Geen gedeelde of standaardcredentials omdat er geen credentials-model is; geen device-provisioning; één lokale gebruiker. Voor de optionele fetch-proxy geldt "geen standaardaccounts" wél (zie `ASVS-5.0.0-scope.md` V6.3.2). |
| 17 | Secure communication by default | **Afgedwongen** | `NetGuard.maySendReusableSecret` (herbruikbaar geheim alleen over HTTPS of letterlijke loopback), certificaatpinning (`connectPinned`, pint IP maar valideert TLS tegen de hostnaam), fail-closed bij verbindingsfout | Geen onveilige terugval. De ene uitzondering — plat HTTP naar een als "vertrouwd intern" gemarkeerd S3-endpoint — is een **gedocumenteerde afwijking** met SigV4-motivering (`ASVS-5.0.0-afwijkingen.md` V12), geen omissie. |
| 18 | Unique device identity & secrets by default | **Deels** | OS-sleutelbos, nooit in voorkeuren (`SECURITY_DESIGN.md` §13); secrets-scanning bewijst dat er geen ingebakken geheimen zijn; `semgrep`-regel dwingt `Random.secure()` af voor secret-benoemde variabelen; SSH-commit-ondertekening optioneel (`GIT_STORAGE.md` §14) | De regels over een unieke cryptografische identiteit **per device** hebben geen onderwerp — er is geen device-vloot. De secret-hygiëne die wél geldt, is streng afgedwongen. |

## Secure by Default — Guided Protection (19–22)

| # | Playbook | Oordeel | Anker in OciDeck | Motivering / open |
|---|---|---|---|---|
| 19 | Mandatory security onboarding | **Buiten scope** | — | Er is geen beveiligingsinstelling die de gebruiker vóór gebruik moet doorlopen: de veilige stand ís de standaardstand (netwerk uit, geen accounts). Er valt niets verplicht in te stellen en dus niets af te dwingen vóór "normaal bedrijf". |
| 20 | Automated maintenance & updates | **Buiten scope (bewuste keuze)** | `SECURITY.md` §"There is no update mechanism" (de app belt nooit naar huis, controleert nooit op een nieuwere versie); macOS-installer genotariseerd; Windows/Linux via `SHA256SUMS` | De afwezigheid van een auto-updater is een **expliciet ontwerpbesluit**, geen gat: geen phone-home weegt hier zwaarder dan auto-patchen. Melding is pull-only (CHANGELOG, forge-feeds). De veilige distributie zelf is #520. |
| 21 | Transparent security posture | **Afgedwongen / Sterk** | `security-insights.yml` (OpenSSF), `web/.well-known/security.txt` (RFC 9116); zichtbare staat via `certificate_trust_dialog.dart`, gemaskeerde OciWacht-bevindingen, zichtbare `NetGuard`-weigeringen; gedegradeerde staten in `SECURITY_DESIGN.md` | De huidige beveiligingsstaat is zichtbaar en in gewone taal uitgelegd; de gebruiker wordt gewaarschuwd wanneer bescherming afneemt (het "vertrouwd intern"-vinkje waarschuwt). Een kernwaarde. |
| 22 | Secure recovery & ownership lifecycle | **Afgedwongen / Sterk** | Data-eigenaarschap: Markdown, geen vendor-lock, geen eigen container (dezelfde belofte die de PBKDF2-afwijking motiveert); herstel via git-opslag, crash-recovery-snapshot, outbox; `DiskTraces` ruimt lokale sporen | Sterk op eigenaarschap en herstel. De "veilige verwijdering" is de **zwakste regel**: unlink, geen overschrijving — al vastgelegd als R10 in `risicoafweging.md` en als deel I-regel in de CRA-positie. Device-ownership-transfer heeft geen onderwerp. |

---

## De open punten

Twee echte gaten, elk met een issue. De uitwerking staat daar, niet hier.

- **O1 — artefactondertekening symmetrisch maken (Linux).** Playbook 14. macOS is
  getekend + genotariseerd; Linux leunt op `SHA256SUMS` (geen handtekening).
  Open issue: **#1014** (Linux, detached signature), onder de
  veilige-distributievraag **#520**. Provenance/SLSA is de vraag erachter. De
  Windows-tak van dit punt is na weging bewust aanvaard — zie *Na weging géén
  open punt* hieronder (#1013).

- **O2 — verversingstrigger voor het dreigingsmodel.** Playbook 01. Het model in
  `docs/SECURITY_DESIGN.md` wordt met de hand ververst. Het lichtste dat werkt is
  een regel in de `PULL_REQUEST_TEMPLATE.md`-checklist, geen nieuwe poort.
  **#1015**.

### Na weging géén open punt

Vastgelegd zodat de afweging terugvindbaar is — een stilzwijgend geschrapt punt
is over een jaar niet te reconstrueren.

- **Externe meldroute (CSIRT/ENISA), playbook 12.** De verplichting hoort bij een
  fabrikant of een rentmeester; [`CRA-2024-2847-positie.md`](CRA-2024-2847-positie.md)
  §artikel 24 concludeert dat geen van beide op Stichting LibreKAT rust. Zonder
  CRA/NIS2-plicht is dit geen openstaand gat maar een voorwaardelijk punt — het
  wordt pas een item als die rol kantelt, en dán is het een adres en een afspraak.

- **CODEOWNERS op gevoelige modules, playbook 09.** De peer-review op die modules
  is al belegd bij de enige onderhouder (busfactor-één, `CONTRIBUTING.md`) en
  wordt geschraagd door de semgrep-grendels rond `net_guard`, de `Process.run`-
  inperking en secret-RNG. Een `CODEOWNERS`-bestand formaliseert dat pas zinvol
  zodra een tweede onderhouder toetreedt — precies het moment waarop CONTRIBUTING
  de "self-merge stopt"-regel al laat ingaan.

- **Windows Authenticode-ondertekening, playbook 14 (#1013, gesloten).** Bewust
  geen ondertekening. Sinds maart 2024 bouwt elk certtype (OV én EV) SmartScreen-
  reputatie alleen op via downloadvolume — geen enkele route neemt de
  waarschuwing meteen weg — terwijl elke betaalde route óf terugkerende kosten +
  een hardware-token, óf een clouddienst met een signeer-secret in de release-
  runner meebrengt (dat laatste botst met least-privilege). De bronroute blijft
  de herkomstgarantie; `SHA256SUMS` + heldere "Run anyway"-uitleg blijven.
  Heroverweging: een OV-certificaat, lokaal-handmatig getekend (het macOS-model),
  zodra downloadvolume dat rechtvaardigt. Uitgelegd in `SECURITY.md`,
  `docs/KNOWN_LIMITATIONS.md` en `docs/BUILD.md`.

Al elders gevolgd, hier alleen genoemd: de Dart-graaf adviserend i.p.v. als poort
(#517), en de smalle, handmatige mutatiedekking (§verificatiediepte in de
CRA-positie).

## Waar OciDeck strenger is dan de playbook vraagt

Dit hoort erbij, anders leest een afbeelding als een tekortenlijst.

- De privacygrens is **compileertijd** afgedwongen: alleen `PrivacyProjection`
  kan een `AudienceDeck` construeren (privéconstructor), en
  `check-audience-boundary` faalt de bouw als een ontvangend oppervlak een kale
  `Deck` aanneemt. De playbook vraagt om een controle; hier is het een
  bouwbreker.
- `NetGuard._embeddedIPv4` pelt IPv4-in-IPv6 in álle drie de vormen — mapped,
  compatible én NAT64 — een klasse fouten die de meeste implementaties laat
  liggen.
- De basislijn voor kale `catch (_)` staat op **nul**; nieuwe stille vangsten
  falen de conventiepoort.
- `BrowserGitTransport` weigert principieel elk verzoek met inloggegevens door
  het fetch-hulppunt te sturen — een fail-closed-keuze, geen configuratie.
- De secret-scanners draaien met `--no-verification` en over de **volledige
  git-historie**: kandidaat-geheimen gaan nooit naar een derde, en een geheim dat
  ooit gecommit is, wordt alsnog gevonden.

## Wanneer dit opnieuw langs moet

Zes van de negen scope-outs (03, 10, 16, 18-deels, 19, 20) rusten op dezelfde
afwezigheid: geen accounts, geen sessie, geen server, geen netwerk-standaard-aan,
geen device-vloot. **Komt één daarvan terug — een server, een account, een
gehoste instantie, een auto-updater — dan kantelen de bijbehorende playbooks van
"buiten scope" naar "in scope", en is deze afbeelding het eerste wat herzien
moet worden, niet het laatste.** Dat is dezelfde voorwaarde als in de
CRA-positie: bij een scopewijziging is de scopebepaling de eerste stap.
