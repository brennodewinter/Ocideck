#!/usr/bin/env bash
set -euo pipefail

# Flutter #196872: on macOS, an orphaned traversal child can corrupt the
# accessibility tree and crash the native bridge. Build with the upstream
# framework fix (#193372) until it reaches OciDeck's stable Flutter pin.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
patch_file="$project_root/third_party/flutter_patches/3.50.0-semantics-b304cf1.patch"
flutter_bin="$(command -v flutter)"
sdk_root="$("$flutter_bin" --version --machine | python3 -c '
import json
import sys

sdk = json.load(sys.stdin)
if sdk["frameworkRevision"] != "ab2912035e160d9cad6306df307576da6128ebdb":
    sys.exit("Unexpected Flutter revision for the macOS semantics backport. "
             "Check whether the new stable SDK already includes flutter/flutter#193372.")
print(sdk["flutterRoot"])
')"
lock="$sdk_root/bin/cache/ocideck-macos-semantics.lock"
if ! mkdir "$lock"; then
  echo "The Flutter SDK semantics backport is already in use: $lock" >&2
  exit 1
fi

patched=false
cleanup() {
  local result=$?
  if [[ "$patched" == true ]] &&
     ! git -C "$sdk_root" apply --reverse "$patch_file"; then
    echo "Could not restore Flutter sources. SDK lock retained: $lock" >&2
    exit 1
  fi
  rmdir "$lock"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

git -C "$sdk_root" apply --check "$patch_file"
git -C "$sdk_root" apply "$patch_file"
patched=true

"$flutter_bin" "$@"
