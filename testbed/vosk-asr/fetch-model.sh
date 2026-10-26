#!/bin/sh
# Haalt het gepinde kleine Vosk-model op voor de live-ASR-testbed.
# Zelfde vorm als de whisper-modelpinning: versie én SHA-256 vast.
set -eu
cd "$(dirname "$0")"

MODEL=vosk-model-small-en-us-0.15
SHA256=30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498
URL="https://alphacephei.com/vosk/models/$MODEL.zip"

if [ -d "model/$MODEL" ]; then
  echo "model/$MODEL is er al"
  exit 0
fi

mkdir -p model
curl -fsSL "$URL" -o "model/$MODEL.zip"
echo "$SHA256  model/$MODEL.zip" | shasum -a 256 -c -
unzip -q "model/$MODEL.zip" -d model
rm "model/$MODEL.zip"
echo "model/$MODEL klaar"
