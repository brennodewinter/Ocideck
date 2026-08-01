# Ketenkeuring — flutter_webrtc (media-plane voor natieve calls) (GO/NO-GO)

> **Status:** opgesteld 2026-08-02 · Stichting LibreKAT · intern werkdocument
>
> Geen conformiteitsclaim en geen auditrapport. Zie [`README.md`](README.md).
>
> Deze keuring hoort bij het ontwerp
> [`docs/design/NATIVE_CALLS.md`](../docs/design/NATIVE_CALLS.md) (natieve calls: één
> interface, Jitsi + Matrix als backends). Zij keurt de **media-plane-afhankelijkheid**
> die dat ontwerp nodig heeft — `flutter_webrtc` — vóór die de netwerklaag in gaat. Zij
> staat naast de drie samenwerkings-keuringen
> ([`ketenkeuring-matrix-sdk.md`](ketenkeuring-matrix-sdk.md),
> [`ketenkeuring-matrix-rust-sdk.md`](ketenkeuring-matrix-rust-sdk.md),
> [`ketenkeuring-self-encrypted-relay.md`](ketenkeuring-self-encrypted-relay.md)), maar
> raakt een ander vlak: díe gingen over de **data-plane** (ops/chat/E2EE); deze gaat
> over de **media-plane** (de audio/video-bytes zelf). Referentie:
> [`COLLABORATION.md`](../docs/design/COLLABORATION.md) §7 (media-plane) en §7.1
> (meeting-providers), en de kernwaarde-toets van de `bewaker`.

## Het besluit

**Aanbeveling: NO-GO om `flutter_webrtc` nú kaal toe te voegen; principieel GO als de
enige realistische media-route voor natieve calls, mits vier voorwaarden vooraf zijn
vervuld.** Anders dan bij de data-plane-keuringen zit de spanning hier **niet** in de
licentie of een tweede toolchain — die zijn schoon (Bevinding 1 en 2). Zij zit in
**netwerkbeheersing en eerlijkheid**: media omzeilt de centrale netwerkwacht
(Bevinding 3), en de dep breekt een publieke belofte die eerst eerlijk bijgewerkt moet
worden (Bevinding 4). Er is geen pure-Dart-alternatief: WebRTC-media is libwebrtc, en
dat herbouw je niet in Dart (`NATIVE_CALLS.md` §4). Wie natieve calls wil, wil deze
dep — de vraag is niet *of* maar *onder welke borging*.

De formele knoop — een tweede netwerkstack aanvaarden die deels búiten NetGuard valt,
achter een standaard-uit module — ligt bij de beheerder. Deze keuring geeft het advies
en de feiten; de knoop is aan de stichting. Zij hangt bovendien aan een voorafgaand
besluit: de **spine-keuze** (`NATIVE_CALLS.md` §5, open vraag 0). Zolang die niet
genomen is, is er geen reden de media-dep binnen te halen.

## Wat er gekeurd is

De afhankelijkheid **`flutter_webrtc`**: de Flutter-binding rond Googles **libwebrtc**
(de C++-WebRTC-implementatie), die op alle vier de bouwtargets — macOS, Windows, Linux
en web — audio/video-tracks, data-channels, schermdeling en peer/SFU-verbindingen
levert. In het ontwerp `NATIVE_CALLS.md` is dit de **gedeelde mediakern** onder zowel
de Jitsi- als de MatrixRTC/LiveKit-adapter; de *signalering* eromheen (XMPP/Jingle/
Colibri2 voor Jitsi, Matrix-events + LiveKit voor Matrix) is pure-Dart-werk en valt
buiten deze keuring.

Wat deze keuring uitdrukkelijk *niet* is: de signaleringslaag (`lib/xmpp/`, de
adapters), en evenmin een oordeel over hosten van een eigen SFU — OciDeck draait er
geen (P1).

De feiten hieronder komen van pub.dev, de projectcode en de openbare
`flutter-webrtc`-repository; er is nagekeken wat er staat. Waar iets pas met een echte
`pub add` + poortdraai sluitend is, staat dat er zo — de dossierlijn uit
[`README.md`](README.md) geldt.

## Bevinding 1 — Licentie & keten: permissief, EUPL blijft

De bouwstenen zijn permissief en botsen niet met `docs/LICENSE_COMPLIANCE.md`:

| Component | Herkomst | Licentie |
|---|---|---|
| `flutter_webrtc` | flutter-webrtc (open collectief) | **MIT** |
| libwebrtc (native kern) | Google/WebRTC-project | **BSD-3-Clause** + aparte patenttoekenning |
| Standaardcodecs VP8/VP9/AV1/Opus | — | royaltyvrij |
| H.264 (optioneel) | — | patent-belast; **niet inschakelen tenzij nodig en gewogen** |

Geen AGPL — de blokker van #976 speelt niet. Geen herlicensering; EUPL-1.2 blijft. Twee
eerlijke kanttekeningen: (1) de **volledige transitieve boom** is pas sluitend na een
echte `pub add flutter_webrtc` gevolgd door `make licenses` en `make sbom` (voorwaarde
2 hieronder) — anders dan bij een Rust-boom valt dit wél binnen de bestaande poorten
(`pubspec.lock`); (2) **codeckeuze is een licentiekeuze**: H.264 uitschakelen houdt de
keten royaltyvrij, VP8/VP9/AV1/Opus volstaan voor OciDecks doel.

## Bevinding 2 — Native code, maar géén tweede toolchain (lichter dan #991)

`flutter_webrtc` bevat platform-native code (C++/ObjC/Swift/Java/Kotlin) maar is een
**gewone Flutter-plugin**: geen tweede verplichte toolchain in het kritieke bouwpad,
geen `Cargo.lock`, geen `make check-toolchain`-uitbreiding. Dit is het grote verschil
met de matrix-rust-sdk-route (#991), waar juist die last de GO in de weg stond. De dep
staat in `pubspec.lock` en valt daarmee vanzelf onder `make sbom` en `make licenses`;
de CRA-inventaris (Annex I) blijft volledig zonder nieuw gereedschap.

Eén reële kanttekening: `flutter_webrtc` bindt doorgaans een **voorgebouwd
libwebrtc-artefact** in plaats van het uit bron te bouwen. Dat is een groot binair
toeleveringsoppervlak op een gevoelige component. Meewegen en vastpinnen in de SBOM
(versie + herkomst + hash waar haalbaar), zoals elke andere binaire afhankelijkheid;
geen blokkade, wel een bewust vertrouwenspunt.

## Bevinding 3 — Netwerkbeheersing: media omzeilt NetGuard (de kern, waarde 1)

Dit is waar deze route staat of valt. `docs/ARCHITECTURE.md` tekent `net_guard` als
*"the single choke every app socket passes"*. WebRTC-media past daar **niet** doorheen:
ICE/STUN/TURN over UDP, SRTP-stromen naar de SFU en naar peers — die verbindingen
komen niet uit de `http`-client en worden niet door `NetGuard.safeResolve`/`connectPinned`
gevalideerd of gepind. Dit is dezelfde klasse gat als het native `git`-subproces (dat
NetGuard óók niet kan onderscheppen), maar wezenlijk breder: geen kortstondige
clone/fetch, maar een **continue realtime mediastroom** naar server én peers.

Wat dit beheersbaar houdt, en wat de voorwaarde is:

- **De signalering blíjft binnen NetGuard.** De origin waar de mediakanalen worden
  onderhandeld (Prosody/Matrix) gaat door dezelfde `NetGuard`/redirect-refusal/
  DNS-rebind-houding als WebDAV, via `MeetingProviderProfile` (`NATIVE_CALLS.md` §8).
  De media *volgt* uit die onderhandelde, gecontroleerde origin — geen willekeurige
  bestemming.
- **Begrensde egress.** Alleen geconfigureerde/goedgekeurde TURN/SFU-origins; geen
  media naar een host die niet uit de gevalideerde sessie komt.
- **Fail-closed op signaleringsniveau.** Faalt de gecontroleerde signalering, dan komt
  er geen mediakanaal — de wacht blijft de facto de poort, één laag hoger.

Dit gat moet **expliciet** in `SECURITY.md` en dit dossier komen te staan, niet
stilzwijgend meeliften. Het eerlijk benoemen is de helft van de borging.

## Bevinding 4 — De belofte "enige HTTP-dependency is `http`"

`docs/ARCHITECTURE.md` stelt letterlijk: *"The only HTTP client dependency is `http`"*
en *"The app never phones home."* Een WebRTC-stack is een **tweede netwerkstack**. De
tweede belofte blijft waar (OciDeck belt niemand ongevraagd — de module staat standaard
uit en verbindt alleen op gebruikersactie naar een door de gebruiker gekozen
deployment), maar de eerste wordt onwaar en moet **eerlijk worden bijgewerkt**: er is
een tweede netwerkstack, achter een standaard-uit module, die pas verbindt na expliciete
toestemming. Dit is precies de projectlijn — een belofte die onwaar wordt, corrigeer je,
je praat hem niet dicht.

## Bevinding 5 — Privacy-projectiegrens: de slide de call in

Het ontwerp laat de presentatie de conferentie in gaan als eigen video-track. Dat is per
definitie een **nieuw `audience`-uitvoerkanaal**, en `tool/check_audience_boundary.dart`
**breekt de build** tot dat kanaal een `AudienceDeck` eist (via
`PrivacyProjection.forAudience`), nooit een rauwe `Deck`. Gevolg: de slide gaat eerst
door de OciWacht-redactie vóór hij een track/schermdeling in mag. Dit is geen last van
`flutter_webrtc` maar een eigenschap van de repo die de dep meteen de goede kant op
dwingt — het sterkste ontwerpargument én een harde bouweis. De audience-window mag geen
presenter-notes of diagnostiek lekken (`COLLABORATION.md` §7.1.4).

## Bevinding 6 — macOS E2EE-voorbehoud (frame cryptor)

`flutter_webrtc` levert media-E2EE via insertable-streams/SFrame (de "frame cryptor").
Op Android werkt dit; op **iOS en macOS** is een bekende crash gerapporteerd. macOS is
OciDecks primaire target. Consequentie voor het ontwerp: media-E2EE is **geen
vanzelfsprekende v1-eigenschap** op macOS. Opties: E2EE eerst op Linux/Windows/web
landen, of v1 zónder media-E2EE uitbrengen met een eerlijke bekendmaking (`MeetingPreflight`
geeft E2EE-status hoe dan ook expliciet, inclusief `unknown` — `COLLABORATION.md` §7.1.1).
Dit is open vraag 2 in `NATIVE_CALLS.md`; het is een voorbehoud, geen blokkade voor de
dep zelf.

## Bevinding 7 — Verdedigende begrenzingen (spiegel van de bestaande houding)

Zoals `COLLABORATION.md` §11 voorschrijft en `file_service.dart`/`webdav_service.dart`
al doen: begrensde afmetingen op inkomende signalering-stanza's/events; oversized invoer
geweigerd; geen signalering-redirects; de fragment-strip tegen Jitsi's `#config.…`
(muted/camera-off komen van OciDeck, niet van de afzender). Op web een CSP
`connect-src`/`media-src`-delta voor de signalering-origin (`tool/check_web_hardening.dart`).
Voordeel van de natieve route: de vendor-SDK-isolatie uit §7.1.6 (sandboxed iframe)
vervalt grotendeels — er draait geen vendor-JS in de pagina.

## Kernwaarde-toets (bewaker)

- **Kan de gebruiker zijn werk meenemen?** Ja, onveranderd. Een call is vergankelijk
  (P2, kamer = transport); het deck blijft een gewoon `.md`/`.ocideck`. De media-dep
  raakt het bestandsformaat niet.
- **Wie moet je vertrouwen, en is dat nieuw?** Runtime: de deployment die de gebruiker
  zelf kiest (P1, bring-your-own). Nieuw en wezenlijk: het **libwebrtc-artefact** en het
  `flutter_webrtc`-collectief voor de mediakern, plus het feit dat mediastromen buiten
  NetGuard vallen (Bevinding 3).

Waar de matrix-sdk-route (#976) op drie waarden botste, botst deze op **één**:

- **Waarde 2 (openheid) en 4 (integriteit van beloftes):** de belofte "enige
  `http`-dependency" moet eerlijk bijgewerkt (Bevinding 4). Doe je dat, dan blijft de
  integriteit overeind; doe je het niet, dan is dát de breuk — niet de code.
- **Waarde 6 (geen groen om de verkeerde reden):** de licentie-/SBOM-poort staat groen
  om de júiste reden (permissieve dep in `pubspec.lock`, geen Cargo-blinde vlek).
- **Waarde 1 (veiligheid op 1):** dít is de spanning. Niet de crypto (die zit in de
  signalering, niet hier), maar de **netwerkbeheersing**: media buiten de wacht. De
  route is alleen verantwoord met de begrenzing van Bevinding 3 en 7, de standaard-uit
  module, en het eerlijk benoemen van het gat.

De botsing is dus **beheersing-en-eerlijkheid tegen gemak**, niet licentie-tegen-belofte
zoals #976. Zij is lichter dan #991 (geen Rust, geen toolchain, geen Cargo-SBOM), maar
draagt één last die de data-plane-routes niet hadden: een deel van het verkeer valt
buiten de centrale wacht.

## Alternatieven, in verhouding

- **A. Geen calls (huidige stand).** Blijft geldig: co-auteuren gaat via de al
  goedgekeurde relay/WebDAV-routes zonder media. Deze keuring vervangt A niet; ze biedt
  de media-stap die A per ontwerp niet is.
- **B. Officiële Jitsi-IFrame/SDK embedden.** Vermijdt een eigen media-stack, maar
  embedt de vreemde client (botst met "eigen interface"), verzwakt de CSP, en op desktop
  is de webview-route onvolgroeid. Bewust afgewezen in `NATIVE_CALLS.md` — de gebruiker
  koos de natieve route.
- **C. `flutter_webrtc` (deze keuring).** De enige route die *natief*, *eigen interface*
  en *één mediakern voor Jitsi én Matrix* tegelijk levert. Er is geen pure-Dart-variant;
  WebRTC-media is libwebrtc.

## Als het toch een GO wordt

Wordt besloten deze route te bouwen, dan is een GO pas verantwoord als deze vier
voorwaarden vooraf en weloverwogen zijn vervuld — elk is echt werk, geen vinkje:

1. **Spine-besluit genomen.** De keuze uit `NATIVE_CALLS.md` §5 (open vraag 0) — één
   XMPP-spine of twee-spine — is een beheerdersbesluit dat vóór de media-dep hoort, want
   het bepaalt welke signaleringslaag de dep aandrijft.
2. **Volledige licentie-/SBOM-bevestiging.** Een echte `pub add flutter_webrtc` gevolgd
   door groene `make licenses` en `make sbom` over de hele transitieve boom, met het
   voorgebouwde libwebrtc-artefact vastgepind (Bevinding 1, 2). Codeckeuze bewust
   (H.264 uit tenzij gewogen).
3. **Netwerkbeheersing gedocumenteerd én begrensd.** Het NetGuard-media-gat expliciet in
   `SECURITY.md` en dit dossier; signalering-origin door de WebDAV-houding
   (`MeetingProviderProfile`); egress begrensd tot geconfigureerde/goedgekeurde
   TURN/SFU-origins; fail-closed op signaleringsniveau (Bevinding 3, 7).
4. **Belofte eerlijk bijgewerkt en module standaard-uit.** De "enige `http`-dependency"-
   zin in `ARCHITECTURE.md` gecorrigeerd (Bevinding 4); de call-module als 6e
   `ModuleEntry`, default `false`, "off = geen adaptercode bereikt" (Bevinding 5,
   `NATIVE_CALLS.md` §8).

Anders dan bij #991 zit er **geen Rust-toolchain-, geen Cargo-SBOM- en geen
WASM-webvoorwaarde** in deze lijst. Anders dan bij #976 zit er **geen licentie-/
beleidsvoorwaarde** in: er hoeft niets overruled te worden. De centrale voorwaarde is
hier **netwerkbeheersing en eerlijke bekendmaking** (voorwaarde 3 en 4).

## Besluit

**NO-GO om `flutter_webrtc` nú kaal toe te voegen; principieel GO als de enige
realistische media-route voor natieve calls, mits de vier voorwaarden vervuld zijn en
het spine-besluit genomen is.** De dep is permissief en licht op toolchain — de blokker
is niet de licentie maar de netwerkbeheersing (media buiten de wacht) en de belofte die
eerst eerlijk bijgewerkt moet worden. Deze keuze houdt elke huidige publieke belofte
overeind zolang voorwaarde 4 wordt nagekomen: er wordt niets geherlicenseerd en geen
poort omzeild.

Het antwoord op de vraag die deze keuring opriep — *kan OciDeck natieve calls doen
zonder zijn beveiligings- en beloftestand te ondermijnen?* — is **ja, mits geborgd**:
media valt onvermijdelijk buiten de centrale wacht, maar de signalering die de media
opzet blijft erbinnen, de module staat standaard uit, en het gat wordt eerlijk benoemd
in plaats van dichtgepraat. Of en wanneer OciDeck die borging aangaat, is een besluit
van de beheerder, niet van de keuring.
