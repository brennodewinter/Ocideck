#!/usr/bin/env bash
set -Eeuo pipefail

# Eenmalige, interactieve opslag. `security -w` als laatste argument vraagt het
# geheim zelf; het verschijnt daardoor niet in shellgeschiedenis of `ps`.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="${OCIDECK_MINISIGN_KEYCHAIN_SERVICE:-ocideck-minisign-password}"
ACCOUNT="$(id -un)"

[ "$(uname -s)" = Darwin ] || { echo 'macOS-sleutelhanger vereist.' >&2; exit 1; }
command -v security >/dev/null || { echo 'security ontbreekt.' >&2; exit 1; }
if security find-generic-password -s "$SERVICE" >/dev/null 2>&1; then
  echo "Sleutelhangeritem '$SERVICE' bestaat al; niets overschreven."
  exit 0
fi

echo 'Voer het bestaande minisign-sleutelwachtwoord één keer in de macOS-prompt in.'
security add-generic-password -a "$ACCOUNT" -s "$SERVICE" \
  -l 'OciDeck release minisign' -w

# Laat een typefout niet als stil, blijvend geheim achter. De proef gebruikt
# dezelfde sign-release-route als release_auto.sh en controleert de publieke
# sleutel. Geen wachtwoord, proefbestand of privésleutel gaat naar CI.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'ocideck signing keychain setup\n' >"$tmp/SHA256SUMS"
password="$(security find-generic-password -s "$SERVICE" -w)" || {
  security delete-generic-password -s "$SERVICE" >/dev/null 2>&1 || true
  echo 'Het nieuwe item kon niet worden gelezen; het is verwijderd.' >&2
  exit 1
}
if ! printf '%s\n' "$password" \
  | "$ROOT_DIR/scripts/sign_release.sh" "$tmp/SHA256SUMS" >/dev/null 2>&1; then
  unset password
  security delete-generic-password -s "$SERVICE" >/dev/null 2>&1 || true
  echo 'De proefhandtekening mislukte; het nieuwe item is verwijderd. Probeer opnieuw.' >&2
  exit 1
fi
unset password
echo 'Sleutelhanger ingesteld en proefhandtekening geverifieerd.'
