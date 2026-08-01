# Ketenkeuring — pure-Dart self-encrypted relay (GO/NO-GO)

> **Status:** vastgesteld 2026-07-31 · Stichting LibreKAT · intern werkdocument
>
> **Bijgesteld 2026-08-02:** na het XMPP-spine-besluit
> ([`ketenkeuring-xmpp-spine.md`](ketenkeuring-xmpp-spine.md)) is deze relay niet langer
> *de* primaire realtime-route, maar de spine voor de **Matrix-mode**. De GO blijft; de
> positionering is versmald. Backend-exclusiviteit houdt de XMPP- en de Matrix-mode
> gescheiden (`docs/design/NATIVE_CALLS.md` §1).
>
> Geen conformiteitsclaim en geen auditrapport. Zie [`README.md`](README.md).
>
> Deze keuring is opgesteld terwijl [issue #977] (Fase 1 — Matrix-dataplane)
> heropend werd met de vraag: *wat is er mogelijk zónder herlicensering, en als de
> voor de hand liggende route dat niet kan, is er dan een alternatief dat de
> functionaliteit in Dart bouwt zodat EUPL-1.2 de licentie kan blijven?* Zij staat
> naast, niet in plaats van, de twee eerdere keuringen:
> [`ketenkeuring-matrix-sdk.md`](ketenkeuring-matrix-sdk.md) (#976, de famedly-SDK
> — NO-GO wegens AGPL) en
> [`ketenkeuring-matrix-rust-sdk.md`](ketenkeuring-matrix-rust-sdk.md) (#991, de
> permissieve Rust-route — NO-GO-nu, principieel GO). Referentie:
> [`COLLABORATION.md`](../docs/design/COLLABORATION.md) §5 (de transport-agnostische
> laag), §6 (Matrix als transport), §9 (E2EE als kernprincipe), en de
> kernwaarde-toets van de `bewaker`.

## Het besluit

**Aanbeveling: NO-GO om het nú te bouwen; principieel GO als de aangewezen route
naar realtime-samenwerken zónder AGPL én zónder Rust — mits de crypto minimaal
blijft en extern getoetst wordt.** Dit is de enige van de vier onderzochte routes
die tegelijk *realtime*, *pure Dart* en *EUPL-schoon* is. De blokker van #976 (een
publieke belofte die niet stilzwijgend gebroken mag worden) speelt hier niet, net
zomin als bij #991: er wordt niets geherlicenseerd. En de last van #991 (een
doorlopende Rust-binding, een tweede toolchain, een SBOM-blinde vlek en een
onopgelost web) valt grotendeels wég.

Wat ervoor in de plaats komt is één ding, en het is wezenlijk: **OciDeck neemt de
E2EE-crypto zelf in beheer.** Niet de zware, beveiligingskritische herbouw van
Olm/Megolm die #976 terecht afraadde — maar een *minimaal* schema op gevette,
permissieve pure-Dart-primitieven. De hele levensvatbaarheid van deze route hangt
aan die ene discipline: zodra het schema richting een eigen ratchet kruipt, is
#991 (de beproefde crypto van matrix.org) strikt beter. Dáár, en niet in een
licentie of een belofte, zit de reden om nu nog niet te bouwen.

De aanbevolen scheepbare stap blijft ongewijzigd: **Fase 0.5 — WebDAV-async**
([#989], geleverd) voor asynchroon co-auteuren zonder nieuwe deps. Deze route is
de te verkiezen *realtime* vervolgstap zodra iemand het beheer van minimale
sessie-crypto weloverwogen aanvaardt en de voorwaarden onder [*Als het toch een GO
wordt*](#als-het-toch-een-go-wordt) vervuld zijn.

De formele knoop — het aangaan van eigen, minimale sessie-crypto met externe toets
— ligt bij de beheerder. Deze keuring geeft het advies en de feiten; de knoop is
aan de stichting.

## Wat er gekeurd is

De route "**Matrix-homeserver als versleuteld doorgeefluik**": een pure-Dart
`CollabTransport`-implementatie die de *gewone* Matrix client-server-API spreekt
(registreren, inloggen, `/sync`, een event versturen) over de al aanwezige
`http`-afhankelijkheid, met de op-payload versleuteld door OciDeck zélf — met een
minimaal X25519→AES-256-GCM-schema uit een permissieve pure-Dart-cryptobibliotheek,
**niet** met Matrix' eigen Olm/Megolm.

Het cruciale onderscheid, en de reden dat deze route bestaat: wat de AGPL (#976) en
de Rust (#991) binnenbracht was **uitsluitend Matrix-eigen E2EE** (Olm/Megolm via
`vodozemac`). Al het andere van de client-server-API is gewoon REST + JSON, in pure
Dart te doen. En OciDeck heeft die Matrix-eigen E2EE niet nodig, omdat zijn ops in
een eigen event-type (`nl.ocideck.op`, `COLLABORATION.md` §6.1) zitten dat geen
enkele andere Matrix-client leest. Door de Matrix-eigen E2EE te vervangen door een
eigen laag over dezelfde REST-API, verdwijnt de hele AGPL/Rust-vraag en wordt #977
een pure-Dart-functie.

Wat deze keuring uitdrukkelijk *niet* is: de upstream `vodozemac`-crate of `libolm`
binden en zélf een volledige Matrix-client schrijven (dat raadde #976 al af), en
evenmin de twee al gekeurde SDK-routes.

De feiten hieronder komen van pub.dev en de code van deze repo; er is nagekeken wat
er staat, niet wat het geheugen ervan maakte. Waar iets niet zonder een echte
`pub add` + poortdraai is vast te stellen, staat dat er zo — de dossierlijn uit
[`README.md`](README.md) geldt: een gat aanwijzen is meer waard dan het dichtpraten.

## Bevinding 1 — Licentie & keten: permissief, EUPL blijft (beide eerdere blokkers vervallen)

De bouwstenen zijn permissief en staan alle in `allowedLicenses`
(`tool/license_detect.dart`):

| Component | Herkomst | Licentie |
|---|---|---|
| `package:cryptography` (X25519, Ed25519, AES-GCM, HKDF) | dint.dev (terrier989) | **Apache-2.0** |
| `http` (al aanwezig) | dart.dev | **BSD-3-Clause** |
| `crypto` (al aanwezig; hashing) | dart.dev | **BSD-3-Clause** |

`package:cryptography` levert de nodige primitieven in **pure Dart** met
platform-versnelde paden waar beschikbaar, en draait op alle vier de bouwtargets
**inclusief web** (JS- én WASM-compiler) — de pure-Dart-fallback dekt web zonder een
zelfgebouwd artefact. Geen AGPL, geen Rust, geen herlicensering, geen breuk met
`docs/LICENSE_COMPLIANCE.md`. Dit haalt de eigen poort waar #976 hem liet vallen, en
zonder de Rust-boom die #991's licentie-oordeel onvolledig liet.

**Twee eerlijke kanttekeningen.**

- *De volledige boom is nog niet opgelost.* `cryptography` brengt zelf een handvol
  transitieve Dart-deps mee. Het Dart-ecosysteem is overweldigend BSD/MIT/Apache,
  maar een *sluitend* oordeel vergt een echte `pub add` gevolgd door `make licenses`
  en `make sbom`. Dat is voorwaarde 2 onder [*Als het toch een GO
  wordt*](#als-het-toch-een-go-wordt), niet iets dat deze keuring al bewijst. Anders
  dan bij #991 valt die boom wél binnen de bestaande poorten (`pubspec.lock`), dus de
  toets is er al — hij is alleen nog niet gedraaid.
- *Eén beheerderspunt.* `cryptography` wordt door één uitgever onderhouden. Klein
  toeleveringsoppervlak, maar wel een vertrouwenspunt op de meest gevoelige
  component. Meewegen, geen blokkade; het pint zich vast in de SBOM zoals elke andere
  dep.

## Bevinding 2 — De crypto komt in eigen beheer: de zwaarste post (waarde 1)

Dit is de kern, en het is waar deze route staat of valt. OciDeck ruilt een
licentie-/toolchainprobleem in voor een **beveiligingsverantwoordelijkheid**: het
schema dat de sessie-inhoud beschermt is voortaan van OciDeck, niet van matrix.org.

Het verschil met de DIY-crypto die #976 afraadde is reëel, maar het moet met
discipline bewaakt worden:

- **Wél aanvaardbaar** — een *minimaal* schema op gevette primitieven: de eigenaar
  wisselt X25519-ECDH met elke joiner, versleutelt een per-sessie AES-256-GCM-sleutel
  naar diens publieke sleutel, en hersleutelt bij een ledenwissel. Authenticated
  encryption, standaard sleuteluitwisseling, niets zelfbedachts op primitiefniveau.
  Dit is dezelfde klasse als de bestaande pakketversleuteling (AES-256), niet zwaarder.
- **De rode lijn** — géén herbouw van een eigen ratchet (Double Ratchet / Megolm).
  Dat is precies de grote, beveiligingskritische onderneming die de `bewaker` bij
  #976 afwees (waarde 1). Kruipt het ontwerp die kant op, dan vervalt de reden om deze
  route boven #991 te verkiezen.

Wat je bewust inlevert tegenover Matrix-eigen E2EE: geen per-bericht forward secrecy
via een ratchet (wél per-sessie plus hersleutelen). Gezien P2 (kamer = vergankelijk
transport, bestand = waarheid) en P3 (owner-authoritative, klein gezelschap) is dat
een verdedigbare, bewuste versimpeling voor kortlevende co-auteursessies — maar het
is een afweging van de stichting, geen bijvangst.

**Daarom is externe toetsing van het crypto-ontwerp voorwaarde 1.** Het schema moet
een geschreven spec krijgen, tegen bekende testvectoren draaien en mutatie-getoetst
zijn — behandeld als beveiligingskritisch onderdeel, op één lijn met de
pakketversleuteling.

## Bevinding 3 — Geen Matrix-eigen E2EE-interop, en dat is precies goed

Doordat de inhoud niet met Olm/Megolm maar met OciDecks eigen laag versleuteld is,
zijn de ops **niet leesbaar of verifieerbaar door Element/FluffyChat**. Dat klinkt
als verlies maar is het niet: de ops zitten in een eigen event-type dat die clients
sowieso nooit lazen. Er gaat niets verloren wat OciDeck wilde.

Wél verlies je twee dingen die de Matrix-SDK gratis meebracht, en beide moeten in
eigen ontwerp terug:

- **Device-verificatie.** Matrix' cross-signing valt weg; de "onbekend nieuw
  device"-moment uit `COLLABORATION.md` §8 moet OciDeck zelf oplossen, met een eigen
  vingerafdruk/SAS-vergelijking tussen deelnemers (voorwaarde 3).
- **Provenance-identiteit.** De Ed25519-ondertekening voor de owner-signature op het
  uitgeleverde deck (Fase 2, [#978], §9.2) komt uit dezelfde `cryptography`-lib in
  plaats van uit Matrix' identiteitslaag — feitelijk eenvoudiger, want geen SSSS/Key
  Backup nodig voor *inhoud* (die overleeft in het bestand, P2).

De runtime-vertrouwensvraag verandert niet: de gebruiker kiest zelf zijn homeserver
(P1, bring-your-own), en die ziet ciphertext. Metadata blijft zichtbaar voor de
server — net als bij Matrix-eigen E2EE (§9.3), dus geen verslechtering.

## Bevinding 4 — Zonder SDK herbouw je de sync-plumbing zelf

`COLLABORATION.md` §6.2 stelt dat ordening en aflevering bij Matrix "gratis" komen —
maar dat geldt via de SDK. Zonder SDK schrijf je zelf: de `/sync`-lus (long-poll met
sync-token), de herverbind-inhaal na een offline-moment, en het chunken van
snapshots onder de ~64 KiB-eventcap (§6.3). Dat is echt werk, en het is de prijs van
"geen SDK". Het is beheersbaar — het is gewone REST-plumbing, geen crypto — maar het
hoort eerlijk op de rekening, niet weggewuifd met "Matrix regelt ordening".

De autoriteit-, lock- en versielogica hoeft *niet* opnieuw: die is transport-agnostisch
gebouwd in Fase 0 ([#975]) en zit in `collab_session.dart` achter de
`CollabTransport`-seam in `collab_transport.dart`. De nieuwe transport is een
inplugbare vierde implementatie naast `LoopbackTransport`, `WebdavAsyncTransport` en
de latere Matrix-SDK-variant; de sessie-bootstrap en snapshot-slot uit Fase 0.5
(`collab_snapshot.dart`, `collab_session_launch.dart`, `collab_log_store.dart`) zijn
er al en zijn transportonafhankelijk herbruikbaar.

## Bevinding 5 — Wat deze route wegneemt tegenover #991

Drie van de vier voorwaarden die #991 (matrix-rust-sdk) een GO in de weg legden,
verdampen hier, omdat ze aan Rust hingen, niet aan de licentie:

- **Geen Rust-toolchainpoort.** Er komt geen tweede verplichte toolchain in het
  kritieke bouwpad; `make check-toolchain` en de uitbrengketen blijven "één Flutter,
  laatste stable".
- **Geen SBOM-blinde vlek.** Er is geen `Cargo.lock`; de nieuwe dep staat in
  `pubspec.lock` en valt daarmee vanzelf onder `make sbom` en `make licenses`. De
  CRA-inventaris (Annex I) blijft volledig zonder nieuw gereedschap.
- **Geen zelfgebouwde WASM-webborging.** De pure-Dart-crypto draait op web zonder een
  buiten-pub-om gebouwd artefact; de webketen-bewaking (`tool/check_bundled_js.dart`
  tegen `MANIFEST.json`) hoeft niet uitgebreid.

Wat overblijft aan webzorg is licht: de CSP `connect-src` moet de homeserver-origin
(https, voor de long-poll — geen `wss:` nodig als je niet streamt) toestaan, langs
`make build-web` / `tool/check_web_hardening.dart`. Dat is een bestaande poort met
een bekende ingreep, niet een nieuwe borgingsopgave.

## Bevinding 6 — Verdedigende begrenzingen (spiegel van de bestaande houding)

Zoals `COLLABORATION.md` §11 voorschrijft en `file_service.dart` /
`webdav_service.dart` al doen: de nieuwe uitgaande host (de homeserver) moet door
dezelfde `NetGuard`/SSRF-houding als WebDAV — geen HTTP-redirects, geen
privé-adresbereik zonder expliciete `trustedInternal`-opt-in. Inkomende ops en
snapshots krijgen begrensde afmetingen en aantallen; oversized invoer wordt
geweigerd. Compressie/crypto voor snapshots draait in een isolate met statische
helpers (perf-patronen). Dit is geen nieuw werk maar het doortrekken van de
bestaande lijn naar transport #4.

## Kernwaarde-toets (bewaker)

- **Kan de gebruiker zijn werk meenemen?** Ja, onveranderd. Samenwerken is
  vergankelijk (P2); het deck blijft een gewoon `.md`. De transportkeuze raakt het
  bestandsformaat niet — stopt OciDeck morgen, dan overleven de decks het.
- **Wie moet je vertrouwen, en is dat nieuw?** Runtime: de homeserver die de
  gebruiker zelf kiest (P1, bring-your-own, blijft overeind) — géén AGPL-partij, géén
  matrix.org-client-code. Nieuw en wezenlijk: **OciDeck zelf**, voor het
  crypto-protocol, plus de `cryptography`-onderhouder voor de primitieven.

Waar #976 op drie waarden botste, botst deze route op **één**:

- **Waarde 2 (openheid) en 4 (integriteit van beloftes):** geruststellend, net als
  bij #991. Er wordt geen publieke belofte gebroken; de licentievloer blijft staan.
- **Waarde 6 (geen groen om de verkeerde reden):** hier *sterker* dan bij #991 — de
  licentie- en SBOM-poort staan groen om de júiste reden (pure-Dart dep in
  `pubspec.lock`), zonder de `Cargo.lock`-blinde vlek die #991 apart moest repareren.
- **Waarde 1 (veiligheid op 1):** dít is de spanning. De crypto komt in eigen beheer.
  De route is alleen verantwoord als het schema minimaal blijft (Bevinding 2) en
  extern getoetst wordt. Dat is geen principieel beletsel zoals de AGPL bij #976, maar
  een discipline- en capaciteitsvraag — dezelfde soort als bij #991, alleen verlegd
  van "onderhoud een Rust-binding" naar "beheer minimale sessie-crypto".

De botsing is dus **ambitie tegen discipline**, niet waarde-tegen-belofte. Daarin
lijkt deze route op #991; het verschil is dat de blijvende last hier *crypto-beheer*
is in plaats van *binding-/toolchainbeheer*, en dat de web-, SBOM- en toolchainkosten
wegvallen.

## Alternatieven, in verhouding

- **A. Fase 0.5 — WebDAV-async ([#989], geleverd).** Blijft de scheepbare stap voor
  asynchroon co-auteuren zonder nieuwe deps. Deze keuring vervangt A niet; ze biedt de
  *realtime* vervolgstap die A per ontwerp niet is.
- **B. matrix-rust-sdk (Apache-2.0) achter een Dart-FFI ([#991]).** De beproefde
  crypto van matrix.org, maar Rust, een doorlopende bindingslast en een onopgelost web.
  Strikt te verkiezen bóven deze route zodra het eigen crypto-schema niet minimaal kan
  blijven, of zodra de bindings-/toolchaincapaciteit er wél is en volledige
  Matrix-interop gewenst is.
- **C. Deze route.** Te verkiezen boven B wanneer *pure Dart, werkend web en een
  schone SBOM* zwaarder wegen dan volledige Matrix-eigen E2EE-interop, én de discipline
  van een minimaal, extern getoetst crypto-schema geborgd is.

De keuze tussen B en C is de kern van wat de beheerder beslist: **beproefde crypto met
zware bouwlast (B), of lichte bouwlast met eigen, minimaal-gehouden crypto (C).**

## Als het toch een GO wordt

Wordt besloten deze route te bouwen, dan is een GO pas verantwoord als deze vier
voorwaarden vooraf en weloverwogen zijn vervuld — elk is echt werk, geen vinkje:

1. **Crypto-ontwerp vastgelegd én extern getoetst.** Een geschreven spec van het
   minimale schema (X25519-ECDH → per-sessie AES-256-GCM, hersleutelen bij ledenwissel),
   met testvectoren en mutatie-getoetste tests, en een externe review. **De rode lijn:
   geen herbouw van een ratchet** (Bevinding 2).
2. **Volledige licentie-/SBOM-bevestiging.** Een echte `pub add cryptography` gevolgd
   door groene `make licenses` en `make sbom` over de hele transitieve boom (Bevinding 1).
3. **Device-verificatie-UX ontworpen.** Het "onbekend nieuw device"-moment uit §8 in
   OciDecks eigen termen — vingerafdruk/SAS-vergelijking — in plaats van Matrix'
   cross-signing (Bevinding 3).
4. **Verdedigende begrenzingen doorgetrokken.** `NetGuard`/SSRF-houding voor de
   homeserver-host, begrensde event-/snapshot-afmetingen, en de CSP `connect-src` voor
   de web-build (Bevindingen 4, 6).

Anders dan bij #991 zit er **geen Rust-toolchain-, geen Cargo-SBOM- en geen
WASM-webvoorwaarde** in deze lijst; de centrale voorwaarde is hier de crypto-review.
En anders dan bij #976 zit er **geen licentie-/beleidsvoorwaarde** in: er hoeft niets
overruled te worden.

## Besluit

**NO-GO om het nú te bouwen; principieel GO als de aangewezen route naar
realtime-samenwerken zónder AGPL of Rust, mits de crypto minimaal blijft en extern
getoetst wordt.** De scheepbare stap blijft Fase 0.5 (WebDAV-async, [#989]). Deze
route is de te verkiezen realtime vervolgstap boven #991 wanneer pure Dart, werkend
web en een schone SBOM zwaarder wegen dan volledige Matrix-eigen E2EE-interop — en
alleen zolang het crypto-schema minimaal en extern getoetst is. Deze keuze houdt elke
huidige publieke belofte overeind: er wordt niets geherlicenseerd en geen poort
omzeild.

Het antwoord op de vraag die deze keuring opriep — *kan realtime-samenwerken zónder
herlicensering, en zo ja in Dart?* — is **ja**: niet via een kant-en-klare
Matrix-SDK (de enige volwassen Dart-SDK is AGPL), maar via de homeserver als
versleuteld doorgeefluik met een eigen, minimaal E2EE-schema in pure Dart. Of en
wanneer OciDeck de bijbehorende crypto-verantwoordelijkheid aangaat, is een besluit
van de beheerder, niet van de keuring.

**Besloten (2026-07-31).** De beheerder heeft de knoop doorgehakt: **GO voor deze
route** als de aangewezen weg naar realtime-samenwerken. OciDeck bouwt een eigen,
pure-Dart implementatie (de homeserver als versleuteld doorgeefluik met een eigen
minimaal E2EE-schema), zodat EUPL-1.2 de licentie blijft; route #991 (matrix-rust-sdk)
en de famedly-SDK (#976) worden niet gevolgd. De vier voorwaarden hierboven blijven
staan als **bouwvoorwaarden**, met voorwaarde 1 (minimaal cryptoschema, geen eigen
ratchet, externe toets) als de harde, want de hele reden dat deze route boven #991
verkozen kan worden hangt aan die discipline. Het licentiebeleid blijft ongewijzigd;
er wordt niets geherlicenseerd.

Het uitgewerkte, bruikbare ontwerp dat op dit besluit volgt staat in
[`docs/design/SELF_ENCRYPTED_RELAY.md`](../docs/design/SELF_ENCRYPTED_RELAY.md).

[issue #977]: https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/977
[#975]: https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/975
[#978]: https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/978
[#989]: https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/989
[#991]: https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/991
