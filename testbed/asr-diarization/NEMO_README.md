# Lokale native batchdiarisatie — Nemotron/Whisper (#2935)

Optionele, expliciet gestarte loopbackserver voor het bestaande
[OciDeck ASR v1-contract](../../docs/design/ASR_BATCH_V1.md). Dit is geen
meegeleverde appengine. De app downloadt/installeert deze onderdelen niet en
schakelt niet vanzelf naar deze server om. Een bestaande server, account,
Hugging Face-token of acceptatie van gated pyannote-voorwaarden is niet nodig.

## Gemeten route en grenzen

Native macOS arm64; Python 3.13, Whisper `small` via de gepinde CTranslate2-CPU/int8-
route met vier threads, plus NVIDIA Nemotron 3 Diarization Q8_0 via de officiële
NeMo-Speech.cpp-runtime. De HTTP- en TLS-routes gebruiken exact dezelfde backend.
De native productieclient is beproefd met hernoemen/opslaan/heropenen; de echte
gecompileerde productie-webclient/CORS/documentmodelroute met Chromium en WebKit.
Dat laatste is **geen** volledige release-UI of bewijs voor browserbestandsopslag.
Die bredere matrix staat afzonderlijk in #2947.

Gemeten op kleine gelabelde NL/EN-fragmenten: één stem, A–B–A, drie stemmen,
overlap, stereo naar mono en spraak met synthetische achtergrondmuziek. Toegekende
IDs blijven bij de bekende bronstem en bij terugkeer gelijk. Onzekere woorden
blijven onbekend; in het moeilijkste NL A–B–A-geval is ongeveer een kwart van de
ASR-uitvoer onbekend. Alle toegewezen labels krijgen `(?)`: het zijn modelclusters,
geen bewezen persoonsidentiteiten. Geen nul-foutengarantie, accent-/vergaderdekking
of volledige reconstructie van gelijktijdige stemmen. Bronintervallen bevatten
natuurlijke pauzes: er is **geen DER verzonnen zonder activiteitreferentie**.

CLI/WASM in OciDeck blijft `diarization:false`; deze server is de afzonderlijke
opt-in. Native Windows/Linux/Intel-backendbuilds en de combinatie met andere
ASR-modellen zijn niet bewezen. Het CLI-argument `--backend metal` is een
experimentele operatoroptie; de end-to-end-matrix gebruikt CPU. Er is geen
cloudfallback en de server bindt uitsluitend aan `127.0.0.1`.

## Bewuste installatie

Vereist native Xcode-commandlinetools, Git, CMake ≥3.26 en Python 3.13. De gemeten
compiler/SDK en exacte native bronrevisie worden in `ocideck-runtime.json`
vastgelegd. Gebruik eigen, **nieuwe** werk-/installatiemappen; de builder weigert
bestaande mappen en verwijdert of vervangt geen bestaande installatie.

```sh
python3.13 -m venv /eigen/build-tools
/eigen/build-tools/bin/pip install ninja==1.13.2
PATH="/eigen/build-tools/bin:$PATH" /eigen/build-tools/bin/python testbed/asr-diarization/build_nemo_runtime.py --work-dir /eigen/nemo-build --prefix /eigen/nemo-runtime

python3.13 -m venv /eigen/asr-venv
/eigen/asr-venv/bin/pip install -r testbed/asr-multilingual/requirements-lock-macos-arm64.txt
/eigen/asr-venv/bin/python testbed/asr-multilingual/fetch_models.py small --cache-dir /eigen/models
/eigen/asr-venv/bin/python testbed/asr-diarization/fetch_nemo_model.py --cache-dir /eigen/models/nemotron

/eigen/asr-venv/bin/python testbed/asr-diarization/nemo_server.py --asr-directory /eigen/models/small --asr-model small --runtime-directory /eigen/nemo-runtime --diarization-model /eigen/models/nemotron/Nemotron-3-Diarization.q8_0.gguf
```

De native builder haalt de exacte officiële bron/gitlinks op, bouwt alleen de
native bibliotheken (ASR/TTS/NMT/CLI/microfoon/HTTP uit, diarisatie aan), gebruikt
Apple clang en installeert volledige notices. Geen globale pakketinstallaties
of modellen in de builder. De aparte modeldownload controleert omvang/SHA-256,
bewaart oorspronkelijke modelnotices en weigert bestaande afwijkende bestanden.
Het model is ongeveer 102 MiB; de ASR-gewichten zijn apart, ongeveer 464 MiB voor small.
Ninja is uitsluitend bouwgereedschap; de inference-venv blijft apart.

Kies in OciDeck het ingeschakelde loopbackprofiel `http://127.0.0.1:8093`, protocol
**OciDeck ASR v1** en bijvoorbeeld profielnaam *Lokaal — Whisper small + Nemotron*.
Na de capabilitycontrole verschijnt **Sprekers onderscheiden**. Kies een taal
of de afzonderlijke taalwisselmodus; bevestig op Start de bestemming voor dit
bestand. Dit vervangt de opnametoestemming van deelnemers niet. Een hernoeming
naar Alice gebeurt door de auteur in gewone Markdown, nooit door stemidentificatie.

Voor web vereist de bestaande productie-CSP HTTPS. Start bijvoorbeeld met
`OCIDECK_ASR_ORIGIN=https://jouw-ocideck-host.example` en aanvullende argumenten
`--port 8443 --tls-cert /eigen/cert.pem --tls-key /eigen/key.pem`; gebruik een
certificaat dat de browser vertrouwt en configureer `https://127.0.0.1:8443`.
Er is exact-origin-CORS, geen wildcard. De browserproef hieronder accepteert
alleen binnen zijn testcontext een zelfgemaakt loopbackcertificaat; app/CSP en
productietransport worden niet versoepeld. Optioneel `OCIDECK_ASR_TOKEN` op de
server en dezelfde sleutel via de bestaande OciDeck-sleutelbos, nooit profiel-JSON.

Stoppen: beëindig alleen deze server (Ctrl+C). Opruimen: verwijder bewust alleen
de eigen venv/model-/runtime-/bouwmappen. Er wordt geen achtergrondservice,
LaunchAgent of blijvende taak geïnstalleerd.

## Werkelijke verwerking en begrenzing

- Eén taak tegelijk, HTTP429 bij bezet; geen retry/wachtrij. Maximaal 64 MiB upload,
  mono 16 kHz PCM16 WAV en twintig minuten. Andere containers lopen eerst door de
  bestaande OciDeck-decoder, niet rechtstreeks door dit endpoint.
- De server verifieert beide native dylibs, oorspronkelijke model-/licentienotices
  en de gepinde GGUF/ASR-bestanden vóór beschikbaarheid. Een native ABI-proef leest
  geen gebruikersaudio. Verkeerde/ontbrekende onderdelen weigeren de start.
- Het native model draait in een apart, begrensd proces. Tot zes minuten gebruikt
  het volledige aandacht; daarna één stateful streamingcache voor het hele bestand.
  De werkelijke 10 ms-activiteit wordt op originele ASR-woordtijden beoordeeld. Geen
  blind om-en-om nummeren of verzonnen woord-/tijdgrenzen. Bij afwijkende woordtekst
  blijft het volledige oorspronkelijke ASR-segment ongewijzigd en zonder IDs staan.
- Eén duidelijke activiteit (`≥0,5`, marge`≥0,1`) krijgt een cluster; meerdere
  sterke activiteiten (`≥0,6`) meerdere IDs. Zwak/ambigu wordt onbekend. Deze
  drempels zijn conservatieve beslisregels, geen gekalibreerde nauwkeurigheidspercentages.
  De native runtime-default is een andere, CallHome-afgestelde postprocessor;
  die mist in onze NL A–B–A-proef een stem en wordt niet stil als voldoende gebruikt.
- De taaldetectie/-wisselroute blijft onafhankelijk van diarisatie. Uitgeschakeld
  betekent geen native taak en geen sprekerdata; de ASR-tekst is in alle gemeten
  gevallen exact gelijk met en zonder diarisatie. De nieuwe route maakt de
  bestaande ASR-tekst dus niet automatisch foutloos, ook niet bij stilte/muziek.
- Annuleren beëindigt/reapt het native kindproces; tijdelijke audio/activiteit
  verdwijnt. Tijdens ASR wordt tussen echte decodersegmenten gecontroleerd.
  Geen audio-/transcript-/requestlogs, modeldownloads tijdens verwerking,
  stemvectoropslag, namen of persoonsdatabase. Modelactiviteit blijft alleen
  tijdelijk in een private stagingmap en werkgeheugen; het document krijgt IDs/tijden.
- Worker-uitvoer is begrensd; tijdslimiet `90+2×audioduur` seconden. Geen overlevend
  kind na annulering/fout. Fouten leveren geen resultaat met verzonnen labels.

## Reproduceren en betekenis van het bewijs

Bereid de bestaande publieke CC-BY-4.0-MLS/LibriSpeech-fixtures voor zoals in
[README.md](README.md#reproduceerbare-fixturematrix). De stemnummers zijn
corpuslabels; zij worden niet aan OciDeck doorgegeven. Bron-IDs/hashes en de
onbekende uitvoer blijven in het rapport, inclusief negatieve controles.

```sh
/eigen/asr-venv/bin/python testbed/asr-diarization/nemo_probe_matrix.py /eigen/fixtures /eigen/http-matrix.json --server-pid EIGEN_SERVER_PID
/eigen/asr-venv/bin/python testbed/asr-diarization/nemo_probe_worker.py /eigen/fixtures /eigen/nemo-runtime /eigen/models/nemotron/Nemotron-3-Diarization.q8_0.gguf /eigen/worker-memory.json

OCIDECK_DIARIZATION_FIXTURE=/eigen/fixtures/nl-aba.wav OCIDECK_DIARIZATION_RESULT=/eigen/client.json scripts/gate_lock.sh flutter test --no-pub testbed/asr-diarization/nemo_client_probe_test.dart
```

`fixture_matrix_pass` betekent alleen: deze bekende bronindelingen hebben stabiele,
verschillende toegekende IDs (onbekend apart gerapporteerd), overlap heeft meerdere
IDs, ASR-tekst blijft gelijk en uitgeschakeld geeft geen labels. Het is geen
corpusbrede DER-/kwaliteitsscore. De geheugenproef rapporteert losse workerpieken;
server-RSS-snapshots zijn geen gecombineerde geheugenpiek met de app.

Web: start de TLS-server met origin `http://localhost:7357` en een expliciet lokaal
proefcertificaat, bouw met
`scripts/gate_lock.sh flutter build web --release --no-web-resources-cdn --target testbed/asr-diarization/nemo_browser_probe.dart`
en roep met bewust geïnstalleerd Playwright `nemo_browser_probe.cjs BUILD FIXTURE
OUTPUT` aan (eventueel NODE_PATH). Geen fakeprovider of stille skip als de
fixture/server/browser ontbreekt. Proeven voor lange invoer en annulering:
`nemo_cancel_probe.py RUNTIME MODEL LANGE_WAV OUTPUT` en
`nemo_http_cancel_probe.py LANGE_WAV EIGEN_SERVER_PID OUTPUT`.
De herhaalde lange fixture dient proces-/klokcontrole, geen natuurlijke gespreksevaluatie.

## Exacte licentie- en distributiegrens

NeMo-Speech.cpp 0.3.0 op revisie `e790e463b2913cff9f989a3df224c587f14b4c5c`
is Apache-2.0; de gebruikte ggml-code MIT. De statische SentencePiece-bron en
gebundelde afhankelijkheden hebben eigen Apache/BSD-notices, door de upstream-
installatie volledig meegegeven en op hash geregistreerd. De concrete dylibs
linken alleen elkaar en Apple-systeembibliotheken/frameworks; geen KenLM,
spraaksynthetisator, download-CLI of externe dylib wordt in deze runtime gebouwd.

De officiële Nemotron 3-GGUF is afzonderlijk gepind in `nemo_model.json`, revisie
`52a432672732425e4c19765b9fec9b5810e6f4ba`, SHA-256
`08456d9e22cd9a323c0364d98375f3746d6e68507ebb705cd46438c534c7a3a1`,
onder **OpenMDW-1.1**, met de volledige overeenkomst en originele notices. Het
model erft Apache/MIT niet van de runtime of Whisper. De bestaande Whisper-
conversies zijn apart MIT; de concrete Python-wheelinventaris blijft nodig
(PyAV omvat bijvoorbeeld FFmpeg met eigen voorwaarden).

Dit alles is een **operatorinstallatie buiten de apprelease**. Er is geen nieuwe
BundledLicenses-/SBOM-goedkeuring voor het meeleveren van willekeurige helpers.
Voor toekomstige distributie in OciDeck blijft de volledige artefact-/noticegate
uit [LICENSE_COMPLIANCE.md](../../docs/LICENSE_COMPLIANCE.md) vereist.
