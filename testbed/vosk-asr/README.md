# Gepinde Vosk-testbed voor de live-ASR-route (#2525)

Een lokale Vosk-WebSocket-server waarmee OciDeck's live-serverroute tegen
een échte ASR-implementatie wordt getest: de protocolproef, partiële
hypothesen tijdens de stroom en de definitieve uitslag over dezelfde audio.

Dit is tevens de **setupgids voor de geteste serverimplementatie** die de
issue-acceptatie vraagt: welk protocol, welke audio, welke authenticatie-
en transportgrenzen OciDeck hanteert, en hoe je de faalmodi herkent. Er is
bewust géén algemene claim: getest is de Vosk-referentieserver
(`alphacep/vosk-server`, `websocket/asr_server.py`); andere servers die dezelfde
vorm spreken zijn mogelijk compatibel, maar dat is niet bewezen.

## Opzetten

```sh
cd testbed/vosk-asr
./fetch-model.sh        # eenmalig: model ophalen + sha256 toetsen
docker compose up -d    # server op ws://127.0.0.1:2700
```

Daarna, vanuit de repo-root:

```sh
make test-asr-integration   # OCIDECK_ASR_INTEGRATION=1 flutter test …
```

De toets bewijst: (1) de capability-proef herkent `vosk-ws-1` op de echte
socket, (2) live partiële hypothesen komen terug terwijl de chunks opgaan,
(3) de definitieve pass over dezelfde WAV (`fixtures/test16k.wav`, uit het
Vosk-project zelf) een transcript met woordtijden levert, en (4) na
`{"eof" : 1}` geen audiopakket meer de deur uit gaat.

## Wat is gepind — en wat betekent dat voor het bewijs

| Wat | Waarde | Waar vastgelegd |
|---|---|---|
| Server-image | `alphacep/kaldi-vosk-server:latest` | `docker-compose.yml` |
| Model | `vosk-model-small-en-us-0.15` (41 MB) | `fetch-model.sh` + sha256 |
| Endpoint | `ws://127.0.0.1:2700` (alleen loopback) | `docker-compose.yml` |
| Protocol-id bij OciDeck | `vosk-ws-1` | `asr_live_protocol.dart` |
| Proeffixture | `fixtures/test16k.wav` (16 kHz mono s16le) | uit de image gehaald |

De testbed is loopback-only opzet: bewijs van clientgedrag tegen een echte
server, niet van een productie-netwerk. De gate-tiers (`lan`, `cloud` met
`wss`) zijn apart getest in `asr_server_gate_test`/`evaluateLive`.

## Het wire-protocol (`vosk-ws-1`)

Exact wat OciDeck stuurt en verwacht — getest tegen `asr_server.py` in de
image:

1. **Open**: `ws://` of `wss://` upgrade op het ingestelde live-endpoint.
   Op desktop stuurt OciDeck de API-sleutel als `Authorization: Bearer …`
   handshake-header; de referentieserver kent zelf geen auth (zie
   *Authenticatie* hieronder).
2. **Config**: één tekstframe
   `{"config":{"sample_rate":16000,"words":true}}` direct na de handshake.
   `words:true` vraagt woordtijden, zodat `result`-berichten echte
   offsets dragen.
3. **Audio**: binaire frames met 16 kHz mono signed-16-bit little-endian
   PCM — hetzelfde formaat dat de capture al levert. Volgorde op de draad
   ís de tijdsvolgorde; het protocol kent geen per-chunk-timestamps.
4. **Antwoorden**: `{"partial":"…"}`-hypothesen (overschrijven zichzelf)
   en `{"result":[…],"text":"…"}`-uitspraken per afgeronde zin.
5. **Einde**: het tekstframe `{"eof" : 1}` — **byte-exact met spaties**:
   de referentieserver vergelijkt de frame letterlijk, niet als JSON.
   `{"eof":1}` leest hij als audio, de sessie sterft zonder slotresultaat.
   Daarna geen audiopakket meer; de socket sluiten is afbreken.
6. **Hervatten bestaat niet**: een nieuwe verbinding is een nieuwe
   sessie. Stil reconnecten is precies wat de sessieconsent verbiedt.

## Authenticatie, TLS, CORS en origin

- **Auth**: de referentieserver kent geen authenticatie. OciDeck leest de
  API-sleutel per verbinding uit de sleutelbos (gekeyd op de profiel-
  `baseUrl`) en stuurt hem op desktop uitsluitend als
  `Authorization`-handshake-header — nooit in de URL, want live-URL's met
  query of fragment wijst de gate sowieso af (tokens in URL's belanden in
  logs en proxies). Een echt eisende server hoort achter een proxy die
  auth afdwingt; dat pad is niet getest.
- **TLS**: `wss://` is verplicht voor de `cloud`-tier; `ws://` mag alleen
  waar platte `http` ook mocht (loopback, of `lan` na de expliciete
  trusted-internal-keuze). De testbed is `ws://` op loopback — de `wss`-vorm
  is gate-getest, niet tegen een TLS-terminerende Vosk bewezen.
- **CORS/origin**: op web is de browser de grens — CORS-preflight en
  mixed-content-regels gelden daar; een browser-WebSocket kan geen
  headers zetten, dus een sleutel-eisend live-endpoint is op web
  onbereikbaar. Bovendien leveren web-opnamebronnen nu geen
  `liveChunks`, dus de live-optie verschijnt daar niet.
- **Netwerkbestemming**: op desktop pint OciDeck de socket aan het adres
  dat de gate resolveerde (DNS-rebinding kan de stroom niet verleggen);
  de testbed bereikt alleen `127.0.0.1` — geen andere bestemming.

## Limieten

- **Model**: `vosk-model-small-en-us-0.15` — klein, Engelstalig, ruim
  genoeg voor de proef; kwaliteit en taaldekking zijn servereigenschappen
  die OciDeck niet claimt.
- **Backpressure**: het protocol kent geen credit-systeem. OciDeck zendt
  op capture-tempo, de `LivePass` meldt achterlopen (`lagging`), en de
  definitieve pass pacing op ~13 MB/s. Een server die niet meekomt
  vertraagt zijn antwoorden — geen verloren audio.
- **Timeouts**: connect 15 s; na `eof` wacht de engine max. 10 s op de
  slotresultaten voordat de socket zelf sluit.
- **Geheugen**: chunks worden doorgeschoven, niet gebufferd; de
  definitieve pass leest de WAV uit staging (max. de 400 MB-uploadgrens
  van de batchroute geldt daar niet — het is streamen in frames).

## Foutdiagnose

| Symptoom | Betekenis | Waar je kijkt |
|---|---|---|
| "Endpoint ontbreekt of is ongeldig" | gate weigert de `liveUrl` (schema, query/fragment, tier) | de poortuitslag onder het live-veld |
| "server is onbereikbaar of spreekt het live-protocol niet" | socket weigert, of het eerste antwoord was geen `partial`/`result` | `docker compose logs` — elke connectie logt `Connection from …` |
| proef slaagt, checkbox verschijnt niet | het profiel heeft geen `liveUrl` of de proef faalde | settings → transcriptieserver |
| status `lost` in de strook | socket weg tijdens de opname — opname loopt door | serverlogs; *opnieuw verbinden* vraagt expliciet opnieuw |
| geen partials maar wel `result` | normaal — hypothesen zijn optioneel in het protocol | niets |
| "server sloot niet af" | geen slotresultaat binnen 10 s na `eof` | server belasting; de clip was te groot of de CPU te traag |
| `Connection reset`/crash in serverlogs | byte-vorm van `eof` klopt niet (`{"eof":1}` i.p.v. `{"eof" : 1}`) | `asr_live_protocol.dart` — het frame is draadcontract |

## Opruimen

```sh
docker compose down          # stack uit; model blijft in ./model staan
rm -rf model                 # alles weg — fetch-model.sh haalt opnieuw
```
