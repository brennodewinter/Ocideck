# OciDeck — Securityreview op APT-weerbaarheidsniveau

> **Datum:** 2026-08-08 · **Branch:** `security/apt-review` · **Reviewers:** GLM-5.2 (geautomatiseerd)
> · **Methode:** statische codeanalyse van `lib/`, `tool/`, `web/`, `assets/` tegen het
> dreigingsniveau *Advanced Persistent Threat* · **Scope:** de volledige app, niet de
> pentestrapportage die ermee wordt gemaakt

Deze review is uitgevoerd op de default branch (commit `265b7b73`) op een aparte branch
zonder de code te wijzigen. Het rapport citeert bestandsnamen en regelnummers zodat elke
bewering tegen de code is na te trekken.

---

## 1. Conclusie

OciDeck is een lokaal-eerst product zonder applicatiebackend. Het beveiligingsontwerp is
bovengemiddeld robuust voor deze categorie: SSRF-bescherming met resolve-then-pin,
certificaat-pinning per verbinding, fail-closed AI-uitgang, HTML-export met per-export
CSP-nonce, padcontainment met symlink-controle, en git-subprocessen met gehardende
omgeving en token via `GIT_CONFIG_*`.

Tegen een APT vertoont het ontwerp **geen kritieke of hoge kwetsbaarheden** die tot
directe code-uitvoering of ongeautoriseerde netwerktoegang leiden vanuit een kwaadaardig
deck. De bevindingen vallen in drie categorieën:

1. **Nieuwe bevindingen** (niet eerder gedocumenteerd) — 2 middelgroot, 3 laag.
2. **Bekende restrisico's** — expliciet gedocumenteerd in `SECURITY_DESIGN.md` en
   `SECURITY.md`, met acceptatiedatum. Deze worden hier bevestigd, niet herontdekt.
3. **Verkeerde bevindingen** — beweringen uit de deelreviews die bij verificatie niet
   kloppen; opgenomen om duplicaat-onderzoek te voorkomen.

### Bevindingenoverzicht

| ID | Bevinding | Ernst | APT-exploiteerbaar? | Status |
|---|---|---|---|---|
| R-01 | Non-constant-time hashvergelijkingen | Middel | Nee (lokaal, trusted machine) | Gefixt (#1366) |
| R-02 | `pinned_http_client` dwingt `followRedirects=false` niet af | Middel | Indirect (nieuwe caller) | Gefixt (#1367) |
| R-03 | `style-src 'unsafe-inline'` in export-CSP | Laag | Theoretisch (CSS-exfiltratie) | Nieuw |
| R-04 | `flutter_webrtc` libvpx-versie niet geverifieerd | Laag | Ja (indien kwetsbaar) | Gefixt (#1368) |
| R-05 | `dartcv4` FFI-bindings als supply-chain-oppervlak | Laag | Ja (indien gecompromitteerd) | Gefixt (#1369) |
| B-01 | TOCTOU in render-path symlink-cache | Laag | Nee (vereist fs-toegang na openen) | Bekend |
| B-02 | Video TOCTOU (platform-speler kan niet pinnen) | Laag | Nee (geen credentials) | Bekend |
| B-03 | Web-platform: geen NetGuard-pinning voor media | Middel | Ja (SSRF via DNS-rebind op web) | Bekend |
| B-04 | Onversleutelde recovery-snapshots en git-working-copies | Middel | Nee (vereist fs-toegang) | Bekend |
| B-05 | macOS App Sandbox uit | Middel | Nee (vereist lokaal proces) | Bekend |
| B-06 | Geen TSA-signatuurverificatie (RFC 3161) | Laag | Ja (token-vervalsing) | Gefixt (#1370) |
| B-07 | PBKDF2 1000 iteraties (WinZip AE-1) | Laag | Ja (offline brute-force zwak wachtwoord) | Bekend |
| B-08 | WebDAV-collab: beacon en log zonder cryptografische integriteit | Middel | Ja (met WebDAV-write access) | Bekend |
| B-09 | WebRTC-media bypast NetGuard | Middel | Ja (indien module aan) | Bekend |

---

## 2. Nieuwe bevindingen

### R-01 — Non-constant-time hashvergelijkingen

**Locaties:**
- `lib/services/document_integrity.dart:123` — `deck.fileHash == deck.sealHash`
- `lib/services/document_integrity.dart:127` — `computeCanonicalHash(deck) == deck.sealHash`
- `lib/services/rfc3161_timestamp.dart:362` — `parsed.messageImprintHex.toLowerCase() == sealHashHex.toLowerCase()`
- `lib/services/privacy/redaction_manifest_service.dart:308` — `commitmentFor(...) == entry.commitment`

**Wat gaat er mis.** Stringvergelijking met `==` in Dart short-circuit per karakter: het
eerste verschil beëindigt de vergelijking, wat een timing-zijkanaal oplevert op hoeveel
karakters van de hash overeenkomen.

**APT-exploiteerbaarheid: LAAG.** Alle vier vergelijkingen zijn lokale operaties in een
desktop-applicatie. Het dreigingsmodel stelt expliciet: "The user's machine is trusted
(not malware-compromised)." Een APT die de timing van een lokale vergelijking kan meten,
heeft al code-executie op de machine en kan de bestanden direct lezen. Bovendien:

- De seal-hash is SHA-512 over publieke bytes — een aanvaller kan de hash zelf berekenen
  en heeft geen timing nodig om te weten of deze klopt.
- De redaction-commitmentvergelijking vereist de salt, die niet in het geredigeerde
  exemplaar zit. Wie de salt heeft (de auteur) kan offline brute-force zonder timing.
- De TSA-imprintvergelijking controleert of een token bij een seal past — ook hier kan
  de aanvaller de imprint zelf berekenen.

**Aanbeveling.** Vervang de vergelijkingen door een constant-time vergelijker
(XOR-accumulatie over alle bytes, return `diff == 0`). Dit is defense-in-depth, geen
kwetsbaarheidsfix. De repo heeft al een voorbeeld in `lib/xmpp/xmpp_sasl.dart` (SASL
mechanism comparison).

**Type:** Implementatieverbetering (defense-in-depth).

### R-02 — `pinned_http_client` dwingt `followRedirects=false` niet af

**Locatie:** `lib/utils/pinned_http_client.dart:16-17` (commentaar), gehele bestand.

**Wat gaat er mis.** De gepinde HTTP-client verwacht dat de caller `followRedirects = false`
zet op elk `HttpClientRequest`-object, maar dwingt dit niet af in de `connectionFactory`
of de client-configuratie. Een nieuwe caller die dit vergeet, kan redirects volgen naar
een niet-gevalideerde host, wat de SSRF-guard omzeilt.

**Huidige stand.** Alle bestaande callers (WebDAV, S3, git-REST, CVE-transport, AI-client,
URL-import, media-fetch) zetten `followRedirects = false` expliciet. De
`test/network_sink_guard_test.dart` scant op alle egress-primitives. Het risico is
puur toekomstig: een nieuwe caller die de conventie niet kent.

**APT-exploiteerbaarheid: INDIRECT.** Een APT kan dit niet direct uitbuiten — er is geen
bestaande caller die redirects volgt. Het risico is dat een toekomstige wijziging een
nieuwe caller toevoegt die de conventie mist, waarna een kwaadaardige server via een 3xx
de SSRF-guard omzeilt en bijvoorbeeld een `Authorization`-header naar een interne host
stuurt.

**Aanbeveling.** Overweeg om `followRedirects = false` in de client zelf af te dwingen
(`HttpClient` heeft geen globale instelling hiervoor, maar een wrapper-functie die elke
`openUrl`-aanroep onderschept wel), of voeg een semgrep-regel toe die `openUrl` zonder
`followRedirects = false` in dezelfde functie flagt.

**Type:** API-ontwerp / defense-in-depth.

### R-03 — `style-src 'unsafe-inline'` in export-CSP

**Locatie:** `lib/services/marp_html_service.dart:323`.

**Wat gaat er mis.** De per-export CSP staat `style-src 'unsafe-inline'` toe, nodig omdat
MathJax en Mermaid inline styles injecteren tijdens het renderen. Theoretisch opent dit
een CSS-exfiltratievector: een aanvaller die Markdown met `<style>`-blokken injecteert
kan CSS-attribute-selectors gebruiken om data via `background: url(...)` te exfiltreren.

**Beperkende factoren.**
- `connect-src 'none'` blokkeert `fetch()`, `XMLHttpRequest`, `Navigator.sendBeacon()`.
- `img-src 'self' data: blob: file:` blokkeert externe URLs in `<img>`.
- `form-action 'none'` blokkeert form-submissions.
- CSS `background: url(https://...)` valt onder `img-src`, dus externe URLs worden
  geblokkeerd. Alleen `url(data:...)` of `url(blob:...)` zou werken, maar deze laden
  geen externe resource en kunnen niet "beacon home".
- De export-DOM bevat geen gevoelige elementen die niet al in het bestand staan — de
  deck-inhoud is zelf het bestand.

**APT-exploiteerbaarheid: ZEER LAAG.** De CSP sluit alle netwerkgebaseerde
exfiltratiepaden af. CSS-exfiltratie vereist gevoelige DOM-elementen met
aanvalscontroleerbare attributen, en die zijn hier niet aanwezig. De deck-inhoud staat
al in het bestand dat de gebruiker opent.

**Aanbeveling.** Accepteer dit als een design-trade-off. Als verharding gewenst is:
gebruik CSP `'nonce-...'` of `'sha256-...'` voor `style-src` in plaats van
`'unsafe-inline'`, en voorzie de bekende inline styles van een nonce of hash.

**Type:** Design-trade-off (noodzakelijk voor MathJax/Mermaid).

### R-04 — `flutter_webrtc` libvpx-versie niet geverifieerd

**Locatie:** `pubspec.yaml:67` (`flutter_webrtc: ^1.5.2`), `pubspec.lock:499`
(opgelost als `1.6.0`).

**Wat gaat er mis.** `flutter_webrtc` bundelt libwebrtc, dat op zijn beurt libvpx
bundelt. CVE-2023-5217 is een buffer-overflow in libvpx VP8-decoding die tot
remote-code-execution kan leiden. De exacte libvpx-versie in `flutter_webrtc 1.6.0`
is niet uit de pubspec-bestanden op te maken.

**Mitigaties.**
- De WebRTC-module is **default-off** (`SECURITY.md`).
- Media bereikt de SFU/peers alleen via NetGuard-gevalideerde signalling.
- E2EE is actief op ondersteunde platforms (uit op iOS/macOS wegens
  `flutter_webrtc#2135`).

**APT-exploiteerbaarheid: MOGELIJK.** Een kwaadaardige peer die een speciaal
geconstrueerde VP8-frame stuurt tijdens een videovergadering kan de buffer-overflow
triggeren — maar alleen als de module aan staat en de gebruiker in een vergadering zit.

**Aanbeveling.** Verifieer de exacte libvpx-versie in de gebundelde
`flutter_webrtc 1.6.0`-binary (via `strings` of de release-notes van het pakket). Als
de versie kwetsbaar is, upgrade dan. Voeg een check toe aan `make deps-outdated` die
de `flutter_webrtc`-versie tegen bekende advisories houdt.

**Type:** Supply-chain-risico (afhankelijkheidsverificatie).

### R-05 — `dartcv4` FFI-bindings als supply-chain-oppervlak

**Locatie:** `pubspec.yaml:39` (`dartcv4: ^2.2.1`), `lib/services/privacy/image_face_scan_io.dart`.

**Wat gaat er mis.** `dartcv4` gebruikt FFI om native OpenCV-code aan te roepen. Native
code via FFI valt buiten Dart's sandbox. Een gecompromitteerde `dartcv4`-pakket kan
native code injecteren die buiten de app's procesgrenzen valt.

**Mitigaties.**
- De package wordt alleen gebruikt voor gezichtsdetectie in de privacyscanner
  (`image_face_scan_io.dart`).
- De module is desktop-only en draait niet in de web-build.
- De invoer is afbeeldingsbytes uit een deck, niet willekeurige invoer.

**APT-exploiteerbaarheid: VIA SUPPLY CHAIN.** Een APT die de `dartcv4`-pakket op pub.dev
compromitteert of een MITM tijdens `flutter pub get` uitvoert, kan native code injecteren.
Dit vereist echter compromittering van de pub.dev-infrastructuur of het
transport — geen aanval via een kwaadaardig deck.

**Aanbeveling.** Pin `dartcv4` aan een specifieke commit-hash als pad-afhankelijkheid
mogelijk is, of verifieer de SHA-256 van de pakket-archive tijdens de build. De SBOM
dekt de pakketversie, maar niet de integriteit van de native binaries.

**Type:** Supply-chain-risico (inherent aan FFI).

---

## 3. Bekende restrisico's (bevestigd)

Deze restrisico's zijn expliciet gedocumenteerd in `docs/SECURITY_DESIGN.md` (Threat
model, §727–748) en `SECURITY.md`, met acceptatiedatum. De review bevestigt dat de
code overeenkomt met de documentatie — er zijn geen ongedocumenteerde afwijkingen
gevonden.

### B-01 — TOCTOU in render-path symlink-cache

`lib/utils/project_path.dart:34-58`. De `isRenderPathContained`-cache slaat het
resultaat van symlink-resolutie per pad op voor de sessie. Een symlink die na de eerste
render wordt gewisseld, wordt niet opnieuw gecontroleerd.

**Bevestigd.** De cache (regel 45-46) retourneert het opgeslagen resultaat zonder
opnieuw te resolven. `resolveContainedRealPath` (regel 16-24), gebruikt voor
copy-to-clipboard, doet geen caching en is fail-closed (`FileSystemException` → `null`).
Het verschil in fail-gedrag is correct: de render-path toont een placeholder voor
missende bestanden, de clipboard-path weigert.

**APT-exploiteerbaarheid: LAAG.** Vereist filesystem-access na openen van het deck,
binnen dezelfde sessie, en alleen voor reeds-gerenderde paden.

### B-02 — Video TOCTOU

`lib/widgets/slides/previews/media_previews.dart:107-112`. `VideoPlayerController.networkUrl()`
doet eigen DNS en kan niet socket-pinnen. `NetGuard.isAllowedMediaUrlResolved()` controleert
vooraf, maar tussen check en connect is een rebind-venster.

**Bevestigd.** Gedocumenteerd in `SECURITY.md` en `net_guard.dart:283-287`. Geen
credentials reizen mee; het is een GET-only operatie met statische-intern-weigering.

### B-03 — Web-platform: geen NetGuard-pinning voor media

`lib/utils/media_fetch_web.dart:5-20`. Op web wordt `NetworkImage` direct gebruikt
zonder NetGuard-pinning. De browser bepaalt de verbinding.

**Bevestigd.** Gedocumenteerd in `SECURITY_DESIGN.md` §1: "On web there is no
`net_guard` SSRF check (unlike desktop), so restricting these to `'self' data: blob:`
is what closes that hole." De web-CSP `img-src 'self' data: blob:` blokkeert externe
media-URLs. Alleen als de hoster `https:` aan `img-src` toevoegt, opent dit gat.

### B-04 — Onversleutelde recovery-snapshots en git-working-copies

`lib/services/recovery_service.dart`. Snapshots zijn plaintext JSON onder app-support,
pruned na 7 dagen. Git-working-copies onder `git_clone/<slug>/` zijn unencrypted zonder
verval.

**Bevestigd.** Gedocumenteerd in `SECURITY.md` (Crash-recovery snapshots) en
`SECURITY_DESIGN.md` §9. Linux: `DiskTraces.restrictToOwner()` chmod 700. macOS:
`~/Library` is 0700. Encryptie is bewust niet geïmplementeerd (zie
`SECURITY.md` voor de afweging).

### B-05 — macOS App Sandbox uit

`macos/Runner/*.entitlements`: `com.apple.security.app-sandbox = false`.

**Bevestigd.** Gedocumenteerd in `SECURITY.md` (Platform sandboxing). Bewuste keuze
omdat het bestandsmodel sibling-asset-directories leest. De in-process verdedigingen
(SSRF, padcontainment, import-caps) blijven actief.

### B-06 — Geen TSA-signatuurverificatie

`lib/services/rfc3161_timestamp.dart:15-20`. De CMS-handtekening van het RFC 3161-token
wordt niet geverifieerd. Alleen de message-imprint wordt vergeleken.

**Bevestigd.** Gedocumenteerd in `AUDIT_RESPONSE.md` (AEG-02), `SECURITY_DESIGN.md` §9,
en in de UI als "assertion" niet "verified fact". Een APT kan een token met willekeurige
`genTime` vervalsen. Volledige CMS-verificatie staat op de roadmap als §8-A3.

### B-07 — PBKDF2 1000 iteraties (WinZip AE-1)

`lib/utils/zip_encryption.dart` via `package:archive`. WinZip AE-1 specificeert
PBKDF2-HMAC-SHA1 met 1000 iteraties — vastgelegd in de specificatie, niet aanpasbaar.

**Bevestigd.** Gedocumenteerd in `SECURITY_DESIGN.md` §12 en `AUDIT_RESPONSE.md`
(AEG-07). Mitigatie: de export-dialog toont een entropie-meter en biedt een generator
(32/256 karakters, `Random.secure`). Met een gegenereerd wachtwoord is de zwakke KDF
irrelevant. Met een gebruikerswachtwoord van 8 karakters is offline brute-force met
GPU-haalbaar in uren.

### B-08 — WebDAV-collab: beacon en log zonder cryptografische integriteit

`lib/collab/collab_log_store.dart:51-65` (beacon is advisory), `lib/collab/webdav_async_transport.dart:191-219`
(log records zijn plain JSON zonder MAC).

**Bevestigd.** Gedocumenteerd in `SECURITY_DESIGN.md` threat model (Async collaboration
handover, 2026-07-31). Fase 0.5 heeft geen participant-authenticatie; WebDAV-write-access
is de enige gate. De Matrix-transport (Fase 2) biedt E2EE via Olm/Megolm.

**APT-exploiteerbaarheid: MOGELIJK met WebDAV-write-access.** Een aanvaller met
gecompromitteerde WebDAV-credentials kan de beacon vervalsen (authority claimen),
log-records injecteren, of geschiedenis manipuleren. De "only the owner saves"-gate is
client-side, niet server-enforced.

### B-09 — WebRTC-media bypast NetGuard

`lib/services/...` via `flutter_webrtc`. ICE/STUN/TURN en SRTP-media worden door
libwebrtc geopend, niet door een `HttpClient`, dus `NetGuard` kan ze niet
resolve-guarden of pinnen.

**Bevestigd.** Gedocumenteerd in `SECURITY.md` (WebRTC media bypasses NetGuard).
Begrensd: media volgt de NetGuard-gevalideerde signalling-origin, module is default-off,
en als signalling faalt opent geen media-kanaal. E2EE uit op iOS/macOS wegens
`flutter_webrtc#2135`.

---

## 4. Verkeerde bevindingen (uit de deelreviews, bij verificatie weerlegd)

### Non-cryptographic RNG in `annotation.dart` is geen beveiligingsissue

**Bewering.** `lib/models/annotation.dart:114` gebruikt `Random()` in plaats van
`Random.secure()` voor stroke-ID's.

**Verweer.** Het commentaar (regel 108-112) stelt expliciet: dit hoeft niet
wereldwijd uniek te zijn, alleen binnen twee kanten van één merge. Stroke-ID's zijn
voor merge-conflict-voorkoming, niet voor authenticatie, audit-trails of
beveiligingsbeslissingen. De semgrep-regel `ocideck-zwakke-random-voor-geheim`
(`semgrep/ocideck.yaml:48-63`) matcht alleen op variabelenamen met
`key|token|secret|nonce|salt|iv|seed|passw` — de variabele heet `r` en wordt
terecht niet geflagd. `question_round_builder.dart:23` gebruikt `math.Random()` voor
quiz-vraagvolgorde, evenmin beveiligingsrelevant.

### SHA-1 in evidence-hashing is een externe normeis

**Bewering.** `lib/services/evidence_hash_service.dart` gebruikt SHA-1.

**Verweer.** De MIAUW-methodiek schrijft SHA-1 voor in bewijstabellen. SHA-256 wordt
ernaast berekend (regel 23). Dit is gedocumenteerd in `SECURITY_DESIGN.md` §12. Geen
actie vereist.

### `isRenderPathContained` fail-open voor missende bestanden is correct

**Bewering.** `lib/utils/project_path.dart:50-51` retourneert `true` bij
`FileSystemException`, wat fail-open is.

**Verweer.** Een missend bestand kan geen symlink-ontsnapping zijn — het bestaat niet.
De normale render-path toont een placeholder. De beveiligingsgevoelige sink
(`resolveContainedRealPath`, regel 21-22) is fail-CLOSED (`FileSystemException` →
`null` = weigeren). Het verschil in fail-gedrag is correct voor de respectievelijke
use-cases.

---

## 5. Wat de review niet dekt

- **Dynamische testen.** Deze review is statisch. De `make check-full`-poort (die
  DAST, SAST, secret-scanning en de volledige testsuite draait) is niet uitgevoerd.
- **Native binaries.** De OpenCV- (`dartcv4`) en WebRTC- (`flutter_webrtc`) binaries
  zijn niet gedemonteerd. Hun kwetsbaarheidsstatus is afgeleid van pakketversies, niet
  van binary-analyse.
- **UI-logica.** Dialogen voor certificaat-pinning, AI-consent en
  classificatie-afdwinging zijn beoordeeld op de achterliggende service-code, niet op
  een volledige UI-walkthrough.
- **Vendored JS in de browser.** DOMPurify 3.4.13, marked 18.0.5, Mermaid 11.16.0,
  highlight.js en MathJax 3.2.2 zijn gepind met SHA-256 in
  `assets/web_export/MANIFEST.json`. De review bevestigt de pinning en de
  OSV-check (`tool/check_bundled_js.dart`), maar heeft niet elke bundel
  afzonderlijk geaudit.
- **Transportbeveiliging van de Forgejo-instantie.** De CI-runner en de
  release-artefact-hosting vallen buiten de app-code.

---

## 6. APT-scenarioanalyse

### Scenario 1: APT levert een kwaadaardig deck

**Kan de APT code-uitvoering bereiken?** Nee. Drie lagen blokkeren dit:
1. `MarkdownSafetyScanner` weigert uitvoerbare markup bij import
   (`lib/services/markdown_safety.dart`).
2. DOMPurify sanitizeert bij export (`lib/services/marp_html_service.dart`).
3. Per-export CSP-nonce blokkeert scripts zonder nonce
   (`lib/services/marp_html_service.dart:317-324`).

**Kan de APT bestanden buiten het project lezen?** Alleen via B-01 (TOCTOU in
symlink-cache), vereist filesystem-access na openen. `../`-escapes en absolute paden
worden geblokkeerd (`lib/utils/project_path.dart:65-72`).

**Kan de APT naar interne hosts verbinden?** Nee. Alle deck-geleverde URLs gaan door
`NetGuard.safeResolve()` (`lib/utils/net_guard.dart:132-146`). Uitzondering: B-02
(video TOCTOU) en B-03 (web media), beide gedocumenteerd.

**Kan de APT exfiltreren via export?** Nee. `connect-src 'none'`, `img-src` zonder
`https:`, `form-action 'none'` sluiten alle netwerkpaden af (R-03 is theoretisch maar
praktisch geblokkeerd).

### Scenario 2: APT compromitteert een git-remote

**Kan dit leiden tot code-uitvoering?** Nee. Git draait met
`includeParentEnvironment: false`, `GIT_CONFIG_NOSYSTEM=1`,
`GIT_CONFIG_GLOBAL=/dev/null`, `core.hooksPath` naar lege sandbox
(`lib/services/git/git_cli_io.dart:156-257, 311-331`). Operand-validatie weigert `-`-prefix
en NUL/newlines. `runInShell: false`.

**Kan de APT het token stelen?** Het token reist via `GIT_CONFIG_VALUE_*` (niet argv,
niet remote-URL, niet `.git/config`). `http.followRedirects = false` voorkomt
token-lekkage via 3xx. `http.curloptResolve` pint het adres. Voor de levensduur van het
subprocess staat het token in de omgeving — een APT met `ptrace`-rechten op hetzelfde
systeem kan het lezen, maar dat vereist al OS-account-access (out of scope).

### Scenario 3: APT met WebDAV-write-access tot de collab-sidecar

**Kan de APT persistentie bereiken?** Ja — malafide log-records worden door alle
deelnemers uitgevoerd bij de volgende poll (B-08). De log heeft geen MAC of signature.

**Kan de APT authority overnemen?** Ja — de beacon is advisory, last-write-wins zonder
integriteit (B-08). De APT kan authority claimen of de sessie destabiliseren.

**Mitigatie.** De Matrix-transport (Fase 2) biedt E2EE. De WebDAV-transport is Fase 0.5
en bewust eenvoudig. "Only the owner saves" is een client-side gate, geen
server-enforced permissie.

### Scenario 4: APT op het netwerk (MITM)

**Kan de APT WebDAV/S3/git-verkeer onderscheppen?** Nee, tenzij de APT het CA-systeem
compromitteert. TLS is verplicht (http alleen met `trustedInternal` en zonder
herbruikbare geheimen voor S3; helemaal nooit voor WebDAV basic-auth). Certificaat-pinning
is fail-closed (`lib/utils/net_guard.dart:341-356`).

**Kan de APT URL-import onderscheppen?** Ja — URL-import heeft geen certificaat-pinning
(bewuste keuze voor publieke decks). De APT kan het deck vervangen als hij een
vertrouwd CA heeft. De inhoud gaat door `MarkdownSafetyScanner`.

### Scenario 5: APT compromitteert de build-pipeline

**Kan de APT de app backdoor-en?** Ja, maar dit valt buiten de app-code. De SBOM
(`make sbom`), de JS-bundel-pinning (`make deps-check`) en de release-signering
(`minisign`, `SHA256SUMS`) bieden detectie, maar geen preventie. De private
minisign-sleutel verlaat nooit de maintainer's machine.

---

## 7. Aanbevelingen naar prioriteit

### Defense-in-depth (implementatieverbeteringen, geen kwetsbaarheden)

1. **Constant-time hashvergelijkingen** (R-01) — voeg een `constantTimeEquals`-helper
   toe en pas toe op de vier locaties. Voeg een semgrep-regel toe die `==` op
   hash-variabelen flagt.

2. **`followRedirects = false` afdwingen in `pinned_http_client`** (R-02) — overweeg
   een wrapper die elke request onderschept, of een semgrep-regel die `openUrl` zonder
   `followRedirects = false` in dezelfde functie flagt.

### Supply chain

3. **`flutter_webrtc` libvpx-versie verifiëren** (R-04) — controleer de gebundelde
   libvpx-versie tegen CVE-2023-5217. Voeg een check toe aan `make deps-outdated`.

4. **`dartcv4` binary-integriteit** (R-05) — overweeg pad-afhankelijkheid met
   commit-hash of SHA-256-verificatie van de pakket-archive.

### Bestaande roadmap-items (bevestigd, geen nieuwe actie)

5. **TSA-signatuurverificatie** (B-06) — staat op de roadmap als §8-A3.
6. **Encryptie van recovery-snapshots** (B-04) — known, unimplemented improvement.
7. **macOS App Sandbox** (B-05) — tracked als migratie, niet een one-line fix.
8. **Collab cryptografische integriteit** (B-08) — Fase 2 (Matrix E2EE) lost dit op.

---

## 8. Oordeel

Het beveiligingsontwerp van OciDeck is **weerbaar tegen APT-niveau bedreigingen** binnen
de gestelde dreigingsaannames (vertrouwde machine, onvertrouwd netwerk, onvertrouwde
bestanden). Er zijn geen kritieke of hoge kwetsbaarheden die tot directe
code-uitvoering, ongeautoriseerde netwerktoegang of exfiltratie leiden vanuit een
kwaadaardig deck.

De bekende restrisico's (B-01 t/m B-09) zijn expliciet gedocumenteerd en geaccepteerd,
met duidelijke eigenaarschap en data. De nieuwe bevindingen (R-01 t/m R-05) zijn
defense-in-depth-verbeteringen en supply-chain-verificaties, geen exploiteerbare
kwetsbaarheden.

De sterkste kant van het ontwerp is de **consistentie**: elke uitgaande verbinding gaat
door dezelfde NetGuard-choke, elke deck-invoer gaat door dezelfde padcontainment- en
sanitatie-pijplijn, en elke beveiligingskeuze is in de code én in de documentatie
terug te vinden — met correctiecijfers waar eerdere documentatie ongelijk had.

De zwakste kant, vanuit APT-perspectief, is de **collab-module (Fase 0.5)**: de
WebDAV-transport heeft geen cryptografische integriteit, en de beacon is advisory. Een
APT met WebDAV-write-access kan de samenwerking saboteren zonder cryptografische
detectie. Dit is bewust zo ontworpen voor Fase 0.5 en wordt opgelost in Fase 2 (Matrix
met E2EE).
