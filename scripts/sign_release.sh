#!/usr/bin/env bash
set -Eeuo pipefail

# Teken de release-manifest `SHA256SUMS` met een minisign detached signature, en
# verifieer die meteen. Zonder dit is `SHA256SUMS` een controle dat je hebt wat
# er lag, maar geen herkomstbewijs: wie de lijst kan vervangen, vervangt ook de
# checksums. Eén handtekening over de manifest verankert de héle release —
# `SHA256SUMS` dekt elk bestand (macOS, Windows, Linux, web, beide SBOM's), dus
# de handtekening dekt ze via de manifest allemaal tegelijk.
#
# Waarom een handmatige, lokale stap en niet in de release-runner: de private
# sleutel hoort niet als secret op een bouwmachine te staan (least-privilege) —
# hetzelfde uitgangspunt als bij de macOS-notarisatie (`scripts/notarize_macos.sh`),
# die ook lokaal en met de hand draait. De keten is: de release-workflow
# publiceert de artefacten + `SHA256SUMS`; jij haalt `SHA256SUMS` op, tekent hem
# hiermee lokaal, en hangt `SHA256SUMS.minisig` aan de release. Zie docs/BUILD.md.
#
# Vereisten (eenmalig, zie docs/BUILD.md):
#   - minisign geïnstalleerd (macOS: `brew install minisign`; Debian/Ubuntu:
#     `sudo apt install minisign`).
#   - Een sleutelpaar:
#       minisign -G -p minisign.pub -s ~/.minisign/ocideck-release.key
#     De publieke helft (`minisign.pub`) staat in de repo-root; de private helft
#     blijft lokaal en gaat nooit naar een runner. Een wachtwoord op de private
#     sleutel is sterk aangeraden — hij is een release-vertrouwenswortel; zet er
#     een op met `minisign -C -s ~/.minisign/ocideck-release.key`. Dit script
#     vraagt er dan bij het tekenen interactief om.
#
# Overschrijfbaar via de omgeving:
#   OCIDECK_RELEASE_KEY     private sleutel (standaard ~/.minisign/ocideck-release.key)
#   OCIDECK_RELEASE_PUBKEY  publieke sleutel om na te verifiëren (standaard <repo>/minisign.pub)
#
# Gebruik:
#   scripts/sign_release.sh path/naar/SHA256SUMS
#   scripts/sign_release.sh                       # standaard: dist/SHA256SUMS

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

KEY="${OCIDECK_RELEASE_KEY:-$HOME/.minisign/ocideck-release.key}"
PUBKEY="${OCIDECK_RELEASE_PUBKEY:-$ROOT_DIR/minisign.pub}"
SUMS="${1:-dist/SHA256SUMS}"

command -v minisign >/dev/null 2>&1 || {
  echo "minisign ontbreekt — installeer het (macOS: brew install minisign; Debian/Ubuntu: sudo apt install minisign)." >&2
  exit 1
}
[ -f "$SUMS" ] || {
  echo "Checksum-lijst niet gevonden: $SUMS" >&2
  echo "Geef het pad naar SHA256SUMS mee, of draai dit vanuit de map waarin 'dist/SHA256SUMS' staat." >&2
  exit 1
}
[ -f "$KEY" ] || {
  echo "Private sleutel niet gevonden: $KEY" >&2
  echo "Genereer hem eenmalig: minisign -G -p \"$PUBKEY\" -s \"$KEY\"  (zie docs/BUILD.md)." >&2
  exit 1
}
[ -f "$PUBKEY" ] || {
  echo "Publieke sleutel niet gevonden: $PUBKEY" >&2
  exit 1
}

# Laat nooit een half product achter. `minisign -Sm` schrijft de .minisig vóór
# de verify; breekt de verify (of wat dan ook) daarna af, dan is die .minisig
# niet te vertrouwen en moet hij weg — anders zou een genegeerde exitcode een
# niet-verifieerbare handtekening kunnen publiceren.
trap 'rm -f "$SUMS.minisig"' ERR

echo "== OciDeck: minisign detached signature over $SUMS =="
minisign -Sm "$SUMS" -s "$KEY"

echo "-- verifiëren tegen $PUBKEY --"
# Een release die je niet meteen kunt verifiëren, teken je niet uit: dit vangt
# een verwisselde sleutel of een corrupte handtekening vóór publicatie.
minisign -Vm "$SUMS" -p "$PUBKEY"

trap - ERR  # geslaagd én geverifieerd: de handtekening mag blijven staan

echo
echo "Klaar: $SUMS.minisig"
echo "Hang zowel SHA256SUMS als SHA256SUMS.minisig aan de release."
echo "Verifiëren doet een ontvanger met: minisign -Vm SHA256SUMS -p minisign.pub"
