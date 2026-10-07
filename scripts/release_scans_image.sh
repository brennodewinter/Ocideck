#!/usr/bin/env bash
# Lokale fallback voor het scans-image van een release (#2295). De normale
# route is een ci-image-scans-dispatch op de releasebranch; faalt die, dan
# publiceerde release_auto vroeger het advies 'make ci-image-scans-publish' —
# maar dat leest de scannerpins uit de hUIDIGE checkout, en die staat na een
# fase-2-fout vaak alweer op main met oudere pins. Dit script bouwt daarom
# aantoonbaar vanuit een tijdelijke werkboom op de release-ref en verifieert
# daarna exact die registrytag terug. Gebruik:
#
#   scripts/release_scans_image.sh vX.Y.Z
#   scripts/release_auto.sh --resume vX.Y.Z
set -euo pipefail
cd "$(dirname "$0")/.."

die() { printf 'release-scans-image: %s\n' "$1" >&2; exit 1; }
log() { printf '   %s\n' "$1"; }

TAG="${1:-}"
[ -n "$TAG" ] || die "gebruik: $0 vX.Y.Z"
for cmd in git jq docker make curl; do
  command -v "$cmd" >/dev/null 2>&1 || die "ontbrekend commando: $cmd"
done

BRANCH="release/$TAG"
git fetch --quiet origin \
  "refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" \
  "refs/tags/$TAG:refs/tags/$TAG" \
  || die "kon origin niet verversen — zonder de release-ref is er geen veilige fallback."

# De releasebranch eerst; is die na de merge al opgeruimd, dan draagt de tag
# dezelfde scannerpins. Geen van beide → geen release-ref, geen fallback.
if git rev-parse -q --verify "refs/remotes/origin/$BRANCH" >/dev/null 2>&1; then
  REF="origin/$BRANCH"
elif git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  REF="refs/tags/$TAG"
else
  die "noch origin/$BRANCH noch tag $TAG staat op origin — er valt geen release-ref te publiceren."
fi
log "Release-ref: $REF"

# De verwachte image-tag volgt dezelfde afleiding als scan_image_tag_for_ref in
# release_auto.sh en het Makefile-target — uit de pins van DE REF, niet van HEAD.
IMAGE_TAG="$(git show "$REF:.github/pinned-ci-versions.json" \
  | jq -r '[.tools[] | select(.name == "gitleaks" or .name == "trufflehog" or .name == "semgrep")
      | {key:.name, value:.version}] | from_entries
      | "gl\(.gitleaks)-th\(.trufflehog)-sg\(.semgrep)"')" \
  || die "kon de scannerpins niet uit $REF lezen."
[ -n "$IMAGE_TAG" ] && [ "$IMAGE_TAG" != "null" ] \
  || die "scannerpins in $REF onleesbaar."
log "Te publiceren registrytag: $IMAGE_TAG — afgeleid van de pins op $REF."

WT="$(mktemp -d "${TMPDIR:-/tmp}/ocideck-scans-XXXXXX")"
cleanup() { git worktree remove --force "$WT" >/dev/null 2>&1 || true; }
trap cleanup EXIT
git worktree add --quiet --detach "$WT" "$REF" \
  || die "kon geen tijdelijke werkboom op $REF zetten."
( cd "$WT" && make ci-image-scans-publish ) \
  || die "make ci-image-scans-publish faalde in de werkboom op $REF."

# Naconditie: alleen een terugleesbare registrytag bewijst de publicatie —
# dezelfde verificatie als scan_image_available in release_auto.sh.
TOKEN="$(curl -fsSLG 'https://pawprint.vigilis.online/v2/token' \
  --data-urlencode 'service=container_registry' \
  --data-urlencode 'scope=repository:librekat/ocideck-scans:pull' \
  | jq -r '.token // .access_token // empty' 2>/dev/null || true)"
[ -n "$TOKEN" ] \
  || die "kon geen registry-pull-token krijgen — de publicatie van $IMAGE_TAG blijft onbewezen."
CODE="$(curl -sS -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json' \
  "https://pawprint.vigilis.online/v2/librekat/ocideck-scans/manifests/$IMAGE_TAG" \
  2>/dev/null || true)"
[ "$CODE" = "200" ] \
  || die "de build eindigde zonder fout, maar $IMAGE_TAG leest niet terug uit de registry (HTTP ${CODE:-onbereikbaar})."

log "Scans-image librekat/ocideck-scans:$IMAGE_TAG gepubliceerd en pullbaar geverifieerd."
log "Hervat de release met:  scripts/release_auto.sh --resume $TAG"
