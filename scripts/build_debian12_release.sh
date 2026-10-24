#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: build_debian12_release.sh <version>}"
VERSION="${VERSION#v}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBSPEC_VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$ROOT/pubspec.yaml")"
[[ "${PUBSPEC_VERSION%%+*}" == "$VERSION" ]] || {
  echo "Release $VERSION does not match pubspec.yaml ($PUBSPEC_VERSION)" >&2
  exit 1
}
FLUTTER_VERSION="$(awk '$1 == "flutter" { print $2; exit }' "$ROOT/.tool-versions")"
[[ -n "$FLUTTER_VERSION" ]] || { echo 'Missing Flutter pin' >&2; exit 1; }

DOCKER=(docker)
if [[ -n "${DOCKER_DAEMON:-}" ]]; then DOCKER+=(-H "$DOCKER_DAEMON"); fi
IMAGE="ocideck-debian12-builder:flutter-$FLUTTER_VERSION"
"${DOCKER[@]}" build --platform linux/amd64 \
  --build-arg "FLUTTER_VERSION=$FLUTTER_VERSION" \
  --build-arg TARGETARCH=amd64 \
  -t "$IMAGE" "$ROOT/scripts/debian12_builder"

CID="$("${DOCKER[@]}" create --platform linux/amd64 \
  --env HOME=/tmp/build-home "$IMAGE")"
trap '"${DOCKER[@]}" rm -f "$CID" >/dev/null 2>&1 || true' EXIT
# A worktree's .git file points to a host path that does not exist in Docker.
git -C "$ROOT" archive HEAD | "${DOCKER[@]}" cp - "$CID:/src"
"${DOCKER[@]}" start -a "$CID"
[[ "$("${DOCKER[@]}" inspect -f '{{.State.ExitCode}}' "$CID")" == 0 ]] || {
  echo 'Debian 12 build failed' >&2
  exit 1
}

mkdir -p "$ROOT/dist"
SAFE_VERSION="${PUBSPEC_VERSION//+/-}"
"${DOCKER[@]}" cp \
  "$CID:/out/ocideck-linux-debian12-$SAFE_VERSION.tar.gz" \
  "$ROOT/dist/ocideck-linux-debian12-x86_64-$VERSION.tar.gz"
