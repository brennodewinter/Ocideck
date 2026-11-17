#!/usr/bin/env bash
# Rebuild the standalone macOS decoder from pinned, unmodified LGPL sources.
# Full sources, configure flags and replacement instructions ship with the app.
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
[[ $(uname -s) == Darwin ]] || { echo 'The extra decoder is macOS-only.' >&2; exit 2; }
case "$(uname -m)" in
  arm64|aarch64) TARGET_ARCH=arm64 ;;
  x86_64) TARGET_ARCH=x64 ;;
  *) echo 'Unsupported decoder architecture.' >&2; exit 2 ;;
esac
for required_tool in python3 curl tar make clang shasum; do
  command -v "$required_tool" >/dev/null || { echo "Missing build tool: $required_tool" >&2; exit 127; }
done
MANIFEST=native/media_decoder/manifest.json
WORK_DIR=native/media_decoder/build
DEST_DIR="native/media_decoder/bin/macos-$TARGET_ARCH"
mkdir -p "$WORK_DIR" "$DEST_DIR"
readarray_compat() {
  # macOS ships Bash 3.2, which has no mapfile/readarray.
  while IFS= read -r line; do CONFIGURE_FLAGS+=("$line"); done
}
VERSION=$(python3 -c 'import json; print(json.load(open("native/media_decoder/manifest.json"))["version"])')
URL=$(python3 -c 'import json; print(json.load(open("native/media_decoder/manifest.json"))["tarball"])')
EXPECTED=$(python3 -c 'import json; print(json.load(open("native/media_decoder/manifest.json"))["tarballSha256"])')
BUILD_INPUT_HASH=$(shasum -a 256 "$MANIFEST" scripts/build_media_decoder.sh | shasum -a 256 | awk '{print $1}')
if [[ -x "$DEST_DIR/ffmpeg" && -f "$DEST_DIR/inputs.sha256" ]] &&
   [[ $(cat "$DEST_DIR/inputs.sha256") == "$BUILD_INPUT_HASH" ]]; then
  echo "Pinned media decoder already built: $DEST_DIR/ffmpeg"
  exit 0
fi
TARBALL="$WORK_DIR/ffmpeg-$VERSION.tar.xz"
if [[ ! -f "$TARBALL" ]]; then
  curl --fail --location --proto '=https' --tlsv1.2 "$URL" -o "$TARBALL.part"
  mv "$TARBALL.part" "$TARBALL"
fi
ACTUAL=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo 'Decoder source SHA-256 mismatch.' >&2; exit 1; }
SOURCE_DIR="$WORK_DIR/ffmpeg-$VERSION"
if [[ -d "$SOURCE_DIR" ]]; then rm -rf "$SOURCE_DIR"; fi
tar -xf "$TARBALL" -C "$WORK_DIR"
BUILD_DIR="$ROOT_DIR/$WORK_DIR/macos-$TARGET_ARCH"
# FFmpeg does not reliably rebuild every object when only compiler flags change.
# Start clean whenever the manifest or recipe invalidated the output cache.
if [[ -d "$BUILD_DIR" ]]; then rm -rf "$BUILD_DIR"; fi
mkdir -p "$BUILD_DIR"
CONFIGURE_FLAGS=()
readarray_compat < <(python3 -c 'import json; print("\n".join(json.load(open("native/media_decoder/manifest.json"))["configureFlags"]))')
(
  cd "$BUILD_DIR"
  unset CC CXX CFLAGS CPPFLAGS CXXFLAGS LDFLAGS LIBS
  "$ROOT_DIR/$SOURCE_DIR/configure" "${CONFIGURE_FLAGS[@]}" --prefix="$BUILD_DIR/install"
  make -j"${FFMPEG_BUILD_JOBS:-8}" ffmpeg
)
install -m 0755 "$BUILD_DIR/ffmpeg" "$DEST_DIR/ffmpeg"
/usr/bin/clang --version > "$DEST_DIR/compiler.txt"
"$DEST_DIR/ffmpeg" -hide_banner -version > "$DEST_DIR/version.txt"
"$DEST_DIR/ffmpeg" -hide_banner -L > "$DEST_DIR/license.txt"
grep -q 'GNU Lesser General Public' "$DEST_DIR/license.txt"
grep -q 'version 2.1' "$DEST_DIR/license.txt"
if otool -L "$DEST_DIR/ffmpeg" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/System/Library/|/usr/lib/)' >/dev/null; then
  echo 'Decoder unexpectedly links a non-system library.' >&2
  exit 1
fi
printf '%s\n' "$BUILD_INPUT_HASH" > "$DEST_DIR/inputs.sha256"
shasum -a 256 "$DEST_DIR/ffmpeg" | awk '{print $1 "  ffmpeg"}' > "$DEST_DIR/binary.sha256"
echo "Built pinned LGPL media decoder: $DEST_DIR/ffmpeg"
