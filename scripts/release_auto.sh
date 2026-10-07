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
#     → momentopname referentiedata bijwerken als upstream bewoog zónder dat de
#       gegenereerde catalogus verandert (verschuift de INHOUD wél, dan stopt het)
#     → bump (pubspec+kOciDeckVersion+CHANGELOG) → make sbom → committen
#     → make check-release → make build-release → make notarize-macos
#     → zegel verifiëren → de nieuwe .app in /Applications zetten
#   PRE-FLIGHT (ná het wachtwoord, vóór elke mutatie): forge-token, mirror-remote,
#     deploy-host (ssh) en een minisign proef-tekening — alles wat later
#     onherroepelijk nodig is, faalt hier vroeg i.p.v. pas ná de tag.
#   FASE 2 (naar de CI-straat + bewaken)
#     branch+PR → poort groen → merge → tag → push origin+mirror → release-CI
#       eens per ~minuut volgen tot alle jobs klaar zijn
#   FASE 3 (verspreiden, pas ná groene CI)
#     make deploy-web (webdemo, onafhankelijk van de platform-artefacten)
#       → SHA256SUMS tekenen (minisign) + aanhangen → release publiceren
#       → website-downloads-workflow dispatchen
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
#     release-branch — mét de al vastgelegde versiebump — wordt VOLLEDIG opgeruimd,
#     zodat main schoon blijft (de bump wordt gecommit vóór de poort, niet als losse
#     werkboom-edit). Repareer en draai opnieuw — vers als fase 1 nog niet af was, of
#     `--resume vX.Y.Z` als de PR al open stond.
#   * Faalt er iets NÁ de tag-push, dan staat de tag vast. Herstel de oorzaak en
#     maak DEZELFDE tag af met `--resume vX.Y.Z`. Alleen als een uitgebracht
#     artefact zélf fout is snijd je de VOLGENDE patch-tag; her-tag nooit (dat
#     degradeert de mirror-Windows-release tot draft en laat `windows-ophalen`
#     eeuwig wachten).
#
# --dry-run doet alle read-only stappen (versie bepalen, verouderingsgate,
# CHANGELOG-preview, plan tonen) en STOPT vóór elke mutatie.
#
# --preflight gaat een stap verder en is de generale repetitie: het vraagt het
# wachtwoord, toetst álles wat de keten onderweg nodig heeft — referentiedata,
# schone én vrije werkboom, forge-token, mirror, deploy-host, minisign-sleutel en
# de macOS-ondertekening/notarisatie — en stopt dan, zonder iets te muteren.
# Bedoeld voor vlak vóór een release: de dure fouten in deze keten waren telkens
# vooraf kenbaar (een notary-profiel dat na een sessieherstart weg was, een
# deploy-host die niet antwoordde, een catalogus die achterliep), maar bleken pas
# tien minuten of een tag verderop.
#
# Gebruik:
#   scripts/release_auto.sh                      # menu kiest het niveau
#   scripts/release_auto.sh patch|minor|major    # niveau meegeven, sla het menu over
#   scripts/release_auto.sh --dry-run [niveau]   # toon het plan, muteer niets
#   scripts/release_auto.sh --preflight          # generale repetitie: toets élke
#                                                # voorwaarde, muteer niets
#   scripts/release_auto.sh --skip-install [..]  # sla /Applications-vervanging over
#   scripts/release_auto.sh --ondanks-fixes [..] # ga door langs ongemergede fix/*-
#                                                # takken en open release-blockers
#   scripts/release_auto.sh --resume vX.Y.Z      # hervat een onderbroken release
#   scripts/release_auto.sh --status vX.Y.Z      # toon waar een release staat (read-only)

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
DEPLOY_HOST="${OCIDECK_DEPLOY_HOST:-ubuntu@vps-40edd80f.vps.ovh.net}"
DEPLOY_URL="${OCIDECK_DEPLOY_URL:-https://ocideck.librekat.nl}"  # voor de liveverificatie
# De productpagina is een tweede publieke uitkomst van dezelfde release. De
# website-workflow kan groen zijn terwijl rsync naar een host gaat waar DNS niet
# naar wijst; daarom is ook hier de pagina die bezoekers krijgen de waarheid.
WEBSITE_URL="${OCIDECK_WEBSITE_URL:-https://librekat.nl/nl/ocideck/}"
# De poort-wachttijd (minuten). Ruim boven linux-gate (~27 min, capacity-1
# serial-runner, kan in de wachtrij staan); de oude 30 min liep daar precies op
# stuk. De release start de drie handmatige workflows zelf en volgt hun taken;
# sinds #2194 leveren ze bewust geen automatische PR-statuscontexten meer. Zie
# wait_gate. Overschrijfbaar via OCIDECK_GATE_TIMEOUT_MIN.
GATE_TIMEOUT_MIN="${OCIDECK_GATE_TIMEOUT_MIN:-75}"
# De wachttijd op de release-CI ná de tag (minuten). Die keten duurt ruim twee
# uur: v0.6.4 2u05 en v0.6.5 2u14 (gate ~12 → Poort ~12 → macOS ~15 naast
# Linux ~50 en web ~45 → publiceren → website). De oude vaste 60 min brak de
# v0.6.5-run midden in "Linux bouwen" af terwijl elke job liep of groen was, en
# schoof fase 3 naar --resume. Zolang een job zichtbaar draait is wachten nooit
# fout; een job die écht hangt kapt de runner zelf af (timeout 2 uur). Deze cap
# is dus een vangnet tegen een keten die nooit terminaal wordt, niet de
# verwachte duur. Overschrijfbaar via OCIDECK_RELEASE_CI_TIMEOUT_MIN.
RELEASE_CI_TIMEOUT_MIN="${OCIDECK_RELEASE_CI_TIMEOUT_MIN:-240}"

DRY_RUN=0
SKIP_INSTALL=0
PRINT_VERSION=0
PREFLIGHT_ONLY=0
IGNORE_FIXES=0  # --ondanks-fixes: bekend herstelwerk bewust buiten deze release laten
LEVEL=""
RESUME_TAG=""   # --resume vX.Y.Z: sla fase 1+2 over, maak alleen fase 3 af
BRANCH_OWNED=0  # alleen een door déze run gemaakte lokale branch mag worden opgeruimd
PENDING_APP=""  # verse build wordt pas ná een volledig publieke release geïnstalleerd

# ── Kleine hulpjes ──────────────────────────────────────────────────────────────
# RUN_T0 stempelt de start; elke sectiekop toont sindsdien verstreken tijd, zodat je
# tijdens de lange onbewaakte keten altijd ziet hoe ver je bent (en hoe lang een stap
# duurt). date is hier toegestaan (geen Workflow-context).
RUN_T0="$(date +%s)"
elapsed() { local d=$(( $(date +%s) - RUN_T0 )); printf '%d:%02d' "$((d / 60))" "$((d % 60))"; }
section() { printf '\n== [%s] %s ==\n' "$(elapsed)" "$1"; }
log()     { printf '   %s\n' "$1"; }
die()     { printf '\nrelease-auto: %s\n' "$1" >&2; cleanup_branch 2>/dev/null || true; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "ontbrekend commando: $1"; }

# ── Fail-safe: waar zijn we, en is de tag al onherroepelijk de deur uit? ─────────
STEP="init"
TAG_PUSHED=0
# Staat de release-branch al op origin, dan is een verse run geen optie meer —
# die weigert er terecht bovenop te bouwen. De juiste route is dan --resume, en
# dat hoort de foutmelding te zeggen in plaats van "draai opnieuw".
BRANCH_PUSHED=0
BRANCH=""
# De branch waar de release vandaan vertrok; cleanup_branch keert hierheen terug.
START_BRANCH="$(git branch --show-current 2>/dev/null || true)"
CLEANUP_BACK=""
cleanup_failed() {
  printf '  LET OP: de release-branch %s is NIET opgeruimd:\n' "$BRANCH" >&2
  printf '%s\n' "$1" | sed 's/^/    /' >&2
  printf '  Hij draagt de versiebump. Ruim hem met de hand op vóórdat je verder werkt —\n' >&2
  printf '  takt er een nieuwe branch van af, dan erft die de bump:\n' >&2
  printf '      git checkout %s && git branch -D %s\n' "${CLEANUP_BACK:-main}" "$BRANCH" >&2
}
rollback_release_edits() {
  [ "$BRANCH_OWNED" -eq 1 ] || return 0
  git restore --staged --worktree -- pubspec.yaml CHANGELOG.md \
    lib/services/export_metadata.dart sbom 2>/dev/null || true
  git clean -fd -- sbom >/dev/null 2>&1 || true
}
cleanup_branch() {
  # BRANCH wordt vroeg gezet (voor --resume), dus ruim alleen op wat fase 1 écht
  # lokaal aanmaakte — anders zou een fout tijdens de pre-flight ongevraagd van
  # branch wisselen.
  [ "$BRANCH_OWNED" -eq 1 ] || return 0
  [ -n "$BRANCH" ] || return 0
  git rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null 2>&1 || return 0
  rollback_release_edits
  # Hier niets stilhouden. Beide commando's stonden op '2>/dev/null || true', en
  # dat maakte de opruiming een bewering in plaats van een feit: faalt de checkout
  # (een werkboom die een bestand draagt dat tussen de branches verschilt is al
  # genoeg), dan faalt 'branch -D' gegárandeerd óók — de branch staat dan immers
  # nog uitgecheckt. De melding zei "wordt opgeruimd", de branch mét versiebump
  # bleef staan, en de eerstvolgende 'git checkout -b' takte er ongemerkt van af.
  # Zo kwam er op 15-08-2026 een versiebump in een PR terecht die een DAST-fix
  # heette. Ga terug naar de branch waar we vandaan kwamen (niet '-': dat leunt op
  # de HEAD-reflog en wijst na een tussentijdse checkout ergens anders heen).
  CLEANUP_BACK="${START_BRANCH:-main}"
  # Stond de run al ópstaand op deze release-branch — precies de nasleep van een
  # eerdere gefaalde run — dan is teruggaan naar zichzelf zinloos: de branch blijft
  # dan uitgecheckt en 'branch -D' weigert. Val in dat geval terug op main.
  [ "$CLEANUP_BACK" != "$BRANCH" ] || CLEANUP_BACK="main"
  local err
  if ! err="$(git checkout --quiet "$CLEANUP_BACK" 2>&1)"; then
    cleanup_failed "$err"
    return 0
  fi
  if ! err="$(git branch -D "$BRANCH" 2>&1)"; then
    cleanup_failed "$err"
    return 0
  fi
  printf '  Release-branch %s opgeruimd; je staat weer op %s.\n' \
    "$BRANCH" "$CLEANUP_BACK" >&2
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
  elif [ "$BRANCH_PUSHED" -eq 1 ]; then
    printf '  Er is niets onherroepelijks gebeurd: de tag staat er niet.\n' >&2
    printf '  Maar de release-branch %s staat wél op origin, dus een verse run\n' "$BRANCH" >&2
    printf '  weigert er straks bovenop te bouwen. Herstel de oorzaak en hervat:\n' >&2
    printf '      scripts/release_auto.sh --resume %s\n' "${TAG:-vX.Y.Z}" >&2
    printf '  (of gooi de branch en de PR weg als je liever helemaal opnieuw begint).\n' >&2
    cleanup_branch
  else
    printf '  Er is nog niets naar buiten gegaan; repareer het en draai het script opnieuw.\n' >&2
    # cleanup_branch meldt zélf wat het deed. Beweer hier dus niets vooraf: de
    # opruiming kán mislukken, en dan moet dát op het scherm staan.
    cleanup_branch
  fi
}
trap 'on_err $LINENO' ERR

# ── Argumenten ──────────────────────────────────────────────────────────────────
RESUME=0
STATUS=0
MODE_COUNT=0
LEVEL_COUNT=0
TAG_COUNT=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1; MODE_COUNT=$((MODE_COUNT + 1)) ;;
    --preflight) PREFLIGHT_ONLY=1; MODE_COUNT=$((MODE_COUNT + 1)) ;;
    --skip-install) SKIP_INSTALL=1 ;;
    --ondanks-fixes) IGNORE_FIXES=1 ;;
    --print-version) PRINT_VERSION=1; MODE_COUNT=$((MODE_COUNT + 1)) ;;
    --resume) RESUME=1; MODE_COUNT=$((MODE_COUNT + 1)) ;;
    --status) STATUS=1; MODE_COUNT=$((MODE_COUNT + 1)) ;;
    patch|minor|major) LEVEL="$arg"; LEVEL_COUNT=$((LEVEL_COUNT + 1)) ;;
    v*)
      if [[ "$arg" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        RESUME_TAG="$arg"; TAG_COUNT=$((TAG_COUNT + 1))
      else
        die "ongeldige release-tag '$arg' — verwacht exact vX.Y.Z zonder voorloopnullen of suffix."
      fi
      ;;
    -h|--help)
      # Alles wat na de shebang aan commentaar staat, tot de eerste code-regel.
      # Stond hier een geteld bereik ('2,66p'), en dat klopte niet meer zodra de
      # kop groeide — dan kreeg je de handleiding half.
      awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' \
        "${BASH_SOURCE[0]}"
      exit 0 ;;
    *) die "onbekend argument: $arg (verwacht: --dry-run, --preflight, --skip-install, --ondanks-fixes, --status vX.Y.Z, --resume vX.Y.Z, patch, minor of major)" ;;
  esac
done

[ "$MODE_COUNT" -le 1 ] \
  || die "combineer niet meerdere modi (--dry-run, --preflight, --print-version, --resume, --status)."
[ "$LEVEL_COUNT" -le 1 ] || die "geef precies één niveau: patch, minor of major."
[ "$TAG_COUNT" -le 1 ] || die "geef precies één release-tag."
[ -z "$RESUME_TAG" ] || [ -z "$LEVEL" ] \
  || die "combineer een release-tag niet met patch, minor of major."
case "$GATE_TIMEOUT_MIN:$RELEASE_CI_TIMEOUT_MIN" in
  *[!0-9:]*|0:*|*:0|:*) die "wachttijden moeten positieve gehele minuten zijn." ;;
esac

# --resume hervat een onderbroken release vanaf het punt waar het bleef. Het kijkt
# wat er al op de forge staat (tag, gemergede PR, open PR of branch) en doet alleen
# de rest; fase 1 (bouwen/notariseren) wordt niet overgedaan. Struikelt de keten ná
# de tag-push, dan staat de tag vast en is her-taggen verboden — ook dan is de
# herstelroute DEZELFDE tag met --resume afmaken, niet de volgende snijden.
if [ "$RESUME" -eq 1 ] && [ -z "$RESUME_TAG" ]; then
  die "geef de tag mee: --resume vX.Y.Z"
fi
if [ "$STATUS" -eq 1 ] && [ -z "$RESUME_TAG" ]; then
  die "geef de tag mee: --status vX.Y.Z"
fi
if [ -n "$RESUME_TAG" ] && [ "$RESUME" -eq 0 ] && [ "$STATUS" -eq 0 ]; then
  die "een losse tag $RESUME_TAG hoort bij --resume of --status; bedoelde je '--resume $RESUME_TAG'?"
fi

# --print-version is een hermetische guard-toets (alleen rekenkunde uit pubspec);
# die vergt niets van de release-toolketen en mag geen menu tonen.
if [ "$PRINT_VERSION" -eq 1 ] && [ -z "$LEVEL" ]; then
  die "geef een niveau: --print-version patch|minor|major"
fi

# ── Voorwaarden ─────────────────────────────────────────────────────────────────
STEP="voorwaarden"
if [ "$PRINT_VERSION" -eq 0 ]; then
  for c in git curl jq sed awk grep sort cmp minisign security; do need_cmd "$c"; done
  if [ "$STATUS" -eq 0 ]; then
    for c in python3 make ssh; do need_cmd "$c"; done
  fi
  if [ "$STATUS" -eq 0 ] && [ -z "$RESUME_TAG" ]; then
    for c in flutter codesign ditto; do need_cmd "$c"; done
  fi
fi

TOKEN=""
read_token() {
  TOKEN="$(security find-generic-password -s "$TOKEN_KEYCHAIN_SERVICE" -w 2>/dev/null || true)"
  [ -n "$TOKEN" ] || die "geen forge-token in de keychain (service '$TOKEN_KEYCHAIN_SERVICE')."
}

api() { # api METHOD PATH [curl-args…]
  local method="$1" path="$2"; shift 2
  # Alleen idempotente GET's herproberen bij een transiënte curl-fout (netwerkhik,
  # 5xx): een losse hik hoort geen release af te breken. POST/DELETE (merge, dispatch,
  # upload) zijn niet idempotent en worden NOOIT herhaald.
  local tries=1 i rc=0
  [ "$method" = "GET" ] && tries=4
  for i in $(seq 1 "$tries"); do
    # --config via een pipe houdt het token uit de procesargumenten (`ps`).
    curl -sf --connect-timeout 10 --max-time 90 -X "$method" \
      --config <(printf 'header = "Authorization: token %s"\n' "$TOKEN") \
      "$FORGE_API/repos/$REPO_SLUG$path" "$@" && return 0
    rc=$?
    [ "$i" -lt "$tries" ] && sleep "$(( i * 2 ))"
  done
  return "$rc"
}

# De nieuwste workflowrun van één workflow op één ref, als "id|status".
# /actions/runs kent een run zodra hij bestaat — ook queued of nog zonder
# runner-taak. Dat is precies wat /actions/tasks niet kan: die toont alleen
# toegewezen taken en maakte de v0.6.14-run 9655 onzichtbaar (#2294).
# Leeg antwoord = geen run; exit≠0 = de API was onleesbaar, en onbekend is
# niet afwezig — aanroepers behandelen dat apart.
latest_workflow_run() { # latest_workflow_run WORKFLOW_ID REF
  api GET "/actions/runs?limit=50&workflow_id=$1" \
    | jq -r --arg ref "$2" --arg wf "$1" '
        [.workflow_runs[]? | select(.workflow_id == $wf) | select(.prettyref == $ref)]
        | sort_by(.id) | .[-1] // empty | "\(.id)|\(.status)"'
}

# Eén bron voor de actuele toestand van deze tag. Zowel de gewone route als
# --resume en fase 3 gebruiken hem, zodat geen van die paden een nog schrijvende
# release-run voor "klaar" kan aanzien.
#
# De snapshot komt uit één run — de nieuwste release.yml-run op de tag — en de
# jobs worden per poging ontleed (de hoogste attempt per jobnaam wint). Zo kan
# een oude complete poging nooit met een nieuwe gedeeltelijke samensmelten tot
# een nep-groene keten.
#
# Uitvoer: één regel per job als "status|naam|job-id". Heeft de run nog geen
# zichtbare jobs (zojuist gedispatcht), dan één regel "status|run|run-id" met
# de runstatus — een wachtende run is actief, niet afwezig.
release_ci_snapshot() {
  local run jobs
  run="$(latest_workflow_run release.yml "$TAG")" || return 2
  [ -n "$run" ] || return 0
  jobs="$(api GET "/actions/runs/${run%%|*}/jobs" \
    | jq -r 'group_by(.name) | map(sort_by([.attempt // 0, .id]) | .[-1])[]
        | "\(.status)|\(.name)|\(.id)"')" \
    || return 2
  if [ -n "$jobs" ]; then
    printf '%s\n' "$jobs"
  else
    printf '%s|run|%s\n' "${run#*|}" "${run%%|*}"
  fi
}

# Zijn er niet-terminale jobs? Alles buiten de terminale verzameling telt als
# actief — ook een toestand die deze Forgejo-versie nog niet kende. Een
# onbekende status mag nooit stil "klaar" betekenen.
release_ci_is_active() { # release_ci_is_active SNAPSHOT
  [ -n "$1" ] || return 1
  printf '%s\n' "$1" | grep -qvE '^(success|failure|cancelled|skipped|error)\|'
}

# Een nog lopende keten hoeft zijn laatste job nog niet te hebben bereikt —
# eindigt een eerdere job rood, dan kan de vervolgjob afwezig of geblokkeerd
# zijn. De laatste job van release.yml is daarom het bewijs dat de hele keten
# is doorlopen; zonder die marker mag "nul actieve jobs" nooit als "release
# klaar" tellen.
release_ci_completion_seen() { # release_ci_completion_seen SNAPSHOT
  local snapshot="$1"
  # Groen is pas compleet na de laatste job. Dat is sinds #2311 'Release
  # publiceren': de website-downloads-job verhuisde naar een eigen workflow die
  # pas ná de (lokale) publicatie dispatcht — hij hoort dus niet meer in deze
  # snapshot. Een fout kan die laatste job juist blokkeren; accepteer die daarom
  # alleen wanneer de falende taak herkenbaar uit release.yml komt. De losse
  # ci.yml-job heet simpelweg `gate` en telt hier uitdrukkelijk niet mee.
  printf '%s\n' "$snapshot" \
    | grep -qE '^(success|failure|cancelled|skipped|error)\|Release publiceren(\|([0-9]+|null))?$' \
    && return 0
  printf '%s\n' "$snapshot" \
    | grep -qE '^(failure|cancelled|skipped|error)\|(Poort \(vóór het bouwen\)|Web bouwen|Webversie live zetten|Linux bouwen|macOS bouwen|Windows ophalen van de spiegel|Release publiceren)(\|([0-9]+|null))?$'
}

release_ci_has_failure() { # release_ci_has_failure SNAPSHOT
  printf '%s\n' "$1" | grep -qE '^(failure|cancelled|skipped|error)\|'
}

# De golden-poort op de tag zelf. macos-gate draait sinds #2321 óók op v*-tags,
# in de eigen concurrencygroep macos-gate-refs/tags/vX.Y.Z die geen main-push
# deelt — daarvoor hing het golden-bewijs van een releasecommit aan een main-run
# die elke volgende merge kon annuleren (run 5477, v0.6.14). Deze helper volgt
# exact de tag-run via prettyref; een gerichte herstart komt onder dezelfde
# run-id met een hogere attempt terug en wordt zo gewoon meegevolgd.
macos_gate_tag_status() { # → "status|run-id" of leeg; exit≠0 als de API hapert
  local run
  run="$(latest_workflow_run macos-gate.yml "$TAG")" || return 2
  [ -n "$run" ] || return 0
  printf '%s\n' "${run#*|}|${run%%|*}"
}

expected_release_assets() {
  printf '%s\n' \
    "ocideck-web-$NEW_VERSION.tar.gz" \
    "ocideck-linux-x64-$NEW_VERSION.tar.gz" \
    "ocideck-linux-amd64-$NEW_VERSION.deb" \
    "ocideck-linux-x86_64-$NEW_VERSION.rpm" \
    "ocideck-linux-x86_64-$NEW_VERSION.AppImage" \
    "ocideck-macos-$NEW_VERSION.zip" \
    "ocideck-windows-x64-$NEW_VERSION.zip" \
    "ocideck-windows-x64-setup-$NEW_VERSION.exe" \
    "ocideck-$NEW_VERSION.cdx.json" \
    "ocideck-$NEW_VERSION.spdx.json"
}

verify_release_manifest() { # verify_release_manifest FILE
  local file="$1" actual expected
  awk 'NF != 2 || $1 !~ /^[[:xdigit:]]{64}$/ || $2 !~ /^\.\/[A-Za-z0-9._+-]+$/ { exit 1 }
       { print substr($2, 3) }' "$file" >"$file.names" || return 1
  [ "$(wc -l <"$file.names" | tr -d ' ')" -eq "$(sort -u "$file.names" | wc -l | tr -d ' ')" ] \
    || return 1
  actual="$(sort "$file.names")"
  expected="$(expected_release_assets | sort)"
  rm -f "$file.names"
  [ "$actual" = "$expected" ]
}

release_asset_url() { # release_asset_url RID NAAM → browser_download_url of leeg
  api GET "/releases/$1/assets" 2>/dev/null \
    | jq -r --arg n "$2" '.[] | select(.name==$n) | .browser_download_url // empty' \
      2>/dev/null | head -n 1
}

# Draft-assets zijn publiek niet bereikbaar (#2311); met het repo-token wel.
# Zo kan fase 3 de release lezen en verifiëren terwijl hij nog draft is.
download_release_asset() { # download_release_asset URL DEST
  curl -fsSL --connect-timeout 10 --max-time 60 \
    -H "Authorization: token $TOKEN" -o "$2" "$1" 2>/dev/null
}

website_has_expected_downloads() {
  local html asset
  html="$(curl -fsSL --connect-timeout 10 --max-time 20 "$WEBSITE_URL" 2>/dev/null)" || return 1
  while IFS= read -r asset; do
    printf '%s' "$html" | grep -Fq "/releases/download/$TAG/$asset" || return 1
  done < <(expected_release_assets \
    | grep -E 'linux-amd64.*\.deb$|linux-x86_64.*\.AppImage$|macos-.*\.zip$|windows-x64-setup-.*\.exe$')
}

assert_release_ci_terminal() {
  local snap_rc=0
  snap="$(release_ci_snapshot)" || snap_rc=$?
  if [ "$snap_rc" -ne 0 ]; then
    die "de release-CI-status voor $TAG is onleesbaar (Forgejo-API-fout) — onbekend is niet afwezig; teken niet zolang de publieke toestand niet bewezen is."
  fi
  if [ -z "$snap" ]; then
    die "geen release-run voor $TAG gevonden — teken niet zolang de publieke toestand niet bewezen is."
  fi
  if release_ci_is_active "$snap"; then
    die "release-CI voor $TAG is nog actief — wacht tot alle jobs terminaal zijn en hervat daarna met: scripts/release_auto.sh --resume $TAG"
  fi
  release_ci_completion_seen "$snap" \
    || die "release-CI voor $TAG heeft de laatste job nog niet bereikt — een afhankelijke vervolgjob kan nog onzichtbaar wachten; hervat later met: scripts/release_auto.sh --resume $TAG"
}

mark() { if [ "$1" -eq 1 ]; then printf '   [x] %s\n' "$2"; else printf '   [ ] %s\n' "$2"; fi; }

# Wat er live staat, vraag je aan de site — niet aan een jobstatus.
#
# `version.json` reist mee in de webbundel en noemt de versie die er op dat
# moment op $DEPLOY_URL staat. Dat is het enige antwoord dat niet kan liegen:
# het meet de uitkomst, niet een stap die de uitkomst zou moeten bereiken.
#
# Staat bewust hier, vóór cmd_status: `--status` roept hem aan op regel ~512 en
# bash zoekt een functie pas op het moment van aanroepen. Stond hij bij fase 3
# (regel ~860), dan was hij daar nog niet gedefinieerd — en zocht bash een
# programma met die naam. Op de MacPorts-bash van deze machine eindigt dat niet
# in "command not found" maar in een segfault in CoreFoundation.
live_web_version() { # → de versie op de live demo, leeg als die niet te lezen is
  curl -fsSL --connect-timeout 10 --max-time 20 "$DEPLOY_URL/version.json" 2>/dev/null \
    | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
}

# Lees de versie uit de release-downloadlinks die bezoekers daadwerkelijk op
# librekat.nl krijgen. Een groene job bewijst alleen dat het publicatiescript met
# status 0 eindigde; bij een verkeerde deployhost of achterlopende DNS kan dat
# nog steeds de verkeerde website zijn (zoals bij v0.6.11 t/m v0.6.13).
live_website_version() {
  curl -fsSL --connect-timeout 10 --max-time 20 "$WEBSITE_URL" 2>/dev/null \
    | awk 'match($0, /releases\/download\/v[0-9]+\.[0-9]+\.[0-9]+/) {
        version = substr($0, RSTART, RLENGTH)
        sub(/^.*\/v/, "", version)
        print version
        exit
      }'
}

# --status vX.Y.Z: read-only overzicht van waar een release staat — geen mutatie,
# geen wachtwoord, geen poort. Beantwoordt "waar ben ik?" na een afbreking en zegt
# wat --resume nu zou doen. Leunt op TAG/NEW_VERSION/BRANCH die hierboven al bepaald
# zijn, en op api(). Elke sonde faalt zacht (|| true): een hik mag geen fout melden.
cmd_status() {
  read_token
  section "Status van $TAG"
  local has_branch=0 has_pr=0 pr_merged=0 has_tag_o=0 has_mirror=0 has_tag_m=0
  local has_rel=0 has_sums=0 manifest_complete=0 has_sig=0 sig_valid=0 web_live=0 website_live=0 ci_stable=0
  local live="" website_version=""
  local prnum="" prstate="" pr rel assets status_snap

  git ls-remote --exit-code origin "refs/heads/$BRANCH" >/dev/null 2>&1 && has_branch=1

  pr="$(api GET "/pulls?state=all&limit=50" 2>/dev/null \
    | jq -r --arg t "chore(release): versie $NEW_VERSION" \
        '[.[] | select(.title == $t)][0] // empty | "\(.number)|\(.state)|\(.merged)"' \
    2>/dev/null || true)"
  if [ -n "$pr" ]; then
    has_pr=1
    prnum="$(printf '%s' "$pr" | cut -d'|' -f1)"
    prstate="$(printf '%s' "$pr" | cut -d'|' -f2)"
    [ "$(printf '%s' "$pr" | cut -d'|' -f3)" = "true" ] && pr_merged=1
  fi

  git ls-remote --exit-code origin "refs/tags/$TAG" >/dev/null 2>&1 && has_tag_o=1
  git remote get-url mirror >/dev/null 2>&1 && has_mirror=1
  [ "$has_mirror" -eq 1 ] && git ls-remote --exit-code mirror "refs/tags/$TAG" >/dev/null 2>&1 && has_tag_m=1

  rel="$(api GET "/releases/tags/$TAG" 2>/dev/null || true)"
  [ -n "$(printf '%s' "$rel" | jq -r '.id // empty' 2>/dev/null || true)" ] && has_rel=1
  if [ "$has_rel" -eq 1 ]; then
    assets="$(printf '%s' "$rel" | jq -r '.assets[]?.name' 2>/dev/null || true)"
    printf '%s\n' "$assets" | grep -qx 'SHA256SUMS' && has_sums=1
    printf '%s\n' "$assets" | grep -qx 'SHA256SUMS.minisig' && has_sig=1
    if [ "$has_sums" -eq 1 ] && [ "$has_sig" -eq 1 ]; then
      local verify_tmp
      verify_tmp="$(mktemp -d)"
      if curl -fsSL --connect-timeout 10 --max-time 30 -o "$verify_tmp/SHA256SUMS" "$RELEASE_BASE_URL/$TAG/SHA256SUMS" 2>/dev/null \
          && curl -fsSL --connect-timeout 10 --max-time 30 -o "$verify_tmp/SHA256SUMS.minisig" "$RELEASE_BASE_URL/$TAG/SHA256SUMS.minisig" 2>/dev/null \
          && minisign -Vm "$verify_tmp/SHA256SUMS" \
            -x "$verify_tmp/SHA256SUMS.minisig" -p "$ROOT_DIR/minisign.pub" >/dev/null 2>&1 \
          && verify_release_manifest "$verify_tmp/SHA256SUMS"; then
        manifest_complete=1
        sig_valid=1
      fi
      rm -rf "$verify_tmp"
    fi
  fi
  local snap_rc=0
  status_snap="$(release_ci_snapshot)" || snap_rc=$?
  if [ "$snap_rc" -eq 0 ] && [ -n "$status_snap" ] \
      && ! release_ci_is_active "$status_snap" \
      && release_ci_completion_seen "$status_snap" \
      && ! release_ci_has_failure "$status_snap"; then
    ci_stable=1
  fi

  # De webdemo hoort bij de release en werd tot v0.6.6 nergens gemeten: het
  # advies zei "controleer nog de live web-versie", en dat deed niemand.
  live="$(live_web_version || true)"
  [ "$live" = "$NEW_VERSION" ] && web_live=1
  website_version="$(live_website_version || true)"
  website_has_expected_downloads && website_live=1

  local prdesc
  if [ "$has_pr" -eq 0 ]; then prdesc="release-PR aangemaakt"
  elif [ "$pr_merged" -eq 1 ]; then prdesc="release-PR #$prnum gemerged"
  else prdesc="release-PR #$prnum ($prstate — nog niet gemerged)"; fi

  # De release-branch wordt bij de merge verwijderd. Ná de merge is "weg" dus de
  # goede afloop en "staat er nog" de afwijking; daarvóór is hij juist
  # voortgang. Eén vaste regel liet op een afgeronde release altijd een leeg
  # vakje achter — een open punt dat geen open punt was.
  if [ "$pr_merged" -eq 0 ]; then
    mark "$has_branch" "release-branch $BRANCH op origin"
  elif [ "$has_branch" -eq 1 ]; then
    mark 0 "release-branch $BRANCH staat nog op origin (de merge hoort 'm te verwijderen)"
  else
    mark 1 "release-branch $BRANCH opgeruimd bij de merge"
  fi
  mark "$pr_merged" "$prdesc"
  mark "$has_tag_o" "tag $TAG op origin (start de Forgejo-release-CI)"
  if [ "$has_mirror" -eq 1 ]; then
    mark "$has_tag_m" "tag $TAG op mirror (start de Windows-build)"
  else
    mark 0 "mirror-remote beschikbaar (nodig voor de Windows-build)"
  fi
  mark "$has_rel" "release aangemaakt op de forge"
  if [ "$snap_rc" -ne 0 ]; then
    mark 0 "release-CI status onleesbaar (Forgejo-API-fout — onbekend is niet afwezig)"
  else
    mark "$ci_stable" "release-CI terminaal groen; geen actieve schrijver"
  fi
  # De golden-poort op de tag (#2321): geen releasejob, maar wél de enige plek
  # waar de goldens van de uitgebrachte commit bewezen worden. Een afwezige of
  # geannuleerde tagrun mag niet onzichtbaar blijven.
  local mgate="" mgate_ok=0
  mgate="$(macos_gate_tag_status || true)"
  if [ -z "$mgate" ]; then
    mark 0 "macos-gate (goldens) op $TAG: geen tagrun gevonden"
  else
    [ "${mgate%%|*}" = "success" ] && mgate_ok=1
    mark "$mgate_ok" "macos-gate (goldens) op $TAG: ${mgate%%|*} (run ${mgate##*|})"
  fi
  mark "$has_sums" "SHA256SUMS aanwezig (van de publiceren-job)"
  mark "$manifest_complete" "SHA256SUMS bevat exact alle verwachte releasebestanden"
  mark "$sig_valid" "publieke SHA256SUMS.minisig cryptografisch geldig"
  local webdesc="webdemo op $DEPLOY_URL draait $NEW_VERSION"
  [ "$web_live" -eq 1 ] || webdesc="$webdesc (nu: ${live:-niet te lezen})"
  mark "$web_live" "$webdesc"
  local websitedesc="downloadpagina op $WEBSITE_URL verwijst naar $TAG"
  [ "$website_live" -eq 1 ] \
    || websitedesc="$websitedesc (nu: ${website_version:+v$website_version}${website_version:-niet te lezen})"
  mark "$website_live" "$websitedesc"

  section "Advies"
  if [ "$has_tag_o" -eq 1 ] && [ "$ci_stable" -eq 1 ] && [ "$manifest_complete" -eq 1 ] && [ "$sig_valid" -eq 1 ] && [ "$web_live" -eq 1 ] \
      && [ "$website_live" -eq 1 ] && [ "$has_mirror" -eq 1 ] && [ "$has_tag_m" -eq 1 ]; then
    log "De release is publiek compleet: artefacten, handtekening, webdemo en downloadpagina kloppen."
    log "Release: ${RELEASE_BASE_URL%/download}/tag/$TAG"
  elif [ "$has_tag_o" -eq 1 ] && [ "$ci_stable" -eq 1 ] && [ "$manifest_complete" -eq 1 ] && [ "$sig_valid" -eq 1 ] && [ "$web_live" -eq 1 ] \
      && [ "$website_live" -eq 0 ]; then
    log "Alles is uitgebracht en getekend, maar de publieke downloadpagina toont ${website_version:+v$website_version}${website_version:-geen leesbare versie} in plaats van $TAG."
    log "Controleer de deployhost/DNS en publiceer de website opnieuw; --resume controleert daarna de publieke pagina."
  elif [ "$has_tag_o" -eq 1 ] && [ "$ci_stable" -eq 1 ] && [ "$manifest_complete" -eq 1 ] && [ "$sig_valid" -eq 1 ] && [ "$web_live" -eq 0 ]; then
    log "Alles is uitgebracht en getekend, maar de webdemo draait ${live:-een onleesbare versie} in plaats van $NEW_VERSION."
    log "Zet hem live met:  scripts/release_auto.sh --resume $TAG"
    log "(die checkt de tag zelf uit; met de hand is het:  git checkout $TAG && make deploy-web)"
  elif [ "$has_tag_o" -eq 1 ]; then
    log "De tag staat vast, maar de release is nog niet af (mirror-tag / tekenen / deploy)."
    log "Maak DEZELFDE tag af met:  scripts/release_auto.sh --resume $TAG"
  elif [ "$has_pr" -eq 1 ] || [ "$has_branch" -eq 1 ]; then
    log "Er is een release-PR of -branch, maar nog geen tag."
    log "Hervat met:  scripts/release_auto.sh --resume $TAG"
  else
    log "Geen lopende release voor $TAG gevonden."
    log "Start een verse release met:  scripts/release_auto.sh patch|minor|major"
  fi
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
  # --preflight maakt niets aan; het niveau bepaalt daar alleen de naam in de
  # uitvoer. Een menu zou daar een vraag stellen die geen gevolg heeft.
  if [ "$PREFLIGHT_ONLY" -eq 1 ]; then LEVEL="patch"; return 0; fi
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

# Een op main gemergede versiebump zonder tag is een half afgemaakte release. Een
# volgende patch starten zou die toestand overslaan en onherstelbaar verhullen.
if [ -z "$RESUME_TAG" ]; then
  current_tag_refs="$(git ls-remote origin "refs/tags/v$CUR_VERSION" "refs/tags/v$CUR_VERSION^{}")" \
    || die "kon niet bewijzen dat de huidige main-versie v$CUR_VERSION is uitgebracht."
  [ -n "$current_tag_refs" ] \
    || die "origin/main draagt $CUR_VERSION, maar tag v$CUR_VERSION ontbreekt — rond eerst die release af met --resume v$CUR_VERSION."
fi

# --status vX.Y.Z: alleen rapporteren waar de release staat, dan stoppen. Read-only,
# dus vóór het plan, de voorwaarden, het wachtwoord en de pre-flight.
if [ "$STATUS" -eq 1 ]; then
  cmd_status
  exit 0
fi

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
# Aan het begin, vóór het wachtwoord. Wat er daarna gebeurt hangt af van wát er
# verouderd is, en dat onderscheid is de hele functie.
#
# Een gebundelde catalogus kan om twee heel verschillende redenen achterlopen:
#   * de **momentopname** is opgeschoven — upstream heeft iets aan de bron gedaan,
#     maar wat wij eruit genereren komt er woordelijk hetzelfde uit. Dan is de
#     afwijking pure boekhouding: een datum in een constante en een regel in de
#     licentietabel. Daar hoeft geen mens naar te kijken, en fase 1 werkt dat
#     vanzelf bij (zie refresh_snapshot) — precies zoals ze de scanner-pins
#     bijwerkt. Het wordt een eigen commit op de release-branch, dus het is
#     achteraf gewoon te zien en terug te draaien.
#   * de **inhoud** is verschoven — er zijn zwakheden of tests bij gekomen,
#     hernoemd of vervallen. Dat verandert waar een rapport naar verwijst, kan
#     vertaalde tekst raken en trekt de vastgepinde aantallen in de tests eronder
#     vandaan. Dat is een beslissing, geen automatisme, en daar stopt de keten.
#
# Het verschil is pas te zien ná het verversen, en daarom valt die splitsing in
# fase 1 en niet hier. Hier bepalen we alleen of verversen überhaupt kán helpen:
# `scripts/refresh_catalogs.sh` kent WSTG, MASTG en MASWE. Loopt CWE of MIAUW
# achter, dan is er niets automatisch aan en stopt het hier meteen — met de
# route die bij díe bron hoort, in plaats van een algemeen advies dat voor deze
# bron niet werkt.
#
# `deps-outdated` (pub) blijft adviserend: een dependency-bump is een aparte
# afweging, geen release-blokker. Scanner-CI-pins idem — die werkt fase 1 bij.

# De catalogi die fase 1 mag verversen. Buiten deze drie is er geen generator.
REFRESHABLE_CATALOGS="wstg mastg maswe"
# Wordt door outdated_gate gevuld met de id's die fase 1 moet verversen.
CATALOGS_STALE=""

# De machineleesbare stand van de bronnen. Eén plek, zodat de gate en de
# nacontrole in fase 1 niet los van elkaar kunnen gaan afwijken — en zodat een
# test hem kan vervangen zonder het netwerk op te gaan.
catalogs_probe_json() { dart run tool/check_reference_data.dart --json 2>/dev/null; }

# De id's van niet-adviserende bronnen die upstream hebben zien bewegen.
stale_catalog_ids() { # stale_catalog_ids JSON
  printf '%s' "$1" \
    | jq -r '.[] | select(.status=="verouderd" and .adviserend==false) | .id' 2>/dev/null
}

# Per bron de route die er écht bij hoort. Een algemene regel ("draai
# refresh-catalogs") is hier erger dan geen regel: voor CWE en MIAUW doet dat
# commando niets, en dan stuur je iemand een middag het bos in.
handmatige_route() { # handmatige_route ID
  case "$1" in
    cwe)
      printf '     * CWE: regenereer met tool/build_cwe_catalog.dart (de bron is een zip van\n' >&2
      printf '       tientallen MB achter een gedateerde URL) en zet cweBundledVersion in\n' >&2
      printf '       lib/services/reference_standards.dart.\n' >&2 ;;
    miauw)
      printf '     * MIAUW: neem een nieuwe momentopname van het werkboek over en zet\n' >&2
      printf '       miauwBundledVersion op de commitdatum van de BRON, niet op de dag\n' >&2
      printf '       waarop je het overnam.\n' >&2 ;;
    cvss)
      printf '     * CVSS: er bestaat een opvolger van de specificatie. Dat is een\n' >&2
      printf '       implementatiebeslissing (lib/services/cvss/), geen verversing.\n' >&2 ;;
    orphanet)
      printf '     * Orphanet: make refresh-lexicon, en weeg de termdiff tegen de\n' >&2
      printf '       vals-positievencorpus — bij een lexicon vuurt elke term.\n' >&2 ;;
    *)
      printf '     * %s: hiervoor is geen generator; werk de bundel met de hand bij en zet\n' "$1" >&2
      printf '       de versie in lib/services/reference_standards.dart.\n' >&2 ;;
  esac
}

outdated_gate() {
  STEP="verouderingsgate"
  section "Verouderingsgate (referentiedata)"
  # De machineleesbare stand eerst: daar valt uit af te lezen wélke bron beweegt,
  # en dat bepaalt of dit een automatische of een handmatige zaak is. Op de groene
  # weg is dit de enige ronde langs de bronnen.
  local json rc=0
  json="$(catalogs_probe_json)" || rc=$?
  if [ "$rc" -eq 2 ]; then
    die "de referentiebronnen waren niet bereikbaar (netwerk?) — niet gekeken is niet hetzelfde als actueel. Probeer opnieuw zodra je online bent."
  fi
  printf '%s' "$json" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || die "de verouderingscontrole gaf geen bruikbare uitkomst — draai 'make catalogs-outdated' met de hand; dit zegt niets over de bundel."

  # Bronnen die niet te bereiken waren blijven hier niet stil. Ze blokkeren de
  # release niet — dat zou elke hik van GitHub een release kosten — maar
  # "ik heb niet kunnen kijken" hoort wel op het scherm te staan.
  local onbekend
  onbekend="$(printf '%s' "$json" | jq -r '.[] | select(.status=="onbekend") | .naam' | paste -sd', ' -)"
  [ -z "$onbekend" ] || log "Niet kunnen kijken bij: $onbekend (blokkeert niet, maar is geen goedkeuring)."

  local stale id
  stale="$(stale_catalog_ids "$json" | tr '\n' ' ')"
  stale="$(printf '%s' "$stale" | xargs || true)"
  if [ -z "$stale" ]; then
    log "Referentiedata actueel."
    log "Scanner-pins worden in fase 1 automatisch bijgewerkt (bump-scanner-pins)."
    log "Dependencies (adviserend):"
    make deps-outdated 2>&1 | grep -iE "upgradable|outdated|newer|→" | head -8 | sed 's/^/     /' || true
    return 0
  fi

  # Er is drift. Nu pas de leesbare tabel erbij — dat is een tweede ronde langs de
  # bronnen, en die kost alleen op deze zeldzame weg iets.
  make catalogs-outdated 2>&1 | sed 's/^/   /' || true

  local handmatig=""
  for id in $stale; do
    case " $REFRESHABLE_CATALOGS " in
      *" $id "*) ;;
      *) handmatig="$handmatig $id" ;;
    esac
  done
  handmatig="$(printf '%s' "$handmatig" | xargs || true)"
  if [ -n "$handmatig" ]; then
    printf '\n   Hiervoor bestaat geen automatische verversing:\n' >&2
    for id in $handmatig; do handmatige_route "$id"; done
    printf '   Werk dat bij, dien het als eigen wijziging in, en draai de release opnieuw.\n' >&2
    die "referentiedata niet actueel — de bundel gaat niet ongezien de deur uit."
  fi

  CATALOGS_STALE="$stale"
  log ""
  log "Fase 1 ververst dit zelf ($CATALOGS_STALE) en legt het vast als eigen commit."
  log "Blijkt de INHOUD verschoven — en niet alleen de momentopname — dan stopt de"
  log "keten daar alsnog: dat verandert waar een rapport naar verwijst."
}

# ── Het plan tonen ──────────────────────────────────────────────────────────────
show_plan() {
  section "Plan"
  # Bij een repetitie hoort dit plan te lezen als "wat er zóu gebeuren". Zonder
  # deze regel leest een versienummer in beeld als een release die al loopt.
  [ "$PREFLIGHT_ONLY" -eq 1 ] && log "REPETITIE (--preflight): hieronder staat wat een release zou doen; er wordt niets gemaakt."
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
    FASE 1  verouderingsgate → scanner-pins bumpen → [momentopname referentiedata]
            → bump → make sbom → committen
            → make check-release → build + notarize → zegel → /Applications
    FASE 2  [scans-image publiceren als pins gebumpt] → PR → poort groen → merge
            → tag $TAG → push origin+mirror → CI volgen
    FASE 3  make deploy-web → SHA256SUMS tekenen + aanhangen → publiceren
            → website-downloads-workflow dispatchen
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
# Vanaf hier is dit een échte run (--dry-run/--status/--print-version zijn er al uit).
# Spiegel alle uitvoer naar een tijdgestempeld logbestand onder build/ (git-genegeerd),
# zodat een afgebroken release achteraf na te lezen is. Het wachtwoord komt via
# 'read -s' binnen en staat dus niet in het log.
# --preflight is een repetitie en schrijft dus geen release-logboek: dat logboek
# hoort bij een run die iets doet.
if [ "$PREFLIGHT_ONLY" -eq 0 ]; then
  LOGFILE="build/release-logs/release-${TAG}-$(date +%Y%m%d-%H%M%S).log"
  mkdir -p "$(dirname "$LOGFILE")"
  exec > >(tee -a "$LOGFILE") 2>&1
  log "Loguitvoer wordt bijgehouden in $LOGFILE"
fi

STEP="voorwaarden"
if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
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
if [ -z "$RESUME_TAG" ] && git rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null 2>&1; then
  die "lokale release-branch $BRANCH bestaat al — overschrijf geen mogelijk werk; maak hem af of ruim hem bewust op."
fi

# De verouderingsgate hoort bij een échte build (fase 1); in resume bouwen we niet.
[ -n "$RESUME_TAG" ] || outdated_gate

# ── Werkboom vrij? Een tweede Flutter in dezelfde map sloopt de release ─────────
# `make notarize-macos` bouwt schoon en begint met `flutter clean`. Draait er in
# deze werkboom nóg een flutter-proces (een `flutter run` die je liet staan, een
# IDE-sessie, een tweede `flutter test`), dan blijft `.dart_tool` staan doordat die
# ander de map blijft aanvullen — en `flutter clean` meldt dat wél, maar eindigt
# met exit 0. De eerstvolgende `dart run` valt dan over een half verdwenen
# hooks_runner-cache (PathNotFoundException op stdout.txt) en de release strandt
# tien minuten verderop op een fout die niets met tekenen te maken heeft. Zo brak
# de v0.4.4-run van 15-08-2026. Toets het vóór het wachtwoord: dan kost het
# dertig seconden in plaats van tien minuten.
#
# Twee ingangen, want geen van beide vangt alles: een `flutter run` draagt het pad
# van de werkboom niet in zijn argumenten (alleen zijn cwd verraadt hem), terwijl
# de compiler-daemon en flutter_tester het pad wél meedragen maar met een andere
# cwd kunnen draaien. Bewust smal op de bouwketen: de analysis server van een
# editor raakt `.dart_tool` niet en mag geen release blokkeren.
#
# 'ps -Ao pid=,command=' en niet 'pgrep -af': die -a drukt op macOS alléén pid's
# af (hij bestaat daar met een andere betekenis), waardoor zowel de padvergelijking
# als de melding leeg zou blijven — precies op de machine waar de release draait.
busy_workspace_procs() {
  local pid cmd cwd
  # shellcheck disable=SC2009 # pgrep kan hier niet: zijn -a drukt op macOS alleen pid's af.
  while read -r pid cmd; do
    [ -n "$pid" ] && [ "$pid" != "$$" ] || continue
    case "$cmd" in
      *"$ROOT_DIR"/*) printf '%s %s\n' "$pid" "$cmd"; continue ;;
    esac
    command -v lsof >/dev/null 2>&1 || continue
    cwd="$(lsof -a -d cwd -p "$pid" -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
    [ "$cwd" = "$ROOT_DIR" ] && printf '%s %s\n' "$pid" "$cmd"
  done < <(ps -Ao pid=,command= \
    | grep -E 'flutter_tools\.snapshot|frontend_server|flutter_tester' \
    | grep -v ' grep ' || true)
}
assert_workspace_idle() {
  STEP="werkboom vrij"
  # Alleen fase 1 bouwt schoon. --resume slaat die fase over en is bovendien de
  # herstelroute: daar een nieuwe drempel opwerpen helpt niemand.
  [ -z "$RESUME_TAG" ] || return 0
  local busy
  busy="$(busy_workspace_procs || true)"
  [ -n "$busy" ] || return 0
  printf '\nrelease-auto: er draait nog een flutter/dart-proces in deze werkboom:\n' >&2
  printf '%s\n' "$busy" | cut -c1-140 | sed 's/^/    /' >&2
  die "sluit dat af (flutter run, flutter test, een IDE-sessie) en draai opnieuw — een schone bouw kan anders niet. Niets gemuteerd."
}

# ── appimagetool-pin: de rollende upstream-asset vóór de tag toetsen ───────────
# appimagetool komt uit een rollende `continuous`-release op GitHub; upstream
# verving die asset op 04-10-2026 en de vastgelegde sha256 faalde terecht — maar
# pas ná de tag, in de Linux-job (release-run 5479, job 23681 — #2324). Deze
# controle vergelijkt de pin vóór elke branch/tagmutatie met de officiële
# asset-digest uit de GitHub-API, zodat een verplaatste upstream de release
# stopt terwijl er nog niets onomkeerbaars is.

# De vastgelegde pin als "url sha256". De env-override deelt het contract met
# scripts/package_linux.sh (en is de testroute); anders wordt de pin uit de
# env-blok van 'Linux-pakketten bouwen' in de release-workflow gelezen.
appimagetool_pin() {
  if [ -n "${APPIMAGETOOL_URL:-}" ] && [ -n "${APPIMAGETOOL_SHA256:-}" ]; then
    printf '%s %s\n' "$APPIMAGETOOL_URL" "$APPIMAGETOOL_SHA256"
    return 0
  fi
  local wf url sha
  wf="${OCIDECK_APPIMAGE_WORKFLOW:-.forgejo/workflows/release.yml}"
  url="$(sed -n 's/^[[:space:]]*APPIMAGETOOL_URL:[[:space:]]*//p' "$wf" | head -n1)"
  sha="$(sed -n 's/^[[:space:]]*APPIMAGETOOL_SHA256:[[:space:]]*//p' "$wf" | head -n1)"
  [ -n "$url" ] && [ -n "$sha" ] || return 1
  printf '%s %s\n' "$url" "$sha"
}

# De GitHub release-API die bij een releases/download-URL hoort:
#   github.com/O/R/releases/download/TAG/ASSET → repos/O/R/releases/tags/TAG
appimagetool_release_api() {
  printf '%s' "$1" | sed -n 's|^https://github\.com/\([^/]*/[^/]*\)/releases/download/\([^/]*\)/.*|https://api.github.com/repos/\1/releases/tags/\2|p'
}

# De officiële sha256 van de asset, zonder prefix. GitHub levert die als
# `digest`-veld op het release-asset. Is de API onleesbaar of ontbreekt het
# veld, dan faalt dit — onbekend is niet afwezig.
appimagetool_official_digest() { # appimagetool_official_digest ASSET_URL
  local url="$1" api_url json digest
  api_url="$(appimagetool_release_api "$url")"
  [ -n "$api_url" ] || return 1
  json="$(curl -fsS --connect-timeout 10 --max-time 30 \
    -H 'Accept: application/vnd.github+json' "$api_url" 2>/dev/null)" || return 1
  digest="$(printf '%s' "$json" | jq -r --arg name "${url##*/}" '
      .assets[]? | select(.name == $name) | .digest // empty' \
    | sed -n 's/^sha256:\([0-9a-fA-F]\{64\}\)$/\1/p' | head -n1)"
  [ -n "$digest" ] || return 1
  printf '%s\n' "$digest"
}

# De pincontrole hoort vóór branch/tagmutatie. Staat de tag bij --resume al op
# origin, dan is er niets meer om vóór te blokkeren: de lopende keten gebruikt
# de pin van de tag-commit, en een afwijking is informatief, geen drempel.
appimagetool_tag_pushed() {
  [ -n "$RESUME_TAG" ] \
    && git ls-remote --exit-code origin "refs/tags/$RESUME_TAG" >/dev/null 2>&1
}

assert_appimagetool_pin() {
  STEP="appimagetool-pin"
  local pin url sha official
  pin="$(appimagetool_pin)" \
    || die "appimagetool-pin niet leesbaar uit ${OCIDECK_APPIMAGE_WORKFLOW:-.forgejo/workflows/release.yml} — verwacht APPIMAGETOOL_URL en APPIMAGETOOL_SHA256 in de env van 'Linux-pakketten bouwen'. Niets gemuteerd."
  url="${pin%% *}"
  sha="${pin##* }"
  if ! official="$(appimagetool_official_digest "$url")"; then
    if appimagetool_tag_pushed; then
      log "appimagetool: officiële digest niet leesbaar; tag $RESUME_TAG staat al op origin — informatief, geen blokkade."
      return 0
    fi
    die "officiële appimagetool-digest niet leesbaar via de GitHub-API — de pinstatus is onbekend, niet afwezig. Controleer netwerk/ rate limit en draai opnieuw. Niets gemuteerd."
  fi
  if [ "$official" = "$sha" ]; then
    log "appimagetool-pin klopt (sha256 ${sha:0:12}…)."
    return 0
  fi
  if appimagetool_tag_pushed; then
    log "appimagetool-pin ($sha) wijkt af van de officiële digest ($official); tag $RESUME_TAG staat al — de lopende keten gebruikt de pin van de tag-commit."
    return 0
  fi
  die "appimagetool-pin verouderd: vastgelegd $sha, officiële asset-digest $official. Upstream verving de rollende 'continuous'-asset — precies wat release-run 5479/job 23681 ná de tag brak (#2324). Herstel na herkomstcontrole van de nieuwe asset: (1) beoordeel de release met 'curl -s $(appimagetool_release_api "$url")' (velden assets[].digest en .updated_at); (2) zet 'APPIMAGETOOL_SHA256: $official' in .forgejo/workflows/release.yml; (3) commit op main en draai de release opnieuw. Niets gemuteerd."
}

# Bepaalt read-only welke capaciteiten een --resume nog nodig heeft (#2303):
#   need_mirror — de tag staat nog niet op de mirror (ensure_mirror_tag pusht 'm)
#   need_deploy — de webdemo draait de nieuwe versie nog niet (deploy-web loopt)
#   need_sign   — de release mist nog een geldige minisign-handtekening
# Een onleesbare toestand laat de vlag op 1 staan: onbekend is niet afwezig.
# Zo bereikt een al live en getekende release het websiteherstel zónder een
# werkende deploy-host of de minisign-privésleutel.
resume_capability_needs() {
  local live rc=0
  live="$(live_web_version || true)"
  [ -n "${NEW_VERSION:-}" ] && [ "$live" = "$NEW_VERSION" ] && need_deploy=0
  remote_tag_commit mirror >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) need_mirror=0 ;;
    1) : ;;  # de tag ontbreekt: ensure_mirror_tag pusht 'm — capaciteit nodig
    *) die "kon de mirror-tagstatus van $TAG niet lezen — onbekend is niet afwezig." ;;
  esac
  # Klopt de combinatie manifest + handtekening al? Lees via de API
  # (draft-proof, #2311). Bestaat de release niet of mist er een asset, dan
  # komt het tekenen nog — de capaciteit blijft nodig.
  local rid sums_url sig_url t
  rid="$(api GET "/releases/tags/$TAG" 2>/dev/null | jq -er '.id' 2>/dev/null)" \
    || return 0
  sums_url="$(release_asset_url "$rid" SHA256SUMS)"
  sig_url="$(release_asset_url "$rid" SHA256SUMS.minisig)"
  [ -n "$sums_url" ] && [ -n "$sig_url" ] || return 0
  t="$(mktemp -d)"
  if download_release_asset "$sums_url" "$t/sums" \
      && download_release_asset "$sig_url" "$t/sig" \
      && minisign -Vm "$t/sums" -x "$t/sig" \
        -p "$ROOT_DIR/minisign.pub" >/dev/null 2>&1; then
    need_sign=0
  fi
  rm -rf "$t"
}

# ── #7 Pre-flight: alles wat later onherroepelijk nodig is, nú toetsen ──────────
# Vandaag brak de keten pas ná de tag op stappen die vooraf toetsbaar waren
# (deploy-ssh, de handtekening). Deze functie faalt vóór elke mutatie.
preflight() {
  STEP="pre-flight"
  section "Pre-flight — forge, mirror, deploy-host en minisign toetsen"
  # Afgeleide staat eerst: een CMake-cache van een vórige pakketversie (na een
  # dartcv4-bump) laat `flutter build macos` in fase 1 falen ná anderhalf uur
  # groene `make check-release`, omdat die bouw een andere configuratiehash
  # heeft dan `dart run` en `flutter test` (0.6.6-run, 20-09-2026). Opruimen
  # is geen mutatie van de release; de volgende bouw configureert opnieuw.
  "$ROOT_DIR/scripts/prune_stale_hook_cache.sh" "$ROOT_DIR" 2>&1 | sed 's/^/   /' \
    || die "kon de native-assets-cache niet beoordelen (scripts/prune_stale_hook_cache.sh) — zie hierboven. Niets gemuteerd."
  api GET "" -o /dev/null \
    || die "forge-token werkt niet tegen $REPO_SLUG (keychain '$TOKEN_KEYCHAIN_SERVICE')."
  # Bij --resume is een deel van de keten al af en de bijbehorende capaciteit
  # overbodig (#2303): een live webdemo vraagt geen deploy-SSH, een geldige
  # handtekening geen privésleutel, een al gepushte mirror-tag geen mirror.
  # Read-only bepaald; een onleesbare toestand laat de vlag aan (fail-closed).
  local need_mirror=1 need_deploy=1 need_sign=1
  if [ -n "$RESUME_TAG" ]; then
    resume_capability_needs
  fi
  if [ "$need_mirror" -eq 1 ]; then
    git ls-remote mirror >/dev/null 2>&1 \
      || die "mirror-remote onbereikbaar — de Windows-build op de spiegel hangt eraan."
  fi
  if [ "$need_deploy" -eq 1 ]; then
    # Bereikbaar alleen is niet genoeg: v0.6.12 werd keurig naar een oude VPS
    # geschreven nadat DNS naar zijn opvolger was verhuisd. `index.html` was
    # toevallig bytegelijk, zodat pas SHA256SUMS na de tag het verkeerde doel
    # ontdekte. Vergelijk daarom vóór de tag het publieke IPv4-adres met de
    # adressen die de SSH-host zelf draagt. De referentiehosting is rechtstreeks;
    # een inzet met proxy/CDN moet deze poort bewust passend maken.
    local deploy_host_ips live_ip
    deploy_host_ips="$(ssh -o BatchMode=yes -o ConnectTimeout=8 \
      "$DEPLOY_HOST" 'command -v flock python3 sudo tar >/dev/null && sudo -n true && python3 -c '\''import ctypes; assert hasattr(ctypes.CDLL(None), "renameat2")'\'' && hostname -I' 2>/dev/null)" \
      || die "deploy-host $DEPLOY_HOST mist bereikbaarheid, flock, python3, sudo, tar of atomaire renameat2 — deploy-web zou ná de tag stranden."
    [ -n "$deploy_host_ips" ] \
      || die "deploy-host $DEPLOY_HOST meldt geen eigen IP-adressen — niet bewijsbaar dat hij $DEPLOY_URL bedient."
    live_ip="$(curl -4 -fsS --max-time 15 -o /dev/null -w '%{remote_ip}' \
      "$DEPLOY_URL/version.json")" \
      || die "publieke webdemo $DEPLOY_URL niet bereikbaar — deploydoel vóór de tag niet verifieerbaar."
    case " $deploy_host_ips " in
      *" $live_ip "*) ;;
      *) die "deploy-host $DEPLOY_HOST draagt [$deploy_host_ips], maar $DEPLOY_URL gaat naar $live_ip — deploy-web zou naar de verkeerde server schrijven." ;;
    esac
  fi
  # De appimagetool-pin hoort hier: de Linux-job toetst de download aan deze
  # hash, en voor de v0.6.14-tag bleek de pin verouderd pas ná de onomkeerbare
  # push (#2324). Toetsen nu kost seconden; toen kostte het een releaserun.
  assert_appimagetool_pin
  if [ "$need_sign" -eq 1 ]; then
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
  fi
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
    local skipped=""
    [ "$need_mirror" -eq 0 ] && skipped="$skipped mirror"
    [ "$need_deploy" -eq 0 ] && skipped="$skipped deploy-host"
    [ "$need_sign" -eq 0 ] && skipped="$skipped minisign"
    if [ -n "$skipped" ]; then
      log "Pre-flight groen: alleen de open capaciteiten getoetst (overgeslagen:${skipped} — die stappen zijn al af)."
    else
      log "Pre-flight groen: forge-token, mirror, deploy-host en minisign kloppen."
    fi
  fi
}

# ── FASE 3 — verspreiden (gedeeld door de normale keten én --resume) ────────────
# De webdemo alleen lokaal bouwen en deployen als hij nog niet live staat, en
# dan alleen vanaf de commit die de tag draagt.

# `make deploy-web` bouwt uit de wérkboom, en die staat na fase 2 nooit op de tag:
# de release-PR landt met een merge-commit, de tag gaat op díe commit, en de
# werkboom blijft op de release-branch staan — de tweede ouder ervan. Twee
# verschillende commits, doorgaans met exact dezelfde inhoud.
#
# Fase 3 eiste alleen dat HEAD de tag-commit wás en stierf anders. Dat maakte van
# een terechte voorwaarde een onhaalbare: zolang de PR met een merge-commit landt
# (v0.6.5 t/m v0.6.8 deden dat alle vier) kán HEAD de tag niet zijn, dus strandde
# élke verse release hier en moest de operator met de hand uitchecken en
# hervatten. De voorwaarde blijft — er mag geen andere code als $TAG live gaan —
# maar het script haalt 'm nu zelf, in plaats van de operator ernaartoe te sturen.
ensure_worktree_on_tag() {
  STEP="werkboom op de tag zetten"
  # Op een andere machine, of na opruiming, kan de tag lokaal ontbreken; --resume
  # moet ook vanaf een verse kloon kunnen deployen.
  if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    git fetch --quiet --force origin "refs/tags/$TAG:refs/tags/$TAG" \
      || die "kon tag $TAG niet lokaal krijgen — zonder de tag-commit zou deploy-web andere code als $TAG publiceren. Is origin bereikbaar?"
  fi
  local tag_sha
  tag_sha="$(git rev-list -n 1 "$TAG")"
  [ "$tag_sha" != "$(git rev-parse HEAD)" ] || return 0
  # Nooit andermans werk onder de checkout vandaan trekken: liever stoppen met een
  # melding dan een niet-gecommitte wijziging meenemen of weggooien.
  if ! git diff --quiet || ! git diff --cached --quiet \
      || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    die "werkboom niet schoon — fase 3 zet 'm daarom niet op $TAG (nooit 'git stash' in deze repo delen). Commit of herstel de wijzigingen en hervat: scripts/release_auto.sh --resume $TAG"
  fi
  git checkout --quiet --detach "$TAG" \
    || die "kon $TAG niet uitchecken — ligt er een niet-gevolgd bestand in de weg? Ruim dat op en hervat: scripts/release_auto.sh --resume $TAG"
  log "Werkboom op $TAG gezet; deploy-web bouwt nu precies de code van de tag."
}

# Of de demo "nog niet live staat" is bewust geen jobstatus. De CI-job *Webversie
# live zetten* meldt `success` óók wanneer hij niets deed: ontbreken
# `DEPLOY_SSH_KEY`/`DEPLOY_KNOWN_HOSTS` — en die ontbreken met opzet, de demo
# gaat met de hand live — dan slaat de job de deploy over en eindigt groen,
# zodat een echte tag geen rode job en faalmail geeft. Deze functie las die
# groene status een release lang als bewijs, waardoor v0.6.5 en v0.6.6 de demo
# op 0.6.4 lieten staan terwijl de keten "klaar" meldde.
deploy_web_if_needed() {
  local tag_sha head_sha live
  live="$(live_web_version || true)"
  if [ "$live" = "$NEW_VERSION" ]; then
    log "De webdemo op $DEPLOY_URL draait al $NEW_VERSION; lokaal deploy-web overgeslagen."
    return 0
  fi
  if [ -n "$live" ]; then
    log "De webdemo op $DEPLOY_URL draait nog $live; die moet naar $NEW_VERSION."
  else
    log "Kon de versie op $DEPLOY_URL niet lezen; deploy-web draait, de verificatie hieronder beslist."
  fi
  ensure_worktree_on_tag
  # Naconditie, geen instructie meer aan de operator: ensure_worktree_on_tag is
  # hierboven geslaagd of gestorven, dus dit hóórt te kloppen. Het blijft staan
  # omdat "wat we publiceren is de tag" de enige bewering is die deze stap doet,
  # en die meet je liever dan dat je 'm aanneemt.
  tag_sha="$(git rev-list -n 1 "$TAG" 2>/dev/null || true)"
  head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
  if [ -z "$tag_sha" ] || [ "$tag_sha" != "$head_sha" ]; then
    die "de werkboom staat ná het uitchecken nog steeds niet op $TAG (HEAD ${head_sha:0:9}, tag ${tag_sha:0:9}) — een lokale deploy-web zou andere code als $TAG publiceren. Onderzoek de repotoestand en hervat: scripts/release_auto.sh --resume $TAG"
  fi
  # ensure_worktree_on_tag gebruikt voor zijn eigen melding tijdelijk een
  # specifiekere stapnaam. Zet de buitenste stap terug, zodat een echte
  # deployfout niet opnieuw als "werkboom op de tag zetten" wordt gemeld.
  STEP="deploy-web"
  make deploy-web
  # Meten, niet aannemen: `deploy_web.sh` verifieert zijn eigen bundel, maar
  # alleen dit zegt dat de bezoeker de nieuwe versie krijgt.
  live="$(live_web_version || true)"
  [ "$live" = "$NEW_VERSION" ] \
    || die "deploy-web is gedraaid, maar $DEPLOY_URL meldt ${live:-geen leesbare versie} in plaats van $NEW_VERSION — kijk op de host voor de wissel en hervat daarna: scripts/release_auto.sh --resume $TAG"
  log "deploy-web klaar; $DEPLOY_URL draait $NEW_VERSION."
}

phase3() {
  # Verdediging in de diepte: de normale route heeft follow_ci al doorlopen en
  # --resume doet dat eveneens. Toch weigert fase 3 zelf ook wanneer een job nog
  # schrijft; precies die ontbrekende grens liet v0.6.2 tweemaal publiceren.
  assert_release_ci_terminal || return $?
  if release_ci_has_failure "$snap"; then
    die "release-CI voor $TAG eindigde met failure/cancelled/skipped/error — deploy of teken niets; herstel de job en hervat daarna dezelfde tag."
  fi

  # #10: eerst de webdemo. Die hangt alleen aan de web-bundel, niet aan de
  # platform-artefacten of de handtekening — dus een teken- of platformfout mag
  # de demo nooit op de oude versie laten staan.
  #
  # Maar `make deploy-web` bouwt uit de wérkboom, en die is niet per se de tag.
  # Een --resume van v0.6.5 draaide een dag later op main, mét vier merges die
  # niet in die tag zaten; alleen een toevallig rode sbom-verify hield tegen dat
  # die code als "v0.6.5" live ging. Daarom bouwt de lokale route alleen vanaf
  # de tag-commit, en beslist `version.json` op de live site of er überhaupt
  # gedeployd moet worden — de CI-job zegt daar niets over (zie hieronder).
  STEP="deploy-web"
  section "Fase 3 — webversie live zetten"
  deploy_web_if_needed

  STEP="SHA256SUMS tekenen"
  section "Fase 3 — SHA256SUMS tekenen, publiceren en aanhangen"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  local rid
  rid="$(api GET "/releases/tags/$TAG" | jq -er '.id')" \
    || die "kon de release-id voor $TAG niet betrouwbaar bepalen."
  # De release is draft (#2311): publieke download-URL's geven 404 tot wij hem
  # hieronder publiceren. Lees daarom alles via de API. `publiceren` kan nog
  # nalopen; wacht begrensd i.p.v. meteen op een ontbrekend asset te sterven.
  local got=0 _ sums_url
  for _ in $(seq 1 20); do
    sums_url="$(release_asset_url "$rid" SHA256SUMS)"
    if [ -n "$sums_url" ] \
        && download_release_asset "$sums_url" "$TMP/SHA256SUMS"; then
      got=1
      break
    fi
    sleep 15
  done
  # Nooit zelf opnieuw dispatchen. Een mislukte releasejob heeft een oorzaak die
  # eerst onderzocht moet worden; blind herhalen introduceert een tweede schrijver
  # en kan bestaande assets vervangen. De operator herstart de bewezen falende job
  # op de forge en hervat daarna dezelfde tag.
  [ "$got" -eq 1 ] \
    || die "release-CI voor $TAG is terminaal groen, maar SHA256SUMS ontbreekt — dispatch niet automatisch; onderzoek de publiceren-job en hervat daarna dezelfde tag."
  verify_release_manifest "$TMP/SHA256SUMS" \
    || die "SHA256SUMS bevat niet exact de tien verwachte artefacten voor $TAG — teken geen onvolledige of onverwachte release."
  local release_assets expected_asset
  release_assets="$(api GET "/releases/$rid/assets" | jq -er '.[].name')" \
    || die "kon de release-assets voor $TAG niet betrouwbaar lezen."
  while IFS= read -r expected_asset; do
    printf '%s\n' "$release_assets" | grep -qxF "$expected_asset" \
      || die "release $TAG mist $expected_asset — teken geen onvolledige release."
  done < <(expected_release_assets)
  printf '%s\n' "$release_assets" | grep -qxF SHA256SUMS \
    || die "release $TAG mist SHA256SUMS als asset."

  # Een hervatting van een al getekende release hoort read-only te zijn. Controleer
  # eerst de aangeboden combinatie en raak de assets alleen aan als die niet
  # exact bij het zojuist gevalideerde manifest hoort. De release is nog draft —
  # lees daarom via de API (publieke URL's bestaan pas na publicatie, #2311).
  local public_sums="$TMP/SHA256SUMS.public"
  local public_sig="$TMP/SHA256SUMS.minisig.public"
  local signature_current=0 existing_sig_url
  existing_sig_url="$(release_asset_url "$rid" SHA256SUMS.minisig)"
  if [ -n "$existing_sig_url" ] \
      && download_release_asset "$sums_url" "$public_sums" \
      && download_release_asset "$existing_sig_url" "$public_sig" \
      && cmp -s "$TMP/SHA256SUMS" "$public_sums" \
      && minisign -Vm "$public_sums" -x "$public_sig" \
        -p "$ROOT_DIR/minisign.pub" >/dev/null 2>&1; then
    signature_current=1
    log "Bestaande handtekening past al exact bij SHA256SUMS; upload overgeslagen."
  fi
  if [ "$signature_current" -eq 0 ]; then
  printf '%s\n' "$MINISIGN_PW" \
    | make sign-release SHA256SUMS="$TMP/SHA256SUMS" >/dev/null || true
  [ -f "$TMP/SHA256SUMS.minisig" ] || die "minisign leverde geen handtekening — controleer het sleutelwachtwoord."
  local old_asset new_asset existing_tmp existing_url downloaded_tmp signature_sha
  # Upload-first-then-replace (#1600): upload de nieuwe handtekening onder een
  # tijdelijke naam vóór de oude verwijderd wordt. De vorige volgorde (DELETE
  # dan POST) liet bij een gefaalde POST de release zonder handtekening achter,
  # en een stil gefaalde DELETE (|| true) leidde tot een 409 op de POST. Nu:
  #   1. POST onder .new — faalt dit, dan staat de oude nog op de release.
  #   2. DELETE de oude — faalt dit, dan staan er twee bijlagen (oude + .new);
  #      de oude is handmatig te verwijderen, de inhoud is er in ieder geval.
  #   3. PATCH hernoem .new naar de definitieve naam.
  signature_sha="$(shasum -a 256 "$TMP/SHA256SUMS.minisig" | awk '{print $1}')"
  local tmp_name="SHA256SUMS.minisig.new.$signature_sha"
  existing_tmp="$(api GET "/releases/$rid/assets" \
    | jq -er --arg n "$tmp_name" '[.[] | select(.name==$n)] | if length > 1 then error("duplicate") else .[0] // empty end | "\(.id)|\(.browser_download_url)"' 2>/dev/null)" || true
  if [ -n "$existing_tmp" ]; then
    new_asset="${existing_tmp%%|*}"
    existing_url="${existing_tmp#*|}"
    downloaded_tmp="$TMP/existing.minisig"
    if ! curl -fsSL --connect-timeout 10 --max-time 30 -o "$downloaded_tmp" "$existing_url" \
        || ! cmp -s "$downloaded_tmp" "$TMP/SHA256SUMS.minisig"; then
      die "tijdelijke handtekening $tmp_name bestaat, maar de inhoud wijkt af — verwijder hem niet automatisch."
    fi
    log "Eerder geüploade tijdelijke handtekening hervat."
  else
    new_asset="$(api POST "/releases/$rid/assets?name=$tmp_name" \
      -F "attachment=@$TMP/SHA256SUMS.minisig" \
      | jq -er '.id' 2>/dev/null)" \
      || die "kon SHA256SUMS.minisig niet uploaden — de oude handtekening staat nog op de release."
  fi
  [ -n "$new_asset" ] && [ "$new_asset" != "null" ] \
    || die "upload van SHA256SUMS.minisig gaf geen asset-id — controleer de release-pagina."
  old_asset="$(api GET "/releases/$rid/assets" 2>/dev/null \
    | jq -r '.[] | select(.name=="SHA256SUMS.minisig") | .id' 2>/dev/null | head -1 || true)"
  if [ -n "$old_asset" ]; then
    api DELETE "/releases/$rid/assets/$old_asset" -o /dev/null \
      || die "kon de oude SHA256SUMS.minisig niet verwijderen — verwijder handmatig en hernoem $tmp_name naar SHA256SUMS.minisig."
  fi
  api PATCH "/releases/$rid/assets/$new_asset" \
    -H 'Content-Type: application/json' \
    -d '{"name":"SHA256SUMS.minisig"}' -o /dev/null \
    || die "kon $tmp_name niet hernoemen naar SHA256SUMS.minisig — hernoem handmatig op de release-pagina."
  fi

  # Vertrouw niet op een geslaagde uploadstatus. Lees precies wat ontvangers
  # krijgen opnieuw terug en verifieer die combinatie — geauthenticeerd, want de
  # release is nog draft (#2311). Zo kan de publicatie hieronder nooit een oude
  # handtekening naast een later vervangen manifest als "getekend" melden.
  local attached_valid=0
  for _ in $(seq 1 12); do
    local check_sig_url
    check_sig_url="$(release_asset_url "$rid" SHA256SUMS.minisig)"
    if [ -n "$check_sig_url" ] \
        && download_release_asset "$sums_url" "$public_sums" \
        && download_release_asset "$check_sig_url" "$public_sig" \
        && cmp -s "$TMP/SHA256SUMS" "$public_sums" \
        && minisign -Vm "$public_sums" -x "$public_sig" \
          -p "$ROOT_DIR/minisign.pub" >/dev/null 2>&1; then
      attached_valid=1
      break
    fi
    sleep 5
  done
  [ "$attached_valid" -eq 1 ] \
    || die "de teruggelezen SHA256SUMS en handtekening verifiëren niet — de release blijft draft; onderzoek en hervat pas nadat geen workflow meer schrijft."
  log "SHA256SUMS.minisig aangehangen en teruggelezen geverifieerd."

  # Alle nacondities kloppen: assets compleet, manifest klopt, handtekening
  # geldig. Nu pas wordt de release publiek — elke eerder gedode stap liet hem
  # als draft staan (#2311). Mislukt de PATCH onzeker, dan reconcilert de
  # GET hieronder; een release die draft blijft is een melding, geen ramp.
  api PATCH "/releases/$rid" -H 'Content-Type: application/json' \
    -d '{"draft":false}' -o /dev/null || {
      local pub_state
      pub_state="$(api GET "/releases/$rid" 2>/dev/null | jq -r '.draft // empty' 2>/dev/null)"
      [ "$pub_state" = "false" ] \
        || die "de release kon niet van draft naar gepubliceerd (externe toestand onbekend) — hij blijft draft; controleer de release-pagina en hervat met --resume $TAG."
    }
  log "Release $TAG gepubliceerd."

  # Laatste bewijs is publiek: precies wat een bezoeker zonder token krijgt.
  local public_valid=0
  for _ in $(seq 1 12); do
    if curl -fsSL --connect-timeout 10 --max-time 30 -o "$public_sums" "$RELEASE_BASE_URL/$TAG/SHA256SUMS" 2>/dev/null \
        && curl -fsSL --connect-timeout 10 --max-time 30 -o "$public_sig" "$RELEASE_BASE_URL/$TAG/SHA256SUMS.minisig" 2>/dev/null \
        && cmp -s "$TMP/SHA256SUMS" "$public_sums" \
        && minisign -Vm "$public_sums" -x "$public_sig" \
          -p "$ROOT_DIR/minisign.pub" >/dev/null 2>&1; then
      public_valid=1
      break
    fi
    sleep 5
  done
  [ "$public_valid" -eq 1 ] \
    || die "de publiek teruggelezen SHA256SUMS en handtekening verifiëren niet na publicatie — onderzoek en hervat pas nadat geen workflow meer schrijft."

  STEP="website-downloads aansturen"
  # De website-downloads-job staat sinds #2311 in een eigen workflow: hij leest
  # publieke release-URL's, en die bestaan pas nu. Dispatch hem op de tag —
  # maar nooit naast een nog actieve run: een tweede publicatie naast een
  # levende externe deploy is een tweede schrijver (#2302). Een leesbare
  # eerdere run die klaar is bepaalt of dispatchen überhaupt nodig is; alleen
  # een terminale mislukking rechtvaardigt opnieuw aansturen.
  case "$TAG" in
    *-*)
      log "Prerelease $TAG: website-downloads wordt niet bijgewerkt." ;;
    *)
      local wrun wrc=0
      wrun="$(latest_workflow_run website-downloads.yml "$TAG" 2>/dev/null)" || wrc=$?
      if [ "$wrc" -ne 0 ]; then
        log "LET OP: kon de website-downloads-runs niet lezen — geen nieuwe dispatch terwijl een actieve deploy niet uit te sluiten is; de publieke naconditie hieronder beslist."
      elif [ -z "$wrun" ]; then
        api POST "/actions/workflows/website-downloads.yml/dispatches" \
          -H 'Content-Type: application/json' \
          -d "{\"ref\":\"$TAG\"}" -o /dev/null \
          && log "website-downloads-workflow gedispatcht op $TAG." \
          || log "LET OP: dispatch van website-downloads.yml faalde — werk de librekat.nl-downloadpagina handmatig bij (scripts/bump-ocideck.sh $NEW_VERSION + ./publiceersite in de website-repo)."
      else
        case "${wrun#*|}" in
          success)
            log "website-downloads voor $TAG is al groen — dispatch overgeslagen." ;;
          failure|cancelled|skipped|error)
            api POST "/actions/workflows/website-downloads.yml/dispatches" \
              -H 'Content-Type: application/json' \
              -d "{\"ref\":\"$TAG\"}" -o /dev/null \
              && log "eerdere website-downloads-run was terminaal-rood; opnieuw gedispatcht op $TAG." \
              || log "LET OP: dispatch van website-downloads.yml faalde — werk de librekat.nl-downloadpagina handmatig bij (scripts/bump-ocideck.sh $NEW_VERSION + ./publiceersite in de website-repo)."
            ;;
          *)
            log "website-downloads-run ${wrun%%|*} is nog actief — geen tweede publicatie; hij wordt hieronder gevolgd." ;;
        esac
      fi
      ;;
  esac

  # De website-repo publiceert asynchroon na de bovenstaande job. Wacht daarom
  # begrensd op de publieke naconditie. Status 0 van beide workflows is niet
  # genoeg: v0.6.11 t/m v0.6.13 werden groen naar een nieuwe VPS gekopieerd,
  # terwijl librekat.nl via DNS nog de oude VPS en v0.6.10 bediende.
  # Prereleases raken de productiesite bewust niet — die wacht is er niet.
  if [[ "$TAG" != *-* ]]; then
    local website_version="" website_live=0
    for _ in $(seq 1 24); do
      website_version="$(live_website_version || true)"
      if website_has_expected_downloads; then
        website_live=1
        break
      fi
      sleep 15
    done
    if [ "$website_live" -eq 0 ]; then
      # Een nog lopende of onleesbare externe deploy is géén mislukking van de
      # release — nooit als "verkeerde host" presenteren, en er staat bewust
      # geen tweede publicatie naast (#2302).
      local wrun_after wst=""
      wrun_after="$(latest_workflow_run website-downloads.yml "$TAG" 2>/dev/null || true)"
      [ -n "$wrun_after" ] && wst="${wrun_after#*|}"
      case "$wst" in
        success)
          die "de website-downloads-run claimt groen, maar $WEBSITE_URL toont ${website_version:+v$website_version}${website_version:-geen leesbare versie} in plaats van $TAG — controleer naar welke host librekat.nl wijst, publiceer de website daar en hervat: scripts/release_auto.sh --resume $TAG" ;;
        failure|cancelled|skipped|error)
          die "de website-downloads-run faalde (run ${wrun_after%%|*}, status $wst) — werk de downloadpagina handmatig bij (scripts/bump-ocideck.sh $NEW_VERSION + ./publiceersite) en hervat: scripts/release_auto.sh --resume $TAG" ;;
        "")
          die "geen website-downloads-run voor $TAG te vinden en $WEBSITE_URL toont niet de release — de dispatch is onzeker; onderzoek de workflow en hervat: scripts/release_auto.sh --resume $TAG" ;;
        *)
          die "de externe website-deploy voor $TAG loopt nog (run ${wrun_after%%|*}) — dat is géén mislukking en er is geen tweede publicatie gestart; kom terug met: scripts/release_auto.sh --resume $TAG" ;;
      esac
    fi
    log "Publieke downloadpagina gecontroleerd: $WEBSITE_URL verwijst naar $TAG."
  fi
}

# Fase 3 bouwt de webdemo vanaf de tag en laat de werkboom dus op een losse HEAD
# achter. Dat is een slechte plek om de volgende ochtend verder te werken: een
# commit erop hangt aan geen enkele tak en is met een checkout zo weg. Zet 'm
# terug waar de release vandaan vertrok. Dit mag nooit een geslaagde release laten
# vallen, dus een mislukking is hier een melding en geen fout.
restore_start_branch() {
  [ -n "${START_BRANCH:-}" ] || return 0
  # Alleen een losse HEAD verzetten; staat de operator al op een tak, dan is dat
  # zijn keuze en niet aan ons.
  [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "HEAD" ] || return 0
  if git checkout --quiet "$START_BRANCH" 2>/dev/null; then
    log "Werkboom terug op $START_BRANCH."
  else
    log "LET OP: de werkboom staat los van elke tak (op $TAG); ga zelf terug met 'git checkout $START_BRANCH'."
  fi
}

install_macos_app() { # install_macos_app SOURCE_APP
  local source_app="$1" target="$APPLICATIONS_DIR/OciDeck.app"
  local stage backup had_old=0
  stage="$(mktemp -d "$APPLICATIONS_DIR/.ocideck-install.XXXXXX")" \
    || die "kon geen tijdelijke installatiemap in $APPLICATIONS_DIR maken."
  backup="$APPLICATIONS_DIR/.OciDeck.app.backup.$$"
  if ! ditto "$source_app" "$stage/OciDeck.app" \
      || ! codesign --verify --deep --strict "$stage/OciDeck.app"; then
    rm -rf "$stage"
    die "kopiëren of verifiëren van de tijdelijke OciDeck.app mislukte; de bestaande app is ongemoeid."
  fi
  if pgrep -x OciDeck >/dev/null 2>&1; then
    osascript -e 'quit app "OciDeck"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5; do pgrep -x OciDeck >/dev/null 2>&1 || break; sleep 1; done
    if pgrep -x OciDeck >/dev/null 2>&1; then
      rm -rf "$stage"
      die "OciDeck draait na vijf seconden nog; bestaande installatie niet vervangen."
    fi
  fi
  if [ -e "$target" ]; then
    mv "$target" "$backup" || { rm -rf "$stage"; die "kon de bestaande OciDeck.app niet veilig apart zetten."; }
    had_old=1
  fi
  if ! mv "$stage/OciDeck.app" "$target"; then
    [ "$had_old" -eq 0 ] || mv "$backup" "$target" 2>/dev/null || true
    rm -rf "$stage"
    die "installatiewissel mislukte; de vorige app is teruggezet waar mogelijk."
  fi
  rm -rf "$stage"
  [ "$had_old" -eq 0 ] || rm -rf "$backup"
  codesign --verify --deep --strict "$target" \
    || die "de geïnstalleerde app faalt de zegelcontrole; stop en onderzoek $target."
}

finish() {
  STEP="klaar"
  if [ -n "${PENDING_APP:-}" ] && [ "$SKIP_INSTALL" -eq 0 ]; then
    STEP="/Applications vervangen"
    install_macos_app "$PENDING_APP"
    log "$APPLICATIONS_DIR/OciDeck.app vervangen door de uitgebrachte, genotariseerde build."
  fi
  STEP="klaar"
  section "Klaar — $TAG in $(elapsed)"
  restore_start_branch
  log "OciDeck $TAG is uitgebracht, getekend en live."
  log ""
  log "Release-pagina : ${RELEASE_BASE_URL%/download}/tag/$TAG"
  [ -n "${LOGFILE:-}" ] && log "Logboek        : $LOGFILE"
  log ""
  log "Volledige staat controleren:  scripts/release_auto.sh --status $TAG"
}

# ── FASE 2 — herbruikbare, idempotente stappen (verse run én --resume) ──────────
# Elke stap detecteert of hij al gedaan is. Zo hervat --resume een onderbroken
# release vanaf het punt waar het bleef, zonder de dure fase 1 over te doen.

# De release-PR voor deze versie, gematcht op TITEL — niet op head-branch: na een
# merge-met-branch-verwijdering wordt head.ref 'refs/pull/N/head', dus de
# branchnaam is dan weg. Echoot "nummer|state|merged|head_sha|merge_commit_sha"
# of niets als er (nog) geen PR is.
find_release_pr() {
  local json matches count
  json="$(api GET "/pulls?state=all&limit=100")" \
    || die "kon bestaande release-PR's niet betrouwbaar lezen — maak geen duplicaat."
  matches="$(printf '%s' "$json" | jq -cer --arg t "chore(release): versie $NEW_VERSION" --arg b "$BRANCH" \
    '[.[] | select(.title == $t)
      | select(.merged == true or .head.ref == $b or .head.label == $b)]')" \
    || die "ongeldig antwoord bij het zoeken naar de release-PR — maak geen duplicaat."
  count="$(printf '%s' "$matches" | jq 'length')"
  [ "$count" -le 1 ] \
    || die "meerdere release-PR's voor $NEW_VERSION gevonden — kies niet automatisch de verkeerde."
  [ "$count" -eq 1 ] || return 0
  printf '%s' "$matches" | jq -r '.[0] | "\(.number)|\(.state)|\(.merged)|\(.head.sha)|\(.merge_commit_sha // "")"'
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
scan_image_tag_for_ref() { # scan_image_tag_for_ref GIT_REF
  git show "$1:.github/pinned-ci-versions.json" \
    | jq -r '[.tools[] | select(.name == "gitleaks" or .name == "trufflehog" or .name == "semgrep")
        | {key:.name, value:.version}] | from_entries
        | "gl\(.gitleaks)-th\(.trufflehog)-sg\(.semgrep)"'
}

scan_image_available() { # scan_image_available TAG
  local image_tag="$1" token code
  token="$(curl -fsSLG 'https://pawprint.vigilis.online/v2/token' \
    --data-urlencode 'service=container_registry' \
    --data-urlencode 'scope=repository:librekat/ocideck-scans:pull' \
    | jq -r '.token // .access_token // empty' 2>/dev/null || true)"
  [ -n "$token" ] || return 1
  code="$(curl -sS -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $token" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json' \
    "https://pawprint.vigilis.online/v2/librekat/ocideck-scans/manifests/$image_tag" \
    2>/dev/null || true)"
  [ "$code" = "200" ]
}

publish_scans_image() { # publish_scans_image IMAGE_TAG
  local image_tag="$1"
  STEP="scans-image publiceren"
  section "Fase 2 — nieuw scans-image publiceren (scanner-pins gebumpt)"
  # De dispatch levert met return_run_info direct de run-id op; oudere Forgejo's
  # antwoorden 204 zonder body — dan resolven we de nieuwste ci-image-scans-run
  # op deze ref zelf. In beide gevallen volgen we daarna de RUN, niet de
  # runner-taken: een wachtende run zonder toegewezen taak is bestaand en
  # actief, niet "nooit aangemaakt" (de v0.6.14-fout, #2294).
  local resp run_id="" run="" ist="" poll
  resp="$(api POST '/actions/workflows/ci-image-scans.yml/dispatches' \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg r "$BRANCH" '{ref:$r, return_run_info:true}')")" \
    || die "dispatch van ci-image-scans op $BRANCH faalde — publiceer lokaal met 'make ci-image-scans-publish' en hervat daarna met: scripts/release_auto.sh --resume $TAG"
  run_id="$(printf '%s' "$resp" | jq -r '.id // empty' 2>/dev/null || true)"
  log "ci-image-scans gedispatcht op $BRANCH${run_id:+ (run $run_id)} — wachten tot het scans-image gepubliceerd is…"
  sleep 10
  for poll in $(seq 1 60); do
    if [ -z "$run_id" ]; then
      run="$(latest_workflow_run ci-image-scans.yml "$BRANCH" 2>/dev/null || true)"
      run_id="${run%%|*}"
    fi
    if [ -n "$run_id" ]; then
      ist="$(api GET "/actions/runs/$run_id/jobs" 2>/dev/null \
        | jq -r '[.[] | select(.name == "build-publish")] | sort_by([.attempt // 0, .id])
            | .[-1] // empty | .status' 2>/dev/null)"
      # De run bestaat — staat de job er nog niet in, dan wacht hij gewoon.
      [ -n "$ist" ] || ist="wachtend"
    else
      ist=""
    fi
    case "$ist" in
      success) break ;;
      failure|cancelled) die "ci-image-scans faalde op $BRANCH — het nieuwe scans-image is niet gepubliceerd; de PR-scan zou het niet vinden." ;;
      "")
        # De dispatch is aanvaard maar er verschijnt geen run — dat is een
        # registratieprobleem, geen wachttoestand. Dit vraagt om de
        # gedocumenteerde lokale publicatieroute en daarna een veilige --resume.
        if [ "$poll" -ge 3 ]; then
          die "geen ci-image-scans-run aangemaakt voor $BRANCH; publiceer lokaal met 'make ci-image-scans-publish' en hervat daarna met: scripts/release_auto.sh --resume $TAG"
        fi
        sleep 20
        ;;
      *) sleep 20 ;;
    esac
  done
  [ "$ist" = "success" ] \
    || die "scans-image werd niet op tijd gepubliceerd — controleer de ci-image-scans-run."
  for _ in $(seq 1 12); do
    scan_image_available "$image_tag" && break
    sleep 5
  done
  scan_image_available "$image_tag" \
    || die "ci-image-scans was groen, maar $image_tag is niet pullbaar uit het register; open geen release-PR."
  log "Nieuw scans-image $image_tag gepubliceerd en pullbaar geverifieerd."
}

ensure_scans_image() {
  local image_tag
  git fetch origin "refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" --quiet
  image_tag="$(scan_image_tag_for_ref "origin/$BRANCH")"
  [ -n "$image_tag" ] && [ "$image_tag" != "null" ] \
    || die "kon de scanner-image-tag niet uit origin/$BRANCH bepalen."
  if scan_image_available "$image_tag"; then
    log "Scans-image $image_tag is al pullbaar; publiceren overslaan."
    return 0
  fi
  publish_scans_image "$image_tag"
}

# De drie releasepoorten zijn sinds b3e182044 bewust alleen handmatig startbaar:
# lokaal `make check-full` is de primaire poort, deze runs zijn de onafhankelijke
# Linux-/scannercontrole vóór de tag. Een PR openen maakt daarom geen
# statuscontexten meer. #2194 bleef toch de lege combined status pollen en kon
# uitsluitend na 75 minuten stoppen. Start ontbrekende workflows hier zelf en
# volg hun workflowRUNS op exact de PR-head: /actions/runs ziet ook een run die
# nog in de runnerwachtrij staat, en de nieuwste run per workflow kan nooit met
# een oudere poging versmelten (#2294).
gate_task_snapshot() { # gate_task_snapshot SHA → "workflow|status|titel|run-id" per poort
  local sha="$1"
  api GET '/actions/runs?limit=50' \
    | jq -r --arg sha "$sha" '
        [.workflow_runs[]?
          | select(.commit_sha == $sha)
          | select(.workflow_id == "static-gate.yml"
              or .workflow_id == "scans.yml"
              or .workflow_id == "linux-gate.yml")]
        | group_by(.workflow_id)
        | map(max_by(.id))[]
        | "\(.workflow_id)|\(.status)|\(.title // "")|\(.id)"'
}

ensure_gate_tasks() { # ensure_gate_tasks SHA PR_NUMBER
  local sha="$1" pr="$2" snap workflow resp run_id
  snap="$(gate_task_snapshot "$sha")" \
    || die "kon bestaande poortruns niet betrouwbaar lezen — dispatch geen duplicaten."
  for workflow in static-gate.yml scans.yml linux-gate.yml; do
    if printf '%s\n' "$snap" | grep -q "^${workflow}|"; then
      continue
    fi
    resp="$(api POST "/actions/workflows/$workflow/dispatches" \
      -H 'Content-Type: application/json' \
      -d "$(jq -n --arg r "$BRANCH" '{ref:$r, return_run_info:true}')")" \
      || die "kon $workflow voor PR #$pr niet starten — niets getagd. Hervat later met: scripts/release_auto.sh --resume $TAG"
    run_id="$(printf '%s' "$resp" | jq -r '.id // empty' 2>/dev/null || true)"
    log "$workflow gestart op $BRANCH (head ${sha:0:10}${run_id:+, run $run_id})."
  done
}

# linux-gate draait de volledige suite op de capacity-1 serial-runner (~27 min,
# langer als er iets vóór in de wachtrij staat). Vandaar GATE_TIMEOUT_MIN (75)
# mét voortgang. Een geaccepteerde dispatch die na vijf minuten nog geen RUN
# opleverde is een registratieprobleem — een queued run zonder runner-taak is
# via /actions/runs wél zichtbaar — geen reden om de overige zeventig minuten
# uit te zitten. Losse API-hikjes binnen dat venster blijven zacht; een
# volhoudend onleesbare API niet: onbekend is niet afwezig.
wait_gate() { # wait_gate SHA PR_NUMBER
  local sha="$1" pr="$2"
  STEP="poort bewaken"
  local polls=$(( GATE_TIMEOUT_MIN * 2 ))   # elke iteratie ~30s
  ensure_gate_tasks "$sha" "$pr"
  log "Wachten op de handmatige poorten (static-gate, scans, linux-gate) — max ${GATE_TIMEOUT_MIN} min."
  log "linux-gate draait de volledige suite op de serial-runner; dat duurt het langst."
  local snap="" count=0 success=0 failed="" i workflow line unreadable=0
  for i in $(seq 1 "$polls"); do
    if snap="$(gate_task_snapshot "$sha")"; then
      unreadable=0
    else
      snap=""
      unreadable=$(( unreadable + 1 ))
    fi
    if [ "$unreadable" -ge 6 ]; then
      die "de poortstatus voor $sha is $unreadable polls onleesbaar (Forgejo-API-fout) — onbekend is niet afwezig. Niets getagd. Hervat later met: scripts/release_auto.sh --resume $TAG"
    fi
    count="$(printf '%s\n' "$snap" | grep -c '^[^|]*|' || true)"
    success="$(printf '%s\n' "$snap" | awk -F'|' '$2 == "success" { n++ } END { print n+0 }')"
    failed="$(printf '%s\n' "$snap" | awk -F'|' '$2 ~ /^(failure|error|cancelled)$/ { print }')"
    if [ -n "$failed" ]; then
      printf '%s\n' "$failed" | awk -F'|' '{ printf "     %s: %s (%s)\n", $1, $2, $3 }' >&2
      die "minstens één handmatige poort faalde op $sha — zie PR #$pr. Niets getagd. Herstel en hervat met: scripts/release_auto.sh --resume $TAG"
    fi
    [ "$count" -eq 3 ] && [ "$success" -eq 3 ] && break
    if [ "$count" -lt 3 ] && [ "$unreadable" -eq 0 ] && [ "$i" -ge 10 ]; then
      die "niet alle handmatige poorten zijn binnen vijf minuten als run geregistreerd voor $sha — zie PR #$pr. Niets getagd. Hervat later met: scripts/release_auto.sh --resume $TAG"
    fi
    if [ $(( (i - 1) % 6 )) -eq 0 ]; then
      for workflow in static-gate.yml scans.yml linux-gate.yml; do
        line="$(printf '%s\n' "$snap" | grep "^${workflow}|" | head -1 || true)"
        if [ -z "$line" ]; then
          printf '     wacht op %s: taakregistratie\n' "$workflow"
        elif [ "$(printf '%s' "$line" | cut -d'|' -f2)" != "success" ]; then
          printf '     wacht op %s: %s\n' "$workflow" "$(printf '%s' "$line" | cut -d'|' -f2)"
        fi
      done
      log "… $(( (i - 1) / 2 )) min verstreken"
    fi
    sleep 30
  done
  [ "$count" -eq 3 ] && [ "$success" -eq 3 ] \
    || die "poort werd niet groen binnen ${GATE_TIMEOUT_MIN} min — zie PR #$pr. Hervat later met: scripts/release_auto.sh --resume $TAG"
  log "Poort groen."
}

# Merge de release-PR. Idempotent: al gemerged → niets doen. head_commit_id maakt de
# merge exact (schone 200 i.p.v. 405, en nooit een stale/verkeerde head).
# De gekeurde base bevriezen vóór de servermerge (#2299). De releasebranch
# werd aan het begin van origin/main getakt en daarna gebouwd en gekeurd.
# Schuift main ondertussen door, dan neemt de servermerge die nieuwe base
# mee in de getagde tree — commits die nooit in deze keten gebouwd of
# gekeurd zijn. De merge-base van branch en main ÍS het vastgelegde
# vertrekpunt: alleen als origin/main er nog exact op staat is de getagde
# tree de gekeurde boom.
assert_release_base_frozen() {
  local base now
  git fetch origin main "$BRANCH" --quiet 2>/dev/null \
    || die "kon origin/main en $BRANCH niet verversen vóór de merge — base-toestand onbekend, niets gemerged."
  base="$(git merge-base "origin/$BRANCH" origin/main 2>/dev/null || true)"
  now="$(git rev-parse origin/main 2>/dev/null || true)"
  [ -n "$base" ] && [ -n "$now" ] \
    || die "kon de gekeurde base van $BRANCH niet bepalen — mergen gestopt, niets gemerged."
  [ "$now" = "$base" ] \
    || die "origin/main schoof door (${base:0:12} → ${now:0:12}) sinds $BRANCH werd gekeurd — de servermerge zou nooit gebouwde base-commits in de getagde tree meenemen. Herstel: merge origin/main in $BRANCH, push, laat de poort opnieuw groen worden en hervat met: scripts/release_auto.sh --resume $TAG. Niets gemerged, niets getagd."
  log "Gekeurde base bevroren op ${base:0:12} — merge heeft geen ongeziene base."
}

merge_pr() { # merge_pr PR_NUMBER HEAD_SHA
  local pr="$1" head="$2" st
  STEP="mergen"
  st="$(find_release_pr)"
  if [ -n "$st" ] && [ "$(printf '%s' "$st" | cut -d'|' -f3)" = "true" ]; then
    log "PR #$pr was al gemerged."
    return 0
  fi
  assert_release_base_frozen
  api POST "/pulls/$pr/merge" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg h "$head" '{Do:"merge", head_commit_id:$h, delete_branch_after_merge:true}')" -o /dev/null
  log "PR #$pr gemergd."
}

# De merge-commit van een (gemergede) PR — daar hangt de tag aan. Precieser dan
# origin/main, dat inmiddels verder kan staan door een andere merge ertussen.
merge_commit_of_pr() { # merge_commit_of_pr PR_NUMBER
  api GET "/pulls/$1" | jq -r '.merge_commit_sha // empty'
}

remote_tag_commit() { # remote_tag_commit REMOTE
  local remote="$1" refs
  refs="$(git ls-remote "$remote" "refs/tags/$TAG" "refs/tags/$TAG^{}")" || return 2
  [ -n "$refs" ] || return 1
  printf '%s\n' "$refs" | awk '$2 ~ /\^\{\}$/ { peeled=$1 } $2 !~ /\^\{\}$/ { direct=$1 }
    END { print (peeled != "" ? peeled : direct) }'
}

assert_tag_commit() { # assert_tag_commit LABEL ACTUAL EXPECTED
  local label="$1" actual="$2" expected="$3"
  [ -n "$actual" ] && [ "$actual" = "$expected" ] \
    || die "tag $TAG op $label wijst naar ${actual:-onbekend}, verwacht $expected — verplaats of overschrijf een releasetag nooit."
}

# De mirror-tag (GitHub-spiegel) is een eigen faalpunt naast origin: de origin-push
# start de Forgejo-CI, maar de Windows-build op de spiegel start pas als de tag ÓÓK
# op de mirror staat (windows-ophalen dispatcht met --ref $TAG). Idempotent: staat de
# tag al op de mirror, dan doet dit niets — zo repareert --resume alsnog een mislukte
# mirror-push, óók als origin de tag al heeft (waar de vroegere early-return de
# mirror-push oversloeg en de Windows-build eeuwig liet wachten).
ensure_mirror_tag() {
  git remote get-url mirror >/dev/null 2>&1 || return 0
  local expected mirror_sha rc=0
  expected="$(git rev-list -n 1 "$TAG" 2>/dev/null)" \
    || die "lokale tag $TAG kan niet tot een commit worden herleid."
  mirror_sha="$(remote_tag_commit mirror)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    assert_tag_commit mirror "$mirror_sha" "$expected"
    return 0
  fi
  [ "$rc" -eq 1 ] || die "kon niet betrouwbaar vaststellen of $TAG al op de mirror staat."
  STEP="mirror-tag zetten"
  # Zorg dat we de tag lokaal hebben: na een verse tag bestaat hij al; op een andere
  # machine (of na opruiming) halen we 'm exact van origin.
  if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    git fetch --quiet --force origin "refs/tags/$TAG:refs/tags/$TAG" \
      || die "kon tag $TAG niet lokaal krijgen voor de mirror-push — is origin bereikbaar?"
  fi
  if ! git push --quiet mirror "$TAG"; then
    mirror_sha="$(remote_tag_commit mirror)" || true
    assert_tag_commit mirror "$mirror_sha" "$expected"
    log "Mirror-push meldde een fout, maar de teruglezing bewijst dat $TAG correct staat."
  else
    mirror_sha="$(remote_tag_commit mirror)" \
      || die "mirror-push meldde succes, maar $TAG is niet terug te lezen."
    assert_tag_commit mirror "$mirror_sha" "$expected"
  fi
  log "Tag $TAG naar de mirror gepusht — de Windows-build kan starten."
}

# Tag op de merge-commit en push naar origin + mirror. Idempotent per remote: staat
# de tag al op een remote, dan slaat die push over. origin en mirror zijn LOS: een
# geslaagde origin-push (die de release-CI start) mag niet verhullen dat de
# mirror-push faalde, en --resume moet een ontbrekende mirror-tag alsnog kunnen
# zetten. De 8-seconden-bail vóór de origin-push is het punt-van-geen-terugkeer.
tag_and_push() { # tag_and_push MERGE_SHA
  local mergesha="$1" i origin_sha rc=0
  STEP="tag pushen"
  origin_sha="$(remote_tag_commit origin)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    assert_tag_commit origin "$origin_sha" "$mergesha"
    log "Tag $TAG stond al op origin — niet opnieuw taggen."
    TAG_PUSHED=1
    ensure_mirror_tag
    return 0
  fi
  [ "$rc" -eq 1 ] || die "kon niet betrouwbaar vaststellen of $TAG al op origin staat."
  # De merge-commit is server-side gemaakt (REST-merge in merge_pr) en zit dus nog
  # niet in onze lokale objectdatabase; 'git tag -a' zou er anders op stuklopen met
  # 'fatal: bad object type' — precies waarop de v0.4.1-release brak. Haal 'm op
  # (bereikbaar via origin/main) en controleer 'm vóór de onherroepelijke stappen.
  # Dit dekt zowel de verse keten als de --resume-route: beide taggen via deze fn.
  git fetch --quiet origin \
    || die "kon origin niet fetchen vóór het taggen — is de forge bereikbaar? Hervat later met: scripts/release_auto.sh --resume $TAG"
  git cat-file -e "$mergesha^{commit}" 2>/dev/null \
    || die "merge-commit $mergesha ontbreekt lokaal na 'git fetch origin' — controleer PR en origin. Hervat met: scripts/release_auto.sh --resume $TAG"
  # Zekerheid dat we de JUISTE commit taggen: de merge-commit moet de nieuwe versie
  # dragen. Zo tagt een verkeerd merge_commit_sha (bv. een andere PR) nooit een
  # willekeurige commit als deze release.
  local tagged_version
  tagged_version="$(git show "$mergesha:pubspec.yaml" 2>/dev/null \
    | sed -n 's/^version:[[:space:]]*\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')"
  [ "$tagged_version" = "$NEW_VERSION" ] \
    || die "merge-commit $mergesha draagt versie '${tagged_version:-onbekend}', niet $NEW_VERSION — dit is niet de release-commit. Niets getagd; controleer de PR."
  section "Fase 2 — tag $TAG pushen (de publieke release-keten start hierna)"
  log "Ctrl-C binnen 8 seconden om af te breken (hierna is de tag onherroepelijk)."
  for i in 8 7 6 5 4 3 2 1; do printf '\r   %s… ' "$i"; sleep 1; done; printf '\r          \n'
  git tag -d "$TAG" >/dev/null 2>&1 || true   # een stale lokale tag van een vorige poging opruimen
  git tag -a "$TAG" -m "OciDeck $TAG" "$mergesha"
  assert_tag_commit lokaal "$(git rev-list -n 1 "$TAG")" "$mergesha"
  if ! git push --quiet origin "$TAG"; then
    origin_sha="$(remote_tag_commit origin)" || true
    assert_tag_commit origin "$origin_sha" "$mergesha"
    log "Origin-push meldde een fout, maar de teruglezing bewijst dat $TAG correct staat."
  else
    origin_sha="$(remote_tag_commit origin)" \
      || die "origin-push meldde succes, maar $TAG is niet terug te lezen."
    assert_tag_commit origin "$origin_sha" "$mergesha"
  fi
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
  local cap="${RELEASE_CI_TIMEOUT_MIN:-240}"
  section "Fase 2 — release-CI volgen (tot alle jobs klaar zijn, max ${cap} min)"
  local prev="" running=0 _ unchanged=0 unreadable=0
  snap=""
  # Elke iteratie ~30 s. Een lange job (Linux bouwen, ~50 min) verandert het
  # beeld een half uur lang niet; daarom is de cap een tijd en geen "geen
  # wijziging"-drempel, en laat een hartslag elke tien minuten zien dat er nog
  # gewacht wordt en niet gehangen.
  for _ in $(seq 1 $(( cap * 2 ))); do
    if snap="$(release_ci_snapshot)"; then
      unreadable=0
    else
      snap=""
      unreadable=$(( unreadable + 1 ))
    fi
    running=0
    if [ -n "$snap" ]; then
      running="$(printf '%s\n' "$snap" | grep -cvE '^(success|failure|cancelled|skipped|error)\|' || true)"
    fi
    if [ "$snap" != "$prev" ] && [ -n "$snap" ]; then
      printf '%s\n' "$snap" | sed 's/^/   /'; prev="$snap"; unchanged=0
    else
      unchanged=$(( unchanged + 1 ))
      if [ $(( unchanged % 20 )) -eq 0 ]; then
        if [ "$unreadable" -gt 0 ]; then
          log "nog bezig na $(elapsed 2>/dev/null || echo '?'): de Forgejo-API is $unreadable polls onleesbaar."
        else
          log "nog bezig na $(elapsed 2>/dev/null || echo '?'): $running job(s) actief, geen wijziging in de laatste 10 min."
        fi
      fi
    fi
    if [ -n "$snap" ] && [ "$running" -eq 0 ] \
        && release_ci_completion_seen "$snap"; then
      break
    fi
    sleep 30
  done
  if [ -z "$snap" ]; then
    if [ "$unreadable" -gt 0 ]; then
      die "de release-CI-status voor $TAG bleef onleesbaar (Forgejo-API-fout) — onbekend is niet afwezig; fase 3 wordt niet gestart. Hervat met: scripts/release_auto.sh --resume $TAG"
    fi
    die "geen release-run voor $TAG gevonden binnen de wachttijd — fase 3 wordt niet gestart."
  fi
  if [ "$running" -ne 0 ] || ! release_ci_completion_seen "$snap"; then
    die "release-CI voor $TAG is na ${cap} minuten nog actief of niet volledig zichtbaar — fase 3 wordt niet gestart; hervat later met: scripts/release_auto.sh --resume $TAG"
  fi
  # De losse ci.yml-poort heet simpelweg `gate` en draait náást release.yml op
  # dezelfde tag. Rood daar is een testuitslag om naar te kijken, geen
  # gefaalde releasejob; het zegt niets over de artefacten. Benoem het apart,
  # anders leest de operator "release-job faalde" en gaat de verkeerde kant op.
  if printf '%s\n' "$snap" | grep -q '^failure|gate$'; then
    log "Terzijde: de losse ci.yml-poort (gate) op $TAG is rood. Dat is een testrun naast de"
    log "releaseketen, geen releasejob — bekijk de uitslag, maar de release gaat door."
  fi
  # Dezelfde terzijde voor de golden-poort op de tag (#2321): die run staat in
  # zijn eigen tag-groep en wordt hier expliciet gevolgd — een afwezige of
  # geannuleerde tagrun mag niet onzichtbaar blijven.
  local mgate=""
  mgate="$(macos_gate_tag_status || true)"
  case "$mgate" in
    "")      log "Terzijde: geen macos-gate-run op $TAG gevonden — de golden-poort van de tagcommit is onbewezen." ;;
    success\|*) log "macos-gate (goldens) op $TAG is groen (run ${mgate##*|})." ;;
    *)       log "Terzijde: macos-gate op $TAG is ${mgate%%|*} (run ${mgate##*|}) — de golden-poort van de tagcommit is niet groen." ;;
  esac
  if printf '%s\n' "$snap" | grep -v '^failure|gate$' | grep -q '^failure|'; then
    log "LET OP: minstens één release-job faalde (zie hierboven). De tag staat vast."
    log "Herstel de upstream-job en maak DEZELFDE tag af met '--resume $TAG'; her-tag niet."
  fi
}

# --resume: hervat een onderbroken release vanaf het punt waar het bleef. Kijkt wat
# er al op de forge staat en doet alleen de rest; fase 1 (bouwen) wordt niet
# overgedaan — die zit al in de gepushte branch/PR als we hier iets vinden.
resume_release() {
  section "Hervatten — $TAG"
  # Wat we hervatten staat al op origin; een fout onderweg hoort dus ook hier
  # naar --resume te wijzen en niet naar een verse run.
  BRANCH_PUSHED=1
  local origin_tag rc=0 tagged_version
  origin_tag="$(remote_tag_commit origin)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    TAG_PUSHED=1
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
      assert_tag_commit lokaal "$(git rev-list -n 1 "$TAG")" "$origin_tag"
    else
      git fetch --quiet origin "refs/tags/$TAG:refs/tags/$TAG" \
        || die "kon bestaande tag $TAG niet lokaal ophalen."
    fi
    tagged_version="$(git show "$origin_tag:pubspec.yaml" 2>/dev/null \
      | sed -n 's/^version:[[:space:]]*\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')"
    [ "$tagged_version" = "$NEW_VERSION" ] \
      || die "tag $TAG op origin draagt versie ${tagged_version:-onbekend}, niet $NEW_VERSION."
    log "Tag $TAG staat al op origin — mirror-tag borgen, dan fase 3 (deploy-web + tekenen)."
    ensure_mirror_tag
    follow_ci
    phase3; finish; return 0
  fi
  [ "$rc" -eq 1 ] || die "kon niet betrouwbaar vaststellen of $TAG op origin staat."
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
    elif [ "$(printf '%s' "$st" | cut -d'|' -f2)" = "closed" ]; then
      die "release-PR #$num is gesloten zonder merge — hervat hem niet automatisch; heropen of ruim branch en PR bewust op."
    else
      ensure_scans_image
      log "PR #$num staat open — poort afwachten, mergen en verder."
      wait_gate "$headsha" "$num"
      merge_pr "$num" "$headsha"
      MERGE_SHA="$(merge_commit_of_pr "$num")"
    fi
  elif git ls-remote --exit-code origin "refs/heads/$BRANCH" >/dev/null 2>&1; then
    ensure_scans_image
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

# Vóór de prompts: een bezette werkboom maakt de schone bouw in fase 1 onmogelijk,
# en dat wil je weten vóór je een wachtwoord intikt.
assert_workspace_idle

# ── Bekend herstelwerk dat nog niet in main zit ────────────────────────────────
# v0.6.5 ging de deur uit terwijl fix/pdfium-framework-casing al op origin stond:
# het herstel van de macOS-startfout van v0.6.4, nog niet gemerged. Niemand zag
# het, want niets in deze keten keek ernaar — de pre-flight toetst de
# gereedschappen, niet of de release inhoudelijk compleet is. Daarom nu, vóór
# het wachtwoord, twee bronnen:
#   1. open issues en pull requests met het label `release-blocker` — de
#      afgesproken manier om te zeggen "niet uitbrengen voordat dit erin zit";
#   2. takken fix/* op origin waarvan de kop niet in origin/main zit — een fix
#      die al gebouwd is maar nog geen PR heeft, precies het v0.6.5-geval.
# Beide stoppen de keten. --ondanks-fixes laat ze bewust buiten deze release; die
# keuze staat dan zwart op wit in het releaselogboek. --resume slaat dit over: de
# inhoud van een lopende release ligt al vast.
unmerged_fix_branches() {
  local refs sha ref rc
  git fetch origin --quiet || return 2
  refs="$(git ls-remote --heads origin 'refs/heads/fix/*')" || return 2
  while read -r sha ref; do
    [ -n "$sha" ] || continue
    rc=0
    git merge-base --is-ancestor "$sha" origin/main 2>/dev/null || rc=$?
    if [ "$rc" -eq 0 ]; then
      continue
    elif [ "$rc" -eq 1 ]; then
      printf '%s\n' "${ref#refs/heads/}"
    else
      return 2
    fi
  done <<<"$refs"
}
open_release_blockers() {
  local json
  json="$(api GET '/issues?state=open&labels=release-blocker&limit=100')" || return 1
  printf '%s' "$json" | jq -e 'type == "array"' >/dev/null || return 1
  printf '%s' "$json" | jq -r '.[] | "#\(.number) \(.title)"'
}
assert_no_pending_fixes() {
  STEP="bekend herstelwerk"
  [ -z "$RESUME_TAG" ] || return 0
  local branches blockers
  branches="$(unmerged_fix_branches)" \
    || die "kon fix/*-takken niet betrouwbaar vergelijken met origin/main — releaseblokkers zijn onbekend."
  blockers="$(open_release_blockers)" \
    || die "kon open release-blockers niet betrouwbaar lezen — releaseblokkers zijn onbekend."
  [ -n "$branches$blockers" ] || return 0
  section "Bekend herstelwerk dat nog niet in main zit"
  [ -z "$blockers" ] || { log "open met label release-blocker:"; printf '%s\n' "$blockers" | sed 's/^/     /'; }
  [ -z "$branches" ] || { log "fix/*-takken op origin, niet in main:"; printf '%s\n' "$branches" | sed 's/^/     /'; }
  if [ "$IGNORE_FIXES" -eq 1 ]; then
    log "--ondanks-fixes: bovenstaand herstelwerk blijft bewust buiten deze release."
    return 0
  fi
  die "een release langs bekend herstelwerk is hoe v0.6.5 de v0.6.4-startfout meenam. Merge het eerst, of geef --ondanks-fixes mee als het bewust buiten deze release blijft. Niets gemuteerd."
}

# ── Nachtelijke main-poort (#2308) ─────────────────────────────────────────────
# De nightly linux-gate stond vier nachten rood terwijl de v0.6.14-release fase
# 1 rustig doorliep en exact dezelfde fout pas ná branch en PR zelf vond. De
# pre-flight toetst gereedschappen, niet of de onafhankelijke Linux-poort deze
# main al als kapot kent. Daarom hier — vóór het wachtwoord, vóór elke mutatie —
# read-only de nieuwste linux-gate-run op de huidige main-geschiedenis lezen.
# Een ontbrekende of niet-relevante run is expliciet onbekend, niet groen. Nooit
# een nieuwe run dispatchen als neveneffect — alleen lezen.
assert_nightly_main_gate() {
  STEP="nachtelijke main-poort"
  # --resume: de inhoud van de lopende release ligt al vast; een intussen rood
  # geworden main-run zegt niets meer over díe inhoud.
  [ -z "$RESUME_TAG" ] || return 0
  local main_sha
  main_sha="$(git rev-parse --verify origin/main 2>/dev/null)" \
    || die "origin/main ontbreekt lokaal — de nachtelijke linux-gate kan niet aan de huidige main-tip gekoppeld worden."
  # De lijst-route geeft geen commit_sha; die staat op de detail-GET per run.
  # Loop van nieuw naar oud over de runs op main tot één run op de tip of een
  # voorvader: alleen díe zeggen iets over de code die deze release uitbrengt.
  local ids rid rinfo rsha rstatus rurl found=""
  ids="$(api GET "/actions/runs?limit=50&workflow_id=linux-gate.yml" 2>/dev/null \
    | jq -r '[.workflow_runs[]? | select(.prettyref == "main") | .id] | sort | reverse | .[]' 2>/dev/null)" \
    || die "kon de linux-gate-runs niet lezen — nachtelijke main-poort is onbekend, niet groen."
  for rid in $ids; do
    rinfo="$(api GET "/actions/runs/$rid" 2>/dev/null \
      | jq -r '[.commit_sha // "", .status // "", .html_url // ""] | @tsv' 2>/dev/null)" || continue
    rsha="$(printf '%s' "$rinfo" | cut -f1)"
    [ -n "$rsha" ] || continue
    git merge-base --is-ancestor "$rsha" "$main_sha" 2>/dev/null || continue
    found="$rid"
    rstatus="$(printf '%s' "$rinfo" | cut -f2)"
    rurl="$(printf '%s' "$rinfo" | cut -f3)"
    break
  done
  [ -n "$found" ] \
    || die "geen linux-gate-run gevonden op de huidige main-geschiedenis — de nachtelijke poort is onbekend, niet groen. Draai linux-gate handmatig (workflow_dispatch op main) of wacht op de nachtrun en begin dan opnieuw. Niets gemuteerd."
  if [ "$rstatus" = "success" ]; then
    log "Nachtelijke linux-gate groen op ${rsha:0:9} (run $found)."
    return 0
  fi
  case "$rstatus" in
    failure|cancelled|skipped|error)
      local jobname jobid rlog=""
      jobname="$(api GET "/actions/runs/$found/jobs" 2>/dev/null \
        | jq -r '[.[]? | select(.status == "failure")] | .[0] | "\(.name // "onbekende job")|\(.id // "")"' 2>/dev/null)"
      jobid="${jobname##*|}"; jobname="${jobname%%|*}"
      [ -n "$jobid" ] \
        && rlog="$(api GET "/actions/jobs/$jobid/logs" 2>/dev/null \
          | grep -v '^[[:space:]]*$' | tail -n 8)"
      section "Nachtelijke linux-gate staat rood op de huidige main"
      log "run: ${rurl:-run $found} (commit ${rsha:0:9}, status $rstatus)"
      [ -z "$jobname" ] || log "eerste falende job: $jobname"
      [ -z "$rlog" ] || { log "foutcontext:"; printf '%s\n' "$rlog" | sed 's/^/     /'; }
      die "dezelfde fout zou deze release ná de tag alsnog breken — repareer main, draai linux-gate groen en begin dan pas. Niets gemuteerd."
      ;;
    *)
      die "de nieuwste linux-gate-run op main is niet voltooid (status: ${rstatus:-leeg}) — onbekend is niet groen. Wacht tot de run klaar is of draai hem handmatig opnieuw, en begin dan. Niets gemuteerd."
      ;;
  esac
}

# ── De twee prompts (de enige interactie) ───────────────────────────────────────
STEP="wachtwoord"
read_token
assert_no_pending_fixes
assert_nightly_main_gate
section "Wachtwoord"
log "Het minisign-sleutelwachtwoord wordt nu gevraagd en blijft alleen in het"
log "geheugen van deze run (voor het tekenen van SHA256SUMS, geheel aan het eind)."
MINISIGN_PW=""
# '|| true': zonder tty (stdin op /dev/null, een pipe) geeft read EOF en dus een
# niet-nul status, waarna set -e in de ERR-trap viel en het scherm de vorige stap
# als schuldige aanwees. De guard hieronder is de juiste melding; laat die 'm
# geven in plaats van 'm onbereikbaar te maken.
read -r -s -p "  minisign-wachtwoord: " MINISIGN_PW || true
echo
[ -n "$MINISIGN_PW" ] || die "leeg wachtwoord — afgebroken."

# #7: faal vóór elke onherroepelijke stap; en in --resume is dit de enige gate.
preflight

# --preflight: hier houdt de repetitie op. Alles wat een release onderweg nodig
# heeft is nu getoetst — referentiedata, schone werkboom, vrije werkboom, bekend
# herstelwerk, forge-token, mirror, deploy-host, minisign-sleutel én de
# macOS-ondertekening —
# en er is niets gemuteerd. Dit bestaat omdat de dure fouten in deze keten
# telkens vooraf kenbaar waren: een notary-profiel dat na een sessieherstart weg
# was, een deploy-host die niet antwoordde, een catalogus die achterliep. Die
# kosten nu een halve minuut in plaats van een halve release.
if [ "$PREFLIGHT_ONLY" -eq 1 ]; then
  section "Pre-flight klaar"
  log "Alles wat deze release onderweg nodig heeft, is er. Niets gemuteerd."
  log "Draai de release met:  scripts/release_auto.sh patch|minor|major"
  exit 0
fi

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
git checkout -b "$BRANCH" origin/main --quiet
BRANCH_OWNED=1
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

# ── Referentiedata: de momentopname mag mee, de inhoud niet ────────────────────
# outdated_gate heeft al vastgesteld dát er iets bewoog en dat er een generator
# voor is. Hier blijkt pas wát er bewoog, en dat bepaalt of de release doorloopt.
#
# De verversing schrijft twee soorten dingen: de gegenereerde catalogusdelen
# (`*_data.dart`, `*_android.dart`, `*_ios.dart`) en de boekhouding eromheen (de
# constante in de catalogus, de rij in de licentietabel). Blijven de eerste
# ongemoeid, dan is de bundel woordelijk gelijk gebleven en is er alleen een datum
# opgeschoven — administratie, en die rijdt gewoon mee als eigen commit.
#
# Raakt de verversing wél een gegenereerd deel, dan stopt het hier. Zo'n wijziging
# verandert waar een rapport naar verwijst, kan de `bundled`-omschrijving (en
# daarmee 31 vertalingen) raken, en trekt de vastgepinde aantallen in
# wstg/mastg/maswe_catalog_test eronder vandaan. Dat hoort iemand te zien.
#
# In beide faalgevallen wordt de werkboom eerst teruggezet. Niet uit netheid: een
# niet-gecommitte wijziging reist met de `git checkout` van cleanup_branch mee
# naar main, en precies zo kwam de v0.4.2-versiebump ooit op een vreemde branch
# terecht. Wat hier blijft staan, staat in een commit of het staat er niet.
refresh_catalog_snapshot() {
  STEP="referentiedata verversen"
  [ -n "$CATALOGS_STALE" ] || return 0
  section "Fase 1 — momentopname referentiedata bijwerken ($CATALOGS_STALE)"
  if ! scripts/refresh_catalogs.sh; then
    git checkout --quiet -- lib/services docs/LICENSE_COMPLIANCE.md 2>/dev/null || true
    die "de verversing van $CATALOGS_STALE faalde — zie hierboven. Niets gemuteerd."
  fi
  if git diff --quiet; then
    die "de poort meldt $CATALOGS_STALE als verouderd, maar verversen levert geen enkele wijziging op — de generator produceert niet waar de probe naar kijkt. Ga daar eerst achteraan; de release stopt hier."
  fi
  if git diff --name-only | grep -qE '_data\.dart|_android\.dart|_ios\.dart'; then
    git diff --stat | sed 's/^/     /'
    git checkout --quiet -- lib/services docs/LICENSE_COMPLIANCE.md 2>/dev/null || true
    die "de INHOUD van een catalogus is verschoven, niet alleen de momentopname. Dat verandert waar een rapport naar verwijst en hoort langs een mens: draai 'make refresh-catalogs', lees de diff (let op de aantallen in de catalogus-tests en op vertaalde tekst) en dien hem als eigen wijziging in. Daarna is deze release een gewone run."
  fi
  git add lib/services docs/LICENSE_COMPLIANCE.md
  CATALOG_MOVES="$(git diff --cached -U0 -- lib/services | grep -E "^[+-]const " | sed 's/^/  /')"
  git commit --quiet -m "chore(referentiedata): momentopname bijwerken ($CATALOGS_STALE)

Upstream bewoog, de gegenereerde catalogus kwam er woordelijk hetzelfde uit. Dan
is dit administratie: de genoteerde momentopname en de regel in de licentietabel.
Automatisch meegenomen door scripts/release_auto.sh; de keten stopt wél zodra een
gegenereerd deel verandert.

$CATALOG_MOVES

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
  log "Momentopname bijgewerkt en vastgelegd; de bundel zelf is niet veranderd."
  # Fail fast: is de poort hiermee echt schoon? Zo niet, dan valt make
  # check-release er straks alsnog over, tien minuten verderop en met een melding
  # die naar de verkeerde stap wijst.
  CATALOGS_LEFT="$(stale_catalog_ids "$(catalogs_probe_json)" | tr '\n' ' ')"
  CATALOGS_LEFT="$(printf '%s' "$CATALOGS_LEFT" | xargs || true)"
  [ -z "$CATALOGS_LEFT" ] \
    || die "na de verversing meldt de poort nog steeds: $CATALOGS_LEFT. De verversing haalt kennelijk iets anders op dan de probe meet."
}

refresh_catalog_snapshot

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

# De versiebump (pubspec, kOciDeckVersion, CHANGELOG, SBOM) wordt HIER — vóór de
# poort — als één commit op de release-branch vastgelegd, niet pas in fase 2. Zo
# haalt een afgebroken fase 1 de wijziging VOLLEDIG weg met 'git branch -D'
# (cleanup_branch) en blijft main schoon. Bleef de bump een niet-gecommitte
# werkboom-edit, dan droeg de 'git checkout -' in cleanup_branch die edits mee naar de
# vorige branch (main) — het v0.4.2-incident: pubspec bleef op de nieuwe versie staan,
# waarna de volgende verse run op de versie-consistentiegate strandde. make
# check-release (en de build) lezen de bestanden ongeacht commit-status, dus
# vervroegen is veilig.
STEP="versiebump committen"
git add pubspec.yaml lib/services/export_metadata.dart sbom/ CHANGELOG.md
git commit --quiet -m "chore(release): versie $NEW_VERSION

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
log "Versiebump vastgelegd op $BRANCH (pubspec, kOciDeckVersion, CHANGELOG, SBOM)."

STEP="make check-release"
section "Fase 1 — volledige poort (make check-release)"
# Kale aanroep, bewust géén 'if ! … then die': een gefaalde poort valt via set -e in
# de ERR-trap (on_err), die vóór de tag-push de release-branch opruimt. die() doet
# 'exit 1' en dat slaat de ERR-trap — en dus cleanup_branch — over; dan bleef de
# half-gebumpte branch staan. on_err meldt zelf stap "make check-release" met
# regelnummer, dus er gaat geen context verloren.
make check-release
log "make check-release groen."

STEP="make build-release"
section "Fase 1 — bouwen, tekenen, notariseren"
make build-release
# Eigen STEP: notarize-macos is een andere stap met andere faaloorzaken (schone
# bouw, zegel, notary-profiel). Onder één label meldde de trap "make
# build-release" terwijl het notariseren viel — dat stuurt de diagnose verkeerd.
STEP="make notarize-macos"
make notarize-macos
APP="$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' 2>/dev/null | head -1)"
[ -n "$APP" ] || die "geen gebouwde .app gevonden na notarize-macos."
STEP="zegel verifiëren"
codesign --verify --deep --strict "$APP"
log "Zegel geverifieerd: $APP"

PENDING_APP="$APP"

# ════════════════════════════ FASE 2 — CI-straat ═══════════════════════════════
STEP="PR openen"
section "Fase 2 — PR openen en laten landen"
# De versiebump is in fase 1 al gecommit (vóór de poort, voor een schone abort); hier
# resteert alleen de push van de release-branch (scanner-pins-commit + versiebump).
git push --quiet -u origin "$BRANCH"
BRANCH_PUSHED=1
HEAD_SHA="$(git rev-parse HEAD)"

# Scanner-pins gebumpt → eerst het nieuwe scans-image publiceren, anders vindt de
# PR-scan het niet.
[ "$PINS_BUMPED" -eq 1 ] && ensure_scans_image

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
