#!/usr/bin/env bash
#
# Zet de geharde webbundel uit `build/web` live op een statische host.
#
# Eén script, twee gebruikers: een mens die `make deploy-web` draait en de
# release-workflow op de tag. Dat is met opzet zo. Een deploy die in CI anders
# verloopt dan met de hand is een deploy waarvan niemand meer weet wat er
# werkelijk gebeurt — en dit is de enige stap in het project die iets naar
# buiten duwt.
#
# De volgorde is de hele truc:
#
#   1. de bundel wordt eerst geverifieerd (SHA256SUMS over precies de
#      bestanden die er liggen), want een half gebouwde map hoort de deur niet
#      uit te gaan;
#   2. uitpakken gebeurt náást de live map, niet erin — een `rsync` over de
#      draaiende site laat bezoekers een mengsel van oud en nieuw zien;
#   3. de wissel is een `mv` van twee mappen, dus ondeelbaar voor de webserver;
#   4. de oude map blijft als `.bak-<datum>` staan tot de liveverificatie
#      groen is, zodat terugdraaien één `mv` is en geen herbouw.
#
# Gebruik:
#   make build-web && scripts/deploy_web.sh
#   scripts/deploy_web.sh --dry-run          toon wat er zou gebeuren
#   scripts/deploy_web.sh --keep-backup      ruim de vorige versie niet op
#
# Instelbaar via de omgeving (de standaarden zijn de publieke webdemo):
#   OCIDECK_DEPLOY_HOST   ssh-doel                     ubuntu@braniebananie.nl
#   OCIDECK_DEPLOY_ROOT   webroot op die host          /var/www/ocideck
#   OCIDECK_DEPLOY_OWNER  eigenaar van de bestanden    brenno:brenno
#   OCIDECK_DEPLOY_URL    URL voor de liveverificatie  https://ocideck.librekat.nl
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

HOST="${OCIDECK_DEPLOY_HOST:-ubuntu@braniebananie.nl}"
WEBROOT="${OCIDECK_DEPLOY_ROOT:-/var/www/ocideck}"
OWNER="${OCIDECK_DEPLOY_OWNER:-brenno:brenno}"
LIVE_URL="${OCIDECK_DEPLOY_URL:-https://ocideck.librekat.nl}"

DRY_RUN=0
KEEP_BACKUP=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --keep-backup) KEEP_BACKUP=1 ;;
    -h|--help) sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Onbekende optie: $arg" >&2; exit 2 ;;
  esac
done

log() { printf '\n== %s ==\n' "$1"; }

# In CI mag ssh nergens op wachten. Zonder BatchMode blijft een onbekende
# hostsleutel of een sleutel met wachtwoord staan wachten op een antwoord dat
# in een container nooit komt — en dan hangt de job tot de timeout van drie uur
# in plaats van meteen te zeggen wat er mis is. Met de hand juist níet: daar
# hoort een sleutel met wachtwoord uit de ssh-agent gewoon te werken.
SSH_OPTS=()
if [[ -n "${CI:-}" ]]; then
  SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=yes)
fi

# --- 1. Is er iets te deployen, en klopt het? --------------------------------

log "Bundel controleren"
if [[ ! -f build/web/index.html ]]; then
  echo "Geen build/web/index.html — draai eerst 'make build-web'." >&2
  exit 1
fi
# Dezelfde controle die `make check-web` doet: de checksumlijst moet exact de
# bestanden beschrijven die er liggen. Vangt zowel een half afgebroken build
# als een bestand dat er ná het inpakken bij is gekomen.
dart run tool/pack_web_release.dart --check

BUNDLE_SHA="$(shasum -a 256 build/web/SHA256SUMS | cut -d' ' -f1)"
echo "SHA256SUMS: $BUNDLE_SHA"

# Wie deployt wat. Niet als poort maar als vermelding: bij een probleem op de
# site is de eerste vraag "welke commit staat er live", en dan wil je dat in
# het deploylog terugvinden in plaats van te moeten reconstrueren.
DESCRIBE="$(git describe --tags --always --dirty 2>/dev/null || echo 'onbekend')"
echo "Broncode:   $DESCRIBE"
if [[ "$DESCRIBE" == *-dirty ]]; then
  echo "Let op: deze bundel komt uit een werkkopie met ongecommitte wijzigingen." >&2
fi

STAMP="$(date -u +%Y%m%d-%H%M%S)"
TARBALL="ocideck-web-$STAMP.tar.gz"
# Een eigen map en niet `mktemp`+achtervoegsel: dat laatste laat het bestand dat
# mktemp werkelijk aanmaakt onopgeruimd achter, want de naam waar je mee verder
# werkt is dan een andere.
WERKMAP="$(mktemp -d -t ocideck-web-XXXXXX)"
trap 'rm -rf "$WERKMAP"' EXIT
TMP_TARBALL="$WERKMAP/$TARBALL"

tar -C build/web -czf "$TMP_TARBALL" .
echo "Tarball:    $(du -h "$TMP_TARBALL" | cut -f1)"

if (( DRY_RUN )); then
  log "Dry run"
  echo "Zou uploaden naar $HOST en wisselen in $WEBROOT (eigenaar $OWNER)."
  echo "Zou daarna verifiëren op $LIVE_URL."
  exit 0
fi

# --- 2. Uploaden ------------------------------------------------------------

log "Uploaden naar $HOST"
scp -q "${SSH_OPTS[@]}" "$TMP_TARBALL" "$HOST:/tmp/$TARBALL"

# --- 3. Uitpakken náást de live map, dan ondeelbaar wisselen -----------------
#
# Alles in één ssh-sessie met `set -e`: breekt het uitpakken af, dan is er nog
# niets gewisseld en staat de oude site er ongemoeid bij.

# De waarden gaan als argumenten mee en niet als tekst in het script: een
# aangehaalde heredoc (<<'REMOTE') wordt lokaal met rust gelaten, dus er is geen
# tweede aanhalingslaag waar een pad met een spatie of een aanhalingsteken
# doorheen kan breken. Ook wat ShellCheck met SC2087 bedoelt.
log "Wisselen op de server"
ssh "${SSH_OPTS[@]}" "$HOST" bash -s -- "$WEBROOT" "$OWNER" "/tmp/$TARBALL" "$STAMP" <<'REMOTE'
set -euo pipefail
WEBROOT="$1"
OWNER="$2"
TARBALL="$3"
STAMP="$4"

NEW="$WEBROOT.new"
BAK="$WEBROOT.bak-$STAMP"

sudo rm -rf "$NEW"
sudo mkdir -p "$NEW"
sudo tar -C "$NEW" -xzf "$TARBALL"
rm -f "$TARBALL"

# Bestandsrechten worden al door `make build-web` genormaliseerd (644/755);
# hier gaat het om het eigendom, want de tarball draagt de uid van de
# bouwmachine mee en die bestaat op de server niet.
sudo chown -R "$OWNER" "$NEW"

if [ -d "$WEBROOT" ]; then
  sudo mv "$WEBROOT" "$BAK"
  echo "Vorige versie bewaard als $BAK"
fi
sudo mv "$NEW" "$WEBROOT"

# De topmap zelf hoort aan de webservergroep, anders leest nginx/Caddy er niet
# in wanneer de eigenaar restrictiever staat dan de bestanden eronder.
sudo chown "${OWNER%%:*}:www-data" "$WEBROOT"
echo "Live: $WEBROOT"
REMOTE

# --- 4. Liveverificatie -----------------------------------------------------
#
# "De wissel is gelukt" is niet hetzelfde als "de site werkt". Er zit een
# webserverconfiguratie, een cache en een CDN tussen, en elk daarvan kan de
# oude bundel blijven serveren. Dus: haal op wat de wereld ophaalt en leg het
# byte voor byte naast wat we net hebben neergezet.

log "Liveverificatie op $LIVE_URL"
REMOTE_INDEX="$WERKMAP/index.html.live"

if ! curl -fsSL --max-time 30 "$LIVE_URL/index.html" -o "$REMOTE_INDEX"; then
  echo "Kon $LIVE_URL/index.html niet ophalen. De wissel is wél gedaan;" >&2
  echo "controleer de site met de hand voordat je de backup opruimt." >&2
  exit 1
fi

if ! cmp -s "$REMOTE_INDEX" build/web/index.html; then
  echo "De live index.html verschilt van de bundel die net is neergezet." >&2
  echo "Waarschijnlijk een cache ertussen. De backup blijft staan; controleer" >&2
  echo "de site en ruim pas op als het klopt." >&2
  exit 1
fi
echo "index.html live en identiek aan de bundel."

# De SHA256SUMS-lijst reist mee in de bundel, dus die is óók op te halen. Dat
# is de sterkere controle: hij dekt elk bestand, niet alleen de pagina.
if curl -fsSL --max-time 30 "$LIVE_URL/SHA256SUMS" | cmp -s - build/web/SHA256SUMS; then
  echo "SHA256SUMS live en identiek — de hele bundel staat er goed op."
else
  echo "Let op: /SHA256SUMS wijkt af of is niet bereikbaar." >&2
  echo "De backup blijft staan." >&2
  exit 1
fi

# --- 5. Opruimen ------------------------------------------------------------
#
# Pas hier, en alleen als alles hierboven groen was. Zolang de verificatie niet
# is gelukt, is de backup het enige wat terugdraaien goedkoop houdt.

if (( KEEP_BACKUP )); then
  log "Backup blijft staan"
  echo "$WEBROOT.bak-$STAMP"
else
  log "Backup opruimen"
  ssh "${SSH_OPTS[@]}" "$HOST" bash -s -- "$WEBROOT.bak-$STAMP" <<'REMOTE'
set -euo pipefail
sudo rm -rf "$1"
REMOTE
  echo "Opgeruimd: $WEBROOT.bak-$STAMP"
fi

log "Deploy voltooid"
echo "$LIVE_URL — $DESCRIBE ($BUNDLE_SHA)"

# --- 6. DAST na deploy (adviserend) -----------------------------------------
#
# Nu de nieuwe bundel écht live staat, scant OWASP ZAP de responseheaders die
# de wereld terugkrijgt — precies het oppervlak waar de scan iets waard is (een
# lokale wegwerpserver antwoordt met zijn eigen headers, een echte host met de
# zijne). Zie `make dast` en zap/baseline.conf voor wat er zichtbaar blijft en
# waarom.
#
# Nadrukkelijk adviserend: dit mag een geslaagde deploy nooit terugdraaien. De
# wissel is hierboven al gebeurd en byte-voor-byte geverifieerd; een ZAP-
# waarschuwing is iets om met de hand te lezen, geen reden om live oud te laten
# staan. Daarom vangt de aanroep elke uitkomst op.
#
# Zonder een container-runtime (typisch in CI, waar geen docker/colima draait)
# slaat de stap zichzelf over in plaats van de deploy te laten struikelen.
# Handmatig overslaan kan met OCIDECK_DEPLOY_SKIP_DAST=1.
if [[ "${OCIDECK_DEPLOY_SKIP_DAST:-0}" == 1 ]]; then
  log "DAST overgeslagen (OCIDECK_DEPLOY_SKIP_DAST=1)"
elif ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  log "DAST overgeslagen — geen container-runtime bereikbaar"
  echo "Draai zelf 'make dast DAST_URL=$LIVE_URL' met een runtime aan (macOS: colima start)."
else
  log "DAST (OWASP ZAP baseline) op $LIVE_URL — adviserend"
  if ! make dast DAST_URL="$LIVE_URL"; then
    echo "ZAP meldde waarschuwingen of kon niet draaien — lees ze met de hand." >&2
    echo "De deploy blijft staan; dit is een advies, geen poort." >&2
  fi
fi
