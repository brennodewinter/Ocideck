#!/usr/bin/env bash
#
# De gebundelde referentiecatalogi bijwerken — en de boekhouding meteen mee.
#
# Dit script bestaat omdat de oude route doodliep. `make refresh-catalogs` haalde
# de bronnen op met een versienummer dat als variabele in de Makefile stond, en
# eindigde met de mededeling "bump the versions" — met de hand, op drie plekken.
# Dat ging precies zoals zoiets gaat:
#
#   * de Makefile stond op MASWE_DATE 2026-08-03, de catalogus op 2026-08-04 en
#     de licentietabel op weer dezelfde 2026-08-04 — drie kopieën, één ervan
#     verlopen, en wie het advies van de Makefile opvolgde zette de datum
#     terúg in de tijd;
#   * de WSTG/MASTG-bronnen werden opgehaald op de vastgezette versie, dus een
#     verversing kon een nieuwe upstreamrelease per definitie niet binnenhalen.
#     De verouderingspoort meldde "VEROUDERD", de verversing haalde braaf
#     dezelfde versie nog eens op, en de poort bleef staan waar hij stond.
#
# Dat laatste is wat een release blokkeerde op 18-08-2026: de gate zei "werk bij
# met make refresh-catalogs", en dat commando kón de melding niet wegnemen. Een
# poort met een remedie die niet werkt is geen poort maar een muur.
#
# Daarom draait dit script de lus rond:
#   1. het vraagt de poort zélf wat upstream de laatste versie is
#      (`check_reference_data.dart --json`) — dezelfde probes, dus verversing en
#      poort kunnen niet over verschillende versies praten;
#   2. het haalt díe versie op en regenereert;
#   3. het schrijft de nieuwe versie in de catalogus én in
#      docs/LICENSE_COMPLIANCE.md, want dat zijn de plekken die de poort en
#      reference_standards_test lezen;
#   4. het vertelt daarna wat er inhoudelijk is verschoven en welke test daar
#      met opzet over valt.
#
# Wat het NIET doet: beslissen. Een catalogus bijwerken verandert waar een
# rapport naar verwijst, dus de diff lees je zelf en je commit hem zelf. Het
# script neemt alleen het typwerk weg dat steeds fout ging.
#
# Gebruik:
#   scripts/refresh_catalogs.sh                  # haal op wat upstream nu is
#   WSTG_VERSION=5.0 scripts/refresh_catalogs.sh # een versie afdwingen
#   MASTG_VERSION=… / MASWE_DATE=…               # idem voor de andere twee
#
# CWE hoort hier niet bij: die bron is een zip van tientallen MB achter een
# gedateerde URL. Zie tool/build_cwe_catalog.dart.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

die() { printf '\nrefresh-catalogs: %s\n' "$1" >&2; exit 1; }
log() { printf '   %s\n' "$1"; }
head_() { printf '\n== %s ==\n' "$1"; }

for c in curl tar jq dart python3 git; do
  command -v "$c" >/dev/null 2>&1 || die "ontbrekend commando: $c"
done

# ── 1. Wat zegt de poort dat upstream heeft? ───────────────────────────────────
# Bewust vóór het downloaden. Landt er tussen probe en download een commit, dan
# is de genoteerde datum ouder dan de opgehaalde inhoud, en meldt de poort de
# volgende keer opnieuw "verouderd" — zichtbaar, en met een verversing die dan
# wél klopt. Andersom (eerst halen, dan de datum vragen) zou de nieuwere datum
# over oudere inhoud schrijven: groen licht op een bundel die achterloopt.
head_ "Upstream bevragen (dezelfde probes als de verouderingspoort)"
PROBES="$(dart run tool/check_reference_data.dart --json)" \
  || die "kon de upstreamversies niet ophalen — is er netwerk?"

# De laatste versie voor één id, of leeg als de bron niets zei.
latest_for() { printf '%s' "$PROBES" | jq -r --arg i "$1" '.[] | select(.id==$i) | .laatste // empty'; }

# De versie die nu in de catalogus staat. Die is de bron van waarheid — niet een
# variabele in de Makefile, want dat wás de kopie die verliep.
bundled_const() { # bundled_const BESTAND CONSTANTE
  sed -n "s/^const $2 = '\([^']*\)';.*/\1/p" "$1" | head -1
}

WSTG_NOW="$(bundled_const lib/services/wstg_catalog.dart wstgVersion)"
MASTG_NOW="$(bundled_const lib/services/mastg_catalog.dart mastgVersion)"
MASWE_NOW="$(bundled_const lib/services/maswe_catalog.dart masweSnapshotDate)"

# Volgorde: een expliciete override wint, dan wat upstream meldt, en als de bron
# onbereikbaar was blijft staan wat we hebben (dan regenereert dit script alleen).
WSTG_TARGET="${WSTG_VERSION:-$(latest_for wstg)}"; WSTG_TARGET="${WSTG_TARGET:-$WSTG_NOW}"
MASTG_TARGET="${MASTG_VERSION:-$(latest_for mastg)}"; MASTG_TARGET="${MASTG_TARGET:-$MASTG_NOW}"
MASWE_TARGET="${MASWE_DATE:-$(latest_for maswe)}"; MASWE_TARGET="${MASWE_TARGET:-$MASWE_NOW}"

for v in "$WSTG_TARGET" "$MASTG_TARGET" "$MASWE_TARGET"; do
  [ -n "$v" ] || die "kon geen doelversie bepalen — staat de catalogus-constante er nog?"
done

log "WSTG   $WSTG_NOW  → $WSTG_TARGET"
log "MASTG  $MASTG_NOW → $MASTG_TARGET"
log "MASWE  $MASWE_NOW → $MASWE_TARGET (momentopname: commitdatum van weaknesses/)"

# ── 2. Ophalen en regenereren ─────────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

head_ "WSTG v$WSTG_TARGET"
curl -sfL "https://raw.githubusercontent.com/OWASP/wstg/v$WSTG_TARGET/checklist/checklist.json" \
  -o "$TMP/wstg.json" \
  || die "WSTG v$WSTG_TARGET heeft geen checklist/checklist.json op die tag — controleer of de bron is verplaatst."
dart run tool/build_wstg_catalog.dart "$TMP/wstg.json" "$WSTG_TARGET"

head_ "MASTG v$MASTG_TARGET"
curl -sfL "https://github.com/OWASP/mastg/archive/refs/tags/v$MASTG_TARGET.tar.gz" | tar xz -C "$TMP" \
  || die "MASTG v$MASTG_TARGET is niet op te halen — bestaat die tag?"
dart run tool/build_mastg_catalog.dart "$TMP/mastg-$MASTG_TARGET" "$MASTG_TARGET"

head_ "MASWE $MASWE_TARGET"
curl -sfL "https://github.com/OWASP/maswe/archive/refs/heads/main.tar.gz" | tar xz -C "$TMP" \
  || die "de MASWE-branch is niet op te halen."
dart run tool/build_maswe_catalog.dart "$TMP/maswe-main" "$MASWE_TARGET"

# ── 3. De boekhouding: de constanten en de licentietabel ──────────────────────
# Dit was tot nu toe het handwerk waarvan de generatoren alleen zéíden dat het
# moest gebeuren. reference_standards_test eist dat de licentietabel dezelfde
# versies noemt als het register, dus dit is geen opsmuk: laat je het weg, dan
# staat de suite rood en gaat de release opnieuw niet door.
head_ "Versies en licentietabel bijwerken"

# record_catalog_version zet de constante in de catalogus, telt de zojuist
# gegenereerde items en schrijft versie én aantal in de licentietabel. Dat
# vervangen is minder triviaal dan het lijkt — "MITRE CWE 4.20" staat één regel
# boven "WSTG v4.2" — en daarom zit het in Dart met een test eronder, niet in een
# sed-regel hier. Zie tool/record_catalog_version.dart.
dart run tool/record_catalog_version.dart wstg "$WSTG_TARGET"
dart run tool/record_catalog_version.dart mastg "$MASTG_TARGET"
dart run tool/record_catalog_version.dart maswe "$MASWE_TARGET"

dart format lib/ >/dev/null

# ── 4. Zeggen wat er is gebeurd ───────────────────────────────────────────────
head_ "Wat er is veranderd"
CHANGED="$(git status --porcelain -- lib/services docs/LICENSE_COMPLIANCE.md | awk '{print $2}')"
if [ -z "$CHANGED" ]; then
  log "Niets. De bundel was al gelijk aan de bron."
  exit 0
fi
printf '%s\n' "$CHANGED" | sed 's/^/     /'

# Alleen-boekhouding versus inhoud. Dat verschil bepaalt wat je hierna moet doen:
# een verschoven momentopname zonder inhoudsverschil is een administratieve
# commit, een gewijzigde catalogus is een inhoudelijke wijziging met gevolgen tot
# in de vertalingen.
if printf '%s\n' "$CHANGED" | grep -qE '_data\.dart|_android\.dart|_ios\.dart'; then
  printf '\n'
  log "INHOUD gewijzigd — lees 'git diff' voordat je commit."
  log "Let op de tripdraden die hier met opzet op vallen:"
  log "  * wstg_catalog_test / mastg_catalog_test / maswe_catalog_test pinnen het"
  log "    aantal en de versie; die getallen horen mee te bewegen."
  log "  * verandert de omschrijving in reference_standards.dart, dan is dat"
  log "    l10n-tekst: 31 vertalingen (make add-l10n)."
  log "  * controleer of de licentie van de bron is gewijzigd (LICENSE_COMPLIANCE.md)."
else
  printf '\n'
  log "Alleen boekhouding: de bundel is woordelijk gelijk gebleven, alleen de"
  log "genoteerde versie/momentopname is verschoven. Commit dat als eigen commit."
fi
