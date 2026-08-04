#!/usr/bin/env bash
#
# Bumpt de exact-gepinde CI-scanners (gitleaks/trufflehog/semgrep) naar hun
# laatste upstream-versie, op ÉLKE plek die samen moet kloppen:
#   * `.github/pinned-ci-versions.json`  — de bron,
#   * de `<TOOL>_VERSION`-env in elke workflow die de pin draagt,
#   * de tag van het voorgebakken scans-image (`…/ocideck-scans:gl…-th…-sg…`)
#     in `.forgejo/workflows/scans.yml` — die tag ís de drie pins.
#
# Waarom apart, en waarom geen versienummer met de hand: die drie plekken lopen
# anders stil uiteen (`test/pinned_versions_manifest_test.dart` vangt dat, maar
# achteraf), en de scanner die stilstaat meldt groen terwijl hij de nieuwe
# credential-/codevormen mist (#802). Dit script zet ze in één stap gelijk.
#
# Het "wat is de laatste versie"-antwoord komt uit `check_pinned_versions.dart`
# (dezelfde monitor als `make check-pins`), zodat die vraag één bron houdt; dit
# script leest die uitkomst en past de bestanden aan. Idempotent: is alles al
# actueel, dan verandert er niets.
#
# Het PUBLICEERT het nieuwe scans-image NIET en committeert niet — de aanroeper
# doet dat: `scripts/release_auto.sh` dispatcht `ci-image-scans` op de bump-branch;
# met de hand draai je `make ci-image-scans-publish` (docker/colima) en een PR.
# Het script drukt die vervolgstap af.
#
# Let op: een nieuwere scanner kan NIEUWE bevindingen opleveren — dan wordt de
# scan-poort alsnog rood en werk je die eerst weg. Dit script bumpt de versie;
# het belooft niet dat de nieuwe versie niets nieuws vindt.
#
# Gebruik:
#   make bump-scanner-pins            # toepassen
#   make bump-scanner-pins DRY_RUN=1  # tonen wat zou wijzigen, niets aanraken
#   scripts/bump_scanner_pins.sh [--dry-run]

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MANIFEST=".github/pinned-ci-versions.json"
SCANS_WORKFLOW=".forgejo/workflows/scans.yml"
DRY_RUN="${DRY_RUN:-0}"
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

die() { printf '\nbump-scanner-pins: %s\n' "$1" >&2; exit 1; }
for c in dart jq sed grep; do command -v "$c" >/dev/null 2>&1 || die "ontbrekend commando: $c"; done
[ -f "$MANIFEST" ] || die "manifest niet gevonden: $MANIFEST"

# De scanners die dit script beheert (de `tools` in het manifest). De trivy-actie
# is een `uses:`-pin zonder image-tag en valt hier bewust buiten.
is_scanner() { case "$1" in gitleaks|trufflehog|semgrep) return 0 ;; *) return 1 ;; esac; }

# Vraag de monitor wat achterloopt. Exit 0 = alles actueel; 1 = iets behind;
# 2 = kon niet checken (netwerk/manifest) → we raken dan niets aan.
set +e
CHECK_OUT="$(dart run tool/check_pinned_versions.dart 2>&1)"
CHECK_RC=$?
set -e

if [ "$CHECK_RC" -eq 0 ]; then
  echo "Scanner-pins zijn actueel — niets te doen."
  exit 0
fi
if [ "$CHECK_RC" -ne 1 ]; then
  printf '%s\n' "$CHECK_OUT" | sed 's/^/  /'
  die "kon de laatste versies niet vaststellen (netwerk of manifest) — niets gewijzigd."
fi

# De samenvattingsregels van de monitor: "  <naam>@<oud> → <nieuw>". Alleen die
# dragen de pijl; de per-pin-regels niet. Actie-pins (met '/') slaan we over.
BEHIND="$(printf '%s\n' "$CHECK_OUT" | grep -E '^[[:space:]]+[^@[:space:]]+@[^[:space:]]+[[:space:]]+→' || true)"
[ -n "$BEHIND" ] || die "monitor meldde 'behind' maar geen bump-regels gevonden — handmatig nakijken."

set_manifest_version() { # old new
  # sed op de unieke versiestring behoudt de handopmaak van het manifest — jq zou
  # het hele bestand herformatteren (compacte arrays uitklappen). De drie
  # scanner-versies zijn onderling uniek, dus de match is eenduidig.
  local old_re; old_re="$(printf '%s' "$1" | sed 's/\./\\./g')"
  sed -i.bak "s/\"version\": \"$old_re\"/\"version\": \"$2\"/" "$MANIFEST" && rm -f "$MANIFEST.bak"
}

replace_in_workflows() { # name env old new
  local name="$1" env="$2" old="$3" new="$4" wf
  while IFS= read -r wf; do
    [ -f "$wf" ] || continue
    sed -i.bak "s/${env}: ${old}/${env}: ${new}/g" "$wf" && rm -f "$wf.bak"
  done < <(jq -r --arg n "$name" '.tools[] | select(.name==$n) | .workflows[]' "$MANIFEST")
}

rebuild_scans_image_tag() {
  local gl th sg newtag
  gl="$(jq -r '.tools[] | select(.name=="gitleaks")   | .version' "$MANIFEST")"
  th="$(jq -r '.tools[] | select(.name=="trufflehog") | .version' "$MANIFEST")"
  sg="$(jq -r '.tools[] | select(.name=="semgrep")    | .version' "$MANIFEST")"
  newtag="gl${gl}-th${th}-sg${sg}"
  sed -i.bak -E "s|ocideck-scans:gl[0-9.]+-th[0-9.]+-sg[0-9.]+|ocideck-scans:${newtag}|g" \
    "$SCANS_WORKFLOW" && rm -f "$SCANS_WORKFLOW.bak"
  echo "  scans-image-tag → $newtag"
}

changed=0
while IFS= read -r line; do
  name="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([^@[:space:]]+)@.*/\1/')"
  old="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[^@[:space:]]+@([^[:space:]]+).*/\1/')"
  new="$(printf '%s' "$line" | sed -E 's/.*→[[:space:]]*v?([0-9][0-9.]*).*/\1/')"
  is_scanner "$name" || { echo "  (overslaan: $name is geen scanner)"; continue; }
  [ -n "$new" ] || die "kon nieuwe versie voor $name niet lezen uit: $line"
  env="$(jq -r --arg n "$name" '.tools[] | select(.name==$n) | .env' "$MANIFEST")"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  $name: $old → $new  (env $env + manifest + image-tag)"
    changed=1
    continue
  fi
  set_manifest_version "$old" "$new"
  replace_in_workflows "$name" "$env" "$old" "$new"
  echo "  $name: $old → $new"
  changed=1
done <<<"$BEHIND"

if [ "$changed" -eq 0 ]; then
  echo "Geen scanner achter — niets gewijzigd."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "Dry-run: bovenstaande zou wijzigen. Laat DRY_RUN weg om toe te passen."
  exit 0
fi

rebuild_scans_image_tag
echo
echo "Bijgewerkt. VOLGENDE STAP (verplicht): publiceer eerst een nieuw scans-image"
echo "vóór een workflow ernaar wijst — dispatch 'ci-image-scans' op deze branch, of"
echo "draai 'make ci-image-scans-publish' (docker/colima). Commit daarna de wijziging."
