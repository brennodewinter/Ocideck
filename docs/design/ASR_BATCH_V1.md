# Optionele batchdiarisatie — OciDeck ASR v1

Status: clientadapter voor #2935; kwaliteitsacceptatie van een diarisatiebackend
staat afzonderlijk open. Gewone whisper.cpp-servers behouden `/inference` en
krijgen geen onbekende diarisatievelden. Niets wordt automatisch geïnstalleerd,
geüpload of van een lokale engine naar een server doorgeschakeld.

Kies onder Instellingen → Transcriptie → Eigen ASR-server expliciet het
serverprotocol **OciDeck ASR v1**. Kies de serverklasse en bevestig de bestemming
zoals bij andere ASR-profielen. API-sleutels blijven in de bestaande sleutelbos,
nooit in profiel-JSON of document. Het audioverzoek gebruikt dezelfde
NetGuard-/TLS-/CORS-regels en toestemming voor precies dit bestand en deze host.

## Capabilitycontrole zonder audio

`GET <basis-URL>/ocideck-asr/v1/capabilities`, antwoord maximaal 64 KiB:

```json
{"protocol":"ocideck-asr","version":1,"languages":["nl","en"],"features":{"timestamps":true,"diarization":true,"language_detection":false}}
```

Alleen een expliciete, geldige capability toont **Sprekers onderscheiden** in de
bestandsdialoog. Een onbekende versie of kapot antwoord biedt geen labels aan.
Iedere transcriptietaak controleert opnieuw vóór het lezen/versturen van audio;
een verdwenen capability leidt tot een fout in plaats van stil verlies van de
keuze. `languages` bevat alleen werkelijk ondersteunde BCP-47-taalcodes. De
referentiebackend vereist een expliciete taal en weigert automatische detectie.
Alleen `features.language_detection: true` biedt de automatische taalkeuze aan;
ontbrekend of `false` vereist een van de geadverteerde talen. Een rechtstreekse
taak zonder zo'n taal wordt vóór audiolezen/upload geweigerd.

## Transcriptieverzoek

`POST <basis-URL>/ocideck-asr/v1/transcribe`, multipart met:

- `file`: genormaliseerde mono 16 kHz PCM16 WAV, vaste naam `audio.wav`;
- `response_format`: `verbose_json`;
- `language`: optioneel de expliciet gekozen taal;
- `diarize`: altijd expliciet `true` of `false`.

Geen lokaal bronpad in de multipartheaders. De bestaande clientlimiet is 400 MiB;
een server mag eerder weigeren. Geen automatische retry. Annuleren stopt ook de
capabilitycontrole en voorbereiding vóór de upload. Afbreken van HTTP garandeert
niet dat een externe server zijn rekentaak stopt: een server moet daarvoor zelf
verbindingsverlies of een eigen begrensde werkqueue afhandelen.

```json
{"protocol":"ocideck-asr","version":1,"diarization_applied":true,"segments":[
 {"text":"Eerste beurt.","start":0.2,"end":2.1,"speaker_ids":["cluster-a"],"speaker_uncertain":false},
 {"text":"Andere stem.","start":2.2,"end":4.4,"speaker_ids":["cluster-b"],"speaker_uncertain":false},
 {"text":"Ik ben terug.","start":4.5,"end":6.8,"speaker_ids":["cluster-a"],"speaker_uncertain":false},
 {"text":"Niet zeker.","start":6.9,"end":7.2,"speaker_ids":[],"speaker_uncertain":true},
 {"text":"Tegelijk.","start":7.3,"end":8.4,"speaker_ids":["cluster-a","cluster-b"],"speaker_uncertain":true}
]}
```

Tijden zijn eindige, niet-negatieve seconden vanaf het opnamebegin. Segmenten
staan op starttijd; `end >= start`; bij diarisatie zijn beide verplicht. IDs zijn
opnamegebonden clusters, maximaal 64 ASCII-tekens (`A-Z a-z 0-9 _ . -`, eerste
teken alfanumeriek), maximaal acht unieke IDs per segment. Leeg betekent onbekend,
meerdere betekent overlap; het zijn **geen** geïdentificeerde personen. Houd
terugkerende stemmen bij hetzelfde ID. `diarization_applied` moet exact de
gevraagde keuze bevestigen. Zonder diarisatie negeert de client alle sprekerdata.

De backend is verantwoordelijk voor uitlijning: splits tekst alleen op echte
ASR-woordgrenzen waar woordtijden bestaan. Als een segment meerdere beurten omvat
zonder onderbouwde woordgrens, verzin geen tijd of tekstdeling; retourneer de
betrokken IDs met `speaker_uncertain: true`, of onbekend. De client neemt geen
woordtijden aan die niet geleverd zijn en kan backendkwaliteit niet uit een
capabilityvlag afleiden.

## Bewerkbaar document

Het eerste voorkomende cluster krijgt Spreker 1, het volgende Spreker 2; A-B-A
blijft 1-2-1. Zichtbare labels zijn gelokaliseerd en gewone Markdown: verander
bijvoorbeeld Spreker 1 in Alice. `(?)` markeert onzekerheid, `+` overlap.

De initiële segmentindex, ruwe start/eindtijd in microseconden, IDs en onzekerheid
blijven in een `ocideck:segments:v1`-HTML-commentaar als onversleuteld JSON behouden.
Dit is direct inspecteerbare documentinhoud. IDs blijven platte tekst zodat de
bestaande privacyscanner en redactie ze ook in metadata kunnen beoordelen; alleen
HTML-commentaartekens worden veilig ge-escaped. Het is de oorspronkelijke
engine-uitvoer, geen automatisch bijgewerkte koppeling na handmatige tekstwijziging;
bij hergebruik moet een exporteur gewijzigde tekst opnieuw laten beoordelen.
Stemvectoren, biometriemodellen en identiteitsprofielen horen nooit in het antwoord
of document. Een nieuwe pass blijft onder de bestaande provenance/bodygrens en
overschrijft geen auteurswijzigingen zonder de bestaande bevestiging.

## Referentieproef en beperking

Zie `testbed/asr-diarization/README.md`. De kleine Vosk-proef detecteert geen
overlap en kan één stem opsplitsen in meerdere clusters. Zij markeert daarom elke
toewijzing als onzeker en is geen aanbevolen productiebackend. Een betrouwbare
NL/EN-diari­satieroute blijft afhankelijk van gemeten kwaliteit van de gekozen
backend; deze clientadapter rechtvaardigt op zichzelf geen kwaliteitsclaim of
sluiting van #2935.

## Optionele taalwisselingen (#2940)

`features.language_switching: true` biedt naast vaste taal en automatische
opnametaal de expliciete keuze **Meerdere talen in deze opname**. Ontbrekend of
false betekent niet ondersteund; meertalige gewichten alleen zijn onvoldoende.
De client controleert opnieuw vóór audiolezen/upload. Alleen in deze modus
stuurt hij multipart `language_mode=mixed`, zonder `language`. Een gewone
whisper.cpp-server krijgt dit veld nooit. De server moet
`language_switching_applied: true` teruggeven; zonder de modus moet dit false
of afwezig zijn. Een mismatch weigert het resultaat, zonder stille fallback.

Segmenten mogen `language` (BCP-47 of `mixed`) en `language_uncertain` (bool)
bevatten. Ontbrekende taal is onbekend; een tag zonder onzekerheidsvlag wordt
voorzichtig als onzeker gelezen. Een tag beschrijft wat de engine onderbouwt,
geen geconstrueerd percentage. Zichtbaar verschijnt bijvoorbeeld `[en?]`;
de oorspronkelijke taal/onzekerheid en tijden blijven in de bestaande
segmentmetadata behouden. Zichtbare tekst/tags blijven bewerkbaar.

Lokale CLI/WASM biedt deze capability niet en weigert een expliciete aanvraag;
bij werkelijk geleverde eindtijden bewaart de client die nu ook voor gewone
transcripties. De experimentele CPU-loopbackbackend in
`testbed/asr-multilingual/README.md` herdetecteert per echte VAD-spraakregio,
zet vertalen uit en herstelt de oorspronkelijke sampleoffsets. Dat verbetert
lange latere taalblokken in de gemeten fixtures, maar korte codewisseling
binnen een regio kan verslechteren. De kwaliteitsacceptatie van #2940 blijft
apart van de geslaagde client-/transportimplementatie.

De afzonderlijke native Nemotron/Whisper-referentiebackend en zijn gemeten
onbekende toewijzingen staan in `testbed/asr-diarization/NEMO_README.md`. Hij
combineert echte modelactiviteit met echte ASR-woordtijden; tekst die niet exact
naar die woorden terugleidt blijft één ongewijzigd onbekend segment. De
diari­satiekeuze uit schakelt de native taak geheel uit. Deze operatorroute
introduceert geen nieuwe velden of automatische installatie in de app.
