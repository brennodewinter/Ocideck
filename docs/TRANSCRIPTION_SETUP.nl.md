# OciDeck — Transcriptie en opname: platformsetup

> **Status:** setupmatrix en stapsgewijze gids voor de vrijgegeven builds · **Status laatst nagekeken:** 2026-10-26 · **Uitgegeven door:** Stichting LibreKAT

Deze pagina beantwoordt, per platform: wat je moet installeren of
toestaan, hoe een opname een transcript wordt, waar de bestanden staan,
en wat je doet als iets faalt. De
[gebruikershandleiding](USER_GUIDE.nl.md#transcriptie-en-opname)
legt de module zelf uit; deze pagina is de platformmatrix waarop de
release wordt getest. Waar een route niet op echte hardware is bewezen,
staat hier *niet getest* in plaats van dat een gedeelde codepad als
ondersteuning leest.

## De drie stappen, op elk platform

1. **Zet de module aan.** *Instellingen → Uitbreidingen → Transcriptie
   en opname*. Hij staat standaard uit; de kaart toont ook de
   capability-matrix die jouw machine echt rapporteert, dus je kunt
   bronnen en modellen bekijken zonder iets aan te zetten.
2. **Kies waar tekst gemaakt wordt.** Lokale verwerking is de
   standaard en vraagt een model dat je eenmalig downloadt (hieronder).
   Een serverroute bestaat pas nadat je zelf een ASR-serverprofiel
   hebt ingesteld — er is geen permanente upload, en een taak die je
   niet bevestigde verstuurt niets.
3. **Neem op of open audio.** *Importeren → Microfoon opnemen…*,
   *Systeemgeluid opnemen…*, *Microfoon en systeemgeluid opnemen…*,
   *Tabbladgeluid opnemen…* (browserafhankelijk), *Bestand
   transcriberen…* voor een bestaand bestand, of *Opnemen en
   transcriberen* in de callbalk tijdens een verbonden call. Stoppen
   biedt overal dezelfde drie keuzes: nu transcriberen, zeven dagen
   bewaren, of weggooien. Het transcript is een gewoon, bewerkbaar
   Markdown-document; de audio reist mee in de `media/`-map van het
   project.

Anderen opnemen — in een ruimte of in een call — kan hun toestemming
vereisen, en een vergaderdeployment kan een eigen opnamebeleid
voorschrijven. De dialogen herinneren je eraan; de wet en de
deployment beslissen. OciDeck is geen Teams- of Jitsi-client en
claimt niet dat elk beschermd audiokanaal op te nemen is: een
besturingssysteem dat DRM-beschermde audio uitsluit wordt gehoorzaamd,
niet omzeild.

## Modellen: wat je downloadt en wat het kost

De lokale engine is whisper.cpp v1.9.5 (MIT), gedraaid als subproces
zodat een native fout de app nooit meeneemt. Modellen zijn
OpenAI-Whisper-gewichten (MIT) in ggml-formaat, gepind op een vaste
revisie van de whisper.cpp-modelrepository en op SHA-256 geverifieerd
vóór gebruik — een mismatch is een weigering, geen waarschuwing. Niets
wordt meegeleverd en niets downloadt vanzelf: de modeldownload, door
jou gestart, is het enige netwerkverkeer van de lokale route.

| Model | Download | Niveau | Web |
|---|---|---|---|
| `small` (standaard) | ~465 MiB | Evenwichtig — het kleinste met bruikbaar Nederlands | Ja |
| `large-v3-turbo` | ~1,5 GiB | Nauwkeurig — beste kwaliteit waar geheugen het toelaat | Nee (boven de 2 GB-WASM-grens) |
| `base` | ~141 MiB | Licht — snel, zichtbaar zwakker | Ja |

`tiny` wordt bewust niet aangeboden: de gemeten output was niet eerlijk
genoeg om voor te stellen. Het piekgeheugen volgt grofweg de
downloadomvang — het nauwkeurige model vraagt ~2 GB vrij terwijl het
draait. Modellen staan in de app-supportmap (IndexedDB op web, die de
browser onder opslagdruk mag opruimen — dat rapporteert als afwezig,
nooit als corruptie, en je downloadt opnieuw). De instellingenkaart
verwijdert ze weer; er is geen andere verwijderroute te vinden.

## Platformmatrix

| | macOS | Windows | Linux | Web |
|---|---|---|---|---|
| Release-artifact | Getekend + genotariseerd, universeel (arm64 + x86_64) | Ongetekende zip en installer (SmartScreen-waarschuwing is verwacht) | Ongetekend | Statische bundel; vereist COOP/COEP-headers van de host voor lokale inferentie |
| Bestaand audiobestand | WAV/PCM bewezen; andere containers decoderen of melden `DecodeFailed` | idem | idem | Browsercodec-dekking beslist |
| Microfoon | Bewezen — na de macOS-prompt | Aangeboden — OS-privacy-schakelaar beslist | Aangeboden — hardware-aanwezigheid beslist, de meeste setups hebben geen OS-prompt | Bewezen — per-site browsertoestemming |
| Systeem-/appgeluid | Aangeboden — ScreenCaptureKit onder *schermopname*-toestemming (macOS 13+); DRM-audio wordt door het OS uitgesloten | Aangeboden — WASAPI-loopback neemt de endpointmix op, niet één app | Aangeboden — alleen PipeWire/PulseAudio `.monitor`-bronnen; kale ALSA heeft er geen | Niet aangeboden als systeemgeluid |
| Tabbladgeluid | — | — | — | Alleen Chromium; Firefox en Safari krijgen een eerlijke melding in plaats van een knop |
| Callaudio (Jitsi in-app) | Bewezen in een echte tweepersoonscall | Niet geclaimd — geen bewezen per-bron-tap | Niet geclaimd — geen bewezen per-bron-tap | Bewezen in een echte tweepersoonscall (getest op Chromium) |
| Lokale engine | Bewezen — gemeten op Apple Silicon | Gebouwd uit dezelfde gepinde bron — hardwarebewijs loopt nog | Gebouwd uit dezelfde gepinde bron — hardwarebewijs loopt nog | Bewezen — gemeten op de verscheepte WASM-artifacten in Chrome, Firefox en WebKit |
| Batchserverroute | Bewezen | Beschikbaar — zelfde egressroute, hardwarebewijs loopt nog | Beschikbaar — zelfde egressroute, hardwarebewijs loopt nog | Bewezen — onderworpen aan CORS |
| Liveserverroute | Bewezen tegen de gepinde Vosk-testbed | Beschikbaar — zelfde egressroute, hardwarebewijs loopt nog | Beschikbaar — zelfde egressroute, hardwarebewijs loopt nog | Alleen beschikbaar zonder API-sleutel — een browser-WebSocket kan de header niet dragen |

Fysieke en virtuele invoeren — ingebouwd, USB, Bluetooth, virtuele
kabels — worden aangeboden zoals het besturingssysteem ze rapporteert.
Bluetooth-headsets werken waar het OS ze als invoer presenteert; een
headset die halverwege een opname van profiel wisselt wordt behandeld
als een bronwijziging, niet als een crash. Waar het platform een bron
niet kan benoemen, zegt de dialoog dat in plaats van te gokken.

## Serverinrichting: batch en live

Beide serverroutes lopen via één **ASR-serverprofiel** (*Instellingen
→ Uitbreidingen → Transcriptie en opname*). Het profiel bevat een
basis-URL, een weergavenaam, een optioneel apart *live-endpoint* en de
opt-ins hieronder. Een API-sleutel, wanneer de server die vraagt, leeft
in de systeemkeychain — nooit in de instellingenblob — en reist alleen
in de `Authorization`-header, en alleen op `https`-endpoints.

Drie bestemmingstiers, elk met een eigen zichtbare toestemming:

- **Loopback** — een server op deze machine, bijv.
  `http://127.0.0.1:8080`. De standaardsuggestie; vraagt geen extra
  bevestiging.
- **LAN** — een host in je netwerk. Vereist de expliciete bevestiging
  *vertrouwde interne server*: een adres dat je niet hebt beoordeeld
  wordt niet stil vertrouwd.
- **Cloud** — een externe bestemming. Vereist een eigen bevestiging en
  is alleen `https`.

### De batchserver — het definitieve transcript

Het contract is whisper.cpp's **`whisper-server`**: één
`POST /inference`-multipartupload van het audiobestand dat je
bevestigde, beantwoord als `verbose_json`. Dat is het enige protocol
dat wordt geclaimd — voor andere ASR-servers wordt geen werking
beloofd, en elke taak vraagt opnieuw in plaats van een oude
toestemming te hergebruiken. Een connectiviteitsprobe die je vooraf
kunt draaien verstuurt geen audio. Uploads zijn begrensd op 400 MiB;
een groter bestand meldt een capaciteitsfout in plaats van een stille
afkap. Een afgebroken upload blijft afgebroken; een mislukte meldt de
getypeerde reden — niets probeert opnieuw of valt vanzelf terug op een
andere bestemming.

**Zelf eentje draaien.** De whisper.cpp-repository bouwt
`whisper-server` uit dezelfde gepinde bron als de lokale engine.
Exposeren is bewust niet de beoogde opstelling: zonder een TLS-,
authenticatie- en (voor browsers) CORS-laag ervoor is een
`whisper-server`-poort een ongeauthenticeerde luisteraar. Beëindig
TLS bij een reverse proxy die je beheert, vereis de API-sleutel die
OciDeck kan sturen, en zet hem pas dán in het profiel. Wat de server
na `POST /inference` bewaart of wist is het beleid van die server —
OciDeck kan je tonen wat het verstuurde, niet wat daarna gebeurt.

### De liveserver — voorlopige tekst tijdens het opnemen

Een tweede endpoint op hetzelfde profiel spreekt **`vosk-ws-1`**: het
Vosk-WebSocket-protocol, bewezen tegen de gepinde referentieserver in
`testbed/vosk-asr` (setup en draadcontract in zijn README; het bewijs
is `make test-asr-integration`). Compatibiliteit met andere
streaming-ASR-servers wordt niet geclaimd. De opnamedialoog biedt de
opt-in pas na een geslaagde protocolprobe, en aanvinken is toestemming
voor die ene sessie — de host staat in het vinkje genoemd. Een
wegvallende verbinding kost alleen de voorvertoning; de opname
schrijft door, en niets verbindt of verstuurt vanzelf opnieuw. In een
browser bestaat deze route alleen voor een ongeauthenticeerd endpoint:
een WebSocket kan de API-sleutelheader niet dragen, dus een
sleuteleisende liveserver is daar eerlijk onbereikbaar in plaats van
stil ongeauthenticeerd. Livebronnen zijn de desktop-opnames;
web-opnames en bestandstranscriptie leveren geen livechunks.

### Browser-eigen regels voor serverroutes

Een pagina kan niet stilletjes een LAN-adres bereiken: CORS beslist of
de server de app antwoordt, `http`-doelen zijn beperkt tot letterlijke
loopback, en een mixed-content-regel blokkeert `http` vanaf een
`https`-pagina. Het profieldialoog test bereikbaarheid voordat het iets
aanbiedt, en PRIVACY.md somt precies op welke bytes waarheen gaan onder
welke toestemming.

## Opslag, bewaring en wissen

- **Gestage opnames** staan zeven dagen in de stagingmap van de app
  nadat je *bewaren* kiest, en worden dan opgeruimd. Op web is er geen
  map: opname en manifest blijven in de tab als `mem:`-assets en een
  reload verliest ze — de bewaarflow waarschuwt daarvoor.
- **Callprovenance** reist mee als `sources.json` naast de opname (als
  `mem:`-asset op web): welke bronnen de mix voedden, hoeveel van elk
  aankwam en hoeveel ontbrak. Een transcript benoemt dat ontbrekende
  geluid in een *Ontbrekend*-regel; het verzint nooit sprekerslabels
  uit de deelnemerslijst.
- **Het transcript** is een Markdown-document in je project; zijn audio
  staat ernaast in `media/`, zodat het paar meereist, exporteert en
  backupt zoals elk deck-asset.
- **Wissen.** Bewaarde opnames verwijder je uit de gestage lijst;
  modellen via de instellingenkaart; de API-sleutel met het geheim van
  het profiel. Verder wordt niets bewaard — er is geen
  transcriptietelemetrie om te zuiveren.

## Wat er echt bewezen is

Elke positieve claim hierboven noemt zijn bewijs; alles wat ontbreekt
is *niet getest*, niet stilletjes ondersteund.

| Route | Bewijs |
|---|---|
| Lokale engine, macOS | Gemeten op Apple Silicon, `whisper-cli` v1.9.5 statische universele binary, Nederlandse referentie-WAV — ontwerpdoc §4.5 |
| Lokale engine, web | Gemeten op de verscheepte WASM-artifacten in Chrome, Firefox en WebKit, dezelfde referentie-audio — §4.6 |
| Liveserverprotocol | Integratietest tegen de gepinde Vosk-referentieserver: probe, partials, definitieve pass — `make test-asr-integration` |
| Jitsi-call end-to-end | Echte tweepersoonscall op de vrijgegeven macOS-build en de vrijgegeven webbundel (join, tweerichtingsmedia, share, leave/rejoin) — #2541, #2544 |
| Callopname → transcript | Echte tweepersoonscall, macOS en web: mix-WAV, `sources.json`, ontbrekend-geluidregel — #2545, #2548 |
| Windows- en Linux-builds | Gedeelde codepaden verschepen en slagen in de volledige testsuite; **er ligt geen hardwarebewijs** — beschouwd als niet getest tot dat er is |
| iOS / Android | Geen releaseplatforms — helemaal geen claim |

## Wanneer iets misgaat

Elke mislukking in deze module is een getypeerde, verklaarbare
uitkomst — de dialoog benoemt hem in plaats van succes te doen alsof:

- **DecodeFailed** — de container is er niet een die de engine leest.
  WAV/PCM werkt altijd; converteer de rest eerst.
- **CapacityExceeded** — het bestand is over de upload- of
  geheugenlimiet. Bij een serverroute is dat het 400 MiB-uploadplafond;
  op web is het het 2 GB-WASM-plafond, en daarom wordt
  `large-v3-turbo` daar ook niet aangeboden.
- **ConsentRequired** — de bestemming vraagt een bevestiging die je
  niet hebt gegeven (LAN-vertrouwen, cloudbevestiging, per-taak
  consent). Geef die bewust of kies lokaal.
- **noIsolation** (alleen web) — de host stuurt geen COOP/COEP-headers,
  dus de browser weigert `SharedArrayBuffer` en lokale inferentie kan
  niet draaien. Serveer de bundel volgens HOSTING.md §3, of gebruik
  een serverroute.
- **Live verbroken** — het live-endpoint viel weg. De voorvertoning is
  weg; de opname en de definitieve pass zijn onaangetast, en een
  retryknop vraagt opnieuw — niets verbindt vanzelf opnieuw.
- **Bron verloren / ontbrekend geluid** — een track of netwerkpad viel
  halverwege een opname weg. Wat geschreven was blijft geschreven, het
  manifest registreert het gat, en het transcript benoemt het.
- **Geen opnameknop in een call** — het platform rapporteert geen
  per-bron-callaudiotap. Dat is een eerlijke afwezigheid, geen
  verborgen schakelaar.

De zevendaagse stagingmap is ook de herstelweg: een opname die zijn
dialoog overleefde kan vanuit de gestage lijst alsnog worden
getranscribeerd of verwijderd.
