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
