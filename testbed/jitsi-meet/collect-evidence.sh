#!/usr/bin/env bash
# Verzamelt een geredigeerd bewijsbundeltje voor het formulier uit
# EVIDENCE_FORM.md: versies, containerlogs en de bereikbaarheidsproef.
#
#   ./collect-evidence.sh [map]   (standaard ./evidence/<timestamp>/)
#
# Redactie (issue #2540: "redigeer tokens, ICE-adressen en deelnemersdata"):
# - de wachtwoorden uit .env worden letterlijk vervangen door <REDACTED:*>
# - jwt=/token=-parameters en Authorization-headers worden weggestreept
# - alle niet-loopback IPv4-adressen (ICE-kandidaten, STUN-uitslagen,
#   deelnemersadressen) worden <REDACTED-IP>
# Loopback- en docker-netwerkadressen blijven staan: die zijn nodig om in het
# bewijs te laten zien dat media alleen naar de JVB op 127.0.0.1:10000 liep.
set -euo pipefail
cd "$(dirname "$0")"

out="${1:-./evidence/$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out"

# --- redactiefilter ---------------------------------------------------------
redact() {
  # Wachtwoordwaarden uit .env als letterlijke strings vervangen.
  local pw_args=()
  while IFS='=' read -r key val; do
    case "$key" in
      *_PASSWORD|*_SECRET)
        [[ -n "$val" ]] && pw_args+=(-e "s/${val}/<REDACTED:${key}>/g")
        ;;
    esac
  done < .env
  sed -E \
    ${pw_args[@]+"${pw_args[@]}"} \
    -e 's/(jwt|token|access_token)=[^ &"'"'"']*/\1=<REDACTED>/gi' \
    -e 's/(authorization:)[^,]*/\1 <REDACTED>/gi' \
    -e 's/\b(10|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.[0-9]{1,3}\.[0-9]{1,3}\b/<REDACTED-IP>/g'
}

# --- context ----------------------------------------------------------------
{
  echo "# stackcontext ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  echo "ocideck_commit: $(git -C ../.. rev-parse HEAD 2>/dev/null || echo onbekend)"
  echo "jitsi_image_version: $(grep -E '^JITSI_IMAGE_VERSION=' .env | cut -d= -f2)"
  echo "host_os: $(uname -srm)"
} | tee "$out/context.txt"

docker compose ps --format '{{.Name}} {{.Image}} {{.Status}}' \
  | tee "$out/containers.txt"

# Image-digests: bewijzen wélke bits er draaiden, los van de tag.
docker compose ps -q | while read -r id; do
  docker inspect --format '{{.Name}} {{.Config.Image}} {{.Image}}' "$id"
done | tee "$out/images.txt"

# --- geredigeerde logs -------------------------------------------------------
for svc in web prosody jicofo jvb; do
  docker compose logs --no-color --timestamps "$svc" 2>&1 \
    | redact > "$out/${svc}.log"
done

# --- bereikbaarheid ----------------------------------------------------------
./run.sh verify > "$out/verify.txt" 2>&1 || true

echo "Bewijsmap: $out"
echo "Let op: logredactie is best-effort — lees het formulier na vóór je deelt."
