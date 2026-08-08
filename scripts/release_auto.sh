#!/usr/bin/env bash
#
# Eén onbewaakte, HERSTARTBARE release van OciDeck — de automatiseringsslag van #1161.
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
#      van deze run; wordt via een stdin-pipe aan minisign gevoerd, nooit naar schijf/log).
#   De macOS-notarisatie leunt op de keychain-items op deze Mac (Developer-ID +
#   notarytool-profiel) en vraagt zelf geen wachtwoord; is de keychain vergrendeld,
#   dan faalt die stap zichtbaar (zie de fail-safe hieronder).
#
# De keten (alles na de twee prompts, onbewaakt), volgens #1161:
#   FASE 1 (lokaal, alles móét groen vóór de tag)
#     verouderingsgate (referentiedata) → scanner-pins bumpen (idempotent)
#     → bump (pubspec+kOciDeckVersion+CHANGELOG) → make sbom → make check-release
#     → make build-release → make notarize-macos → zegel verifiëren → de nieuwe
#       .app in /Applications zetten
#   PRE-FLIGHT (ná het wachtwoord, vóór elke mutatie): forge-token, mirror-remote,
#     deploy-host (ssh) en een minisign proef-tekening — alles wat later
#     onherroepelijk nodig is, faalt hier vroeg i.p.v. pas ná de tag.
#   FASE 2 (naar de CI-straat + bewaken)
#     branch+PR → poort groen → merge → tag → push origin+mirror → release-CI
#       eens per ~minuut volgen tot alle jobs klaar zijn
#   FASE 3 (verspreiden, pas ná groene CI)
#     make deploy-web (webdemo, onafhankelijk van de platform-artefacten)
#       → SHA256SUMS tekenen (minisign) + aanhangen → website-downloads-job bewaken
#     De webdemo gaat bewust EERST: ze hangt alleen aan de web-bundel, dus een
#     teken- of platformfout laat de demo nooit op de oude versie staan.
#
# HERSTARTBAAR (--resume vX.Y.Z): breekt de keten af — een time-out op de poort,
# een netwerkhik of een gefaalde upstream CI-job — dan hervat je met
# `scripts/release_auto.sh --resume vX.Y.Z` vanaf precies het punt waar het bleef.
# Het script kijkt wat er al op de forge staat (tag? gemergede PR? open PR? branch?)
# en doet alleen wat nog resteert; de dure fase 1 (bouwen/notariseren) wordt niet
# overgedaan. Elke fase-2-stap is idempotent, dus opnieuw draaien is veilig.
#
# FAIL-SAFE (elke faalstap stopt de keten, met de juiste informatie):
#   * `set -Eeuo pipefail` + een ERR-trap melden WELKE stap op WELKE regel faalde.
#   * Faalt er iets VÓÓR de tag-push, dan is er niets naar buiten gegaan: de lokale
#     release-branch wordt opgeruimd. Repareer en draai opnieuw — vers als fase 1
#     nog niet af was, of `--resume vX.Y.Z` als de PR al open stond.
#   * Faalt er iets NÁ de tag-push, dan staat de tag vast. Herstel de oorzaak en
#     maak DEZELFDE tag af met `--resume vX.Y.Z`. Alleen als een uitgebracht
#     artefact zélf fout is snijd je de VOLGENDE patch-tag; her-tag nooit (dat
#     degradeert de mirror-Windows-release tot draft en laat `windows-ophalen`
#     eeuwig wachten).
#
# --dry-run doet alle read-only stappen (versie bepalen, verouderingsgate,
# CHANGELOG-preview, plan tonen) en STOPT vóór elke mutatie.
#
# Gebruik:
#   scripts/release_auto.sh                      # menu kiest het niveau
#   scripts/release_auto.sh patch|minor|major    # niveau meegeven, sla het menu over
#   scripts/release_auto.sh --dry-run [niveau]   # toon het plan, muteer niets
#   scripts/release_auto.sh --skip-install [..]  # sla /Applications-vervanging over
#   scripts/release_auto.sh --resume vX.Y.Z      # hervat een onderbroken release

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# ── Configuratie (met env-overrides voor een andere forge/ondertekenaar) ────────
FORGE_API="${OCIDECK_FORGE_API:-https://pawprint.vigilis.online/api/v1}"
REPO_SLUG="${OCIDECK_REPO_SLUG:-LibreKAT/Ocideck}"
RELEASE_BASE_URL="${OCIDECK_RELEASE_BASE_URL:-https://pawprint.vigilis.online/${REPO_SLUG}/releases/download}"
TOKEN_KEYCHAIN_SERVICE="${OCIDECK_TOKEN_SERVICE:-forgejo-pawprint-api}"
APPLICATIONS_DIR="${OCIDECK_APPLICATIONS_DIR:-/Applications}"
# Zelfde standaard-doel als scripts/deploy_web.sh; de pre-flight toetst dat het
# bereikbaar is vóór de tag, zodat deploy-web niet ná de tag strandt.
DEPLOY_HOST="${OCIDECK_DEPLOY_HOST:-ubuntu@braniebananie.nl}"
# De poort-wachttijd (minuten). Ruim boven linux-gate (~27 min, capacity-1
# serial-runner, kan in de wachtrij staan); de oude 30 min liep daar precies op
# stuk. Zie wait_gate. Overschrijfbaar via OCIDECK_GATE_TIMEOUT_MIN.
GATE_TIMEOUT_MIN="${OCIDECK_GATE_TIMEOUT_MIN:-75}"

DRY_RUN=0
SKIP_INSTALL=0
PRINT_VERSION=0
LEVEL=""
RESUME_TAG=""   # --resume vX.Y.Z: sla fase 1+2 over, maak alleen fase 3 af

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
  # BRANCH wordt vroeg gezet (voor --resume), dus ruim alleen op wat fase 1 écht
  # lokaal aanmaakte — anders zou een fout tijdens de pre-flight ongevraagd van
  # branch wisselen.
  [ -n "$BRANCH" ] || return 0
  git rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null 2>&1 || return 0
  git checkout --quiet - 2>/dev/null || true
  git branch -D "$BRANCH" >/dev/null 2>&1 || true
}
on_err() {
  local ec=$? ln=${1:-?}
  printf '\nrelease-auto: FOUT in stap "%s" (regel %s, exit %s).\n' "$STEP" "$ln" "$ec" >&2
  if [ "$TAG_PUSHED" -eq 1 ]; then
    printf '  De tag %s is AL gepusht — de release staat vast.\n' "${TAG:-?}" >&2
    printf '  Faalde het in fase 3 (tekenen/deploy) of op een upstream CI-job, maak dan\n' >&2
    printf '  DEZELFDE tag af zodra dat hersteld is:  scripts/release_auto.sh --resume %s\n' "${TAG:-vX.Y.Z}" >&2
    printf '  Alleen als een uitgebracht artefact zelf fout is, snijd je de VOLGENDE patch-tag;\n' >&2
    printf '  verplaats deze tag nooit (dat breekt de mirror-Windows-release).\n' >&2
  else
    printf '  Er is nog niets naar buiten gegaan. De release-branch wordt opgeruimd;\n' >&2
    printf '  repareer het en draai het script opnieuw.\n' >&2
    cleanup_branch
  fi
}
trap 'on_err $LINENO' ERR

# ── Argumenten ──────────────────────────────────────────────────────────────────
RESUME=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-install) SKIP_INSTALL=1 ;;
    --print-version) PRINT_VERSION=1 ;;
    --resume) RESUME=1 ;;
    patch|minor|major) LEVEL="$arg" ;;
    v[0-9]*.[0-9]*.[0-9]*) RESUME_TAG="$arg" ;;
    -h|--help)
      sed -n '2,65p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "onbekend argument: $arg (verwacht: --dry-run, --skip-install, --resume vX.Y.Z, patch, minor of major)" ;;
  esac
done

# --resume hervat een onderbroken release vanaf het punt waar het bleef. Het kijkt
# wat er al op de forge staat (tag, gemergede PR, open PR of branch) en doet alleen
# de rest; fase 1 (bouwen/notariseren) wordt niet overgedaan. Struikelt de keten ná
# de tag-push, dan staat de tag vast en is her-taggen verboden — ook dan is de
# herstelroute DEZELFDE tag met --resume afmaken, niet de volgende snijden.
if [ "$RESUME" -eq 1 ] && [ -z "$RESUME_TAG" ]; then
  die "geef de tag mee: --resume vX.Y.Z"
fi
if [ -n "$RESUME_TAG" ] && [ "$RESUME" -eq 0 ]; then
  die "een losse tag $RESUME_TAG hoort bij --resume; bedoelde je '--resume $RESUME_TAG'?"
fi

# --print-version is een hermetische guard-toets (alleen rekenkunde uit pubspec);
# die vergt niets van de release-toolketen en mag geen menu tonen.
if [ "$PRINT_VERSION" -eq 1 ] && [ -z "$LEVEL" ]; then
  die "geef een niveau: --print-version patch|minor|major"
fi

# ── Voorwaarden ─────────────────────────────────────────────────────────────────
STEP="voorwaarden"
if [ "$PRINT_VERSION" -eq 0 ]; then
  for c in git curl jq python3 make flutter minisign codesign ditto; do need_cmd "$c"; done
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

# --print-version blijft hermetisch op de lokale pubspec (zie de guard-test). Een
# échte, verse run baseert de bump op origin/main: sta je nog op een oude,
# al-gebumpte release-branch, dan zou de menu-rekenkunde de volgende versie fout
# berekenen (bv. 0.4.0→0.5.0 terwijl 0.4.0 nog niet uit is). Vang dat vóór het menu.
if [ "$PRINT_VERSION" -eq 0 ] && [ -z "$RESUME_TAG" ]; then
  git fetch origin --quiet 2>/dev/null || true
  MAIN_VERSION="$(git show origin/main:pubspec.yaml 2>/dev/null \
    | sed -n 's/^version:[[:space:]]*\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')"
  if [ -n "$MAIN_VERSION" ] && [ "$MAIN_VERSION" != "$CUR_VERSION" ]; then
    die "pubspec staat op $CUR_VERSION maar origin/main op $MAIN_VERSION — waarschijnlijk sta je nog op een oude release-branch. Ga naar main ('git checkout main && git pull') voor een verse release, of hervat de lopende met 'scripts/release_auto.sh --resume v$CUR_VERSION'."
  fi
fi

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

if [ -n "$RESUME_TAG" ]; then
  # Resume: de tag bestaat al; leid versie/build eruit af en sla het menu over.
  TAG="$RESUME_TAG"
  NEW_VERSION="${RESUME_TAG#v}"
  NEW_BUILD="$CUR_BUILD"
else
  choose_level
  case "$LEVEL" in
    patch) NEW_VERSION="$PATCH_V" ;;
    minor) NEW_VERSION="$MINOR_V" ;;
    major) NEW_VERSION="$MAJOR_V" ;;
  esac
  NEW_BUILD=$((CUR_BUILD + 1))
  TAG="v$NEW_VERSION"
fi

# Hermetische modus voor de guard-toets: alléén de berekende tag, geen git,
# netwerk of gate. Zie test/release_auto_version_test.dart.
if [ "$PRINT_VERSION" -eq 1 ]; then
  [ -n "$LEVEL" ] || die "geef een niveau: --print-version patch|minor|major"
  printf '%s\n' "$TAG"
  exit 0
fi

# De release-branch hoort bij de tag; zowel de verse run als --resume gebruiken 'm.
BRANCH="release/$TAG"

# Een verse run mag geen bestaande tag verplaatsen. --resume mág juist doorlopen
# als de tag er al staat (dan resteert alleen fase 3) — resume_release beslist dat.
if [ -z "$RESUME_TAG" ]; then
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 \
    && die "tag $TAG bestaat al — een uitgebrachte tag verplaats je nooit; kies het volgende niveau."
fi

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
# De verouderingsgate is nu ALLEEN de referentiedata (WSTG/MASTG/MASWE/CWE …): die
# hard stoppen is terecht, want `make refresh-catalogs` verandert waar een rapport
# naar verwijst — een bewuste stap, geen automaat. De scanner-CI-pins
# (gitleaks/trufflehog/semgrep) worden NIET meer hier hard gestopt: die werkt
# fase 1 automatisch bij met `make bump-scanner-pins` (zie hieronder). Zo blokkeert
# een advisory scanner-drift geen release; catalogus-drift wel.
outdated_gate() {
  STEP="verouderingsgate"
  section "Verouderingsgate (referentiedata)"
  local co
  co="$(make catalogs-outdated 2>&1 || true)"
  if ! printf '%s' "$co" | grep -q "Reference data OK."; then
    printf '%s\n' "$co" | sed 's/^/   /'
    die "referentiedata niet actueel — werk bij met 'make refresh-catalogs' (+ de versies in lib/services/reference_standards.dart) en draai opnieuw."
  fi
  log "Referentiedata actueel."
  log "Scanner-pins worden in fase 1 automatisch bijgewerkt (bump-scanner-pins)."
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
    FASE 1  verouderingsgate → scanner-pins bumpen → bump → make sbom
            → make check-release → build + notarize → zegel → /Applications
    FASE 2  [scans-image publiceren als pins gebumpt] → PR → poort groen → merge
            → tag $TAG → push origin+mirror → CI volgen
    FASE 3  make deploy-web → SHA256SUMS tekenen + aanhangen → website-job bewaken
STEPS
  if ! changelog_has_section; then
    section "CHANGELOG-preview"
    generate_changelog_section
  fi
}

if [ -n "$RESUME_TAG" ]; then
  section "Plan — hervatten $TAG"
  log "Het script hervat $TAG vanaf het punt waar het bleef (tag, gemergede PR,"
  log "open PR of branch op origin) en doet alleen wat nog resteert; fase 1 (bouwen)"
  log "wordt niet overgedaan."
  if [ "$DRY_RUN" -eq 1 ]; then
    section "Dry-run"
    log "Niets gemuteerd. Laat --dry-run weg om de release echt te hervatten."
    exit 0
  fi
else
  show_plan
  if [ "$DRY_RUN" -eq 1 ]; then
    outdated_gate
    section "Dry-run"
    log "Niets gemuteerd. Laat --dry-run weg om de release echt te draaien."
    exit 0
  fi
fi

# ── Harde voorwaarden vóór de mutaties (falen vóór het wachtwoord) ───────────────
STEP="voorwaarden"
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "working tree niet schoon — commit eerst (nooit 'git stash' in deze repo delen)."
fi
git remote get-url mirror >/dev/null 2>&1 \
  || die "geen 'mirror'-remote — die is nodig voor de Windows-build op de spiegel."

# Een verse run mag niet bovenop een half-af gebleven release-branch bouwen: de
# branch-push zou later botsen (non-fast-forward), en een lopende poging hoort met
# --resume verder, niet met een tweede verse build. In --resume is de branch normaal.
if [ -z "$RESUME_TAG" ] && git ls-remote --exit-code origin "refs/heads/$BRANCH" >/dev/null 2>&1; then
  die "release-branch $BRANCH staat al op origin van een eerdere, afgebroken poging — maak die af met 'scripts/release_auto.sh --resume $TAG' i.p.v. een verse run."
fi

# De verouderingsgate hoort bij een échte build (fase 1); in resume bouwen we niet.
[ -n "$RESUME_TAG" ] || outdated_gate

# ── #7 Pre-flight: alles wat later onherroepelijk nodig is, nú toetsen ──────────
# Vandaag brak de keten pas ná de tag op stappen die vooraf toetsbaar waren
# (deploy-ssh, de handtekening). Deze functie faalt vóór elke mutatie.
preflight() {
  STEP="pre-flight"
  section "Pre-flight — forge, mirror, deploy-host en minisign toetsen"
  api GET "" -o /dev/null \
    || die "forge-token werkt niet tegen $REPO_SLUG (keychain '$TOKEN_KEYCHAIN_SERVICE')."
  git ls-remote mirror >/dev/null 2>&1 \
    || die "mirror-remote onbereikbaar — de Windows-build op de spiegel hangt eraan."
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$DEPLOY_HOST" true >/dev/null 2>&1 \
    || die "deploy-host $DEPLOY_HOST onbereikbaar via ssh — deploy-web zou ná de tag stranden."
  # Proef-tekening: valideert sleutel én wachtwoord vóór de lange build/tag,
  # zodat een fout wachtwoord niet pas aan het eind (na de tag) opduikt.
  local t; t="$(mktemp -d)"
  printf 'preflight\n' >"$t/probe"
  printf '%s\n' "$MINISIGN_PW" \
    | make sign-release SHA256SUMS="$t/probe" >/dev/null 2>&1 || true
  if [ ! -f "$t/probe.minisig" ]; then
    rm -rf "$t"
    die "minisign proef-tekening faalde — sleutelwachtwoord fout of sleutel ontbreekt. Niets gemuteerd."
  fi
  rm -rf "$t"
  if [ -z "$RESUME_TAG" ]; then
    # macOS-ondertekening + notarisatie zijn alleen voor fase 1 (een verse build)
    # nodig. Toets identiteit én notary-profiel nu, vóór de ~10 min build — niet pas
    # bij het inzenden (v0.1.3-rc1: notary-profiel na sessieherstart weg).
    local sigout
    if ! sigout="$(scripts/notarize_macos.sh --preflight 2>&1)"; then
      printf '%s\n' "$sigout" | sed 's/^/   /'
      die "macOS-ondertekening/notarisatie niet gereed — repareer bovenstaande en draai opnieuw. Niets gemuteerd."
    fi
    log "Pre-flight groen: forge-token, mirror, deploy-host, minisign en macOS-ondertekening kloppen."
  else
    log "Pre-flight groen: forge-token, mirror, deploy-host en minisign kloppen."
  fi
}

# ── FASE 3 — verspreiden (gedeeld door de normale keten én --resume) ────────────
phase3() {
  # #10: eerst de webdemo. Die hangt alleen aan de web-bundel, niet aan de
  # platform-artefacten of de handtekening — dus een teken- of platformfout mag
  # de demo nooit op de oude versie laten staan.
  STEP="deploy-web"
  section "Fase 3 — webversie live zetten"
  make deploy-web
  log "deploy-web klaar."

  STEP="SHA256SUMS tekenen"
  section "Fase 3 — SHA256SUMS tekenen en aanhangen"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  # `publiceren` kan nog nalopen; wacht begrensd i.p.v. meteen op 404 te sterven.
  local got=0 _
  for _ in $(seq 1 20); do
    if curl -fsSLo "$TMP/SHA256SUMS" "$RELEASE_BASE_URL/$TAG/SHA256SUMS"; then got=1; break; fi
    sleep 15
  done
  [ "$got" -eq 1 ] \
    || die "SHA256SUMS staat na wachten niet op de release voor $TAG — waarschijnlijk faalde een upstream release-job (publiceren draaide niet). Ga de release-CI na en maak daarna DEZELFDE tag af: scripts/release_auto.sh --resume $TAG."
  printf '%s\n' "$MINISIGN_PW" \
    | make sign-release SHA256SUMS="$TMP/SHA256SUMS" >/dev/null || true
  [ -f "$TMP/SHA256SUMS.minisig" ] || die "minisign leverde geen handtekening — controleer het sleutelwachtwoord."
  local rid
  rid="$(api GET "/releases/tags/$TAG" | jq -r '.id')"
  api POST "/releases/$rid/assets?name=SHA256SUMS.minisig" \
    -F "attachment=@$TMP/SHA256SUMS.minisig" -o /dev/null
  log "SHA256SUMS.minisig aangehangen aan release $TAG."

  STEP="website bewaken"
  # In --resume is er geen fase-2-snapshot; haal er dan vers een op voor deze tag.
  local snap3="${snap:-}"
  if [ -z "$snap3" ]; then
    snap3="$(api GET '/actions/tasks?limit=25' \
      | jq -r --arg ref "$TAG" '(.workflow_runs // .tasks // [])[]
          | select(.head_branch==$ref) | "\(.status)|\(.name)"' | sort -u)"
  fi
  if printf '%s\n' "$snap3" | grep -q 'Website-downloads'; then
    if printf '%s\n' "$snap3" | grep -q '^failure|Website-downloads'; then
      log "LET OP: de website-downloads-job faalde — werk de librekat.nl-downloadpagina"
      log "handmatig bij (scripts/bump-ocideck.sh $NEW_VERSION + ./publiceersite in de website-repo)."
    else
      log "Website-downloads-job groen."
    fi
  fi
}

finish() {
  STEP="klaar"
  section "Klaar"
  log "OciDeck $TAG is uitgebracht, getekend en live."
  log "Release: ${RELEASE_BASE_URL%/download}/tag/$TAG"
}

# ── FASE 2 — herbruikbare, idempotente stappen (verse run én --resume) ──────────
# Elke stap detecteert of hij al gedaan is. Zo hervat --resume een onderbroken
# release vanaf het punt waar het bleef, zonder de dure fase 1 over te doen.

# De release-PR voor deze versie, gematcht op TITEL — niet op head-branch: na een
# merge-met-branch-verwijdering wordt head.ref 'refs/pull/N/head', dus de
# branchnaam is dan weg. Echoot "nummer|state|merged|head_sha|merge_commit_sha"
# of niets als er (nog) geen PR is.
find_release_pr() {
  api GET "/pulls?state=all&limit=50" 2>/dev/null \
    | jq -r --arg t "chore(release): versie $NEW_VERSION" \
        '[.[] | select(.title == $t)][0] // empty
         | "\(.number)|\(.state)|\(.merged)|\(.head.sha)|\(.merge_commit_sha // "")"' \
    2>/dev/null || true
}

# Zorg dat er een open PR is en echoot het nummer; hergebruikt een bestaande i.p.v.
# een duplicaat te maken.
open_or_find_pr() {
  local existing; existing="$(find_release_pr)"
  if [ -n "$existing" ]; then
    printf '%s\n' "$existing" | cut -d'|' -f1
    return 0
  fi
  api POST /pulls -H 'Content-Type: application/json' \
    -d "$(jq -n --arg b main --arg h "$BRANCH" --arg t "chore(release): versie $NEW_VERSION" \
          '{base:$b, head:$h, title:$t, body:"Geautomatiseerde release-bump door scripts/release_auto.sh (#1161)."}')" \
    | jq -r '.number'
}

# Scanner-pins gebumpt → scans.yml wijst naar een image-tag die nog niet bestaat.
# Publiceer dat EERST (ci-image-scans op deze branch) vóór de PR-scan draait.
# Zie [[scans-image-eerst-publiceren]].
publish_scans_image() {
  STEP="scans-image publiceren"
  section "Fase 2 — nieuw scans-image publiceren (scanner-pins gebumpt)"
  api POST "/actions/workflows/ci-image-scans.yml/dispatches" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg r "$BRANCH" '{ref:$r}')" -o /dev/null
  log "ci-image-scans gedispatcht op $BRANCH — wachten tot het scans-image gepubliceerd is…"
  sleep 10
  local ist="" _
  for _ in $(seq 1 60); do
    ist="$(api GET '/actions/tasks?limit=20' \
      | jq -r --arg ref "$BRANCH" '[(.workflow_runs // .tasks // [])[]
          | select(.head_branch==$ref and .name=="build-publish") | .status][0] // "onbekend"')"
    case "$ist" in
      success) break ;;
      failure|cancelled) die "ci-image-scans faalde op $BRANCH — het nieuwe scans-image is niet gepubliceerd; de PR-scan zou het niet vinden." ;;
      *) sleep 20 ;;
    esac
  done
  [ "$ist" = "success" ] || die "scans-image werd niet op tijd gepubliceerd — controleer de ci-image-scans-run."
  log "Nieuw scans-image gepubliceerd."
}

# Wacht tot de PR-poort groen is. De combined status wordt pas 'success' als ÁLLE
# contexts groen zijn — en linux-gate draait de volledige suite per-PR op een
# capacity-1 serial-runner (~27 min, langer als er iets vóór in de wachtrij staat).
# Vandaar GATE_TIMEOUT_MIN (75) mét voortgang i.p.v. de oude 30 min die precies op
# linux-gate stuk liep. Curl-hikjes tellen niet als falen: dan blijven we pollen.
wait_gate() { # wait_gate SHA PR_NUMBER
  local sha="$1" pr="$2"
  STEP="poort bewaken"
  local polls=$(( GATE_TIMEOUT_MIN * 2 ))   # elke iteratie ~30s
  log "Wachten op de poort (static-gate, scans, linux-gate) — max ${GATE_TIMEOUT_MIN} min."
  log "linux-gate draait de volledige suite op de serial-runner; dat duurt het langst."
  local st="" resp="" i
  for i in $(seq 1 "$polls"); do
    resp="$(api GET "/commits/$sha/status" 2>/dev/null || true)"
    st="$(printf '%s' "$resp" | jq -r '.state' 2>/dev/null || true)"
    [ -n "$st" ] || st="pending"
    case "$st" in
      success) break ;;
      failure|error) die "poort faalde op $sha — zie PR #$pr. Niets getagd. Herstel en hervat met: scripts/release_auto.sh --resume $TAG" ;;
    esac
    if [ $(( (i - 1) % 6 )) -eq 0 ]; then
      printf '%s' "$resp" \
        | jq -r '.statuses[]? | select(.state!="success") | "     wacht op \(.context): \(.description // .state)"' \
        2>/dev/null | sort -u || true
      log "… $(( (i - 1) / 2 )) min verstreken"
    fi
    sleep 30
  done
  [ "$st" = "success" ] \
    || die "poort werd niet groen binnen ${GATE_TIMEOUT_MIN} min — zie PR #$pr. Hervat later met: scripts/release_auto.sh --resume $TAG"
  log "Poort groen."
}

# Merge de release-PR. Idempotent: al gemerged → niets doen. head_commit_id maakt de
# merge exact (schone 200 i.p.v. 405, en nooit een stale/verkeerde head).
merge_pr() { # merge_pr PR_NUMBER HEAD_SHA
  local pr="$1" head="$2" st
  STEP="mergen"
  st="$(find_release_pr)"
  if [ -n "$st" ] && [ "$(printf '%s' "$st" | cut -d'|' -f3)" = "true" ]; then
    log "PR #$pr was al gemerged."
    return 0
  fi
  api POST "/pulls/$pr/merge" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg h "$head" '{Do:"merge", head_commit_id:$h, delete_branch_after_merge:true}')" -o /dev/null
  log "PR #$pr gemergd."
}

# De merge-commit van een (gemergede) PR — daar hangt de tag aan. Precieser dan
# origin/main, dat inmiddels verder kan staan door een andere merge ertussen.
merge_commit_of_pr() { # merge_commit_of_pr PR_NUMBER
  api GET "/pulls/$1" | jq -r '.merge_commit_sha // empty'
}

# De mirror-tag (GitHub-spiegel) is een eigen faalpunt naast origin: de origin-push
# start de Forgejo-CI, maar de Windows-build op de spiegel start pas als de tag ÓÓK
# op de mirror staat (windows-ophalen dispatcht met --ref $TAG). Idempotent: staat de
# tag al op de mirror, dan doet dit niets — zo repareert --resume alsnog een mislukte
# mirror-push, óók als origin de tag al heeft (waar de vroegere early-return de
# mirror-push oversloeg en de Windows-build eeuwig liet wachten).
ensure_mirror_tag() {
  git remote get-url mirror >/dev/null 2>&1 || return 0
  if git ls-remote --exit-code mirror "refs/tags/$TAG" >/dev/null 2>&1; then
    return 0
  fi
  STEP="mirror-tag zetten"
  # Zorg dat we de tag lokaal hebben: na een verse tag bestaat hij al; op een andere
  # machine (of na opruiming) halen we 'm exact van origin.
  if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    git fetch --quiet --force origin "refs/tags/$TAG:refs/tags/$TAG" \
      || die "kon tag $TAG niet lokaal krijgen voor de mirror-push — is origin bereikbaar?"
  fi
  git push --quiet mirror "$TAG" \
    || die "mirror-push van $TAG faalde — de Windows-build op de spiegel start pas mét de mirror-tag. Herstel de mirror en hervat: scripts/release_auto.sh --resume $TAG"
  log "Tag $TAG naar de mirror gepusht — de Windows-build kan starten."
}

# Tag op de merge-commit en push naar origin + mirror. Idempotent per remote: staat
# de tag al op een remote, dan slaat die push over. origin en mirror zijn LOS: een
# geslaagde origin-push (die de release-CI start) mag niet verhullen dat de
# mirror-push faalde, en --resume moet een ontbrekende mirror-tag alsnog kunnen
# zetten. De 8-seconden-bail vóór de origin-push is het punt-van-geen-terugkeer.
tag_and_push() { # tag_and_push MERGE_SHA
  local mergesha="$1" i
  STEP="tag pushen"
  if git ls-remote --exit-code origin "refs/tags/$TAG" >/dev/null 2>&1; then
    log "Tag $TAG stond al op origin — niet opnieuw taggen."
    TAG_PUSHED=1
    ensure_mirror_tag
    return 0
  fi
  # De merge-commit is server-side gemaakt (REST-merge in merge_pr) en zit dus nog
  # niet in onze lokale objectdatabase; 'git tag -a' zou er anders op stuklopen met
  # 'fatal: bad object type' — precies waarop de v0.4.1-release brak. Haal 'm op
  # (bereikbaar via origin/main) en controleer 'm vóór de onherroepelijke stappen.
  # Dit dekt zowel de verse keten als de --resume-route: beide taggen via deze fn.
  git fetch --quiet origin \
    || die "kon origin niet fetchen vóór het taggen — is de forge bereikbaar? Hervat later met: scripts/release_auto.sh --resume $TAG"
  git cat-file -e "$mergesha^{commit}" 2>/dev/null \
    || die "merge-commit $mergesha ontbreekt lokaal na 'git fetch origin' — controleer PR en origin. Hervat met: scripts/release_auto.sh --resume $TAG"
  section "Fase 2 — tag $TAG pushen (de publieke release-keten start hierna)"
  log "Ctrl-C binnen 8 seconden om af te breken (hierna is de tag onherroepelijk)."
  for i in 8 7 6 5 4 3 2 1; do printf '\r   %s… ' "$i"; sleep 1; done; printf '\r          \n'
  git tag -d "$TAG" >/dev/null 2>&1 || true   # een stale lokale tag van een vorige poging opruimen
  git tag -a "$TAG" -m "OciDeck $TAG" "$mergesha"
  git push --quiet origin "$TAG"
  TAG_PUSHED=1   # origin heeft de tag: de release-CI is gestart, ongeacht de mirror
  log "Tag $TAG gepusht naar origin."
  ensure_mirror_tag
}

# Volg de release-CI tot alle jobs klaar zijn. Zet 'snap' (globaal) voor phase3's
# website-job-check. Een gefaalde job is een waarschuwing, geen harde stop: phase3
# wacht daarna begrensd op SHA256SUMS en stopt met de juiste raad als 'publiceren'
# echt niet groen werd.
follow_ci() {
  STEP="release-CI volgen"
  section "Fase 2 — release-CI volgen (tot alle jobs klaar zijn)"
  local prev="" running _
  snap=""
  for _ in $(seq 1 120); do
    snap="$(api GET '/actions/tasks?limit=25' 2>/dev/null \
      | jq -r --arg ref "$TAG" '(.workflow_runs // .tasks // [])[]
          | select(.head_branch==$ref) | "\(.status)|\(.name)"' 2>/dev/null | sort -u || true)"
    running="$(printf '%s\n' "$snap" | grep -cE '^(running|waiting|pending)\|' || true)"
    if [ "$snap" != "$prev" ] && [ -n "$snap" ]; then printf '%s\n' "$snap" | sed 's/^/   /'; prev="$snap"; fi
    { [ -n "$snap" ] && [ "$running" -eq 0 ]; } && break
    sleep 30
  done
  if printf '%s\n' "$snap" | grep -q '^failure|'; then
    log "LET OP: minstens één release-job faalde (zie hierboven). De tag staat vast."
    log "Herstel de upstream-job en maak DEZELFDE tag af met '--resume $TAG'; her-tag niet."
  fi
}

# --resume: hervat een onderbroken release vanaf het punt waar het bleef. Kijkt wat
# er al op de forge staat en doet alleen de rest; fase 1 (bouwen) wordt niet
# overgedaan — die zit al in de gepushte branch/PR als we hier iets vinden.
resume_release() {
  section "Hervatten — $TAG"
  if git ls-remote --exit-code origin "refs/tags/$TAG" >/dev/null 2>&1; then
    TAG_PUSHED=1
    log "Tag $TAG staat al op origin — mirror-tag borgen, dan fase 3 (deploy-web + tekenen)."
    ensure_mirror_tag
    phase3; finish; return 0
  fi
  local st num merged headsha mergesha
  st="$(find_release_pr)"
  if [ -n "$st" ]; then
    num="$(printf '%s' "$st" | cut -d'|' -f1)"
    merged="$(printf '%s' "$st" | cut -d'|' -f3)"
    headsha="$(printf '%s' "$st" | cut -d'|' -f4)"
    mergesha="$(printf '%s' "$st" | cut -d'|' -f5)"
    if [ "$merged" = "true" ]; then
      log "PR #$num is gemerged, maar de tag ontbreekt — taggen en verder."
      MERGE_SHA="$mergesha"
    else
      log "PR #$num staat open — poort afwachten, mergen en verder."
      wait_gate "$headsha" "$num"
      merge_pr "$num" "$headsha"
      MERGE_SHA="$(merge_commit_of_pr "$num")"
    fi
  elif git ls-remote --exit-code origin "refs/heads/$BRANCH" >/dev/null 2>&1; then
    headsha="$(git ls-remote origin "refs/heads/$BRANCH" | awk 'NR==1{print $1}')"
    log "Branch $BRANCH staat gepusht zonder PR — PR openen en verder."
    num="$(open_or_find_pr)"
    [ -n "$num" ] && [ "$num" != "null" ] || die "PR openen mislukte tijdens hervatten."
    wait_gate "$headsha" "$num"
    merge_pr "$num" "$headsha"
    MERGE_SHA="$(merge_commit_of_pr "$num")"
  else
    die "niets te hervatten voor $TAG (geen tag, PR of branch op origin). Draai een verse release met patch/minor/major."
  fi
  [ -n "${MERGE_SHA:-}" ] && [ "$MERGE_SHA" != "null" ] \
    || die "kon de merge-commit voor $TAG niet bepalen."
  tag_and_push "$MERGE_SHA"
  follow_ci
  phase3
  finish
}

# ── De twee prompts (de enige interactie) ───────────────────────────────────────
read_token
section "Wachtwoord"
log "Het minisign-sleutelwachtwoord wordt nu gevraagd en blijft alleen in het"
log "geheugen van deze run (voor het tekenen van SHA256SUMS, geheel aan het eind)."
MINISIGN_PW=""
read -r -s -p "  minisign-wachtwoord: " MINISIGN_PW; echo
[ -n "$MINISIGN_PW" ] || die "leeg wachtwoord — afgebroken."

# #7: faal vóór elke onherroepelijke stap; en in --resume is dit de enige gate.
preflight

# #9: --resume hervat een onderbroken release vanaf het punt waar het bleef
# (tag? gemergede PR? open PR? branch?), zonder fase 1 (bouwen) over te doen.
if [ -n "$RESUME_TAG" ]; then
  resume_release
  exit 0
fi

# ════════════════════════════ FASE 1 — lokaal ══════════════════════════════════
# BRANCH is hierboven al bepaald (release/$TAG), zodat --resume 'm ook kent.

STEP="voorbereiden"
section "Fase 1 — voorbereiden"
git fetch origin --quiet
git checkout -B "$BRANCH" origin/main --quiet
log "Branch $BRANCH van origin/main."

# Aan het begin van élke release: scanner-pins naar de laatste upstream. Idempotent
# — verandert niets als ze al kloppen. Wijzigt hij wel iets, dan committen we dat
# als eigen commit op de release-branch; fase 2 publiceert dan éérst een nieuw
# scans-image vóór de PR-scan draait. Een nieuwere scanner kan nieuwe bevindingen
# vinden — dan valt `make check-release` of de PR-scan, en stopt de keten netjes.
STEP="scanner-pins bumpen"
PINS_BUMPED=0
make bump-scanner-pins
if ! git diff --quiet; then
  PINS_BUMPED=1
  git add .github/pinned-ci-versions.json .forgejo/workflows/scans.yml .github/workflows/ci.yml
  git commit --quiet -m "ci: scanner-pins bijwerken naar de laatste upstream

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  log "Scanner-pins gebumpt en gecommit; nieuw scans-image volgt in fase 2."
else
  log "Scanner-pins waren al actueel."
fi

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

# Scanner-pins gebumpt → eerst het nieuwe scans-image publiceren, anders vindt de
# PR-scan het niet.
[ "$PINS_BUMPED" -eq 1 ] && publish_scans_image

PR_NUMBER="$(open_or_find_pr)"
[ -n "$PR_NUMBER" ] && [ "$PR_NUMBER" != "null" ] || die "PR aanmaken mislukte."
log "PR #$PR_NUMBER geopend (head $HEAD_SHA)."

wait_gate "$HEAD_SHA" "$PR_NUMBER"
merge_pr "$PR_NUMBER" "$HEAD_SHA"
MERGE_SHA="$(merge_commit_of_pr "$PR_NUMBER")"
[ -n "$MERGE_SHA" ] && [ "$MERGE_SHA" != "null" ] || die "kon de merge-commit van PR #$PR_NUMBER niet bepalen."
tag_and_push "$MERGE_SHA"
follow_ci

# ════════════════════════════ FASE 3 — verspreiden ═════════════════════════════
# Zelfde stappen als een --resume: eerst deploy-web (onafhankelijk), dan tekenen.
phase3
finish
