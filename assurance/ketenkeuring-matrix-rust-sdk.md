# Ketenkeuring — `matrix-rust-sdk` (GO/NO-GO)

> **Status:** vastgesteld 2026-07-30 · Stichting LibreKAT · intern werkdocument
>
> Geen conformiteitsclaim en geen auditrapport. Zie [`README.md`](README.md).
>
> Dit is de toeleveringsketenkeuring die [issue #991] vraagt: de **permissieve**
> route naar vól Matrix — matrix.org's eigen `matrix-rust-sdk` (Apache-2.0) achter
> een zelf te bouwen Dart-binding. Hij staat naast, niet in plaats van, de NO-GO op
> de famedly-SDK in [`ketenkeuring-matrix-sdk.md`](ketenkeuring-matrix-sdk.md) (#976,
> alternatief B daar). Referentie: [`COLLABORATION.md`](../docs/design/COLLABORATION.md)
> §6 (Matrix als transport) en §9 (E2EE als kernprincipe), en de kernwaarde-toets
> van de `bewaker`.

## Het besluit

**Aanbeveling: NO-GO om het nú te bouwen — maar een principieel GO als de erkende
toekomstige route naar realtime-Matrix.** De reden verschilt fundamenteel van
#976: daar was het bezwaar een *publieke belofte* die niet stilzwijgend gebroken
mag worden (de AGPL-licentievloer). **Dat bezwaar is hier weg.** `matrix-rust-sdk`
en zijn cryptolaag zijn Apache-2.0; opnemen breekt geen enkele belofte, herlicenseert
niets en laat geen poort rood staan. De licentievraag — de enige echt principiële
bij #976 — valt in het voordeel van deze route uit.

Wat overblijft is geen principe maar **kosten, en die zijn reëel en nog niet
betaald**:

1. **Er bestaat geen Dart/Flutter-binding.** Die bouw én onderhoud je zelf; het is
   een doorlopende ingenieursverplichting die meebeweegt met de API van
   `matrix-rust-sdk`, geen eenmalige klus (Bevinding 2).
2. **Het web is onopgelost.** Native (macOS/Windows/Linux, iOS/Android) is het
   solide geval, precies zoals Element X. Het web is de moeilijke kant en dwingt een
   expliciete keuze af (Bevinding 3).
3. **De Rust-toolchain en de SBOM-blinde vlek uit #976 blijven staan** — ze horen
   bij vodozemac-E2EE uit welke bron dan ook, permissief of niet (Bevindingen 4 en 5).

Geen daarvan is gebouwd, en alle drie zijn ze echt werk. Daarom is de aanbeveling
**niet** die kosten nú op zich nemen, maar de al aanvaarde **Fase 0.5 —
WebDAV-async-transport** ([#989](https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/989),
[`COLLABORATION.md`](../docs/design/COLLABORATION.md) §10) als de scheepbare
tussenstap houden, en `matrix-rust-sdk` oppakken zodra iemand de bindingslast
weloverwogen aanvaardt en de voorwaarden onder [*Als het toch nu een GO
wordt*](#als-het-toch-nu-een-go-wordt) gebouwd zijn.

De formele knoop — de doorlopende bindings- en toolchainverplichting aangaan — ligt
bij de beheerder. Deze keuring geeft het advies en de feiten; de knoop is aan de
stichting.

## Wat er gekeurd is

`matrix-rust-sdk` (uitgever matrix.org / element-hq), de volwaardige Matrix-client
in Rust die onder Element X (iOS/Android) in productie draait. Gekeurd op de vijf
punten die #991 noemt: (1) de Cargo-boom, licenties en kwetsbaarheidsscanning; (2)
de bindingslast; (3) native versus web; (4) de Rust-toolchainkost op de bouw-/
uitbrengketen; (5) de SBOM naar `Cargo.lock`.

De feiten hieronder komen van de repository van matrix.org en de bindings-mappen
daar, niet uit het geheugen; de poortverwijzingen zijn nagekeken in de code van
deze repo. Waar iets niet vast te stellen was zonder een lokale `Cargo.lock` en
`cargo tree`, staat dat er zo — de dossierlijn uit [`README.md`](README.md) geldt:
een dossier dat gaten aanwijst is meer waard dan een dat ze dichtpraat.

## Bevinding 1 — Licentie & keten: permissief (de #976-blokker vervalt)

De workspace draagt **Apache-2.0** (`[workspace.package] license` in de root-
`Cargo.toml`). De cryptolaag is `vodozemac` 0.10.0 — de **Apache-2.0**-crate van
matrix.org zelf, dezelfde Olm/Megolm-implementatie die #976 al als de permissieve
kern aanwees, nu rechtstreeks in plaats van via een AGPL-Dart-binding.

| Component | Herkomst | Licentie |
|---|---|---|
| `matrix-rust-sdk` (workspace, crates `0.18.0`) | matrix.org / element-hq | **Apache-2.0** |
| `vodozemac` 0.10.0 (E2EE-crypto) | matrix.org | **Apache-2.0** |
| `ruma` 0.31.0 (Matrix-typen, via git-revisie) | ruma-project | MIT |
| `uniffi` 0.31.0 (bindingsgereedschap) | Mozilla | MPL-2.0 / Apache-2.0 |

**Dit haalt de eigen poort, waar #976 hem liet vallen.** `tool/check_licenses.dart`
toetst elk opgelost pakket tegen `allowedLicenses` in `tool/license_detect.dart`;
Apache-2.0, MIT en MPL-2.0 staan daar alle drie in. De route die #976 blokkeerde —
AGPL — komt hier niet voor. Geen herlicensering van EUPL-1.2, geen breuk met
`docs/LICENSE_COMPLIANCE.md`. **Dit is de hele reden dat #991 bestaat en het klopt.**

**Twee eerlijke kanttekeningen bij "permissief".**

- *De licentiepoort van OciDeck ziet de Rust-boom niet.* `make licenses` leest
  `pubspec.lock`, niet `Cargo.lock`. De honderden transitieve crates die
  `matrix-rust-sdk` binnenhaalt (tokio, hyper/reqwest, de `ring`/`rustls`-familie,
  ed25519/curve25519-dalek, en wat die weer meebrengen) worden door de bestaande
  poort dus **niet** getoetst. Het Rust-ecosysteem is overweldigend MIT/Apache-2.0,
  maar een *sluitend* licentie-oordeel over de volledige boom vergt een
  `cargo-deny check licenses` op een echte `Cargo.lock` — dat is voorwaarde 3 onder
  [*Als het toch nu een GO wordt*](#als-het-toch-nu-een-go-wordt), niet iets dat de
  huidige poort al dekt.
- *De omvang is groot en niet exact vastgesteld.* Waar de famedly-SDK 22 directe
  Dart-afhankelijkheden meebracht (#976, Bevinding 5), is de transitieve Rust-boom
  van `matrix-rust-sdk` in de honderden crates — inherent aan een volledige client
  plus async-runtime plus TLS-stack. Het precieze getal is niet vast te stellen
  zonder de `Cargo.lock` lokaal op te lossen; het hoort in de eerste SBOM-run
  (Bevinding 5), niet in een geschat cijfer hier.

**Kwetsbaarheidsscanning is juist het sterke punt van deze keten.** Anders dan bij
een zelfgebouwde WASM-blob is de Rust-crateboom uitstekend te scannen: `cargo-audit`
en `cargo-deny` toetsen `Cargo.lock` tegen de RustSec-adviesdatabase, en Google's
`osv-scanner` leest dezelfde `Cargo.lock` tegen OSV.dev (dat RustSec omvat). Dat is
volwassener gereedschap dan er voor de npm-webbundels (`tool/check_bundled_js.dart`
→ OSV) al staat. Eén nuance: `ruma` komt via een **git-revisie** binnen, niet van
crates.io; git-deps zijn reproduceerbaar (gepind op commit) maar vallen buiten het
crates.io-geïndexeerde deel van de adviesdatabases — dat is een aandachtspunt voor
de scanopzet, geen blokkade.

## Bevinding 2 — De bindingslast: nieuw, en de zwaarste post

**Er is geen officiële Dart/Flutter-binding.** De `bindings/`-map van
`matrix-rust-sdk` levert er vier, alle via uniffi:

| Binding | Doel |
|---|---|
| `bindings/apple` (`matrix-rust-components-swift`) | Swift, voor Element X iOS |
| `bindings/matrix-sdk-ffi` | uniffi-binding van de volledige `matrix-sdk` (Swift/Kotlin) |
| `bindings/matrix-sdk-crypto-ffi` | uniffi-binding van alleen de crypto (Kotlin/Swift/Python/Ruby) |
| `bindings/matrix-sdk-ffi-macros` | ondersteunende macro's |

Dart en Flutter ontbreken. Er zijn dan twee zelfbouwroutes, en beide zijn echt werk:

- **`flutter_rust_bridge` over een eigen Rust-schil.** De beproefde Flutter↔Rust-route
  (MIT, op pub.dev). Je schrijft een dunne Rust-facade om het API-oppervlak dat
  OciDeck nodig heeft (sessie, kamers, ops, E2EE-sleutelbeheer) en genereert daaruit
  de Dart-binding. Automatisch de héle `matrix-sdk` scannen werkt níet — dat is
  empirisch bevestigd in `flutter_rust_bridge` issue #2486; je bindt bewust een
  afgebakend oppervlak, niet de crate in zijn geheel.
- **`uniffi-dart` over `matrix-sdk-ffi`.** Hergebruik van de al bestaande uniffi-
  interface via een Dart-uniffi-generator. Aantrekkelijk omdat matrix.org
  `matrix-sdk-ffi` zelf onderhoudt, maar de Dart-tak van uniffi is onvolwassen
  vergeleken met Swift/Kotlin.

Wat beide routes gemeen hebben: **de binding is geen eenmalige klus.** Hij beweegt
mee met elke API-wijziging van `matrix-rust-sdk` (een project met een MSRV van Rust
1.95 dat snel beweegt), met elke E2EE-nuance, en met elk platform. Dit is de post
die #976 niet had en die deze route kwalitatief verandert: OciDeck neemt een
**doorlopende onderhoudsverplichting** op zich die het bij een gewone `pub add` niet
heeft. Precies daarom is dit geen "haal de crate binnen"-besluit maar een
capaciteitsbesluit.

## Bevinding 3 — Native versus web: de kernvraag, en de web-stand

Dit is het beslispunt dat #991 als kern benoemt. De platformverdeling is omgekeerd
aan de intuïtie.

**Native is het solide geval.** Rust → native lib → Dart-FFI is precies hoe Element X
draait. De `matrix-sdk-sqlite`-crate levert de lokale opslag; `flutter_rust_bridge`
of de uniffi-FFI overbrugt naar Dart. Voor de vijf app-doelen (macOS, Windows, Linux,
iOS, Android) is dit een bekende, in productie beproefde vorm. Geen onbekend terrein —
alleen de bindingslast van Bevinding 2.

**Het web is de moeilijke kant, en er is geen kant-en-klare uitweg.** Drie routes,
geen ervan gratis:

1. **De beproefde browserroute is *niet* de rust-sdk.** Het web draait vandaag op
   `matrix-js-sdk` (een aparte JS-client) met alleen de crypto in WASM
   (`matrix-sdk-crypto-wasm`, "designed to run on a JavaScript host"). Dat is een
   *tweede*, in JavaScript geschreven client — geen deel van de Rust-binding die je
   voor native bouwt. Hem gebruiken betekent twee clientimplementaties onderhouden.
2. **De volledige rust-sdk in de browser is experimenteel.** element-hq's
   [`aurora`](https://github.com/element-hq/aurora) is een "highly experimental
   attempt" om `matrix-rust-sdk` via WASM in de browser (en Tauri) te draaien, als
   verkenning van wat Element X Web/Desktop kán worden. Proof-of-concept, geen
   productieroute. De crate `matrix-sdk-indexeddb` laat zien dat de web-opslag
   *bestaat*, dus de intentie is er — maar de volledige rust-sdk past nog niet netjes
   op Flutter-web/CanvasKit, dat de DOM/JS-omgeving niet op dezelfde manier gebruikt
   als een gewone webclient.
3. **Geen live-samenwerking op web, en terugvallen op async.** Web krijgt geen
   realtime-Matrix maar de al geplande WebDAV-async (#989); de losse apps krijgen wel
   realtime.

**Aanbevolen web-stand: route 3 — native realtime, web async (#989), tot aurora of
een JS-brug het verdient.** Dit vermijdt de twee dure vallen (twee clients
onderhouden, of leunen op een experimentele WASM-poort) en sluit aan op wat er al
aanvaard is: web co-auteurt asynchroon over de opslag die de gebruiker al heeft, de
apps krijgen de volle Matrix-ervaring. De keuze is omkeerbaar: zodra `aurora` volwassen
is of een `matrix-js-sdk`-brug de moeite waard blijkt, kan web alsnog realtime worden
zonder dat de native binding daarvoor iets hoeft in te leveren.

## Bevinding 4 — De Rust-toolchain op de bouw-/uitbrengketen (carry-over #976)

Ongewijzigd ten opzichte van #976, Bevinding 2 — het hoort bij vodozemac-E2EE, niet
bij de licentie. `matrix-rust-sdk` heeft een MSRV van **Rust 1.95** en levert geen
kant-en-klare desktopbinaries; die worden bij de app-bouw uit de bron gecompileerd.
Dat zet een tweede verplichte toolchain in het kritieke bouwpad, tegen drie vaste
lijnen van dit project:

- **"Eén Flutter, laatste stable."** `make check-toolchain` eist voor Flutter een
  vast kanaal, officiële herkomst en gelijkheid met de pin in `.tool-versions`. Voor
  Rust bestaat dat niet; een gelijkwaardige poort en pin (kanaal, herkomst,
  `rust-toolchain.toml`) zijn nodig, anders is de bouwreproduceerbaarheid weg — en de
  recente MSRV betekent dat die pin actief bijgehouden moet worden.
- **De uitbrengketen.** Eén `v*`-tag bouwt de targets; elke release-runner (en de
  GitHub-spiegel-CI) zou voortaan `cargo` moeten hebben. Vandaag heeft de keten
  alleen Flutter nodig, plus een C++-toolchain voor `dartcv4` (OpenCV). Daar komt de
  **code-signing van de native blob** bij: de gecompileerde Rust-lib moet mee in de
  platformhandtekening (denk aan de macOS-`App.framework`-zegelkwestie uit het
  releaseproces).
- **Het web.** Áls web ooit de rust-sdk-in-WASM-route neemt (Bevinding 3, route 2),
  krijgt de hardened webbouw er een `cargo`+WASM-stap bij. Bij de aanbevolen web-stand
  (route 3) speelt dit niet — een reden te meer voor die keuze.

## Bevinding 5 — SBOM naar `Cargo.lock` (carry-over #976)

Ongewijzigd ten opzichte van #976, Bevinding 3. `tool/generate_sbom.dart` (via
`tool/sbom_build.dart`) stelt de SBOM samen uit `pubspec.lock`,
`assets/web_export/MANIFEST.json`, `pubspec.yaml` en `.tool-versions`. Het leest
**geen** `Cargo.lock`. De crates die de daadwerkelijk uitgeleverde crypto en
Matrix-client vormen zijn voor de generator onzichtbaar.

Gevolg: de SBOM die `COLLABORATION.md` §11 als voorwaarde noemt zou de meest
beveiligingsgevoelige component — native crypto- en netwerkcode — **onvolledig**
beschrijven, precies het tegendeel van waarvoor de SBOM bestaat (de CRA-inventaris,
Annex I deel II §1). Vóór een eerlijke GO moet het SBOM-gereedschap `Cargo.lock` mee
kunnen lopen. Dit is nodig ongeacht de bron van de crypto (permissief of niet) en
dient hier dubbel: het is óók de plek waar het sluitende licentie-oordeel over de
Rust-boom (Bevinding 1) en de kwetsbaarheidsinventaris landen.

## Bevinding 6 — Native SQLite-opslag en het extra oppervlak

`matrix-rust-sdk` brengt naast `vodozemac` een tweede native afhankelijkheid mee:
`matrix-sdk-sqlite` (SQLite, C) voor de lokale Matrix-opslag, met `matrix-sdk-indexeddb`
als web-tegenhanger. Zoals bij #976 (Bevinding 5) is dit mogelijk vermijdbaar: P2 zegt
*bestand = waarheid, sessie = vergankelijk transport*, dus een sessie hoeft geen
duurzame SQLite-store — een geheugenopslag zou de C-afhankelijkheid kunnen wegnemen.
Te bepalen bij de bouw, niet nu. Het overige crate-oppervlak (Bevinding 1) valt in het
SBOM-werk.

## Kernwaarde-toets (bewaker)

De vragen van de `bewaker`, toegepast op déze keten:

- **Kan de gebruiker zijn werk meenemen?** Ja, onveranderd sinds #976. Samenwerken is
  vergankelijk (P2); het deck blijft een gewoon `.md`. Fase 0 is bewust
  transport-agnostisch; stopt OciDeck morgen, dan overleven de decks het.
- **Wie moet je vertrouwen, en is dat nieuw?** Runtime: matrix.org's client-code en,
  net als bij elke Matrix-keuze, de homeserver die de gebruiker zelf kiest (P1,
  bring-your-own, blijft overeind). Bij de bouw: de Rust-toolchain plus crates.io.
  Géén AGPL-partij, géén herlicensering — dat is de winst tegenover #976.

Waar #976 op drie waarden botste, botst deze route op **geen enkele principiële
waarde**:

- **Waarde 2 (openheid) en 4 (integriteit van beloftes):** hier gerúststellend in
  plaats van bezwaarlijk. Er wordt geen publieke belofte gebroken; de licentievloer
  blijft staan zoals hij is. Dit is juist de route die #976 openliet omdat hij de
  belofte respecteert.
- **Waarde 6 (geen groen om de verkeerde reden):** de licentiepoort staat groen om de
  júiste reden (Apache-2.0). Wél moeten de SBOM- en toolchainpoorten mee-groeien met
  de Rust-boom (Bevindingen 4, 5), anders zou de dekking schijnvolledig zijn.
- **Waarde 1 (veiligheid op 1):** dit pleit vóór deze route en tégen het alternatief
  dat #976 afraadde. Je gebruikt matrix.org's in productie beproefde client en crypto,
  je schrijft géén eigen E2EE-machinerie. Het beveiligingsoppervlak zit in
  onderhouden, gescande crates, niet in DIY-crypto.

De botsing bij deze route is dus niet waarde-tegen-waarde maar **ambitie tegen
capaciteit**: een rijke functie die een blijvende onderhoudsverplichting en een web-knoop
meebrengt, tegen de discipline van "neem niet meer op je dan je kunt dragen". Dáár, niet
in een principe, zit de reden om nu nog niet te bouwen.

## Als het toch nu een GO wordt

Wordt besloten de kosten wél nú te betalen, dan is een GO pas verantwoord als deze vier
voorwaarden vooraf en weloverwogen zijn vervuld — elk is echt werk, geen vinkje:

1. **Bindingsbesluit en -eigenaarschap.** Een expliciet besluit dat OciDeck de
   doorlopende Dart↔Rust-binding bouwt en onderhoudt (Bevinding 2), met de keuze
   `flutter_rust_bridge` versus `uniffi-dart` en een benoemde onderhoudseigenaar. Dit
   is een capaciteits-, geen technisch besluit.
2. **Rust-toolchainpoort.** Een `check-toolchain`-equivalent voor Rust (kanaal,
   herkomst, pin) op elke bouwmachine inclusief de release-CI en de GitHub-spiegel,
   plus de code-signing van de native blob in het releaseproces (Bevinding 4).
3. **SBOM-tool uitgebreid naar `Cargo.lock`,** zodat de native crate-boom in de
   CRA-inventaris verschijnt; tegelijk het sluitende licentie-oordeel (`cargo-deny
   check licenses`) en de kwetsbaarheidsscan (`cargo-audit`/`osv-scanner`) op die
   boom (Bevindingen 1, 5).
4. **De web-stand vastgelegd.** Een gedateerd besluit welke van de drie routes uit
   Bevinding 3 het web neemt. De aanbeveling is route 3 (native realtime, web async via
   #989); een andere keuze brengt de bijbehorende kosten (twee clients, of de
   experimentele WASM-poort) expliciet in beeld.

Anders dan bij #976 zit er **geen licentie-/beleidsvoorwaarde** in deze lijst. Dat is
het verschil dat #991 wilde vaststellen: de weg naar een GO loopt hier via capaciteit
en gereedschap, niet via het overrulen van een publieke belofte.

## Besluit

**NO-GO om het nú te bouwen; principieel GO als de erkende toekomstige route naar
realtime-Matrix.** De aanbeveling is Fase 0.5 (WebDAV-async, #989) als de scheepbare
stap te houden en `matrix-rust-sdk` op te pakken zodra de bindingslast weloverwogen is
aanvaard en de vier voorwaarden hierboven gebouwd zijn. Deze keuze houdt elke huidige
publieke belofte overeind — er wordt niets herlicenseerd en geen poort omzeild — en zij
verschilt daarin niet van #976; het verschil zit erin dat de blokkade hier *tijdelijk en
opheffbaar* is (capaciteit en gereedschap) in plaats van *principieel* (een licentievloer).

De permissieve route naar vól Matrix ís dus haalbaar zónder beleidswijziging — dat was de
vraag van #991, en het antwoord is ja. Of en wanneer OciDeck de bijbehorende doorlopende
verplichting aangaat, is een besluit van de beheerder, niet van de keuring.

**Besloten (2026-07-30).** De beheerder heeft het advies gevolgd: **NO-GO om het nú te
bouwen, principieel GO als de erkende toekomstige route** naar realtime-Matrix. De
volgende stap blijft Fase 0.5 (WebDAV-async, #989); `matrix-rust-sdk` wordt pas opgepakt
zodra de doorlopende bindings-/toolchainverplichting weloverwogen is aanvaard en de vier
voorwaarden hierboven gebouwd zijn. Het licentiebeleid blijft ongewijzigd — deze route
vergt geen beleidswijziging.

[issue #991]: https://pawprint.vigilis.online/LibreKAT/Ocideck/issues/991
