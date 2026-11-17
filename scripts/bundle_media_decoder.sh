#!/usr/bin/env bash
# Bundle the decoder and its complete corresponding source, then reseal app.
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
"$ROOT_DIR/scripts/build_media_decoder.sh"
case "$(uname -m)" in
  arm64|aarch64) TARGET_ARCH=arm64 ;;
  *) TARGET_ARCH=x64 ;;
esac
APP=${1:-}
if [[ -z "$APP" ]]; then
  APP=$(find build/macos/Build/Products/Release -maxdepth 1 -type d -name '*.app' -print -quit)
fi
[[ -d "$APP/Contents" ]] || { echo 'No macOS app bundle found.' >&2; exit 1; }
SOURCE="native/media_decoder/bin/macos-$TARGET_ARCH"
NOTICE_DIR="$APP/Contents/Resources/ffmpeg"
mkdir -p "$APP/Contents/Helpers" "$NOTICE_DIR"
install -m 0755 "$SOURCE/ffmpeg" "$APP/Contents/Helpers/ffmpeg"
VERSION=$(python3 -c 'import json; print(json.load(open("native/media_decoder/manifest.json"))["version"])')
install -m 0644 "native/media_decoder/build/ffmpeg-$VERSION.tar.xz" "$NOTICE_DIR/ffmpeg-$VERSION.tar.xz"
for source in native/media_decoder/manifest.json native/media_decoder/README.md assets/licenses/ffmpeg-LGPL-2.1.txt scripts/build_media_decoder.sh "$SOURCE/compiler.txt" "$SOURCE/version.txt" "$SOURCE/license.txt" "$SOURCE/binary.sha256"; do
  install -m 0644 "$source" "$NOTICE_DIR/$(basename "$source")"
done
codesign --force --options runtime -s - "$APP/Contents/Helpers/ffmpeg"
codesign --force --sign - --preserve-metadata=entitlements,requirements,flags,runtime "$APP"
codesign --verify --deep --strict "$APP"
echo "Decoder, corresponding source and replacement instructions → $APP"
