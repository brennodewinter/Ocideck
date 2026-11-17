# ASR v1: transportbewijs en experimentele backendkwaliteit

Broncode van server/backend/proef: `1c5a9f1bf74b37134d17898c469339ea80bbce9a`.
De JSON bevat daarnaast exacte server-/backendhashes, containerpin, modelhashes,
broncorpushashes, geselecteerde publieke bron-IDs en hashes van alle WAV-fixtures.
De serverinferentie blijft op die broncommit en die componenthashes. De herhaalde
clientproef registreert afzonderlijk de formatter-/proefhash: metadata is nu direct
inspecteerbaar JSON, getoetst tegen privacyredactie. Daarnaast zijn de vereiste
cache-uitsluitingen en een accoladecorrectie toegevoegd; de ASR-uitvoer is niet
gewijzigd en de twaalf backendmetingen zijn niet opnieuw op uitkomst afgestemd.

`client-roundtrip-2026-11-17.json`: echte productie-I/O-transport naar de
loopbackserver, capabilitycontrole en bewuste upload van NL A-B-A. Geleverde tijden,
onzekere clusters en een auteurswijziging (Spreker 1 → Alice) doorstaan documentmodel
→ opslaan → heropenen byte-identiek. Dit is geen volledige geïnstalleerde-app-/UI-
of hardwareproef en vervangt #2947 niet.

`reference-matrix-2026-11-17.json`: 12 echte serververzoeken, allemaal met een
voltooid ASR v1-antwoord. Kleine publieke NL/EN-fragmenten in zes configuraties:
één stem, A-B-A, drie stemmen, overlap, gescheiden stereobronnen na monodownmix,
en eigen synthetische muziek onder één stem. De originele stereo-WAV wordt door de
fixturebouwer behouden; de backend krijgt uitsluitend het afgesproken monoformaat,
geen vermeende persoon per kanaal.

| Configuratie | NL | EN |
| --- | --- | --- |
| Eén stem | 2 clusters, onvoldoende | 1 cluster, correct voor dit fragment |
| A-B-A | 4 clusters, onvoldoende | 2 clusters, terugkeer correct |
| Drie stemmen | 5 clusters, onvoldoende | 3 clusters, correct voor deze fragmenten |
| Overlap / stereo naar mono | geen overlapdetectie | geen overlapdetectie |
| Muziek onder één stem | 2 clusters, onvoldoende | 1 cluster, correct voor dit fragment |

De backend groepeert Vosk-uitingsvectoren met afstand 0,3; die waarde is niet op deze
resultaten aangepast. Iedere toewijzing blijft expliciet onzeker. De Engelse
uitkomst op deze kleine leesfragmenten rechtvaardigt geen algemene kwaliteitsclaim.
**`quality_acceptance` is false: #2935 blijft open.** Succesvolle HTTP-/document-
afhandeling betekent niet dat de stemmen goed onderscheiden zijn.

Er is geen DER-score: de corpora leveren leesstem-IDs, maar geen handmatig
uitgelijnde spraakactiviteit/overlapreferentie. De synthetische bronintervallen
bevatten ook natuurlijke pauzes; die als DER-noemer gebruiken zou een andere
maat als DER presenteren. De gemeten maat is strikte clusterconsistentie per
bekende bronvoorkoming, naast aantal clusters, tijd, tijdvakken en onbekende IDs.

Dit is Linux/amd64 onder Colima-emulatie op een Apple Silicon-host, begrensd tot
2 CPU's en 1 GiB. De tijd en realtimefactor staan per verzoek in de JSON. Het
geheugen is de waargenomen Docker-werkset vóór/na een verzoek, geen piek-RSS en
geen prestatiebelofte voor een releaseplatform.

Herhalen: volg `testbed/asr-diarization/README.md`. Audiobestanden/modellen blijven
in expliciete lokale caches; de repository bevat alleen broncode en meetgegevens.
MLS (Facebook/Meta, revision 2e83e61823b4c47dcbcb1980bb88601274127609) en LibriSpeech
(OpenSLR 12; Vassil Panayotov en Daniel Povey, afgeleid van LibriVox) zijn CC-BY-4.0.
De JSON verwijst naar hun primaire bron en registreert de geselecteerde fragmenten.
