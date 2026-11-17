# Gemeten taalwisselingen — #2940

Engine/backendcode: `dd41eda4bf38b470c3a519d3b1d137be8338e93c`. Ruwe JSON bevat referenties, hypotheses, woordtijden, segmenten en model-/fixturehashes. Model- en bronattributie: [testbedREADME](../../../testbed/asr-multilingual/README.md).

**Kwaliteitsacceptatie: niet behaald.** Lange latere Engelse blokken verbeteren; korte citaten kunnen verslechteren. Dezelfde voorlezer in beide talen is met corpusmetadata onderbouwd, maar de opname is synthetisch samengesteld. Natuurlijke codewisseling binnen een zin en representatieve muziek ontbreken. CLI/WASM biedt de nieuwe modus niet aan; backendkwaliteit op Windows/Linux/Intel is niet gemeten.

WER hieronder: één-pass → herdetectie per spraakregio. Lager is beter;1.0 betekent 100% fouten volgens woordeditafstand, waarden boven 1 zijn mogelijk. Geen algemene kwaliteitsclaim.

| Model | Fixture | Engels WER | NL/PL WER |
|---|---|---|---|
| base | nl-en-nl.wav | 1.000 → 0.036 | 0.431 → 0.255 |
| base | pl-en.wav | 1.000 → 0.036 | 0.200 → 0.235 |
| base | same-reader-nl-en-nl.wav | 0.709 → 0.206 | 0.288 → 0.385 |
| base | same-reader-short-quote.wav | 0.143 → 0.286 | 0.288 → 0.375 |
| small | nl-en-nl.wav | 1.000 → 0.036 | 0.176 → 0.157 |
| small | pl-en.wav | 1.571 → 0.036 | 0.113 → 0.096 |
| small | same-reader-nl-en-nl.wav | 0.479 → 0.109 | 0.202 → 0.192 |
| small | same-reader-short-quote.wav | 0.286 → 0.429 | 0.183 → 0.192 |
| large-v3-turbo | nl-en-nl.wav | 1.000 → 0.000 | 0.078 → 0.069 |
| large-v3-turbo | pl-en.wav | 0.054 → 0.000 | 0.009 → 0.017 |
| large-v3-turbo | same-reader-nl-en-nl.wav | 0.018 → 0.018 | 0.077 → 0.087 |
| large-v3-turbo | same-reader-short-quote.wav | 0.286 → 0.000 | 0.115 → 0.077 |

De stille en synthetische akkoordcontroles leveren in alle drie spraakregiomodi geen tekst; alle drie één-passmodi hallucineren daar tekst. Dat akkoord vervangt geen muziekproef. Alle gemeten segmenten staan op oorspronkelijke starttijd met niet-negatieve, geldige eindtijden. Dit bewijst geen woord-perfecte uitlijning of afwezigheid van alle gemiste/dubbele woorden.

| Model | Cumulatieve procespiek MiB | Som transcriptietijd één-pass / spraakregio’s (zes fixtures) |
|---|---|---|
| base | 648.0 | 42.9s / 46.1s |
| small | 978.7 | 135.2s / 166.5s |
| large-v3-turbo | 1971.6 | 120.2s / 350.0s |

Native macOS arm64, CPU/int8, vier threads; één proces per model. RSS is een cumulatieve procespiek, geen geheugendelta per geval. De machine draaide ook andere tests: tijden zijn observaties onder wisselende belasting, geen gecontroleerde snelheidsvergelijking.

De bestaande, werkelijk gebundelde whisper.cpp 1.9.5/base-route draaide met de productieargumenten (`-l auto`, `translate=false`): NL→EN→NL 1.99s/402522112bytes maximale RSS, PL→EN 2.29s/454852608bytes. In beide ruwe JSON-uitkomsten ontbreekt de Engelse tekst. Zonder woorduitlijning geven we hiervoor geen per-taal-WER. Metal/ggml-f16 versus CPU/int8 verhindert een causale snelheidsvergelijking tussen engines.

De echte native productieclient slaagt voor upload, metadata, bewerken, opslaan en heropenen. Gecompileerde productie-webclient/CORS/documentmodel slaagt in de versies uit browser-result.json (Chromium en WebKit). Het is geen volledige release-UI-/browserbestandopslagproef; die matrix blijft #2947. De TLS-annuleringsproef verbreekt na twee seconden een bezette modeltaak en meet vrijgave bij de volgende controlegrens; zij bewijst geen onderbreking midden in een native decoderstap.

Concrete operatorvenvlicenties/FFmpeg-bouwflags en ingebedde bibliotheekhashes staan in operator-runtime-license.json. Geen van deze artefacten wordt met OciDeck gedistribueerd. De oorspronkelijke corpusbestanden blijven buiten de repository; de teksten/hashes zijn behouden met CC-BY-4.0-/LibriVox-/Gutenberg-attributie in de testbedREADME. fixture-reproduction.json toont de gemeten Opus-herdecodeerverschillen tot één PCM16-LSB.
