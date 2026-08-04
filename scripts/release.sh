#!/usr/bin/env bash
#
# One orchestrating command for cutting an OciDeck release (#1161): validate,
# prepare and build locally first, then — once everything local is green — hand
# off to the tag-driven CI chain and the distribution steps. The human role is
# to watch the outcome and confirm the interactive trust points (Developer-ID /
# notarisation and minisign passwords).
#
# The release runs on a single `v*` tag (see docs/BUILD.md § "Cutting a
# release"). This script does NOT reinvent that chain — it orchestrates the
# pieces that already exist (build_release.sh, notarize_macos.sh,
# sign_release.sh, deploy_web.sh, the `make` gates and the CI workflow).
#
#   scripts/release.sh v0.2.2      # or: make release TAG=v0.2.2
#
# SAFETY — first increment (#1161). Phase 1 (guard + local validation + build)
# is non-destructive and runs automatically. The IRREVERSIBLE, outward steps of
# phases 2 and 3 — pushing the tag, replacing the app in /Applications, and the
# public distribution — are NOT fired automatically here: each is printed as an
# explicit, ordered next step for the operator to run and confirm. A release
# orchestrator that pushes tags and overwrites the installed app must be proven
# before it fires those on its own; until then the toil this removes is the
# validation + build, and the irreversible acts stay deliberate.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TAG="${1:-${TAG:-}}"

section() { printf '\n== %s ==\n' "$1"; }
die() { printf '\nrelease: %s\n' "$1" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# ── The monotone tag-guard ──────────────────────────────────────────────────
# Refuses anything that is not a clean, strictly-higher release tag, WITHOUT
# changing a thing. The three checks:
#   1. shape        — vX.Y.Z, no pre-release/build suffix (a release, not a dev tag);
#   2. consistency  — the tag equals `v` + the version in pubspec.yaml;
#   3. monotonicity — strictly higher than the last released tag, and a legal
#                     one-axis bump — the latter delegated to the tested
#                     `make check-version-bump` gate so the semver rules live in
#                     exactly one place (tool/check_version_bump.dart, #1195).
validate_tag() {
  [ -n "$TAG" ] || die "give a tag: scripts/release.sh vX.Y.Z (or make release TAG=vX.Y.Z)"

  [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "tag '$TAG' is not a release tag of the form vX.Y.Z (no pre-release/build suffix)"
  local version="${TAG#v}"

  local pubspec_version
  pubspec_version="$(sed -n 's/^version:[[:space:]]*\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' pubspec.yaml)"
  [ -n "$pubspec_version" ] || die "could not read version: from pubspec.yaml"
  [ "$version" = "$pubspec_version" ] \
    || die "tag $TAG disagrees with pubspec.yaml version $pubspec_version — bump pubspec (and kOciDeckVersion, CHANGELOG, sbom) to $version first"

  # Strictly higher than the highest existing release tag. `sort -V` orders
  # semver correctly; the guard fails if $TAG is not strictly the greatest.
  local highest
  highest="$(git tag --list 'v*' | sort -V | tail -n1 || true)"
  if [ -n "$highest" ] && [ "$highest" != "$TAG" ]; then
    local top
    top="$(printf '%s\n%s\n' "$highest" "$TAG" | sort -V | tail -n1)"
    [ "$top" = "$TAG" ] || die "tag $TAG is not strictly higher than the last release tag $highest"
  fi
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    die "tag $TAG already exists — a released v* tag is never moved; cut the next patch instead"
  fi

  # The one-axis bump legality (patch/minor/major, nothing else) is the tested
  # gate's job; run it here so `pubspec.yaml` is judged by the same rules a PR is.
  section "Tag-guard: $TAG (version $version)"
  make check-version-bump
  echo "Tag-guard OK: $TAG is a clean, strictly-higher release tag consistent with pubspec.yaml."
}

# ── Phase 1 — prepare and build locally (non-destructive) ───────────────────
phase1_local() {
  section "Phase 1 — local validation and build"

  # Updates you'd rather find now than mid-release (advisory; does not fail).
  make catalogs-outdated || true

  # The blocking pre-tag gate: full quality pass + advisory DAST of the live host.
  make check-release

  # Build the artefacts this machine is responsible for and sign/notarise macOS.
  make build-release
  make notarize-macos

  echo
  echo "Phase 1 complete: $TAG validated, built and signed locally."
}

# ── Phases 2 & 3 — the irreversible, outward steps (guided, not auto-fired) ──
guide_remaining() {
  local version="${TAG#v}"
  cat <<EOF

== Phase 2 — tag → CI, then watch (run when Phase 1 is green) ==
The tag drives the whole CI chain (.forgejo/workflows/release.yml: web, linux,
macos, windows-ophalen, publiceren, website-downloads). A pushed v* tag is
NEVER moved — a failed release becomes the next patch tag, not a re-tag.

  1. Replace the installed app once the local build is verified:
       # close the running app first (check with pgrep, not osascript's exit code)
       ditto build/macos/Build/Products/Release/OciDeck.app /Applications/OciDeck.app
  2. Push the tag to origin (forge) AND the GitHub mirror (Windows builds there):
       git push origin $TAG && git push mirror $TAG
  3. Watch the release run once a minute until every job is done (REST route that
     works on this instance — GET /releases?limit=N filtered by tag_name, and
     actions/runs/{id}/jobs for status; /releases/tags/{tag} is unreliable here).

== Phase 3 — distribute (run only after CI is green) ==
  4. Sign the manifest and attach it:
       make sign-release SHA256SUMS=<downloaded SHA256SUMS>
  5. LibreKAT website: the website-downloads CI job runs scripts/bump-ocideck.sh
     $version + ./publiceersite; if it was skipped/failed, run that by hand in the
     website repo.
  6. Web live where CI does not (deploy secrets unset): make deploy-web.

See docs/BUILD.md § "Cutting a release" for the why behind each step.
EOF
}

require_cmd flutter
require_cmd dart
require_cmd make
require_cmd git

validate_tag
phase1_local
guide_remaining
