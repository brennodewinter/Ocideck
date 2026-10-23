#!/usr/bin/env bash
# Bouwt de whisper-cli-helper voor de lokale transcriptie-engine (#2512).
#
# De runtime komt uit een gepinde upstream-source-tarball die op SHA-256
# wordt getoetst — zie native/whisper_cli/manifest.json. Er wordt nooit een
# binair artefact van een derde gedownload: het contract staat alleen
# gepinde bron plus lokale compilatie toe.
#
# Gebruik:
#   scripts/build_whisper_cli.sh            # bouwt voor dit platform
#
# Uitvoer:
#   native/whisper_cli/bin/<platform>-<arch>/whisper-cli[.exe]
#
# Vereisten: cmake, een C++17-compiler, curl, shasum (macOS) of sha256sum.
# Op Windows draait dit in dezelfde Git-Bash/MSYS2-schil als
# `make build-windows`; daar is `cmake -A x64` de generator.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MANIFEST="native/whisper_cli/manifest.json"
OUT_DIR="native/whisper_cli/bin"
WORK_DIR="native/whisper_cli/build"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 127
  fi
}

require_cmd cmake
require_cmd curl

# Manifestvelden zonder json-afhankelijkheid: het bestand is klein en vlak.
field() { sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$MANIFEST" | head -1; }

VERSION="$(field version)"
TARBALL_URL="$(field tarball)"
TARBALL_SHA="$(field tarballSha256)"
if [[ -z "$VERSION" || -z "$TARBALL_URL" || -z "$TARBALL_SHA" ]]; then
  echo "manifest.json mist version/tarball/tarballSha256" >&2
  exit 2
fi

# Platform/architectuur: de uitvoer mapnaam die de engine en de
# bundelscripts kennen.
case "$(uname -s)" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
  *) echo "Onbekend platform: $(uname -s)" >&2; exit 2 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|AMD64)  ARCH="x64" ;;
  *) echo "Onbekende architectuur: $(uname -m)" >&2; exit 2 ;;
esac

# Windows heeft geen uname-arch onderscheid in MSYS; de doelarchitectuur
# staat in het manifest-contract (x64) en in de naam van dit script-
# contract. AMD64 → x64.

DEST_DIR="$OUT_DIR/$PLATFORM-$ARCH"
BINARY_NAME="whisper-cli"
[[ "$PLATFORM" == "windows" ]] && BINARY_NAME="whisper-cli.exe"

if [[ -x "$DEST_DIR/$BINARY_NAME" ]]; then
  echo "whisper-cli voor $PLATFORM-$ARCH is al gebouwd ($DEST_DIR/$BINARY_NAME)"
  exit 0
fi

mkdir -p "$WORK_DIR" "$DEST_DIR"
TARBALL="$WORK_DIR/whisper.cpp-$VERSION.tar.gz"
SRC_DIR="$WORK_DIR/whisper.cpp-$VERSION"
BUILD_DIR="$WORK_DIR/build-$PLATFORM-$ARCH"

if [[ ! -f "$TARBALL" ]]; then
  echo "Ophalen: $TARBALL_URL"
  curl -fsSL -o "$TARBALL" "$TARBALL_URL"
fi

echo "$TARBALL_SHA  $TARBALL" | shasum -a 256 -c - 2>/dev/null \
  || echo "$TARBALL_SHA  $TARBALL" | sha256sum -c -

if [[ ! -d "$SRC_DIR" ]]; then
  tar -xzf "$TARBALL" -C "$WORK_DIR"
fi

# Statisch: één binair artefact, geen ggml-*.dylib/.dll mee te slepen.
# GGML_NATIVE=OFF op niet-macOS zodat de instructieset-basislijn van de
# distributie klopt; op macOS dekt Metal het zware werk en is arm64 uniform
# genoeg (de releasebundel is universeel → beide architecturen gebouwd).
CMAKE_ARGS=(
  -B "$BUILD_DIR"
  -S "$SRC_DIR"
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DWHISPER_BUILD_TESTS=OFF
  -DWHISPER_BUILD_EXAMPLES=ON
)
if [[ "$PLATFORM" == "macos" ]]; then
  CMAKE_ARGS+=(
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
    -DGGML_NATIVE=OFF
  )
else
  CMAKE_ARGS+=(-DGGML_NATIVE=OFF)
fi

cmake "${CMAKE_ARGS[@]}"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
cmake --build "$BUILD_DIR" --config Release --target whisper-cli -j"$JOBS"

# De binary verschijnt onder build/bin/; bij multi-config generators
# (Windows/MSVC) onder build/bin/Release/.
BUILT="$BUILD_DIR/bin/$BINARY_NAME"
[[ -f "$BUILD_DIR/bin/Release/$BINARY_NAME" ]] && BUILT="$BUILD_DIR/bin/Release/$BINARY_NAME"
if [[ ! -f "$BUILT" ]]; then
  echo "build leverde geen $BINARY_NAME op onder $BUILD_DIR/bin" >&2
  exit 1
fi
install -m 0755 "$BUILT" "$DEST_DIR/$BINARY_NAME"
echo "whisper-cli $VERSION → $DEST_DIR/$BINARY_NAME"
