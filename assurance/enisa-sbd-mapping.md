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

## Lokale controles en uitvoering op Pawprint

De onderhouder draait `make check-full` en legt het getoetste commit vast vóór
de merge. Dat is een afspraak. De PR-geheimenscan op Pawprint geeft een
automatische uitslag. De branchregel eist geen statuschecks. De nachtelijke
Linux-suite, macOS-goldens op repository-PR’s en `main`, en de tijdscontroles
leveren aanvullend uitvoeringsbewijs. De releaseketen toetst een kandidaat vóór de tag. Zie
[Checks & CI](../docs/CHECKS.md#all-checks-at-a-glance).

## Legenda voor het oordeel

| Oordeel | Betekenis |
|---|---|
| **Afgedwongen** | Een uitgevoerde poort of test faalt bij een afwijking. De uitvoeringsmomenten staan hierboven. |
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
| 01 | Trust boundaries & threat modelling | **Deels** | [Dreigingsmodel](../docs/SECURITY_DESIGN.md#threat-model) (14 rijen), [risicoafweging](risicoafweging.md), `make check-dated-claims` | De poort signaleert wijzigingen in netwerksinks en servicemodules. Een reviewer beoordeelt de gevolgen en de acceptatie. Zie O2. |
| 02 | Least privilege | **Deels** | OS-sleutelbos, begrensd git-subproces, `NetGuard`, `/me` en rollen in `XmppTransport` | OciServe, XMPP en de WebDAV-ACL hebben eigen autorisatiegrenzen. De externe diensten moeten hun rollen zelf afdwingen. Zie [ASVS V8](ASVS-5.0.0-scope.md#per-hoofdstuk). |
| 03 | Strong identity & authentication | **Deels** | OciServe OIDC/PKCE, step-up en XMPP SASL | De client toetst accepteerbare sessies. OciServe- en IdP-beleid voor authenticatie blijven per uitrol te beoordelen. De oude WebDAV-route gebruikt de server-ACL. |
| 04 | Attack surface minimisation | **Afgedwongen** | `make check-web` (`tool/check_web_hardening.dart`); `check-dead-code`; `check-conventions` (verbiedt `print()`); de beveiligingsmodule is een schakelaar over ingebakken catalogi zonder netwerkuitgang | Productiebouw is minimaal; wees interfaces zijn de webbundel (gehard) en niets meer. Geen diagnostische gereedschappen in release. |
| 05 | Defence in depth | **Afgedwongen** | `NetGuard` (SSRF-classificatie → resolve-then-pin → certificaatpin → poort-allowlist), `MarkdownSafetyScanner` (fail-closed vóór het parsen), `PrivacyProjection` + compileertijdgrens (`check-audience-boundary`) | Kritieke activa hebben meer dan één onafhankelijke laag. De gate-regels over "logging op meerdere lagen" en "alerts" hebben geen onderwerp: één logafvoer, geen SIEM (zie [`ASVS-5.0.0-afwijkingen.md`](ASVS-5.0.0-afwijkingen.md) V16). |
| 06 | Open design | **Afgedwongen** | Volledig openbaar; `semgrep/ocideck.yaml` verbiedt een eigen `badCertificateCallback` buiten `net_guard.dart`; geen eigen crypto (SHA-512-zegel op standaardprimitieven); `make sbom-verify`; meldkanaal `security.txt` + `tool/check_service_norms.dart` | Geen beveiliging-door-onbekendheid; dat is een kernwaarde, niet een maatregel. |

## Secure by Design — Operational Integrity (07–14)

| # | Playbook | Oordeel | Anker in OciDeck | Motivering / open |
|---|---|---|---|---|
| 07 | Life-cycle management | **Deels** | EOL-beleid in `SECURITY.md` (≥3 maanden aanzegging); `make deps-check` (OSV) + `make sbom`; `DiskTraces` voor buitenbedrijfstelling; aanvaarde restrisico's met eigenaar in `risicoafweging.md` + `AUDIT_RESPONSE.md` | Sterk op EOL, SBOM en restrisico. De gate-regel "secure update path" is **bewust afwezig** — zie 20. |
| 08 | User-centric design | **Deels** | Veilige standaard (netwerk uit, module uit); `certificate_trust_dialog.dart`; OciWacht-bevindingen gemaskeerd getoond; `check-hardcoded-text` (elke zichtbare tekst via `l10n.d()`, dus vertaalbaar en te herschrijven); toetsing via de `gebruikerstest`-agent | Geen standaard-adminwachtwoord (n.v.t.). Beveiligingswaarschuwingen zijn handelingsgericht. |
| 09 | Secure coding & verification | **Deels** | PR-scan van inkomende commits, lokaal `make check-full` met SAST, volledige geheimenscan, analyse en dekkingsvloer | De automatische scan rapporteert op de PR. De merge blijft een beheerdersbesluit. Onafhankelijke review wordt beperkt door één onderhouder. Mutatietesten zijn handmatig en worden gevolgd bij de verificatiediepte in de CRA-positie. |
| 10 | Logging, monitoring & alerting | **Buiten scope** | `lib/utils/log.dart` (één afvoer, `dart:developer`); `_safeError` houdt deckinhoud uit de log; weigeringen van `TabsProvider`/`GitCliIo`/`ExportService` laten een spoor zónder inhoud | Geen logverwerker, geen SIEM, geen tweede machine — centralisatie en alerting missen hun onderwerp (zie `ASVS-5.0.0-afwijkingen.md` V16.2.4/16.4.2/16.4.3). De **privacy**kant van logging is juist streng: bijzondere persoonsgegevens mogen niet in een log echoën. |
| 11 | Configuration & change management | **Afgedwongen** | Alles in git + DCO (`dco.txt`, `PULL_REQUEST_TEMPLATE.md`); `test/pinned_versions_manifest_test.dart` (harde pin-poort) + `.github/pinned-ci-versions.json`; `make check-toolchain` | Sterk op versiebeheer, pins en toolchain-basislijn. De gate-regel "dev/test/prod gescheiden" heeft geen onderwerp: er is geen IaC en geen productieomgeving. |
| 12 | Incident response & recovery | **Deels** | `SECURITY.md` (rollen, escalatieadres `security@librekat.nl`, runbook detect→reproduce→tracker); SLA gemeten door `tool/check_service_norms.dart` (5/10/90 werkdagen); herstel via git-opslag + crash-recovery-snapshot | Intern proces bestaat en wordt gemeten. De **externe meldroute** (CSIRT/ENISA) is géén openstaand gat: die hoort bij een fabrikants- of rentmeestersplicht, en [`CRA-2024-2847-positie.md`](CRA-2024-2847-positie.md) §artikel 24 concludeert dat geen van beide op LibreKAT rust. Komt die rol ooit alsnog, dan is het een adres en een afspraak — zie daar. |
| 13 | Vulnerability & patch management | **Deels** | `make deps-check` (OSV over de gebundelde JS), `make sbom`, `make sast`, `make check-secrets`; triage vastgelegd in `risicoafweging.md`, `AUDIT_RESPONSE.md`, CHANGELOG; fix staat op `main` zodra gemerged | Proces en JS-graaf gedekt. Open: de **Dart-afhankelijkheidsgraaf** wordt niet automatisch afgezocht — Trivy draait adviserend, niet als poort (#517). |
| 14 | Supply chain controls | **Afgedwongen** | `make sbom` (CycloneDX 1.6 + SPDX 2.3) + `sbom-verify`-poort + `test/sbom_test.dart`; leveranciersweging in `ketenkeuring-matrix-sdk.md` / `-rust-sdk.md` (GO/NO-GO); build-secrets minimaal in de workflows | Een uitschieter. De release-manifest `SHA256SUMS` draagt nu een **minisign detached signature** (`SHA256SUMS.minisig`, publieke sleutel `minisign.pub` in de repo-root, lokaal-handmatig getekend met `make sign-release`), die élk genoemd artefact verankert — alle platformen tegelijk (#1014, `SECURITY.md` §"Release artifact integrity and signing", `docs/BUILD.md`). macOS is daarbovenop Developer-ID-getekend + genotariseerd (`scripts/notarize_macos.sh`); per-binary Windows-ondertekening (Authenticode) is na weging **bewust aanvaard** (#1013, gesloten). **Provenance/SLSA** (reproduceerbare build, **#1027**) is onderzocht en gewogen ([`reproduceerbare-builds.md`](reproduceerbare-builds.md)): de webbundel is content-reproduceerbaar gemaakt en het determinisme is getoetst binnen een vaste bouwomgeving, desktop en SLSA-attestatie zijn gewogen weg. Een cross-OS-meting toont verschillen in de gecompileerde webartefacten. Zie [meetbewijs #3247](#meetbewijs-3247-28-november-2026) en [O1](#de-open-punten). |

## Secure by Default — Default Hardening (15–18)

| # | Playbook | Oordeel | Anker in OciDeck | Motivering / open |
|---|---|---|---|---|
| 15 | Minimisation of default services | **Afgedwongen** | Netwerk staat standaard uit (`NetGuard`, `SECURITY_DESIGN.md` §3); de beveiligingsmodule is een uit-standaard schakelaar over ingebakken catalogi | Alleen kernfunctionaliteit staat standaard aan; optionele diensten zijn uit tot de gebruiker ze aanzet. |
| 16 | Restrictive initial access | **Deels** | Modules staan standaard uit. OciServe start met een actief lidmaatschap en XMPP-companion koppelt op uitnodiging en apparaatgoedkeuring | De externe server en IdP regelen de initiële rechten van hun accounts. |
| 17 | Secure communication by default | **Deels** | Native HTTPS/WSS en routegebonden NetGuard-pinning. WebRTC gebruikt DTLS-SRTP naar de bridge | Vertrouwd intern S3 en ASR hebben expliciete opt-ins. Browsertransport, WebRTC en serverhardening hebben eigen grenzen. Zie [ASVS-afwijkingen](ASVS-5.0.0-afwijkingen.md). |
| 18 | Unique device identity & secrets by default | **Deels** | OS-sleutelbos, PR-geheimenscan, Semgrep-regels, XMPP-apparaatsleutels | XMPP heeft een eigen apparaatidentiteit en goedkeuring. Client- en uitrolgeheimen volgen hun eigen beheer. |

## Secure by Default — Guided Protection (19–22)

| # | Playbook | Oordeel | Anker in OciDeck | Motivering / open |
|---|---|---|---|---|
| 19 | Mandatory security onboarding | **Deels** | De lokale basis werkt met uitgeschakelde optionele routes. ASR, OciServe en XMPP vragen handelingen bij inschakeling | Systeembrede uitrol en IdP-aanmeldbeleid horen bij de beheerder. |
| 20 | Automated maintenance & updates | **Buiten scope (bewuste keuze)** | `SECURITY.md` §"There is no update mechanism" (de app belt nooit naar huis, controleert nooit op een nieuwere versie); macOS-installer genotariseerd; Windows/Linux via `SHA256SUMS` | De afwezigheid van een auto-updater is een **expliciet ontwerpbesluit**, geen gat: geen phone-home weegt hier zwaarder dan auto-patchen. Melding is pull-only (CHANGELOG, forge-feeds). De veilige distributie zelf is #520. |
| 21 | Transparent security posture | **Afgedwongen / Sterk** | `security-insights.yml` (OpenSSF), `web/.well-known/security.txt` (RFC 9116); zichtbare staat via `certificate_trust_dialog.dart`, gemaskeerde OciWacht-bevindingen, zichtbare `NetGuard`-weigeringen; gedegradeerde staten in `SECURITY_DESIGN.md` | De huidige beveiligingsstaat is zichtbaar en in gewone taal uitgelegd; de gebruiker wordt gewaarschuwd wanneer bescherming afneemt (het "vertrouwd intern"-vinkje waarschuwt). Een kernwaarde. |
| 22 | Secure recovery & ownership lifecycle | **Afgedwongen / Sterk** | Data-eigenaarschap: Markdown, geen vendor-lock, geen eigen container (dezelfde belofte die de PBKDF2-afwijking motiveert); herstel via git-opslag, crash-recovery-snapshot, outbox; `DiskTraces` ruimt lokale sporen | Sterk op eigenaarschap en herstel. De "veilige verwijdering" is de **zwakste regel**: unlink, geen overschrijving — al vastgelegd als R10 in `risicoafweging.md` en als deel I-regel in de CRA-positie. Device-ownership-transfer heeft geen onderwerp. |

---

## De open punten

O1 en O2 staan hieronder met hun uitkomst. De resterende onderwerpen in de
matrix zijn adviescontrole van de Dart-graaf (#517), verificatiediepte (CRA-dossier)
en het bewijs voor platformdistributie en cross-OS-bouw (#520). De gerichte
metingen uit [#3247](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/3247)
staan hieronder.
Voor de nieuwe grenzen staan de uitrolafhankelijke risico’s in de risicoafweging en volgt
dossierherziening via #3243.

- **O1 — artefactondertekening: gedicht via een getekende release-manifest.**
  Playbook 14. De release-manifest `SHA256SUMS` draagt nu een minisign detached
  signature (`SHA256SUMS.minisig`, publieke sleutel `minisign.pub` in de
  repo-root), lokaal-handmatig getekend (`make sign-release`) — dat verankert élk
  artefact dat de lijst noemt, alle platformen tegelijk (**#1014**). macOS is
  daarbovenop Developer-ID-getekend + genotariseerd. De Windows-tak — per-binary
  Authenticode — is na weging bewust aanvaard (**#1013**, zie *Na weging géén open
  punt* hieronder). Het residu **provenance/SLSA** (reproduceerbare build,
  **#1027**) is onderzocht en gewogen in
  [`reproduceerbare-builds.md`](reproduceerbare-builds.md): de webbundel is
  content-reproduceerbaar gemaakt binnen een vaste bouwomgeving (de intrinsieke
  per-build-willekeur is weg, `pack_web_release.dart`), bit-repro voor macOS en
  Windows is principieel resp. qua opbrengst gewogen weg, en een aparte
  SLSA-provenance-attestatie voegt voor één vertrouwenswortel niets toe boven de
  off-runner getekende manifest. De vergelijking tussen Linux en macOS
  hieronder laat zien dat beide bouwomgevingen verschillende gecompileerde
  webartefacten leveren. Dit valt onder de veilige-distributievraag **#520**.

- **O2 — verversingstrigger voor het dreigingsmodel.** De PR-checklist vraagt
  een review bij veranderingen aan interfaces, identiteit, gevoelige gegevens,
  afhankelijkheden en distributie (#1015). Na #3242 signaleert
  `make check-dated-claims` ook nieuwe `HttpClient`-aanroepen en gewijzigde
  netwerksinkpaden. #3243 voegt de servicemodule-inventaris en termijn voor
  herziening toe. De inhoud en acceptatie van restrisico’s blijven een
  menselijke beoordeling.

### Meetbewijs #3247, 28 november 2026

**Dart-advisories.** De hoofdlockfile bevat 223 vermeldingen (SHA-256
`71db73781b8dbd3c3b83edca03b1bd6a7849c927c1f3c404e17e1ccb96639fb3`).
Daarvan zijn er 201 via pub.dev op naam en exacte versie te bevragen
(90,1%). De andere 22 zijn zeven git-, zeven pad- en acht SDK-dependencies.
De [OSV-export van de Pub-bron](https://osv-vulnerabilities.storage.googleapis.com/Pub/all.zip)
bevatte 14 records, met actuele advisories voor elf pakketnamen. De bron noemt vier
pakketnamen uit de lockfile (`archive`, `http`, `jose` en
`shared_preferences_android`). Dat meet historische zichtbaarheid per
naam. [OSV QueryBatch](https://google.github.io/osv.dev/post-v1-querybatch/)
antwoordde voor alle 201 vastgezette versies met nul toepasselijke advisories.

Trivy 0.76.2 met database bijgewerkt op 2026-11-28 om 07:04 UTC
(`mirror.gcr.io/aquasec/trivy-db:2`) herkende alle 223 lockfilevermeldingen.
Het rapporteerde nul Pub-kwetsbaarheden in de hoofdlockfile en de twee
aangetroffen pakketlockfiles. De [Trivy-bronbeschrijving](https://trivy.dev/docs/latest/guide/scanner/vulnerability/)
documenteert de GitHub Advisory Database voor Pub. Houd het oordeel adviserend
totdat een automatisering de databron beschikbaar en actueel kan houden, de
git-/pad-/SDK-dependencies apart adresseert en een test met een publiek bekende
getroffen versie betrouwbaar ziet.

```sh
curl -fLO https://osv-vulnerabilities.storage.googleapis.com/Pub/all.zip
trivy fs --scanners vuln --list-all-pkgs --format json --output trivy-dart.json .
jq '.Results[] | select(.Type == "pub") | {Target, packages: (.Packages|length), findings: ((.Vulnerabilities // [])|length)}' trivy-dart.json
```

Selecteer voor de OSV-batch uit `pubspec.lock` de entries met
`source: hosted` en URL `https://pub.dev`. Stuur die als
`queries: [{package: {name, ecosystem: "Pub"}, version}]` naar
`POST https://api.osv.dev/v1/querybatch` en vergelijk het antwoord op
volgorde met alle invoerregels. Een onbekende pakketnaam en een pakket zonder
advisory kunnen beide een lege lijst opleveren.

**Webrelease op Linux en macOS.** De [Linux/amd64-uitvoering op Pawprint](https://pawprint.vigilis.online/LibreKAT/Ocideck/actions/runs/6943)
en de lokale macOS/arm64-uitvoering op 27.3 gebruikten commit
`d2e778167d8e1c446379554cd9debdd0dd30b499`, Flutter 3.50.0 met frameworkrevisie
`ab2912035e160d9cad6306df307576da6128ebdb` en dezelfde lockfile als hierboven.
`make check-web` slaagde op beide hosts.

| Omgeving | SHA-256 van `build/web/SHA256SUMS` |
|---|---|
| Linux, ondiepe checkout | `779a3ad6e36940940a4a817df2fb61fa6d5740a534658c135b51d53f6ace33f0` |
| macOS, volledige Git-geschiedenis | `7732a727a66b57e760d1dfba9e03ed57321412da46b3b3dcc75551749bf3daaf` |
| macOS, na gelijktrekken van de Git-aanduiding | `a3d432931303cd41232a1a9fd15d67228ec7299f96d21a7a8c4549775458e370` |

Het verschil tussen `d2e7781` in Linux en `v0.7.15-240-gd2e778167` in
macOS wijzigt twee bestanden, `build-info.json` en de cacheverwijzing ernaar
in `precache_manifest.json`. Ook met `d2e7781` in beide bundels wijkt de
checksumlijst af. Twee inhoudsgehashte compilerartefacten verschillen al in de
bestandsnaam. De Linux-browserlog laadt `main.dart.c02d0c5c.wasm` en bij
terugval `main.dart.50a87307.js`. Op macOS zijn dat respectievelijk
`main.dart.884d76ce.wasm` en `main.dart.4d1fd39e.js`. De moduleloader
`main.dart.83f18b95.mjs` heeft op beide dezelfde inhoudsprefix. De Linux-run
bewaart de digest en de geladen bestanden, waardoor andere verschilregels
pas bij een vervolgmeting met beide volledige lijsten te herleiden zijn.
De meting toont reproduceerbaarheid van deze bundel tussen de twee
bouwomgevingen niet aan. Houd cross-OS-gelijkheid daarom buiten de
releasevoorwaarden.

Maak op beide hosts een schone checkout met dezelfde commit, dezelfde
ondiepe Git-geschiedenis (`--depth=1`, geen tags) en dezelfde Flutter-pin.
Bewaar de checksumlijst naast het log zodra de controle gereed is.

```sh
git rev-parse HEAD
make check-toolchain
shasum -a 256 pubspec.lock
flutter pub get --enforce-lockfile
make check-web
shasum -a 256 build/web/SHA256SUMS
```

Vergelijk de twee `SHA256SUMS`-bestanden met `diff -u` als de totalen
verschillen. Onderzoek `build-info.json` afzonderlijk. De aanduiding uit
`git describe` hangt mede van aanwezige tags en geschiedenis af en werkt door
in `precache_manifest.json`.

**Gerichte mutatie.** De fixture van
`test/json_depth_guard_test.dart` draait op de productiegrens in
`lib/utils/json_depth_guard.dart`. Met het maximum tijdelijk elf niveaus
ruimer faalt de bestaande test *diep geneste input wordt geweigerd vóór
jsonDecode*. De bestaande suite blijft groen wanneer de vergelijking van
`>` naar `>=` gaat. Daarmee is acceptatie precies op de maximale diepte
een aantoonbaar ongetoetste rand. De ongewijzigde bron slaagt met zeven
tests. Dit resultaat blijft beperkt tot de JSON-dieptevergelijking.

```sh
flutter test test/json_depth_guard_test.dart
```

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
