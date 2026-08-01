# Ketenkeuring — XMPP als enkelvoudige spine (data + Jitsi-media) (GO/NO-GO)

> **Status:** opgesteld 2026-08-02 · Stichting LibreKAT · intern werkdocument
>
> Geen conformiteitsclaim en geen auditrapport. Zie [`README.md`](README.md).
>
> Deze keuring volgt op een **beheerdersbesluit (2026-08-02)**: uit open vraag 0 van
> [`docs/design/NATIVE_CALLS.md`](../docs/design/NATIVE_CALLS.md) §5 (één XMPP-spine vs
> twee-spine) is de **enkelvoudige XMPP-spine** gekozen. Zij keurt die route vóór de
> XMPP-clientlaag de netwerklaag in gaat, en staat naast de vier eerdere keuringen
> ([`ketenkeuring-matrix-sdk.md`](ketenkeuring-matrix-sdk.md),
> [`ketenkeuring-matrix-rust-sdk.md`](ketenkeuring-matrix-rust-sdk.md),
> [`ketenkeuring-self-encrypted-relay.md`](ketenkeuring-self-encrypted-relay.md),
> [`ketenkeuring-flutter-webrtc.md`](ketenkeuring-flutter-webrtc.md)). Zij deelt haar
> crypto-kern met de relay-keuring; lees die eerst.
>
> **De harde randvoorwaarde die het beeld bepaalt: backend-exclusiviteit.** Een sessie
> draait op precies één backend-familie — **óf** XMPP/Jitsi (calls én data-plane over
> één XMPP-verbinding), **óf** Matrix (self-encrypted relay + MatrixRTC). Deze twee
> **lopen nooit door elkaar**: nooit Jitsi-media met een Matrix-data-plane, nooit
> XMPP-data met MatrixRTC-media. "Hosten via de Matrix-backend" is een Matrix-mode-
> sessie, volledig los van de XMPP-mode. Dit is geen implementatiedetail maar de
> invariant die het hele vertrouwensmodel leesbaar houdt (Bevinding 6).

## Het besluit

**Aanbeveling: principieel GO — de XMPP-spine is de juiste primaire route naar
realtime-samenwerken *plus* calls; NO-GO om de code nú te bouwen tot vier voorwaarden
vervuld zijn.** De route is pure-Dart/permissief (Bevinding 1), en — cruciaal — zij
**hergebruikt de al aanvaarde minimale crypto-discipline van de relay** in plaats van
een nieuwe aan te gaan (Bevinding 2). De al-GE-GO'de self-encrypted relay
(`ketenkeuring-self-encrypted-relay.md`, 2026-07-31) wordt hierdoor **niet
overruled**: die blijft de spine voor de Matrix-mode; XMPP wordt de primaire spine.
Backend-exclusiviteit houdt beide coherent (Bevinding 3, 6).

Het besluit welke spine primair is, is genomen door de beheerder. Deze keuring geeft
de feiten en de vier bouwvoorwaarden; de formele bouw-GO hangt aan die voorwaarden, en
aan de GO van de losse media-dep (`ketenkeuring-flutter-webrtc.md`).

## Wat er gekeurd is

Het aannemen van **XMPP als primaire enkelvoudige spine**: een pure-Dart XMPP-cliënt
(`lib/xmpp/`) die één verbinding naar een Prosody/XMPP-server onderhoudt, waarover
tegelijk lopen:

- **de Jitsi-call-signalering** (MUC, Jingle, Colibri2 — de media-adapter uit
  `NATIVE_CALLS.md` §3/§7); en
- **de samenwerkings-data-plane** — `XmppTransport implements CollabTransport`
  (`lib/collab/collab_transport.dart`), de vierde transport naast Loopback,
  WebDAV-async en de Matrix-relay, met de op-payload versleuteld door OciDeck zelf.

Plus de invariant **backend-exclusiviteit** (één sessie = één familie, §boven).

Wat deze keuring uitdrukkelijk *niet* is: de media-dep zelf (`flutter_webrtc`, eigen
keuring), en niet het hosten van een eigen XMPP/SFU-server — OciDeck draait er geen
(P1, bring-your-own).

De feiten hieronder komen van pub.dev en de projectcode. Waar iets pas met een echte
`pub add` + poortdraai sluitend is, staat dat er zo — de dossierlijn uit
[`README.md`](README.md) geldt.

## Bevinding 1 — Licentie & keten: permissief, EUPL blijft

De data-spine voegt geen zware afhankelijkheid toe. Twee routes voor de XMPP-core, elk
door de bestaande poorten:

| Route | Wat het toevoegt | Aandachtspunt |
|---|---|---|
| **From-scratch `lib/xmpp/`** | vrijwel niets extern — Dart-sockets/`web_socket_channel`; hergebruikt `crypto`/`cryptography` (al aanwezig) | meer eigen code, dus meer eigen onderhoud en testlast |
| **Permissieve core forken** (bv. `moxxmpp`) | één lib + transitieve boom | licentie + boom te bevestigen met `pub add` → `make licenses`/`make sbom` |

Het Dart-XMPP-ecosysteem is overweldigend permissief (MIT/BSD/Apache); een *sluitend*
licentie-oordeel vergt een echte `pub add` gevolgd door `make licenses` en `make sbom`
(voorwaarde 1). Anders dan bij de Rust-route (#991) valt die boom binnen de bestaande
poorten (`pubspec.lock`) — geen Cargo-blinde vlek, geen tweede toolchain. Geen AGPL,
geen herlicensering; EUPL-1.2 blijft. Jingle/Colibri2 en de Jitsi-presence-extensies
zijn net-nieuw in beide routes.

## Bevinding 2 — De crypto is niet nieuw: het is het relay-schema (waarde 1)

Dit is de kern, en het is waar deze route *lichter* is dan het lijkt. E2EE over XMPP
vraagt **geen nieuwe crypto-verantwoordelijkheid**: het is exact het minimale schema
dat de relay-keuring al aanvaardde — X25519-ECDH → per-sessie AES-256-GCM (of
XChaCha20-Poly1305 zoals `SELF_ENCRYPTED_RELAY.md`), hersleutelen bij ledenwissel,
authenticated encryption — nu gedragen door een eigen XMPP-event-type/PubSub-item in
plaats van een Matrix-event. Dezelfde `CollabCrypto`, hetzelfde `package:cryptography`
(Apache-2.0).

- **De rode lijn is dezelfde en blijft staan:** géén herbouw van een eigen ratchet.
  XMPP's eigen volwassen E2EE (OMEMO, XEP-0384) *is* Double-Ratchet (libsignal) — exact
  de rode lijn. Die gebruiken we dus **niet**; we gebruiken het eigen minimale schema,
  net als bij de relay.
- **Gevolg:** de zwaarste post uit de relay-keuring (eigen crypto in beheer, externe
  toets) wordt niet twee keer betaald — het *schema* en de primitieven zijn hergebruikt.
  Eén crypto-kern, twee transporten: een reëel argument *vóór* de XMPP-spine. Maar "geen
  nieuw schema" is niet "geen nieuwe review": de **transport-binding is per drager
  nieuw** — herordening/replay (Matrix `/sync` vs. XMPP MUC/MAM/PubSub verschillen),
  ledenwissel→hersleutelen (Matrix-membership vs. MUC-affiliaties/presence), en
  associated-data die sessie én mode aan de ciphertext bindt zodat een Matrix-mode-
  ciphertext niet in XMPP-mode herbruikbaar is. Die binding hoort expliciet in de
  externe review-scope (voorwaarde 2).

## Bevinding 3 — Relatie tot de relay-GO: aanvullend, niet vervangend

De relay-GO (2026-07-31) wordt **niet overruled**. De verhouding, met
backend-exclusiviteit als scharnier:

- **XMPP-mode (primair):** één XMPP-verbinding draagt de Jitsi-calls én de data-plane.
  Voor wie óók belt is dit de zuinigste vorm — je hebt de verbinding tóch al.
- **Matrix-mode (alternatief):** de relay draagt de data-plane, MatrixRTC de media. Dit
  blijft de route voor wie in het Matrix-ecosysteem zit of via MatrixRTC belt.

De keuze van XMPP als *primaire* spine verschuift wel de **prioriteit**: de relay was
"de route naar realtime"; nu is XMPP dat voor de primaire/Jitsi-mode, en is de relay de
route voor de Matrix-mode. Welke van de twee eerst gebouwd wordt, is F-fase-planning
(`NATIVE_CALLS.md` §7), geen onderdeel van deze keuring. Wat vast staat: ze bestaan
naast elkaar en mengen niet.

## Bevinding 4 — Zonder SDK bouw je de sync-plumbing zelf (lateraal t.o.v. de relay)

Zoals de relay-keuring (Bevinding 4) al vaststelde voor Matrix' `/sync`: zonder
kant-en-klare SDK schrijf je de ordening en inhaal zelf. Bij XMPP is dat de MUC-stroom
plus **MAM** (XEP-0313, archief/inhaal na offline) en/of **PubSub** (XEP-0060,
persistente geordende event-nodes) voor de op-log en locks, en **HTTP File Upload**
(XEP-0363) of chunking voor snapshots onder de stanza-limiet. Dat is echt werk, en het
hoort eerlijk op de rekening — maar het is gewone REST/stanza-plumbing, geen crypto, en
het is *lateraal* aan wat de relay-route óók vergt. De autoriteit-, lock- en
versielogica hoeft niet opnieuw: die zit transport-agnostisch in `collab_session.dart`
achter de `CollabTransport`-seam.

## Bevinding 5 — Netwerkbeheersing: de signalering blijft binnen NetGuard

De uitgaande XMPP-verbinding (naar de door de gebruiker gekozen Prosody) gaat door
dezelfde `NetGuard`/redirect-refusal/DNS-rebind-houding als WebDAV, via
`MeetingProviderProfile` (`NATIVE_CALLS.md` §8). Anders dan de *media* (die buiten
NetGuard valt — de zorg van `ketenkeuring-flutter-webrtc.md`, Bevinding 3) is de
**data-spine gewoon een gecontroleerde socket**: begrensde stanza-afmetingen, geen
redirects, oversized invoer geweigerd. Onboarding via in-band registratie (XEP-0077)
kan in-app, zoals `COLLABORATION.md` §8 voor Matrix beschrijft — bring-your-own blijft
(P1). Metadata blijft zichtbaar voor de server (wie in welke MUC, wanneer), net als bij
Matrix (§9.3) — geen verslechtering.

Twee eerlijke toevoegingen. **(a)** De XMPP-cliënt is technisch een *tweede
netwerkstack* — Dart-sockets/`web_socket_channel`, niet het `http`-pakket. Net als bij
`flutter_webrtc` breekt dat de belofte *"the only HTTP client dependency is `http`"*
(`docs/ARCHITECTURE.md`); die zin wordt eerlijk bijgewerkt vóór de code landt
(voorwaarde 4). **(b)** Een zelfgebouwde stanza-parser leest *onvertrouwde XML* van het
net: naast begrensde afmetingen horen entiteitsexpansie-/XXE-weren en
namespace-verwarring bij de begrenzingen (voorwaarde 4).

## Bevinding 6 — Backend-exclusiviteit als beveiligings- en soevereiniteitseigenschap

Dat een sessie op precies één familie draait, is geen beperking maar een eigenschap.
Het houdt het vertrouwensmodel **leesbaar**: je weet welke server (Prosody óf de
homeserver) welke ciphertext en welke metadata ziet, omdat er per sessie maar één is.
Een mengvorm — Jitsi-media met een Matrix-data-plane, of omgekeerd — zou een tweede,
verborgen vertrouwenspartij en een cross-familie-datapad introduceren zonder dat de
gebruiker dat één-op-één kan overzien. De invariant sluit dat uit. Zij hoort daarom
niet alleen in de UI-laag maar als expliciete regel in het ontwerp
(`NATIVE_CALLS.md`), en als toets: geen codepad koppelt een `MeetingSession` van familie
A aan een `CollabTransport` van familie B.

De kostenkant, eerlijkheidshalve: er is **geen cross-familie-hergebruik**. Een
Matrix-native gebruiker die andermans publieke Jitsi joint, draait voor díe sessie een
*aparte* XMPP-data-plane en kan zijn Matrix-vertrouwen (verificaties, identiteit) er niet
in meenemen — de keerzijde van de leesbaarheid (§5, "publieke Jitsi ≠ jouw XMPP-server").

## Kernwaarde-toets (bewaker)

De ontwerprichting (natieve calls, de XMPP-spine als optie) is al eerder vanuit de
bewaker-blik goedgekeurd (PR #1095, "akkoord om te landen, mits de botsing hardop
benoemd"). Deze keuring legt de kéuze uit die botsing vast. De toets:

- **Kan de gebruiker zijn werk meenemen?** Ja, onveranderd. De sessie is vergankelijk
  (P2); het deck blijft een gewoon `.md`. De spine-keuze raakt het bestandsformaat niet.
- **Wie moet je vertrouwen, en is dat nieuw?** Runtime: de Prosody die de gebruiker zelf
  kiest (P1, bring-your-own) — een **open, gefedereerd** protocol, in openheid (waarde 2)
  eerder een winst dan een last t.o.v. een propriëtaire dienst. Nieuw: de XMPP-cliëntcode
  (`lib/xmpp/`), die net als de relay-transport getest en begrensd moet worden. De crypto
  is niet nieuw (Bevinding 2).
- **Waarde 6 (geen groen om de verkeerde reden):** de licentie-/SBOM-poort staat groen
  om de júiste reden (permissieve/pure-Dart route in `pubspec.lock`).
- **Waarde 1 (veiligheid op 1):** de spanning zit niet in de crypto (hergebruikt,
  aanvaard) maar in de **nieuwe netwerk-clientcode** en in het strak handhaven van
  backend-exclusiviteit. Beide zijn testbaar en begrensbaar; geen principieel beletsel.

De botsing die deze keuring beslecht — XMPP-spine boven de twee-spine-splitsing — is er
één van **coherentie tegen optooptelling**: één spine die je tóch al hebt, versus twee
stacks naast elkaar. Voor "meedoen én hosten even belangrijk" wint de coherentie.

## Alternatieven, in verhouding

- **A. Relay-only (Matrix-mode).** Blijft geldig en al GO, maar draagt geen calls op één
  spine; voor wie belt is een tweede stack nodig. Deze keuring vervangt A niet — A is de
  Matrix-mode die naast de XMPP-mode bestaat.
- **B. Twee-spine (relay voor data + Jitsi/LiveKit los voor media).** De afgewezen
  splitsing: meer bewegende delen, twee vertrouwenspartijen per sessie, en het risico op
  een cross-familie-datapad dat backend-exclusiviteit nu juist uitsluit.
- **C. Deze route — XMPP als primaire enkelvoudige spine.** Te verkiezen wanneer calls en
  co-auteuren beide tellen: één verbinding, één vertrouwenspartij per sessie, gedeelde
  crypto.

## Als het toch een GO wordt

Wordt besloten de code te bouwen, dan is een bouw-GO pas verantwoord als deze vier
voorwaarden vooraf en weloverwogen zijn vervuld — elk echt werk, geen vinkje:

1. **XMPP-lib-keuze + licentie-/SBOM-bevestiging.** Fork (bv. `moxxmpp`) of from-scratch
   beslist; een echte `pub add` gevolgd door groene `make licenses` en `make sbom` over
   de hele boom (Bevinding 1).
2. **Crypto = het relay-schema, extern getoetst — óók de tweede drager.** Geen nieuw
   schema: dezelfde minimale `CollabCrypto` als `SELF_ENCRYPTED_RELAY.md`, met
   testvectoren en mutatie-getoetste tests. De externe review moet **de
   XMPP-transport-binding expliciet dekken**, niet alleen de relay: herordening/replay
   via MUC/MAM/PubSub, ledenwissel→hersleutelen via MUC-affiliaties/presence, en
   mode/sessie-bindende associated-data. **Rode lijn: geen ratchet, dus geen OMEMO**
   (Bevinding 2).
3. **Backend-exclusiviteit als invariant vastgelegd en getoetst.** Eén sessie = één
   familie; een test die aantoont dat geen codepad een `MeetingSession` en
   `CollabTransport` van verschillende families koppelt (Bevinding 6).
4. **Verdedigende begrenzingen + eerlijke belofte.** `NetGuard`/SSRF-houding voor de
   Prosody-origin; begrensde stanza-/event-afmetingen; entiteitsexpansie-/XXE-weren in de
   stanza-parser; geen redirects; CSP `connect-src` voor de web-build. En: de "enige
   `http`-dependency"-belofte in `ARCHITECTURE.md` bijgewerkt, want de XMPP-cliënt is een
   tweede netwerkstack (Bevinding 5).

Anders dan bij #976 zit er geen licentie-/beleidsvoorwaarde in, en anders dan bij #991
geen Rust-/Cargo-/WASM-voorwaarde. De centrale voorwaarden zijn hier de **lib-keuze**
(1) en de **backend-exclusiviteit** (3); de crypto (2) leunt op de al lopende
relay-voorwaarde.

## Besluit

**Principieel GO — XMPP is de juiste primaire enkelvoudige spine voor realtime-
samenwerken plus Jitsi-calls; NO-GO om de code nú te bouwen tot de vier voorwaarden
vervuld zijn en de media-dep-GO (`ketenkeuring-flutter-webrtc.md`) genomen is.** De
route is *licentie- en toolchain-technisch* licht (pure-Dart/permissief, geen Rust) en
hergebruikt de al aanvaarde crypto-discipline; in code-oppervlak is zij juist de
zwáárste van de vier routes (XMPP-core + Jingle/Colibri2 + `flutter_webrtc`), wat het
onderhoudsbeslag (waarde 10) bij de bouw-GO reëel maakt. De relay-GO blijft staan als de
Matrix-mode-spine, en backend-exclusiviteit houdt beide gescheiden. Deze keuze
herlicenseert niets en omzeilt geen poort — maar zij houdt *niet* vanzelf elke belofte
overeind: de XMPP-cliënt is een tweede netwerkstack (geen `http`), dus de belofte *"the
only HTTP client dependency is `http`"* in `ARCHITECTURE.md` wordt eerlijk bijgewerkt,
net als bij `flutter_webrtc` (voorwaarde 4).

**Besloten (2026-08-02).** De beheerder heeft de knoop doorgehakt: **de enkelvoudige
XMPP-spine wordt de primaire route.** De self-encrypted relay (#977) blijft de
Matrix-mode-spine; de twee-spine-splitsing als vermenging wordt niet gevolgd. De vier
voorwaarden hierboven blijven staan als **bouwvoorwaarden**, met de lib-keuze en de
backend-exclusiviteit als de scherpe. Het uitgewerkte ontwerp staat in
[`docs/design/NATIVE_CALLS.md`](../docs/design/NATIVE_CALLS.md).
