# Experimentele taalwisselroute (#2940)

Optioneel, expliciet gestart **lokaal referentie-endpoint**, geen meegeleverde
appengine of algemeen kwaliteitsadvies. OciDeck biedt de keuze *Meerdere talen
in deze opname* uitsluitend voor een OciDeck ASR v1-server die
`features.language_switching` bevestigt. De bestaande lokale CLI/WASM blijft
één taal per taak gebruiken en weigert een aangevraagde taalwisseltaak. Een
meertalig model alleen bewijst geen taalherdetectie.

## Installeren en starten

Gemeten op native macOS arm64, Python 3.13, CPU/int8 met vier threads. Windows,
Linux, Intel-macOS en GPU-inferentie zijn voor dit endpoint **niet bewezen**.
Maak een eigen venv; niets installeert/downloadt vanuit OciDeck:

```sh
python3.13 -m venv /eigen/venv
/eigen/venv/bin/pip install -r testbed/asr-multilingual/requirements-lock-macos-arm64.txt
/eigen/venv/bin/python testbed/asr-multilingual/fetch_models.py small --cache-dir /eigen/models
/eigen/venv/bin/python testbed/asr-multilingual/server.py --model-directory /eigen/models/small --model-name small
```

Zie `fetch_models.py --help` voor de argumenten. `models.json` pint afzonderlijk
base, small en large-v3-turbo op upstreamrevisie, omvang en SHA-256. De server
verifieert ieder bestand opnieuw vóór laden, gebruikt uitsluitend lokale bestanden,
zet HF offline en schakelt telemetry uit. Geen token of gated modelvoorwaarden.
Na starten: profiel loopback `http://127.0.0.1:8093`, protocol **OciDeck ASR v1**.
Kies bewust de taalwisselmodus en bevestig de bestemming voor dit bestand.

Voor web vereist de bestaande productie-CSP HTTPS. Start met `--port 8443
--tls-cert /eigen/cert.pem --tls-key /eigen/key.pem`, gebruik
`https://127.0.0.1:8443` en stel precies de browserorigin in via
`OCIDECK_ASR_ORIGIN`. Gebruik een door die browser vertrouwd certificaat. De
geautomatiseerde browserproef accepteert uitsluitend in zijn testcontext een
zelfgemaakt lokaal certificaat; dit wijzigt app/CSP/transport niet.

Eén taak tegelijk, HTTP429 als bezet, maximaal 64 MiB upload en 20 minuten PCM16
mono16kHz. Geen retries, audio-/transcript-/requestlogs, automatische modeldownload,
cloudfallback, opgeslagen audio of stemprofielen. Afbreken wordt tussen echte
ASR-segmenten gecontroleerd; een lopende native decoderstap is niet onderbreekbaar.
Stop de server en verwijder alleen de eigen modelmap/venv om op te ruimen.

## Segmentatie en beperkingen

Silero VAD levert spraakregio's (minimaal250ms spraak,500ms stilte,400ms padding),
geen blinde N-secondenknip. Iedere regio detecteert opnieuw een taal met
`task=transcribe`, beam5, temperatuur0, zonder vorige tekst als context. Originele
sampleoffsets blijven in start/eindtijden behouden. De taaltag is een **onzekere
regiotag**, geen oordeel over ieder woord; een taalwisseling binnen een doorlopende
spraakregio kan nog steeds verkeerd worden herkend of vertaald. Diarisatie wordt
niet ondersteund. Gebruikers kunnen gewone transcripttekst en zichtbare tags
bewerken; metadata blijft de oorspronkelijke engine-uitvoer.

De metingen en ruwe uitvoer staan in `integration_test/results/multilingual/`.
Lezen van meerdere talen door dezelfde persoon is bevestigd met corpusmetadata
(Bianca Kramer, reader3798), niet door automatische persoonsherkenning. De bestanden
zijn samengestelde voorleesfragmenten; zij bewijzen geen spontane vergadering,
accentdekking of natuurlijke codewisseling. Een synthetisch akkoord is slechts
een niet-spraakcontrole en vervangt geen representatieve muziekproef. Kwaliteits-
acceptatie blijft open waar deze gevallen niet slagen of niet vertegenwoordigd zijn.

## Reproduceren

Bewuste bronbestanden in een eigen corpuscache:

- MLS NL en Pools: `https://huggingface.co/datasets/facebook/multilingual_librispeech/resolve/2e83e61823b4c47dcbcb1980bb88601274127609/dutch/test-00000-of-00001.parquet`
  respectievelijk `polish/test-00000-of-00001.parquet`, als `nl-test.parquet` en
  `polish-test.parquet` (CC-BY-4.0; Meta/MLS, LibriVox-vrijwilligers).
- `https://www.openslr.org/resources/12/test-clean.tar.gz` als
  `en-test-clean.tar.gz` (CC-BY-4.0; OpenSLR/LibriSpeech, LibriVox-vrijwilligers).
- `https://archive.org/download/dutch_twins_1001_librivox/dutchtwins_00_perkins_64kb.mp3`
  als `bianca-en-introduction.mp3`; [LibriVox-boek](https://librivox.org/the-dutch-twins-by-lucy-fitch-perkins/),
  Bianca Kramer, Lucy Fitch Perkins1911, publieke-domeintoewijding.
- Onafhankelijke gedrukte referentie: [Project Gutenberg4012](https://www.gutenberg.org/ebooks/4012),
  als `dutch-twins.txt`; bij onbereikbaarheid de publieke spiegel
  `https://mirrors.xmission.com/gutenberg/4/0/1/4012/4012.txt`.

Met apart geïnstalleerde `pyarrow==23.0.0` en FFmpeg op PATH:

```sh
python3.13 testbed/asr-multilingual/prepare_fixtures.py /eigen/corpus /eigen/fixtures
/eigen/venv/bin/python testbed/asr-multilingual/benchmark.py /eigen/fixtures /eigen/fixtures/fixture-manifest.json /eigen/models/small small /eigen/small.json
```

Herhaal in een **nieuw proces** voor base en large-v3-turbo. Een exit0 betekent
meting voltooid, geen kwaliteitspass. WER/CER normaliseert Unicode/case/punctuatie;
woordmiddentijden wijzen uitvoer aan bronintervallen toe. Getallen en oude spelling
blijven staan. RSS is de cumulatieve procespiek, geen per-geval geheugendelta.

Echte native productieclient + documentbewerking/opslaan/heropenen:

```sh
OCIDECK_LANGUAGE_FIXTURE=/eigen/fixtures/nl-en-nl.wav OCIDECK_LANGUAGE_RESULT=/eigen/client.json scripts/gate_lock.sh flutter test --no-pub testbed/asr-multilingual/client_probe_test.dart
```

Web: start de TLS-server met origin `http://localhost:7357`, bouw via
`scripts/gate_lock.sh flutter build web --release --no-web-resources-cdn --target testbed/asr-multilingual/browser_probe.dart`,
installeer Playwright/browserartefacten bewust en roep `browser_probe.cjs BUILD
FIXTURE OUTPUT` aan (eventueel NODE_PATH). Deze proef meet echte gecompileerde
productie-ASR-client/CORS en het documentmodel in Chromium en WebKit; **geen volledige
release-UI of browserbestand-opslaan/heropenen**. Geen fakeprovider of stil overgeslagen
proef als invoer/server ontbreekt.

## Licenties en distributiegrens

Niets uit deze venv of modelmap komt in OciDeck-releases. De manifesten identificeren
MIT-modelconversies van OpenAI Whisper; dit is geen overdraagbare goedkeuring van
willekeurige helpers. Faster-whisper en CTranslate2 zijn MIT; ONNX Runtime is MIT,
Silero VAD MIT; PyAV is BSD-3-Clause maar zijn concrete wheels bevatten FFmpeg en
hebben eigen LGPL/GPL-bouwverplichtingen. De gemeten macOS-wheel meldt
LGPL-3.0-or-later; zijn concrete vlaggen en ingebedde dylibhashes staan in het
bewaarde operatorlicentierapport. Dat rapport is geen distributiegoedkeuring. `requirements-lock-macos-arm64.txt` legt
alleen de gemeten operatorinstallatie vast, geen gebundelde-artefactlicentiereview.
Bij toekomstige appdistributie geldt eerst de volledige artefactreview/noticegate
uit `docs/LICENSE_COMPLIANCE.md`; de experimentele installatie wijzigt die niet.

De bewaarde hashes identificeren de daadwerkelijk gemeten WAV-bestanden. Bij
herhaald Opus-decoderen met FFmpeg zijn enkele samples tot één PCM16-LSB
verschillend gebleken (42 van1.144.800 samples in NL→EN→NL); de scripts
beloven daarom geen platformonafhankelijke bitidentieke Opus-decodering.
Controleer bronhashes, lengtes en sampleverschillen voordat nieuwe metingen
als rechtstreeks gepaard bewijs worden gebruikt.

Verwerkingstijden zijn waarnemingen op een gedeelde ontwikkelmachine met
ander testwerk, geen gecontroleerde snelheidsbenchmark. De native whisper.cpp-
baseline gebruikt standaard Metal/ggml-f16; CTranslate2 gebruikt CPU/int8.
Snelheidsverschillen tussen deze engines zijn daarom geen zuivere meting van
alleen het segmentatie-algoritme.

Een aparte echte TLS-annuleringsmeting wacht twee seconden met een bezette
modeltaak, verbreekt de client en meet wanneer een nieuwe aanvraag geen429
meer krijgt:

```sh
python3 testbed/asr-multilingual/cancel_probe.py /eigen/fixtures/nl-en-nl.wav /eigen/cancel.json
```

Deze proef is bewust op `127.0.0.1:8443` begrensd en accepteert daar alleen
voor de proef het lokale certificaat. Zij bewijst vrijgave bij een volgende
controlegrens, niet het onderbreken van een al lopende native decoderstap.
