#!/usr/bin/env bash
# Plaatst de whisper-cli-helper in een net gebouwd artefact (#2512).
#
#   scripts/bundle_whisper_cli.sh macos    # → <app>/Contents/Helpers/
#   scripts/bundle_whisper_cli.sh windows  # → build/windows/x64/runner/Release/
#   scripts/bundle_whisper_cli.sh linux    # → build/linux/x64/release/bundle/
#
# De helper wordt eerst gebouwd als hij er nog niet is
# (scripts/build_whisper_cli.sh is idempotent). De engine vindt hem op
# deze plekken naast het hoofdproces (local_whisper_engine_io.dart).
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PLATFORM="${1:?gebruik: bundle_whisper_cli.sh macos|windows|linux}"

arch_dir() {
  case "$(uname -m)" in
    arm64|aarch64) echo "arm64" ;;
    *) echo "x64" ;;
  esac
}

"$ROOT_DIR/scripts/build_whisper_cli.sh"

case "$PLATFORM" in
  macos)
    SRC="native/whisper_cli/bin/macos-$(arch_dir)/whisper-cli"
    APP=$(find build/macos/Build/Products/Release -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null || true)
    [[ -z "$APP" ]] && { echo "geen .app onder build/macos/…" >&2; exit 1; }
    mkdir -p "$APP/Contents/Helpers"
    install -m 0755 "$SRC" "$APP/Contents/Helpers/whisper-cli"
    echo "whisper-cli → $APP/Contents/Helpers/"
    ;;
  windows)
    SRC="native/whisper_cli/bin/windows-$(arch_dir)/whisper-cli.exe"
    DEST="build/windows/x64/runner/Release"
    [[ -d "$DEST" ]] || { echo "geen Windows-bundel onder $DEST" >&2; exit 1; }
    install -m 0755 "$SRC" "$DEST/whisper-cli.exe"
    echo "whisper-cli.exe → $DEST/"
    ;;
  linux)
    SRC="native/whisper_cli/bin/linux-$(arch_dir)/whisper-cli"
    DEST="build/linux/x64/release/bundle"
    [[ -d "$DEST" ]] || { echo "geen Linux-bundel onder $DEST" >&2; exit 1; }
    install -m 0755 "$SRC" "$DEST/whisper-cli"
    echo "whisper-cli → $DEST/"
    ;;
  *)
    echo "onbekend platform: $PLATFORM" >&2
    exit 2
    ;;
esac
