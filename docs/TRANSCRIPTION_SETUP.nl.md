# OciDeck — Transcriptie en opname: platformsetup

> **Status:** setupmatrix en stapsgewijze gids voor de vrijgegeven builds · **Status laatst nagekeken:** 2026-11-17 · **Uitgegeven door:** Stichting LibreKAT

Deze pagina beantwoordt, per platform: wat je moet installeren of
toestaan, hoe een opname een transcript wordt, waar de bestanden staan,
en wat je doet als iets faalt. De
[gebruikershandleiding](USER_GUIDE.nl.md#transcriptie-en-opname)
legt de module zelf uit; deze pagina is de platformmatrix waarop de
release wordt getest. Waar een route niet op echte hardware is bewezen,
staat hier *niet getest* in plaats van dat een gedeelde codepad als
ondersteuning leest.

Bij het aanzetten van de uitbreiding verschijnt eerst een waarschuwing over
mogelijke gegevensuitwisseling. Tonen en accepteren of weigeren komen in het
logboek. Dat vervangt de latere toestemming voor een opname of servertaak niet.
Een expliciete browserkopie bewaart een presentatiepakket inclusief opgenomen
media die daarin zijn opgenomen; dit bewaart geen losse opname of
transcriptiesessie automatisch. Zie [USER_GUIDE.md](USER_GUIDE.md).
*(Bijgewerkt 2026-11-08.)*

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
verwijdert ze weer, na een vraag — die noemt het model en zijn
grootte, en *Annuleren* laat het staan; er is geen andere verwijderroute
te vinden.

**Heb je het bestand al?** Op desktop scant de instellingenkaart ook een
paar bekende plekken — `~/Downloads`, een `~/whisper.cpp`-checkout, de
huggingface-cli-cache van de gepinde modelrepository en de datamap van
pywhispercpp — naar `ggml-*.bin`-bestanden met precies de catalogusomvang.
Een treffer verschijnt als "Gevonden op schijf: <pad>" met een knop
**Van schijf installeren**: het bestand wordt op SHA-256 getoetst en naar
de modelmap gekopieerd; jouw origineel blijft waar het ligt. Een bestand
dat de hash niet haalt, wordt geweigerd — nooit geïnstalleerd. De kaart
kijkt bij elke opening opnieuw, dus een model dat je later neerzet
verschijnt zonder herstart.

## Platformmatrix

| | macOS | Windows | Linux | Web |
|---|---|---|---|---|
| Release-artifact | Getekend + genotariseerd, universeel (arm64 + x86_64) | Ongetekende zip en installer (SmartScreen-waarschuwing is verwacht) | Ongetekend | Statische bundel; vereist COOP/COEP-headers van de host voor lokale inferentie |
| Bestaand audiobestand | WAV/PCM bewezen; andere containers decoderen of melden `DecodeFailed` | idem | idem | Browsercodec-dekking beslist |
| Microfoon | Bewezen — na de macOS-prompt | Aangeboden — OS-privacy-schakelaar beslist | Aangeboden — hardware-aanwezigheid beslist, de meeste setups hebben geen OS-prompt | Bewezen — per-site browsertoestemming |
| Systeem-/appgeluid | Aangeboden — ScreenCaptureKit onder *schermopname*-toestemming (macOS 13+); DRM-audio wordt door het OS uitgesloten | Aangeboden — WASAPI-loopback neemt de endpointmix op, niet één app | Aangeboden — alleen PipeWire/PulseAudio `.monitor`-bronnen; kale ALSA heeft er geen | Niet aangeboden als systeemgeluid |
| Tabbladgeluid | — | — | — | Alleen Chromium; Firefox en Safari krijgen een eerlijke melding in plaats van een knop |
| Callaudio (Jitsi in-app) | Bewezen in een echte tweepersoonscall | Native per-track-sink aanwezig; echte releasecall nog niet bewezen | Native per-track-sink aanwezig; echte releasecall nog niet bewezen | Bewezen in een echte tweepersoonscall (getest op Chromium) |
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
in de `Authorization`-header, en alleen over `https`/`wss` of naar deze
machine zelf. Staat er een sleutel, dan wordt een kale `http`/`ws`-route
naar een ander apparaat geweigerd voordat er iets vertrekt, in plaats
van de sleutel leesbaar over het netwerk te sturen. *(Rechtgezet
03-11-2026, #2758: deze zin beloofde al alleen `https`, maar de sleutel
ging ook over kale `http` naar een LAN-server.)*

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

### Antwoordbudgetten aan de clientkant

Batchantwoorden via HTTP worden als stroom gelezen en stoppen bij 16 MiB,
ook in de browser. Een ontbrekende of onjuiste `Content-Length` verandert
die grens niet.

De liveroute past afzonderlijke grenzen toe vóór JSON-parsing en tijdens het
verzamelen van resultaten: 256 KiB per bericht, 64 KiB per tekstveld, 4.096
woorden per resultaat, 64 MiB of 250.000 ontvangen berichten per sessie en
8 MiB of 100.000 bewaarde resultaatsegmenten. Voor een gepauzeerde afnemer
blijven hooguit 1 MiB of 256 berichten in de wachtrij. UTF-8-bytes tellen,
niet alleen het aantal tekens. Bij overschrijding sluit de serverroute met
een fout; een afgekapt transcript wordt niet als volledig resultaat gemeld.
De lokale opname blijft onafhankelijk.

Deze grenzen beperken conversie, parsing, wachtrijen en bewaarde resultaten
in de applicatie. De WebSocket-API's van de browser en `dart:io` leveren
complete berichten en kunnen een te groot bericht dus al hebben toegewezen
voordat de app het afwijst. Een berichtlimiet op de server en een vertrouwde
serverinrichting blijven nodig; dit belooft geen door OciDeck afgedwongen
grens aan de eerste WebSocket-buffer van het platform.

## Opslag, bewaring en wissen

- **Gestage opnames** staan in de stagingmap van de app,
  `transcription/recordings/` in de app-supportmap, en worden zeven
  dagen na het begin van de opname opgeruimd. Niet in de tijdelijke map
  van het besturingssysteem: macOS leegt die na drie dagen en veel
  Linux-systemen bij elke herstart, vóór de zeven dagen om zijn.
  *(Rechtgezet 03-11-2026, #2761: tot dan stond de staging in de
  tijdelijke map, en telde deze regel de dagen vanaf *bewaren*.)* Op web
  is er geen
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

## Native hulpmiddel op Windows en Linux

De build installeert `ocideck-audio` naast OciDeck. Bestands­transcriptie gebruikt
op Windows Media Foundation en op Linux GStreamer. Een losse FFmpeg-installatie
is niet meer nodig; de oude PATH-route blijft een terugval voor ontwikkelbuilds
zonder helper. Windows N/KN vraagt nog de Media Feature Pack; op Linux blijven
de gedeclareerde GStreamer-codecs en een werkende PulseAudio/PipeWire-sessie
systeemvoorwaarden. De Linux-helper leest bronnen en PCM rechtstreeks via
libpulse: `parecord` en `pactl` hoeven niet meer aanwezig te zijn.

De code bevat integratieproeven met synthetische MP3/M4A/MP4-bestanden, een video
zonder audiotrack, en de echte C++-callaudiosink. Deze bewijzen de betreffende
paden; zij vervangen geen tweepersoonscall met echte apparaten op ieder OS.

## Meerdere talen binnen één opname

De taalkeuze maakt onderscheid tussen een vaste taal, **Automatisch detecteren
(één taal)** en **Meerdere talen in deze opname**. Die laatste keuze verschijnt
alleen bij een zelf ingesteld OciDeck ASR v1-serverprofiel dat taalwisselingen
expliciet ondersteunt. De talenlijst volgt de werkelijk gerapporteerde
mogelijkheden, waaronder Pools waar ondersteund. Lokale whisper.cpp/WASM biedt
de taalwisselmodus nog niet; een meertalig model alleen herdetecteert niet
vanzelf de taal bij elke passage.

De optionele [lokale referentieproef](https://pawprint.vigilis.online/LibreKAT/Ocideck/src/branch/main/testbed/asr-multilingual/README.md)
verwerkt spraakregio's afzonderlijk zonder vertaalopdracht. Zij downloadt of
installeert niets vanuit de app. De bestaande toestemming voor dit bestand
en deze bestemming blijft vereist. Lange NL/EN- en PL/EN-blokken verbeteren
in de proef, maar korte citaten of taalwisselingen zonder pauze kunnen fout
blijven of verslechteren; dit is geen algemene kwaliteitsgarantie. `[en?]`
betekent een onzekere taaltoewijzing aan die regio. Je kunt transcripttekst
en zichtbare tags gewoon corrigeren en opslaan. Oorspronkelijke tijden en
taaltags blijven als inspecteerbare documentmetadata behouden.

## Optionele sprekerdiarisatie via een lokale server

Voor native macOS arm64 is een expliciet te installeren
[Nemotron/Whisper-loopbackserver](https://pawprint.vigilis.online/LibreKAT/Ocideck/src/branch/main/testbed/asr-diarization/NEMO_README.md)
beproefd. Er is geen bestaande ASR-server, modelaccount of gated pyannote-toegang
voor nodig. De app installeert of kiest deze route niet vanzelf. Configureer
OciDeck ASR v1, wacht op de capabilitycontrole en kies **Sprekers onderscheiden**;
Start bevestigt dit bestand en deze bestemming. Lokale CLI/WASM biedt dit niet aan.

In de kleine NL/EN-proeven blijven toegekende sprekernummers bij terugkeer gelijk.
Onzekere passages worden onbekend of krijgen `(?)`; in het moeilijkste NL-fragment
blijft ongeveer een kwart onbekend. Overlap kan meerdere IDs krijgen. Dit zijn
geen persoonsnamen of algemene nauwkeurigheidsgarantie. Je kunt zichtbare labels
zelf hernoemen; oorspronkelijke tijden en cluster-IDs blijven documentmetadata.
Bij lange streaminginvoer kan een eerste overgang enkele seconden verkeerd
worden toegewezen; controleer de labels. De volledige release-UI-/hardwarematrix
staat los van deze beperkte client-/modelproeven.
