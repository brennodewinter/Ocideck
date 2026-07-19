#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 127
  fi
}

section() {
  printf '\n== %s ==\n' "$1"
}

require_cmd flutter
require_cmd dart
require_cmd make

section "OciDeck release build"
echo "Workspace: $ROOT_DIR"
echo "Flutter: $(flutter --version | sed -n '1p')"

# Kijken vóór inpakken. Een release-artefact draagt zijn gebundelde
# referentiedata een jaar met zich mee, dus dit is het moment waarop je wilt
# weten dat er upstream iets nieuwers is — niet drie maanden later.
#
# Bewust adviserend, en bewust vóór de builds. Adviserend omdat een nieuwe
# upstreamversie geen defect is in wat je bouwt: het is een afweging, en die is
# aan de mens die de release maakt. Zou dit de build afbreken, dan wordt het
# binnen twee releases weggevlagd en is de zichtbaarheid weg die het hele doel
# was. Vóór de builds omdat de melding anders onder twintig minuten
# compileruitvoer verdwijnt.
#
# Geen netwerk is geen reden om niet te bouwen; het is wel een reden om te
# zeggen dát er niet gekeken is. Stilte mag hier niet als goedkeuring lezen.
section "Gebundelde referentiedata"
if make catalogs-outdated; then
  :
else
  status=$?
  if [[ $status -eq 2 ]]; then
    echo "Let op: upstream niet bereikbaar — er is niet gecontroleerd of de" >&2
    echo "gebundelde referentiedata nog actueel is. De build gaat door." >&2
  else
    echo "Let op: de controle op referentiedata eindigde onverwacht ($status)." >&2
  fi
fi

section "Web"
echo "Building hardened web bundle and verifying CSP/CanvasKit hardening."
make check-web

section "macOS"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script builds the macOS app, so it must run on macOS." >&2
  exit 1
fi
echo "Building release .app."
make build-macos

section "Artifacts"
echo "Web deploy directory:"
echo "  $ROOT_DIR/build/web"
echo
echo "macOS release app directory:"
echo "  $ROOT_DIR/build/macos/Build/Products/Release"
echo
echo "Release build complete."
