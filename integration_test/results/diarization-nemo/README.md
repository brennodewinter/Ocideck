# Native diarisatie — afgebakend bewijs voor #2935

Server/worker/woordkoppeling gemeten op `660b57c5e94bf07fdbd5280e830a7f7d44b2472a`. De native bibliotheken zijn opnieuw uit de gepinde bron gebouwd, geïnstalleerd en op bytes/notices/ABI getoetst; de concrete manifesten staan erbij. [Reproductie en installatie](../../../testbed/asr-diarization/NEMO_README.md).

**Twaalf kleine NL/EN-fixtures via echte HTTP, met en zonder diarisatie, slagen voor de vastgelegde bronindeling.** Toegekende IDs zijn per bekende bronstem verschillend en bij terugkeer gelijk; onzekere uitvoer blijft apart geteld. Dit is geen claim dat elk woord een correct label heeft of dat iedere vergadering/accent/overlap wordt opgelost. Alle labels blijven onzeker.

| Fixture | Toegekende indeling | Onbekende uitvoertokens | Tijd met diarisatie | ASR-tekst gelijk aan zonder diarisatie |
|---|---|---:|---:|---|
| nl-single.wav | stabiele bron-IDs | 1/28 | 2.32s | ja |
| nl-aba.wav | stabiele bron-IDs | 28/110 | 6.59s | ja |
| nl-three.wav | stabiele bron-IDs | 3/107 | 6.04s | ja |
| nl-overlap.wav | twee IDs + overlap aanwezig | 1/42 | 2.79s | ja |
| nl-stereo-downmix.wav | twee IDs + overlap aanwezig | 1/42 | 2.89s | ja |
| nl-music.wav | stabiele bron-IDs | 1/28 | 2.24s | ja |
| en-single.wav | stabiele bron-IDs | 0/8 | 1.31s | ja |
| en-aba.wav | stabiele bron-IDs | 1/38 | 2.00s | ja |
| en-three.wav | stabiele bron-IDs | 2/85 | 4.05s | ja |
| en-overlap.wav | twee IDs + overlap aanwezig | 0/14 | 1.34s | ja |
| en-stereo-downmix.wav | twee IDs + overlap aanwezig | 0/14 | 1.34s | ja |
| en-music.wav | stabiele bron-IDs | 0/8 | 1.39s | ja |

Tokens hierboven zijn Unicode-`\w+`-uitvoertokens, geen handgeannoteerde referentiewoorden. Onbekend telt niet als een correcte toewijzing. Het moeilijkste NL A–B–A-geval laat circa 25% onbekend; de ruwe segmenten/IDs/tijden blijven in `http-matrix.json`. De ASR-tekst is in ieder geval exact behouden en uitgeschakelde diarisatie levert geen labels. Bron-/corpushashes en CC-BY-4.0-attributie staan in de opgenomen fixturemanifestgegevens. De muziekcontrole gebruikt synthetische achtergrondtonen bij echte spraak.

**Geen DER:** de bronintervallen bevatten natuurlijke pauzes en zijn geen handmatig uitgelijnde spraak-/overlapreferentie. Het detecteren van meerdere actieve IDs bewijst niet dat ieder gelijktijdig gesproken woord is teruggewonnen.

**Bekende negatieve uitkomsten blijven zichtbaar.** De aparte upstream-CLI met zijn standaard CallHome-drempel mist de tweede stem in NL A–B–A (`upstream-default-cli-nl-aba.json`). De server gebruikt daarom echte modelscores op echte ASR-woordtijden en laat zwak/ambigu onbekend. De lange streamingproef heeft bovendien bij de eerste wissel circa 2,8s modelactiviteit in broninterval B met slot A; latere herhalingen behouden de verwachte slots (`streaming-source-check.json`). De korte volle-aandachtmatrix mag niet als bewijs voor gelijke lange-streamkwaliteit worden gelezen.

De procescontrole van 625,56s gebruikt één streamingcache en retourneert 62557 native 10ms-frames. De herhaalde fixture is geen natuurlijk gesprek. De twee annuleringsproeven observeren echte native kinderen; beëindigen/reapen en tijdelijke-audio-/scoreopruiming slagen, en na de HTTP-disconnect wordt de capaciteit vrijgegeven. Zie de afzonderlijke JSON, inclusief tijdmetingen.

De native productieclient bewijst A–B–A, hernoemen, opslaan en heropenen. Chromium en WebKit bewijzen de echte gecompileerde productieclient/CORS plus documentmodel/naamswijziging; **geen volledige release-UI of browserbestandopslag**. #2947 blijft de bredere release-/hardwarematrix. In de extra gecombineerde NL/EN/NL-proef van één via corpusmetadata gedocumenteerde voorlezer blijven één cluster, beide modusvlaggen en de oorspronkelijke ASR-tekst behouden. Dat is geen algemene identiteits- of meertalige kwaliteitsgarantie.

Losse native CPU-workerpieken: maximaal 249.9MiB op de korte fixtures, 346.4MiB op de lange procescontrole. Dit zijn geen gecombineerde pieken met ASR-server/app. Server-RSS-snapshots: vóór 305.9MiB, na 951.6MiB; ook dat zijn geen pieken. De OS-resource-uitvoer van de gehele servercommando’s staat apart. Tijden zijn waarnemingen op deze gedeelde ontwikkelmachine, geen gecontroleerde vergelijking van verschillende engines.

De native runtime is Apache-2.0, met afzonderlijke ggml/SentencePiece-notices; het model is OpenMDW-1.1, de Whisper-conversie MIT. Concrete native bibliotheken, modelrevisies, oorspronkelijke noticehashes, buildflags/compiler/SDK en Python-wheelinventaris zijn vastgelegd. Dit zijn operatorinstallaties buiten OciDeck-bundles/SBOM; deze gegevens zijn geen blanket-goedkeuring voor toekomstige helperdistributie.

De gecomprimeerde activiteit van uitsluitend deze openbare lange proef staat in
`streaming-activity.npz` (NumPy, allow_pickle=False); het herhaalde bronbestand
zelf blijft buiten de repository. `nemo_streaming_source_probe.py` reproduceert
de behouden diagnostische tellingen. Operationele serveraanvragen bewaren zulke
activiteit of audio niet blijvend.
