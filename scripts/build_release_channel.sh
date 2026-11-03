#!/usr/bin/env bash
# Bouw uitsluitend het gekozen kanaal; deze route publiceert niets.
set -euo pipefail
TAG="${1:?tag vereist}"
SHA="${2:?volledige bron-SHA vereist}"
REF="${3:?vaste kandidaatref vereist}"
CHANNEL="${4:?kanaal vereist}"
python3 - "$TAG" "$SHA" "$CHANNEL" <<'PY'
import sys
import re
tag, sha, channel = sys.argv[1:]
if not re.fullmatch(r'v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)', tag):
    raise ValueError('invalid tag')
if not re.fullmatch(r'[0-9a-f]{40}', sha) or sha == '0' * 40:
    raise ValueError('source must be a nonzero full lowercase commit SHA')
if channel not in ('web', 'linux-debian12', 'linux-tar', 'linux-deb', 'linux-rpm', 'linux-appimage', 'linux-flatpak'):
    raise ValueError('unsupported independent channel')
PY
[[ "$REF" == "codex/release-candidate-${TAG}-${SHA}" ]] || { echo 'Onjuiste vaste kandidaatref' >&2; exit 1; }
[[ "$(git rev-parse HEAD)" == "$SHA" ]] || { echo 'Checkout wijkt af van bron-SHA' >&2; exit 1; }
[[ "$(git ls-remote --exit-code origin "refs/heads/$REF" | awk '{print $1}')" == "$SHA" ]] || { echo 'Kandidaatref wijkt af van bron-SHA' >&2; exit 1; }
[[ "$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)" == "${TAG#v}" ]] || { echo 'Bronversie wijkt af' >&2; exit 1; }
# Nieuwe jobwerkmap vereist: oude bestanden mogen niet als bouwresultaat meetellen.
[[ ! -e dist ]] || { echo 'dist moet afwezig zijn' >&2; exit 1; }
# Twee compilatietaken binnen de containerquota; Debian controleert zijn eigen SDK.
export CMAKE_BUILD_PARALLEL_LEVEL=2
if [[ "$CHANNEL" != linux-debian12 ]]; then
  make check-toolchain
fi
case "$CHANNEL" in
  web)
    make check-web
    mkdir dist
    tar -C build/web -czf "dist/ocideck-web-${TAG#v}.tar.gz" .
    ;;
  linux-debian12)
    scripts/build_debian12_release.sh "${TAG#v}"
    ;;
  linux-tar|linux-deb|linux-rpm|linux-appimage|linux-flatpak)
    bash "$(dirname "$0")/run_release_linux_build.sh" make build-linux
    mkdir dist
    if [[ "$CHANNEL" == linux-tar ]]; then
      tar -C build/linux/x64/release --transform "s,^bundle,ocideck-${TAG#v}," -czf "dist/ocideck-linux-x64-${TAG#v}.tar.gz" bundle
    else
      FORMATS="${CHANNEL#linux-}" scripts/package_linux.sh "${TAG#v}"
    fi
    ;;
  *) echo "Kanaal $CHANNEL heeft nog geen onafhankelijke bouwroute; gebruik de bestaande volledige workflow." >&2; exit 1 ;;
esac
