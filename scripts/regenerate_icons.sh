#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Snijdt élke app-icoonset opnieuw uit één master.
#
# Dit script bestaat omdat het handwerk erdoorheen glipte. De rebrand van juni
# heeft macOS en web opnieuw gegenereerd en Linux en Windows vergeten; die twee
# droegen daarna een maand het vorige logo, en niets werd rood. Zes sets met de
# hand bijhouden is de fout die daarna nog een keer gemaakt wordt. Eén script
# dat ze alle zes doet, is dat niet.
#
# De master is macos/…/app_icon_1024.png, niet assets/images/ocideck-logo.png.
# Dat laatste is het logo *in* de app, 512 pixels, met een ruimere marge; de
# master is 1024 en draagt ruim drie keer zoveel randdetail (randafwijking 0,22
# tegen 0,08 na opschalen). Elk app-icoon hieronder is dus een verkleining,
# nooit een vergroting — dat verschil zie je terug in het 1024-icoon dat Apple
# in de App Store toont. Alleen de webiconen komen uit het logo; zie daar.
#
# Dat de macOS-set hieruit bit-voor-bit terugkomt zoals hij in de repo staat, is
# het bewijs dat dit hetzelfde recept is als waarmee hij ooit gesneden is, en
# niet een nieuw recept dat er toevallig op lijkt.
#
# De inkadering (bijsnijden, schalen tot 87,7% van de canvashoogte, centreren op
# wit) zit al ín de master; opnieuw inkaderen zou alleen een extra
# herbemonstering kosten. Wie de master zelf vervangt, moet die regel dus
# aanhouden — test/platform_icon_branding_test.dart toetst achteraf of elk doel
# nog dezelfde tekening draagt.
#
# Ondoorzichtig wit, geen transparantie: het merk is donkere inkt en verdwijnt
# op een donkere taakbalk zonder de witte plaat eronder. Voor iOS is dat geen
# smaak maar een eis — Apple weigert een icoon met alfakanaal — en daar wordt
# het kleurtype daarom hard afgedwongen; zie cut_zonder_alfa.

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 127
  fi
}

section() {
  printf '\n== %s ==\n' "$1"
}

require_cmd magick

MASTER="macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
[[ -f "$MASTER" ]] || { echo "Master ontbreekt: $MASTER" >&2; exit 1; }

# Eén formaat uit de master snijden.
cut() {
  local size="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  magick "$MASTER" -alpha off -resize "${size}x${size}" -strip "$out"
  echo "  ${size}px  $out"
}

# Idem, met het kleurtype hard vastgelegd. `-alpha off` levert hier al een PNG
# zonder alfakanaal op, dus dit verándert niets aan de uitvoer; het legt vast
# dat het zo hoort te blijven. Apple weigert een icoon met transparantie, en dat
# is te veel gedoe om af te laten hangen van wat ImageMagick per maat besluit.
cut_zonder_alfa() {
  local size="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  magick "$MASTER" -alpha off -resize "${size}x${size}" -strip \
    -define png:color-type=2 "$out"
  echo "  ${size}px  $out"
}

section "macOS ($MASTER is zelf de 1024)"
for size in 512 256 128 64 32 16; do
  cut "$size" "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_${size}.png"
done

section "Windows"
# Zeven maten in één .ico; laat Windows niet zelf verkleinen, dat leest slechter
# in de taakbalk dan een eigen 16 en 24.
magick "$MASTER" -alpha off -define icon:auto-resize=256,128,64,48,32,24,16 \
  windows/runner/resources/app_icon.ico
echo "  16–256  windows/runner/resources/app_icon.ico"

section "Linux"
cut 512 linux/runner/resources/app_icon.png

section "web"
# Het web volgt bewust een ándere bron: assets/images/ocideck-logo.png, recht
# verkleind, zonder de krappere inkadering van de app-iconen. Een favicon staat
# op een tabblad naast andere favicons en niet in een dock, en de ruimere marge
# leest daar rustiger. Dat is geen vergissing uit het verleden — het is
# nagemeten (de gecommitte set komt op 0,3 tot 1,9% na uit dit recept) en
# daarom hier vastgelegd in plaats van rechtgetrokken.
WEB_SOURCE="assets/images/ocideck-logo.png"
for size in 512 192; do
  magick "$WEB_SOURCE" -resize "${size}x${size}" -strip "web/icons/Icon-${size}.png"
  echo "  ${size}px  web/icons/Icon-${size}.png"
done
magick "$WEB_SOURCE" -resize 64x64 -strip web/favicon.png
echo "  64px  web/favicon.png"
# De maskable-varianten zetten de tekening op 80% in een wit vlak, zodat een
# platform dat er een cirkel uit knipt niets van de kat afsnijdt.
for size in 512 192; do
  magick "$WEB_SOURCE" -alpha off -resize "$((size * 8 / 10))x$((size * 8 / 10))" \
    -background white -gravity center -extent "${size}x${size}" -strip \
    "web/icons/Icon-maskable-${size}.png"
  echo "  ${size}px  web/icons/Icon-maskable-${size}.png (veilige zone)"
done

section "iOS"
IOS_DIR="ios/Runner/Assets.xcassets/AppIcon.appiconset"
# Naam → pixels, precies zoals Contents.json ze opvraagt.
cut_zonder_alfa 1024 "$IOS_DIR/Icon-App-1024x1024@1x.png"
cut_zonder_alfa 20 "$IOS_DIR/Icon-App-20x20@1x.png"
cut_zonder_alfa 40 "$IOS_DIR/Icon-App-20x20@2x.png"
cut_zonder_alfa 60 "$IOS_DIR/Icon-App-20x20@3x.png"
cut_zonder_alfa 29 "$IOS_DIR/Icon-App-29x29@1x.png"
cut_zonder_alfa 58 "$IOS_DIR/Icon-App-29x29@2x.png"
cut_zonder_alfa 87 "$IOS_DIR/Icon-App-29x29@3x.png"
cut_zonder_alfa 40 "$IOS_DIR/Icon-App-40x40@1x.png"
cut_zonder_alfa 80 "$IOS_DIR/Icon-App-40x40@2x.png"
cut_zonder_alfa 120 "$IOS_DIR/Icon-App-40x40@3x.png"
cut_zonder_alfa 120 "$IOS_DIR/Icon-App-60x60@2x.png"
cut_zonder_alfa 180 "$IOS_DIR/Icon-App-60x60@3x.png"
cut_zonder_alfa 76 "$IOS_DIR/Icon-App-76x76@1x.png"
cut_zonder_alfa 152 "$IOS_DIR/Icon-App-76x76@2x.png"
cut_zonder_alfa 167 "$IOS_DIR/Icon-App-83.5x83.5@2x.png"

section "Android"
cut 48 android/app/src/main/res/mipmap-mdpi/ic_launcher.png
cut 72 android/app/src/main/res/mipmap-hdpi/ic_launcher.png
cut 96 android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
cut 144 android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
cut 192 android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png

section "Klaar"
echo "Draai nu 'flutter test test/platform_icon_branding_test.dart' en bekijk"
echo "de kleine maten met eigen ogen — 16 en 24 pixels vergeven weinig."
