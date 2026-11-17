# Experimentele batchdiarisatieproef (#2935)

Dit is een optioneel, expliciet gestart referentie-endpoint voor
[OciDeck ASR v1](../../docs/design/ASR_BATCH_V1.md). Het is geen appafhankelijkheid
of productieadvies. De bestaande WebSocket-Vosk-testbed blijft apart.

```sh
python3 testbed/asr-diarization/fetch_models.py
docker compose -f testbed/asr-diarization/docker-compose.yml up
```

Kies in OciDeck de loopbackserver `http://127.0.0.1:8093`, protocol OciDeck ASR v1
en voor deze backend expliciet Nederlands of Engels. Alleen na een geldige
capabilitycontrole verschijnt Sprekers onderscheiden. Starten bevestigt de upload
van dit bestand aan deze loopbackserver. De eerste verbinding kan tijdens het
laden van de modellen nog weigeren; probeer daarna bewust opnieuw.

De modeldownload is een aparte operatoractie, met exacte SHA-256 in `models.json`.
De drie [upstream Vosk-modellen](https://alphacephei.com/vosk/models) zijn Apache-2.0;
zij worden niet met de app gebundeld. Verwijderen: stop deze compose-stack en wis
alleen de map `testbed/asr-diarization/model`. De uitpakkende installer behoudt de
archieven ter hashcontrole. Geen Hugging Face-token of impliciete acceptatie van
modelvoorwaarden. Het bestaande gepinde Vosk-containerimage draait op amd64;
op deze Apple Silicon-proefmachine is dat emulatie, geen native prestatiemeting.

Begrenzing: één taak tegelijk, 64 MiB upload, maximaal 20 minuten PCM16 mono,
30 seconden per socketoperatie. Andere taken krijgen HTTP 429; geen wachtrij,
geen retry. Alleen host-loopback gepubliceerd, read-only container zonder extra
capabilities. Geen logs van requests, audio, transcript of stemvectoren; geen
resultaatopslag, automatische downloads, cloudfallback of database van personen.
Een afgebroken client krijgt geen resultaat; berekening kan tot de begrensde taak
klaar is doorgaan. Gebruik dit niet als publiek netwerkendpoint.

Optioneel `OCIDECK_ASR_TOKEN` op de server activeren en dezelfde sleutel via de
OciDeck-sleutelbos instellen; geef deze variabele zelf expliciet aan de container
door. Voor een browserproef is één exacte `OCIDECK_ASR_ORIGIN` nodig; er is geen
wildcard-CORS. Onbekende browserorigins worden ook zonder token geweigerd.

De backend gebruikt Vosk-woordtijden voor segmentbegin/-einde en één stemvector per
Vosk-uiting. Clustering vergelijkt genormaliseerde vectoren binnen één opname met
cosinusafstand 0,3; geen opgeslagen stemafdrukken, namen of koppeling tussen taken.
Weinig spraakframes levert onbekend. Het model detecteert geen overlap of
sprekerwissel midden in een uiting; elke toewijzing is daarom onzeker. Een eerste
NL A-B-A-proef gaf vier clusters voor twee stemmen. Dat is een aangetoonde
kwaliteitsbeperking, geen geslaagde algemene sprekerherkenning. Gebruik deze proef
om het transport/documentcontract te toetsen, en beoordeel een volwaardige
backend met gelabelde NL/EN-fixtures vóór een kwaliteitsclaim.

## Reproduceerbare fixturematrix

Download bewust de twee publieke bronarchieven naar een eigen cachemap:

- MLS Dutch: `https://huggingface.co/datasets/facebook/multilingual_librispeech/resolve/2e83e61823b4c47dcbcb1980bb88601274127609/dutch/test-00000-of-00001.parquet`, als `nl-test.parquet`;
- LibriSpeech: `https://www.openslr.org/resources/12/test-clean.tar.gz`, als `en-test-clean.tar.gz`.

Beide corpora zijn CC-BY-4.0; bron-IDs en SHA-256 staan in het bewaarde rapport.
Gebruik Python 3.13 met expliciet geïnstalleerde `pyarrow==23.0.0` en FFmpeg:

```sh
python3.13 prepare_fixtures.py /eigen/cache /eigen/fixtures
python3 probe_matrix.py /eigen/fixtures /eigen/rapport.json --container eigen-containernaam
```

De scripts downloaden niets. `probe_matrix.py` is een meetprogramma: een normale
afsluiting betekent dat de meting voltooid is, **niet** dat backendkwaliteit is
goedgekeurd. Lees `quality_acceptance` en de uitkomsten per geval. Er wordt geen
DER verzonnen zonder een geschikte referentie voor spraakactiviteit.

Voor de echte productieclient/documentmodel-proef, vanuit de repositoryroot:

```sh
OCIDECK_DIARIZATION_FIXTURE=/eigen/fixtures/nl-aba.wav \
OCIDECK_DIARIZATION_RESULT=/eigen/client-rapport.json \
  scripts/gate_lock.sh flutter test --no-pub testbed/asr-diarization/client_probe_test.dart
```

Beide paden zijn verplicht; ontbrekende invoer faalt en wordt niet stil overgeslagen.
De proef is een echte netwerk-/documentintegratie, geen volledige release-UI-proef.
De eerste volledige meetuitkomst staat in
[`integration_test/results/diarization`](../../integration_test/results/diarization/README.md).
