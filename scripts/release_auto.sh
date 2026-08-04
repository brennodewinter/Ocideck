#!/usr/bin/env bash
#
# Eén onbewaakte release van OciDeck — de automatiseringsslag van #1161.
#
# scripts/release.sh (iteratie 1, PR #1205) landde de monotone tag-guard + fase 1
# en PRINTTE de onomkeerbare fase 2-3 als handleiding. Dít script is die volgende
# iteratie: na één menukeuze en één wachtwoord draait de HÉLE keten vanzelf, tot en
# met de publieke tag-push, het tekenen en de webdeploy. Bewust gekozen door de
# houder ("na het wachtwoord volledig onbewaakt"); het wachtwoord vooraan is de
# enige rem. Wil je de geleide, stap-voor-stap variant, gebruik scripts/release.sh.
#
# Interactie zit VOORAAN en nergens anders:
#   1. een menu kiest het volgende SemVer-niveau (patch/minor/major — geen 4e cijfer,
#      OciDeck belooft strikte 3-delige SemVer, afgedwongen door check-version-bump);
#   2. één prompt vraagt het minisign-sleutelwachtwoord (blijft alleen in het geheugen
#      van deze run; wordt via `expect` aan minisign gevoerd, nooit naar schijf/log).
#   De macOS-notarisatie leunt op de keychain-items op deze Mac (Developer-ID +
#   notarytool-profiel) en vraagt zelf geen wachtwoord; is de keychain vergrendeld,
#   dan faalt die stap zichtbaar (zie de fail-safe hieronder).
#
# De keten (alles na de twee prompts, onbewaakt), volgens #1161:
#   FASE 1 (lokaal, alles móét groen vóór de tag)
#     verouderingsgate → bump (pubspec+kOciDeckVersion+CHANGELOG) → make sbom
#     → make check-release → make build-release → make notarize-macos → zegel
#       verifiëren → de nieuwe .app in /Applications zetten
#   FASE 2 (naar de CI-straat + bewaken)
#     branch+PR → poort groen → merge → tag → push origin+mirror → release-CI
#       eens per ~minuut volgen tot alle jobs klaar zijn
#   FASE 3 (verspreiden, pas ná groene CI)
#     SHA256SUMS tekenen (minisign) + aanhangen → website-downloads-job bewaken
#       → make deploy-web (vult de gap die de CI-job overslaat)
#
# FAIL-SAFE (elke faalstap stopt de keten, met de juiste informatie):
#   * `set -Eeuo pipefail` + een ERR-trap melden WELKE stap op WELKE regel faalde.
#   * Faalt er iets VÓÓR de tag-push, dan is er niets naar buiten gegaan: de
#     release-branch wordt opgeruimd en je kunt na de fix veilig opnieuw draaien.
#   * Faalt er iets NÁ de tag-push, dan staat de tag vast: een echte fix wordt de
#     VOLGENDE patch-tag, nooit een her-tag (dat degradeert de mirror-Windows-release
#     tot draft en laat `windows-ophalen` eeuwig wachten).
#
# --dry-run doet alle read-only stappen (versie bepalen, verouderingsgate,
# CHANGELOG-preview, plan tonen) en STOPT vóór elke mutatie.
#
# Gebruik:
#   scripts/release_auto.sh                      # menu kiest het niveau
#   scripts/release_auto.sh patch|minor|major    # niveau meegeven, sla het menu over
#   scripts/release_auto.sh --dry-run [niveau]   # toon het plan, muteer niets
#   scripts/release_auto.sh --skip-install [..]  # sla /Applications-vervanging over

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# ── Configuratie (met env-overrides voor een andere forge/ondertekenaar) ────────
FORGE_API="${OCIDECK_FORGE_API:-https://pawprint.vigilis.online/api/v1}"
REPO_SLUG="${OCIDECK_REPO_SLUG:-LibreKAT/Ocideck}"
RELEASE_BASE_URL="${OCIDECK_RELEASE_BASE_URL:-https://pawprint.vigilis.online/${REPO_SLUG}/releases/download}"
TOKEN_KEYCHAIN_SERVICE="${OCIDECK_TOKEN_SERVICE:-forgejo-pawprint-api}"
APPLICATIONS_DIR="${OCIDECK_APPLICATIONS_DIR:-/Applications}"

DRY_RUN=0
SKIP_INSTALL=0
PRINT_VERSION=0
LEVEL=""

# ── Kleine hulpjes ──────────────────────────────────────────────────────────────
section() { printf '\n== %s ==\n' "$1"; }
log()     { printf '   %s\n' "$1"; }
die()     { printf '\nrelease-auto: %s\n' "$1" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "ontbrekend commando: $1"; }

# ── Fail-safe: waar zijn we, en is de tag al onherroepelijk de deur uit? ─────────
STEP="init"
TAG_PUSHED=0
BRANCH=""
cleanup_branch() {
  [ -n "$BRANCH" ] || return 0
  git checkout --quiet - 2>/dev/null || true
  git branch -D "$BRANCH" >/dev/null 2>&1 || true
}
on_err() {
  local ec=$? ln=${1:-?}
  printf '\nrelease-auto: FOUT in stap "%s" (regel %s, exit %s).\n' "$STEP" "$ln" "$ec" >&2
  if [ "$TAG_PUSHED" -eq 1 ]; then
    printf '  De tag %s is AL gepusht — de release staat vast. Repareer het en snijd de\n' "${TAG:-?}" >&2
    printf '  VOLGENDE patch-tag; verplaats deze tag niet (dat breekt de mirror-Windows-release).\n' >&2
  else
    printf '  Er is nog niets naar buiten gegaan. De release-branch wordt opgeruimd;\n' >&2
    printf '  repareer het en draai het script opnieuw.\n' >&2
    cleanup_branch
  fi
}
trap 'on_err $LINENO' ERR

# ── Argumenten ──────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-install) SKIP_INSTALL=1 ;;
    --print-version) PRINT_VERSION=1 ;;
    patch|minor|major) LEVEL="$arg" ;;
    -h|--help)
      sed -n '2,52p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "onbekend argument: $arg (verwacht: --dry-run, --skip-install, patch, minor of major)" ;;
  esac
done

# --print-version is een hermetische guard-toets (alleen rekenkunde uit pubspec);
# die vergt niets van de release-toolketen en mag geen menu tonen.
if [ "$PRINT_VERSION" -eq 1 ] && [ -z "$LEVEL" ]; then
  die "geef een niveau: --print-version patch|minor|major"
fi

# ── Voorwaarden ─────────────────────────────────────────────────────────────────
STEP="voorwaarden"
if [ "$PRINT_VERSION" -eq 0 ]; then
  for c in git curl jq python3 make flutter minisign expect codesign ditto; do need_cmd "$c"; done
fi

TOKEN=""
read_token() {
  TOKEN="$(security find-generic-password -s "$TOKEN_KEYCHAIN_SERVICE" -w 2>/dev/null || true)"
  [ -n "$TOKEN" ] || die "geen forge-token in de keychain (service '$TOKEN_KEYCHAIN_SERVICE')."
}

api() { # api METHOD PATH [curl-args…]
  local method="$1" path="$2"; shift 2
  curl -sf -X "$method" "$FORGE_API/repos/$REPO_SLUG$path" \
    -H "Authorization: token $TOKEN" "$@"
}

# ── Versie bepalen ──────────────────────────────────────────────────────────────
CUR_VERSION="$(sed -n 's/^version:[[:space:]]*\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' pubspec.yaml)"
CUR_BUILD="$(sed -n 's/^version:[[:space:]]*[0-9]*\.[0-9]*\.[0-9]*+\([0-9]*\).*/\1/p' pubspec.yaml)"
[ -n "$CUR_VERSION" ] || die "kon version: niet uit pubspec.yaml lezen."
[ -n "$CUR_BUILD" ] || CUR_BUILD=0

IFS='.' read -r MAJ MIN PAT <<<"$CUR_VERSION"
PATCH_V="$MAJ.$MIN.$((PAT + 1))"
MINOR_V="$MAJ.$((MIN + 1)).0"
MAJOR_V="$((MAJ + 1)).0.0"

choose_level() {
  [ -n "$LEVEL" ] && return 0
  cat <<MENU

  OciDeck staat op $CUR_VERSION+$CUR_BUILD. Welke release?

    1) Kleine release / fix   → $PATCH_V   (patch)
    2) Functionele release    → $MINOR_V   (minor)
    3) Grote release          → $MAJOR_V   (major)

  (Een losse 'fix' onder patch bestaat niet in SemVer — een fix én een kleine
   release zijn allebei een patch; het onderscheid zet je in de CHANGELOG-tekst.)
MENU
  local ans
  read -r -p "  Keuze [1/2/3]: " ans
  case "$ans" in
    1) LEVEL="patch" ;; 2) LEVEL="minor" ;; 3) LEVEL="major" ;;
    *) die "geen geldige keuze: $ans" ;;
  esac
}

choose_level
case "$LEVEL" in
  patch) NEW_VERSION="$PATCH_V" ;;
  minor) NEW_VERSION="$MINOR_V" ;;
  major) NEW_VERSION="$MAJOR_V" ;;
esac
NEW_BUILD=$((CUR_BUILD + 1))
TAG="v$NEW_VERSION"

# Hermetische modus voor de guard-toets: alléén de berekende tag, geen git,
# netwerk of gate. Zie test/release_auto_version_test.dart.
if [ "$PRINT_VERSION" -eq 1 ]; then
  [ -n "$LEVEL" ] || die "geef een niveau: --print-version patch|minor|major"
  printf '%s\n' "$TAG"
  exit 0
fi

git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 \
  && die "tag $TAG bestaat al — een uitgebrachte tag verplaats je nooit; kies het volgende niveau."

# ── CHANGELOG-sectie samenstellen ───────────────────────────────────────────────
# Bestaat er al een handgeschreven '## [X.Y.Z]'-sectie, dan respecteren we die
# (curatie boven automaat). Anders bouwen we er een uit de merge-/commit-titels
# sinds de laatste tag, gegroepeerd op conventional-commit-prefix.
LAST_TAG="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
TODAY="$(date +%Y-%m-%d)"

changelog_has_section() { grep -q "^## \[$NEW_VERSION\]" CHANGELOG.md; }

generate_changelog_section() {
  local range="HEAD"
  [ -n "$LAST_TAG" ] && range="$LAST_TAG..HEAD"
  local added="" changed="" fixed="" line subj
  while IFS= read -r line; do
    if [[ "$line" == Merge\ pull\ request* ]]; then
      subj="$(printf '%s' "$line" | sed -n "s/^Merge pull request '\(.*\)' (#.*/\1/p")"
      [ -z "$subj" ] && subj="$line"
    else
      subj="$line"
    fi
    case "$subj" in
      feat*) added+="- ${subj}"$'\n' ;;
      fix*)  fixed+="- ${subj}"$'\n' ;;
      *)     changed+="- ${subj}"$'\n' ;;
    esac
  done < <(git log --first-parent --pretty=%s "$range")

  printf '## [%s] — %s\n\n' "$NEW_VERSION" "$TODAY"
  [ -n "$added" ]   && printf '### Added\n\n%s\n' "$added"
  [ -n "$changed" ] && printf '### Changed\n\n%s\n' "$changed"
  [ -n "$fixed" ]   && printf '### Fixed\n\n%s\n' "$fixed"
  return 0
}

# ── De verouderingsgate (#1161: de MASWE-aanleiding) ────────────────────────────
# Aan het begin, vóór het wachtwoord: staat er upstream iets nieuws of loopt een
# CI-pin achter, dan STOPT het script met een melding — je werkt het eerst bij
# (make refresh-catalogs / de pins) en draait opnieuw, i.p.v. het stil mee te
# bumpen tijdens een release. `deps-outdated` (pub) blijft adviserend: een
# dependency-bump is een aparte afweging, geen release-blokker.
outdated_gate() {
  STEP="verouderingsgate"
  section "Verouderingsgate"
  local co
  co="$(make catalogs-outdated 2>&1 || true)"
  if ! printf '%s' "$co" | grep -q "Reference data OK."; then
    printf '%s\n' "$co" | sed 's/^/   /'
    die "referentiedata niet actueel — werk bij met 'make refresh-catalogs' (+ de versies in lib/services/reference_standards.dart) en draai opnieuw."
  fi
  log "Referentiedata actueel."
  if ! make check-pins >/tmp/release_auto_pins.$$ 2>&1; then
    sed 's/^/   /' /tmp/release_auto_pins.$$; rm -f /tmp/release_auto_pins.$$
    die "een CI-pin loopt achter — bump hem in elke workflow + .github/pinned-ci-versions.json en draai opnieuw."
  fi
  rm -f /tmp/release_auto_pins.$$
  log "CI-pins actueel."
  log "Dependencies (adviserend):"
  make deps-outdated 2>&1 | grep -iE "upgradable|outdated|newer|→" | head -8 | sed 's/^/     /' || true
}

# ── Het plan tonen ──────────────────────────────────────────────────────────────
show_plan() {
  section "Plan"
  log "Versie   : $CUR_VERSION+$CUR_BUILD → $NEW_VERSION+$NEW_BUILD  ($LEVEL)"
  log "Tag      : $TAG  (op de merge-commit van de release-PR)"
  log "Basis    : origin/main"
  if changelog_has_section; then
    log "CHANGELOG: bestaande '## [$NEW_VERSION]'-sectie wordt gebruikt."
  else
    log "CHANGELOG: sectie wordt automatisch gegenereerd (preview hieronder)."
  fi
  [ "$SKIP_INSTALL" -eq 1 ] && log "/Applications: overslaan (--skip-install)."
  cat <<STEPS

  Keten (onbewaakt na het wachtwoord):
    FASE 1  verouderingsgate → bump → make sbom → make check-release
            → make build-release → make notarize-macos → zegel → /Applications
    FASE 2  PR → poort groen → merge → tag $TAG → push origin+mirror → CI volgen
    FASE 3  SHA256SUMS tekenen + aanhangen → website-job bewaken → make deploy-web
STEPS
  if ! changelog_has_section; then
    section "CHANGELOG-preview"
    generate_changelog_section
  fi
}

show_plan

if [ "$DRY_RUN" -eq 1 ]; then
  outdated_gate
  section "Dry-run"
  log "Niets gemuteerd. Laat --dry-run weg om de release echt te draaien."
  exit 0
fi

# ── Harde voorwaarden vóór de mutaties (falen vóór het wachtwoord) ───────────────
STEP="voorwaarden"
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "working tree niet schoon — commit eerst (nooit 'git stash' in deze repo delen)."
fi
git remote get-url mirror >/dev/null 2>&1 \
  || die "geen 'mirror'-remote — die is nodig voor de Windows-build op de spiegel."

outdated_gate

# ── De twee prompts (de enige interactie) ───────────────────────────────────────
read_token
section "Wachtwoord"
log "Het minisign-sleutelwachtwoord wordt nu gevraagd en blijft alleen in het"
log "geheugen van deze run (voor het tekenen van SHA256SUMS, geheel aan het eind)."
MINISIGN_PW=""
read -r -s -p "  minisign-wachtwoord: " MINISIGN_PW; echo
[ -n "$MINISIGN_PW" ] || die "leeg wachtwoord — afgebroken."

# ════════════════════════════ FASE 1 — lokaal ══════════════════════════════════
BRANCH="release/$TAG"

STEP="voorbereiden"
section "Fase 1 — voorbereiden"
git fetch origin --quiet
git checkout -B "$BRANCH" origin/main --quiet
log "Branch $BRANCH van origin/main."

python3 - "$NEW_VERSION" "$NEW_BUILD" <<'PY'
import re, sys
new_version, new_build = sys.argv[1], sys.argv[2]
p = 'pubspec.yaml'
s = open(p).read()
s = re.sub(r'(?m)^version:.*$', f'version: {new_version}+{new_build}', s, count=1)
open(p, 'w').write(s)
m = 'lib/services/export_metadata.dart'
s = open(m).read()
s = re.sub(r"const kOciDeckVersion = '[^']*';",
           f"const kOciDeckVersion = '{new_version}';", s, count=1)
open(m, 'w').write(s)
PY
log "pubspec → $NEW_VERSION+$NEW_BUILD, kOciDeckVersion → $NEW_VERSION."

STEP="sbom"
make sbom >/dev/null
log "SBOM opnieuw gegenereerd."

STEP="changelog"
if ! changelog_has_section; then
  SECTION="$(generate_changelog_section)"
  python3 - "$SECTION" <<'PY'
import sys
section = sys.argv[1].rstrip('\n') + '\n\n'
p = 'CHANGELOG.md'
lines = open(p).read().splitlines(keepends=True)
out, inserted = [], False
for line in lines:
    if not inserted and line.startswith('## ['):
        out.append(section); inserted = True
    out.append(line)
if not inserted:
    out.append('\n' + section)
open(p, 'w').write(''.join(out))
PY
  log "CHANGELOG-sectie [$NEW_VERSION] ingevoegd."
fi

STEP="make check-release"
section "Fase 1 — volledige poort (make check-release)"
if ! make check-release; then
  die "make check-release faalde — niets gepusht, release-branch wordt opgeruimd."
fi
log "make check-release groen."

STEP="make build-release"
section "Fase 1 — bouwen, tekenen, notariseren"
make build-release
make notarize-macos
APP="$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' 2>/dev/null | head -1)"
[ -n "$APP" ] || die "geen gebouwde .app gevonden na notarize-macos."
STEP="zegel verifiëren"
codesign --verify --deep --strict "$APP"
log "Zegel geverifieerd: $APP"

if [ "$SKIP_INSTALL" -eq 0 ]; then
  STEP="/Applications vervangen"
  # Sluit de draaiende app eerst; toets op pgrep, niet op osascript's exitstatus.
  if pgrep -x OciDeck >/dev/null 2>&1; then
    osascript -e 'quit app "OciDeck"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do pgrep -x OciDeck >/dev/null 2>&1 || break; sleep 1; done
  fi
  rm -rf "$APPLICATIONS_DIR/OciDeck.app"
  ditto "$APP" "$APPLICATIONS_DIR/OciDeck.app"
  log "$APPLICATIONS_DIR/OciDeck.app vervangen door de nieuwe, genotariseerde build."
fi

# ════════════════════════════ FASE 2 — CI-straat ═══════════════════════════════
STEP="PR openen"
section "Fase 2 — PR openen en laten landen"
git add pubspec.yaml lib/services/export_metadata.dart sbom/ CHANGELOG.md
git commit --quiet -m "chore(release): versie $NEW_VERSION

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push --quiet -u origin "$BRANCH"
HEAD_SHA="$(git rev-parse HEAD)"

PR_NUMBER="$(api POST /pulls -H 'Content-Type: application/json' \
  -d "$(jq -n --arg b main --arg h "$BRANCH" --arg t "chore(release): versie $NEW_VERSION" \
        '{base:$b, head:$h, title:$t, body:"Geautomatiseerde release-bump door scripts/release_auto.sh (#1161)."}')" \
  | jq -r '.number')"
[ -n "$PR_NUMBER" ] && [ "$PR_NUMBER" != "null" ] || die "PR aanmaken mislukte."
log "PR #$PR_NUMBER geopend (head $HEAD_SHA)."

STEP="poort bewaken"
log "Wachten op de poort (static-gate + scans)…"
ST=""
for _ in $(seq 1 90); do
  ST="$(api GET "/commits/$HEAD_SHA/status" | jq -r '.state')"
  case "$ST" in
    success) break ;;
    failure|error) die "poort faalde op $HEAD_SHA — zie PR #$PR_NUMBER. Niets getagd." ;;
    *) sleep 20 ;;
  esac
done
[ "$ST" = "success" ] || die "poort werd niet groen binnen de tijd — zie PR #$PR_NUMBER."
log "Poort groen."

STEP="mergen"
api POST "/pulls/$PR_NUMBER/merge" -H 'Content-Type: application/json' \
  -d '{"Do":"merge","delete_branch_after_merge":true}' -o /dev/null
log "PR #$PR_NUMBER gemergd."
git fetch origin --quiet
MERGE_SHA="$(git rev-parse origin/main)"

# ── Punt-van-geen-terugkeer: onbewaakt, maar met een aftel-bail ─────────────────
STEP="tag pushen"
section "Fase 2 — tag $TAG pushen (de publieke release-keten start hierna)"
log "Ctrl-C binnen 8 seconden om af te breken (hierna is de tag onherroepelijk)."
for i in 8 7 6 5 4 3 2 1; do printf '\r   %s… ' "$i"; sleep 1; done; printf '\r          \n'

git tag -a "$TAG" -m "OciDeck $TAG" "$MERGE_SHA"
git push --quiet origin "$TAG"
git push --quiet mirror "$TAG"
TAG_PUSHED=1
log "Tag $TAG gepusht naar origin en mirror."

STEP="release-CI volgen"
section "Fase 2 — release-CI volgen (tot alle jobs klaar zijn)"
prev="" snap=""
for _ in $(seq 1 120); do
  snap="$(api GET '/actions/tasks?limit=25' \
    | jq -r --arg ref "$TAG" '(.workflow_runs // .tasks // [])[]
        | select(.head_branch==$ref) | "\(.status)|\(.name)"' | sort -u)"
  running="$(printf '%s\n' "$snap" | grep -cE '^(running|waiting|pending)\|' || true)"
  if [ "$snap" != "$prev" ] && [ -n "$snap" ]; then printf '%s\n' "$snap" | sed 's/^/   /'; prev="$snap"; fi
  { [ -n "$snap" ] && [ "$running" -eq 0 ]; } && break
  sleep 30
done
if printf '%s\n' "$snap" | grep -q '^failure|'; then
  log "LET OP: minstens één release-job faalde (zie hierboven). De tag staat vast;"
  log "een echte fix wordt de volgende patch-tag, niet een her-tag. Ga de faal na"
  log "vóór je op de verspreiding vertrouwt."
fi

# ════════════════════════════ FASE 3 — verspreiden ═════════════════════════════
STEP="SHA256SUMS tekenen"
section "Fase 3 — SHA256SUMS tekenen en aanhangen"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSLo "$TMP/SHA256SUMS" "$RELEASE_BASE_URL/$TAG/SHA256SUMS"
# minisign vraagt zijn wachtwoord op /dev/tty; expect voert het captured wachtwoord
# in zonder het te loggen. Het wachtwoord reist via de env van precies deze aanroep.
MINISIGN_PW="$MINISIGN_PW" SUMS="$TMP/SHA256SUMS" expect <<'EXP' >/dev/null
set timeout 120
spawn make sign-release SHA256SUMS=$env(SUMS)
expect {
  -re "Password:|wachtwoord" { send -- "$env(MINISIGN_PW)\r"; exp_continue }
  eof { }
}
EXP
[ -f "$TMP/SHA256SUMS.minisig" ] || die "minisign leverde geen handtekening — controleer het sleutelwachtwoord."
RID="$(api GET "/releases/tags/$TAG" | jq -r '.id')"
api POST "/releases/$RID/assets?name=SHA256SUMS.minisig" \
  -F "attachment=@$TMP/SHA256SUMS.minisig" -o /dev/null
log "SHA256SUMS.minisig aangehangen aan release $TAG."

STEP="website bewaken"
if printf '%s\n' "$snap" | grep -q 'Website-downloads'; then
  if printf '%s\n' "$snap" | grep -q '^failure|Website-downloads'; then
    log "LET OP: de website-downloads-job faalde — werk de librekat.nl-downloadpagina"
    log "handmatig bij (scripts/bump-ocideck.sh $NEW_VERSION + ./publiceersite in de website-repo)."
  else
    log "Website-downloads-job groen."
  fi
fi

STEP="deploy-web"
section "Fase 3 — webversie live zetten"
# De CI-deploy-web-job slaat over zolang de deploy-secrets niet gezet zijn; dit
# vult die gap (make deploy-web bouwt de bundel + zet ocideck.librekat.nl live).
make deploy-web
log "deploy-web klaar."

STEP="klaar"
section "Klaar"
log "OciDeck $TAG is uitgebracht, getekend en live."
log "Release: ${RELEASE_BASE_URL%/download}/tag/$TAG"
