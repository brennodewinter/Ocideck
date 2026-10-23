# WASM-engine probe — meten, niet geloven (#2513)

Deze map is de reproduceerbare meetopstelling waarmee de web-transcriptieroute
is bewezen, vóórdat er één regel Dart aan is geschreven. Zie
`docs/design/TRANSCRIPTION.md` §4.6 voor de volledige tabel en conclusies.

## Wat hier staat

- `probe.html` — de ruwe proef: laadt `libmain.js` direct, voedt een model en
  een WAV, meet laad-/inferentietijd, piekgeheugen en netwerkverkeer, en POST
  het resultaat terug naar de server.
- `probe-bridge.html` — dezelfde meting maar door de *echte* shipped shim
  `web/whisper/bridge.js` (`window.ocideckWhisper`), inclusief `cancelMs=` voor
  een annuleerproef.
- `server.py` — een minimale server: serveert een map (`--root`), zet
  optioneel COOP/COEP (`--coi`), verzamelt `POST /result` en logt elke
  request (de netwerk-log is het bewijs dat audio nooit weggaat).
- `results/` — ruwe meetbestanden per browser en model/audio-combinatie,
  `bridge-*` is de shipped-shim-route.

## Opnieuw draaien

```sh
# 1. Build de wasm-artifacten (docker, gepinde toolchain):
docker run --rm -v "$PWD/../../whisper_cli/build/whisper.cpp-1.9.5":/src -w /src \
  emscripten/emsdk:3.1.74 \
  sh -c 'cd examples/whisper.wasm && patch -p0 < /src/../../whisper_wasm/emscripten-cancel.patch 2>/dev/null; emcmake cmake -B build-wasm -DWHISPER_WASM_SINGLE_FILE=OFF ... && cmake --build build-wasm'
#    (of gebruik de bestaande build-boom onder native/whisper_cli/build/)

# 2. Stage een proefmap met de artifacten + testaudio + modellen:
mkdir -p /tmp/wasm-harness && cd /tmp/wasm-harness
ln -s <repo>/native/whisper_wasm/probe/probe.html .
ln -s <repo>/native/whisper_wasm/probe/probe-bridge.html .
mkdir -p whisper && ln -s <repo>/web/whisper/* whisper/
#    + ggml-*.bin modellen en *.wav testaudio

# 3. Server mét cross-origin isolatie (zoals .htaccess het doet):
python3 <repo>/native/whisper_wasm/probe/server.py --coi --root /tmp/wasm-harness

# 4. Open in de te meten browser:
#    http://127.0.0.1:8931/probe-bridge.html?model=ggml-base.bin&audio=vlot.wav
#    Zonder --coi (tweede instantie op --port 8932) meet je de weigerroute.
```

`results/` laat per bestand zien: `sab`/`isocross` (had de context
SharedArrayBuffer), `supported` (wat de bridge rapporteert), `inferMs`/`rtf`
(realtimelactor), `memMB` (JS-heap), `cancelled` en `errors`. `net` in elk
resultaat is de volledige requestlijst van de pagina — alles same-origin.

## Waarom de grenzen zijn wat ze zijn

- `*-nocoi-*` en `nocoi-abort.json`: zonder COOP/COEP is `SharedArrayBuffer`
  er niet; de module abort zichtbaar en `isSupported()` meldt `false`.
- `turbo-init-abort.json`: `large-v3-turbo` (1,5 GiB) overlijdt in `Module.init`
  — het 2 GB-WASM-adresplafond. Daarom draagt die rij `webCapable: false`.
- `bridge-chrome-tiny-lang-cancel.json`: `requestCancel` om t=3 s stopte een
  212 s-run op 4,4 s met `cancelled: true` — de abort_callback-route werkt.
