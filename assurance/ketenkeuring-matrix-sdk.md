# Ketenkeuring — de Matrix-Dart-SDK (GO/NO-GO)

> **Status:** vastgesteld 2026-07-30 · Stichting LibreKAT · intern werkdocument
>
> Geen conformiteitsclaim en geen auditrapport. Zie [`README.md`](README.md).
>
> Dit is de toeleveringsketenkeuring die [issue #976] vraagt: het enige moment
> waarop spoor B (samenwerken) nog kan terugsturen vóórdat de netwerklaag de repo
> in gaat. Referentie: [`COLLABORATION.md`](../docs/design/COLLABORATION.md) §6
> (Matrix als transport) en §11 (afhankelijkheden), en de kernwaarde-toets van de
> `bewaker`.

## Het besluit

**Aanbeveling: NO-GO op de `matrix`-Dart-SDK zoals voorgesteld** — niet omdat
samenwerken verkeerd is, maar omdat déze keten twee dingen meebrengt die het
project bewust buiten de deur houdt, en één daarvan is een *publieke belofte* die
niet stilzwijgend gewijzigd mag worden:

1. De SDK én zijn verplichte cryptolaag (`vodozemac`) zijn **AGPL-3.0**. Dat botst
   frontaal met het eigen, in code afgedwongen licentiebeleid van OciDeck, en
   opnemen betekent dat de *uitgeleverde gecombineerde binary* onder AGPL-3.0
   komt te vallen — een de-facto herlicensering van EUPL-1.2 naar AGPL-3.0.
2. De cryptolaag is **native Rust** die op drie van de vier bouwtargets uit de
   bron gecompileerd moet worden, plus een handmatige WASM-bouw voor het web. Dat
   zet een tweede verplichte toolchain in het kritieke bouwpad, tegen de vaste
   lijn "één Flutter, laatste stable".

De keten is *technisch* draagbaar — alle platformen worden ondersteund en de
licentie is onder EUPL-1.2 artikel 5 juridisch combineerbaar — maar alleen na
expliciete besluiten en gereedschapswerk die de huidige poorten nog niet dekken.
Zolang die besluiten niet genomen zijn, valt de licentiepoort (`make licenses`)
rood en zou een merge de eigen belofte breken.

**De aanbevolen weg vooruit is niet die kosten nú betalen**, maar de al geplande
**Fase 0.5 — WebDAV-async-transport** ([`COLLABORATION.md`](../docs/design/COLLABORATION.md)
§10, Fase 0.5): asynchroon co-auteuren over de Nextcloud/WebDAV die de gebruiker
al heeft ingesteld, met **nul nieuwe afhankelijkheden, geen AGPL en geen Rust**.
Realtime-Matrix komt terug op tafel zodra de beheerder het licentiebeleid
weloverwogen wil bijstellen, of er een lichtere weg blijkt.

De formele knoop — het beleid overrulen en de vier voorwaarden hieronder
aanvaarden, wat een *GO* is — ligt bij de beheerder; die staat in
[*Als het toch een GO wordt*](#als-het-toch-een-go-wordt).

## Wat er gekeurd is

De `matrix`-Dart-SDK (uitgever famedly.com, laatste versie 9.0.0), de SDK die
FluffyChat gebruikt en die `COLLABORATION.md` §6 voorstelt. Gekeurd op de vier
punten die #976 noemt: de transitieve boom inclusief de native crypto voor E2EE,
de licenties, de SBOM-gevolgen, en de vraag of de native component op de vier
bouwtargets (macOS, Windows, Linux) + web te dragen is.

De feiten hieronder komen van pub.dev en de uitgever, niet uit het geheugen; de
poortverwijzingen zijn nagekeken in de code van deze repo.

## Bevinding 1 — Licentie: AGPL-3.0 (blokkerend onder het huidige beleid)

Zowel de SDK als zijn verplichte cryptolaag is AGPL-3.0:

| Pakket | Uitgever | Licentie |
|---|---|---|
| `matrix` 9.0.0 | famedly.com | **AGPL-3.0** |
| `vodozemac` 0.5.0 (Dart-binding, transitief via `matrix`) | famedly.com | **AGPL-3.0** |
| `flutter_vodozemac` 0.6.0 (native laadlaag) | famedly.com | **AGPL-3.0** |

**Dit valt de eigen poort.** OciDeck heeft een geschreven én afgedwongen
licentiebeleid. `docs/LICENSE_COMPLIANCE.md` somt de aanvaarde families op (MIT,
BSD, Apache-2.0, MPL-2.0, ISC, Zlib, BSL-1.0, Unlicense, OFL-1.1, CC0, en
EUPL-1.2 voor OciDeck zelf) en zegt met zoveel woorden: "Anything else — in
particular GPL/AGPL/LGPL — is flagged for review before it can be added." Die
regel is geen tekst maar code: `tool/check_licenses.dart` toetst elk opgelost
pakket tegen `allowedLicenses` in `tool/license_detect.dart` (AGPL zit daar niet
in; `licenseForPackage` herkent "gnu affero" als `AGPL`) en beëindigt met een
foutcode. De poort draait als `make licenses`, onderdeel van `make check-full` en
`make check-release`. Twee AGPL-pakketten toevoegen laat die poort dus hard
vallen.

**Juridisch mág het — maar het herlicenseert het product.** AGPL-3.0 staat op de
compatibiliteitslijst van EUPL-1.2 (artikel 5). Combineert EUPL-code met een
compatibel-gelicentieerd werk, dan bepaalt de compatibele licentie het
gecombineerde werk: bij een botsing "shall the obligations of the Compatible
Licence prevail". De uitgeleverde OciDeck-binary die de matrix-SDK linkt, wordt
daarmee een **AGPL-3.0-werk** — met onder meer de netwerkclausule (§13: wie een
gewijzigde versie als netwerkdienst draait, moet de bron aanbieden). Dat is niet
verboden en het schaadt de vrijheid van de gebruiker niet (AGPL is opensource),
maar het is een verandering van wat OciDeck publiek over zichzelf zegt. Zo'n
wijziging is een besluit van de stichting, geen bijvangst van een `pub add`.

**Nuance die de alternatieven opent.** De AGPL is een keuze van famedly voor hun
Dart-laag, niet van de cryptografie zelf. De *upstream* Rust-crate
[`vodozemac`](https://github.com/matrix-org/vodozemac) van matrix.org is
**Apache-2.0**; het oudere `libolm` is dat ook. De AGPL wordt binnengebracht door
de Dart-bindingen en de SDK, niet door de onderliggende Olm/Megolm-implementatie.
Zie [alternatief B](#alternatieven-bij-no-go).

## Bevinding 2 — Native toolchain: Rust verplicht op drie van de vier targets

`vodozemac` is een Rust-bibliotheek, gebonden via `flutter_rust_bridge` (exact
gepind op 2.11.1) en gebouwd met cargokit. De uitgever levert **geen** kant-en-
klare binaries voor de bureaubladtargets; die worden bij de app-bouw uit de
Rust-bron gecompileerd, waarvoor cargokit een lokale Rust-toolchain nodig heeft
(het bootstrapt rustup en de doeltripletten op de eerste bouw). Uitgesplitst naar
de OciDeck-targets:

| Target | Native-crypto-route | Rust nodig bij de bouw? |
|---|---|---|
| macOS / iOS (via Swift Package Manager) | voorgebouwd `flutter_vodozemac.xcframework` | Nee |
| macOS / iOS (via CocoaPods) | cargokit-bronbouw | Ja |
| Windows | cargokit-bronbouw | **Ja** |
| Linux | cargokit-bronbouw | **Ja** |
| Web | handmatige WASM-bouw (`cargo` + `flutter_rust_bridge_codegen`) | **Ja** |

Dat is een tweede verplichte toolchain in het kritieke bouwpad. Het botst met
drie vaste lijnen van dit project:

- **"Eén Flutter, laatste stable."** `make check-toolchain` (een statische poort
  in `make check`) eist voor Flutter een vast kanaal, een officiële herkomst en
  gelijkheid met de pin in `.tool-versions`. Voor een Rust-toolchain bestaat dat
  niet; die zou een gelijkwaardige poort en pin nodig hebben, anders is de
  bouwreproduceerbaarheid weg.
- **De uitbrengketen.** Eén `v*`-tag bouwt de vier targets; elke release-runner
  (en de GitHub-spiegel-CI) zou voortaan `cargo` moeten hebben en het WASM-
  artefact moeten kunnen produceren. Vandaag heeft de keten alleen Flutter nodig,
  plus een C++-toolchain voor `dartcv4` (OpenCV).
- **Het web.** De hardened webbouw (`make build-web`) krijgt er een handmatige,
  buiten-pub-om gebouwde WASM-crypto bij. `COLLABORATION.md` §10 (Fase 1) noemt al
  dat de CSP `connect-src` de homeserver-`wss:` moet toestaan; de WASM-bouwstap
  komt daar bovenop.

## Bevinding 3 — SBOM-blinde vlek (CRA Annex I onderrapporteert)

`tool/generate_sbom.dart` (via `tool/sbom_build.dart`) stelt de SBOM samen uit
`pubspec.lock`, `assets/web_export/MANIFEST.json`, `pubspec.yaml` en
`.tool-versions`. Het leest **geen** `Cargo.lock`. De eigen
afhankelijkhedenboom van `vodozemac` — de Rust-crates die de daadwerkelijk
uitgeleverde crypto vormen (curve25519-dalek, ed25519-dalek, en wat die weer
binnenhalen) — is voor de generator onzichtbaar.

Gevolg: de SBOM die `COLLABORATION.md` §11 als voorwaarde noemt ("keep the SBOM
in step") zou de meest beveiligingsgevoelige component in het hele pakket —
native cryptocode — **onvolledig** beschrijven. Dat is precies het tegendeel van
waarvoor de SBOM bestaat (de inventaris die de CRA, Annex I deel II §1, vraagt).
Vóór een eerlijke GO moet het SBOM-gereedschap eerst `Cargo.lock` mee kunnen
lopen; anders is "make sbom is groen" groen om de verkeerde reden.

## Bevinding 4 — De webbundel-borging dekt geen zelfgebouwde WASM

De supply-chain-poort voor het web is `make deps-check` (`tool/check_bundled_js.dart`)
tegen `assets/web_export/MANIFEST.json`: elk ingesloten JS/CSS-bundel is een
npm-pakket met een exacte versie (voor de OSV-kwetsbaarheidsquery) en een sha256
(integriteit tegen sluipende vervanging). Een zelfgebouwde Rust→WASM-cryptoblob
past niet in dat model: het is geen npm-pakket dat OSV kent, en het wordt
*gebouwd*, niet gedownload. De bestaande webketen-bewaking zou de nieuwe
WASM-crypto dus **niet** dekken. Er is een aparte integriteits- en
herkomstborging nodig (pin op de bron-crate-versie plus een reproduceerbare
bouw), en die bestaat nu niet.

## Bevinding 5 — Transitief Dart-oppervlak en een native SQLite-opslag

`matrix` 9.0.0 brengt 22 directe afhankelijkheden mee. De meeste zijn onschuldig
of al aanwezig (`http`, `markdown`, `image`, `web`, `collection`, `path`), maar
twee categorieën verdienen aandacht:

- **Native erbij naast `vodozemac`:** `sqlite3` (C) voor de lokale Matrix-opslag,
  meestal met `sqlite3_flutter_libs` per platform. Mogelijk vermijdbaar: P2 zegt
  *bestand = waarheid, room = vergankelijk transport*, dus een sessie hoeft geen
  duurzame SQLite-store — een in-memory- of geen-persistentie-store zou de C-
  afhankelijkheid kunnen wegnemen. Te onderzoeken bij een eventuele GO.
- **Kleine één-beheerder-pakketten:** `base58check`, `random_string`, `slugify`,
  `sdp_transform`, `canonical_json`. Klein toeleveringsoppervlak, elk een eigen
  vertrouwenspunt. Geen blokkade, wel meetellen.

Het SBOM-onderdeeltal springt van de huidige 210 (alle permissief:
BSD/MIT/Apache/MPL/OFL/BSL) omhoog, en de licentietabel krijgt er voor het eerst
een netwerk-copyleft-familie bij.

## Kernwaarde-toets (bewaker)

De vijf vragen van de `bewaker`, toegepast op déze keten:

- **Kan de gebruiker zijn werk meenemen?** Ja. Samenwerken is vergankelijk (P2);
  het deck blijft een gewoon `.md`. De transportkeuze raakt het bestandsformaat
  niet — Fase 0 is bewust transport-agnostisch gebouwd. De scherpste toets ("stopt
  OciDeck morgen — kan de gebruiker verder?") slaagt: de decks overleven het.
- **Wie moet je vertrouwen, en is dat nieuw?** Twee nieuwe partijen: famedly (de
  code) en, bij de bouw, de Rust-toolchain plus crates.io. Runtime-vertrouwen in
  een homeserver is de keuze van de gebruiker (P1 blijft overeind — bring-your-own).

Het **ontwerp** botst dus niet met de waarden; de **keten** doet dat wel, en op
drie waarden:

- **Waarde 2 (openheid, navolgbaar besluit) en 4 (integriteit, toetsbare
  beloftes):** OciDeck belooft publiek een licentievloer die AGPL uitsluit. Die
  belofte stilzwijgend breken om een functie te krijgen, is precies wat waarde 4
  verbiedt. Overrulen mag, maar dan hardop en gedateerd.
- **Waarde 6 (betrouwbaarheid, geen groen om de verkeerde reden):** de licentie-
  en SBOM-poort zouden rood staan; ze omzeilen is de fout die de poorten juist
  moeten vangen.
- **Waarde 1 (veiligheid op 1):** dit pleit tegen alternatief B — zelf een
  crypto-/E2EE-machinerie bouwen om de AGPL te ontwijken, verruilt een
  licentieprobleem voor een veel groter beveiligingsoppervlak.

De botsing is de bekende "uitwisselbaarheid/rijke functie tegen de eigen
discipline". Hier wint de discipline: de functie is haalbaar zónder de keten nu
binnen te halen (alternatief A), dus er is geen noodzaak de belofte te breken.

## Alternatieven (bij NO-GO)

**A. Fase 0.5 — WebDAV-async-transport (aanbevolen).** Een `WebdavAsyncTransport`
achter het bestaande `CollabTransport`-contract, over de Nextcloud/WebDAV die de
gebruiker al heeft (`lib/services/webdav_service.dart`). Nul nieuwe
afhankelijkheden, geen AGPL, geen Rust, geen nieuwe vertrouwenspartij. Levert
asynchroon co-auteuren (geen realtime, geen chat-presence). Al voorzien in
`COLLABORATION.md` §10 als "near-free given Phase 0". Dit is de waarde-uitlijnende
volgende stap: samenwerken op wat er al is.

**B. Kleinere Matrix-client + directe binding van Apache-2.0-crypto.** Bind de
upstream `vodozemac`-crate (Apache-2.0) of `libolm` (Apache-2.0) rechtstreeks en
schrijf een minimale Matrix-client in Dart, buiten de AGPL-laag van famedly om.
Ontwijkt de licentie, maar is een grote, beveiligingskritische DIY-onderneming
(waarde 1 pleit ertegen), en houdt de Rust-toolchain (of het uitgefaseerde,
onderhoudsarme `libolm`). Niet aanbevolen tenzij realtime-Matrix onmisbaar blijkt
én de AGPL onaanvaardbaar.

**C. Uitstel.** Houd Fase 0 (loopback) en pak realtime pas op wanneer er een
lichtere weg is of het beleidsbesluit genomen is. Kost niets en sluit niets af.

## Als het toch een GO wordt

Wordt besloten de kosten wél te betalen, dan is een GO pas verantwoord als deze
vier voorwaarden vooraf en weloverwogen zijn vervuld — elk is echt werk, geen
vinkje:

1. **Beleidsbesluit AGPL + herlicensering.** Een gedateerd besluit van de
   stichting om AGPL-3.0 te aanvaarden en de uitgeleverde binary onder AGPL-3.0 te
   distribueren, doorgevoerd in `docs/LICENSE_COMPLIANCE.md`, in `allowedLicenses`
   (`tool/license_detect.dart`), in `THIRD_PARTY_NOTICES.md`, en in de publieke
   belofte zelf. Toetsen bij `jurist` en `bewaker`.
2. **Rust-toolchainpoort.** Een `check-toolchain`-equivalent voor Rust (kanaal,
   herkomst, pin in `.tool-versions`) op elke bouwmachine, inclusief de
   release-CI en de GitHub-spiegel.
3. **SBOM-tool uitgebreid naar `Cargo.lock`,** zodat de native cryptoboom in de
   CRA-inventaris verschijnt.
4. **Webborging voor de WASM-crypto:** een pin- en integriteitsmodel voor het
   zelfgebouwde WASM-artefact, gelijkwaardig aan wat `MANIFEST.json` voor de
   npm-bundels doet.

## Besluit

**NO-GO onder het huidige beleid.** De aanbeveling is alternatief A (Fase 0.5,
WebDAV-async) en het uitstellen van realtime-Matrix (spoor B, #977) tot de vier
voorwaarden hierboven bewust zijn vervuld. Deze keuze houdt elke huidige publieke
belofte overeind — er wordt niets herlicenseerd en geen poort omzeild.

De enige weg naar een GO loopt via voorwaarde 1: het licentiebeleid overrulen. Dat
is een besluit van de beheerder, niet van de keuring. Deze keuring geeft het
advies en de feiten; de knoop is aan de stichting.

[issue #976]: https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/976
