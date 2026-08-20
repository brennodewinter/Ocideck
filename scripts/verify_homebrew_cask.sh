#!/usr/bin/env bash
# Checks that the Homebrew tap really carries a release, by reading the cask
# back out of the tap and comparing its version to the tag.
#
# Why this exists: the cask job in the release chain deliberately swallows a
# failed clone (exit 0) so an unreachable tap cannot turn a finished release
# red. That made a green job also read as "tap updated" when nothing had been
# pushed at all — a revoked HOMEBREW_TAP_TOKEN stayed invisible until someone
# installed a stale version. This measures "pushed" instead of assuming it.
#
# The tap is read unauthenticated, over the same public URL Homebrew itself
# uses: the question is what a `brew install` gets, not what a token can see.
#
# With --mirror it also checks the GitHub mirror of the tap. That mirror is a
# backup, not the source, but the `brew tap brennodewinter/ocideck` shorthand
# still resolves there, so a stalled push-mirror serves stale casks while the
# forge is perfectly up to date. Mirroring is asynchronous, so a mirror that
# lags a *fresh* release is normal: it only counts as a failure once the
# release is older than MIRROR_GRACE_HOURS (default 24). That is why --mirror
# belongs in a periodic check and not in the release run itself.
#
# Without a tag it checks the newest release — the same by-hand comparison in
# one command. CASK_FILE / MIRROR_CASK_FILE read a local cask instead of
# querying the tap, and RELEASE_PUBLISHED_AT skips the release lookup (used by
# the test, which must not depend on the network).
set -euo pipefail

FORGE_URL="${GITHUB_SERVER_URL:-https://pawprint.vigilis.online}"
API="$FORGE_URL/api/v1"
TAP_REPOSITORY="${HOMEBREW_TAP_REPOSITORY:-LibreKAT/homebrew-ocideck}"
SOURCE_REPOSITORY="${OCIDECK_REPOSITORY:-LibreKAT/Ocideck}"
MIRROR_REPOSITORY="${MIRROR_REPOSITORY:-brennodewinter/homebrew-ocideck}"
MIRROR_GRACE_HOURS="${MIRROR_GRACE_HOURS:-24}"

usage() {
  cat <<'USAGE'
Usage: verify_homebrew_cask.sh [--mirror] [tag]

  tag        release tag to check against (default: the newest release)
  --mirror   also check the GitHub mirror of the tap, tolerating a lag of
             MIRROR_GRACE_HOURS after the release
USAGE
}

CHECK_MIRROR=0
TAG=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mirror) CHECK_MIRROR=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) TAG="$1" ;;
  esac
  shift
done

# Pulls the first "version" line out of a cask on stdin.
cask_version() {
  sed -n 's/^[[:space:]]*version "\([^"]*\)".*/\1/p' | head -n1
}

# GNU date first, BSD date second: this runs both on the Linux CI container and
# on a maintainer's Mac, and the two spell the same parse incompatibly.
iso_to_epoch() {
  date -u -d "$1" +%s 2>/dev/null \
    || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
}

if [ -z "$TAG" ]; then
  # One release object, so one tag_name; splitting on commas keeps the match
  # anchored to that field instead of letting a greedy `.*` run past it.
  TAG="$(curl -fsSL "$API/repos/$SOURCE_REPOSITORY/releases?limit=1" \
    | tr ',' '\n' | sed -n 's/.*"tag_name":"\([^"]*\)".*/\1/p' | head -n1)"
  if [ -z "$TAG" ]; then
    echo "Could not read the newest release tag from $SOURCE_REPOSITORY." >&2
    exit 1
  fi
  echo "No tag given; checking the newest release: $TAG"
fi

# Prereleases never reach the tap (the generator skips them too), so there is
# nothing to compare -- staying at the previous stable version is correct.
if [[ "$TAG" == *-* ]]; then
  echo "Prerelease tag $TAG is never published to the tap; nothing to check."
  exit 0
fi

case "$TAG" in
  v*) EXPECTED="${TAG#v}" ;;
  *)  EXPECTED="$TAG" ;;
esac

if [ -n "${CASK_FILE:-}" ]; then
  if [ ! -f "$CASK_FILE" ]; then
    echo "Cask file not found: $CASK_FILE" >&2
    exit 1
  fi
  CASK="$(cat "$CASK_FILE")"
  SOURCE="$CASK_FILE"
else
  SOURCE="$TAP_REPOSITORY"
  CASK_URL="$API/repos/$TAP_REPOSITORY/raw/Casks/ocideck.rb"
  if ! CASK="$(curl -fsSL "$CASK_URL")"; then
    echo "Could not read Casks/ocideck.rb from $TAP_REPOSITORY ($CASK_URL)." >&2
    echo "The tap is gone, private, or was never populated." >&2
    exit 1
  fi
fi

FOUND="$(printf '%s\n' "$CASK" | cask_version)"

if [ -z "$FOUND" ]; then
  echo "No version found in the cask from $SOURCE." >&2
  exit 1
fi

if [ "$FOUND" != "$EXPECTED" ]; then
  echo "Tap is not on this release: cask says $FOUND, release is $EXPECTED." >&2
  echo "The push into $TAP_REPOSITORY did not land -- check HOMEBREW_TAP_TOKEN." >&2
  exit 1
fi

echo "Tap $SOURCE is on $FOUND, matching $TAG."

if [ "$CHECK_MIRROR" = 0 ]; then
  exit 0
fi

if [ -n "${MIRROR_CASK_FILE:-}" ]; then
  if [ ! -f "$MIRROR_CASK_FILE" ]; then
    echo "Mirror cask file not found: $MIRROR_CASK_FILE" >&2
    exit 1
  fi
  MIRROR_CASK="$(cat "$MIRROR_CASK_FILE")"
  MIRROR_SOURCE="$MIRROR_CASK_FILE"
else
  MIRROR_SOURCE="$MIRROR_REPOSITORY"
  # HEAD rather than a branch name: the mirror follows whatever the tap's
  # default branch is called, and that is not this script's business.
  MIRROR_URL="https://raw.githubusercontent.com/$MIRROR_REPOSITORY/HEAD/Casks/ocideck.rb"
  if ! MIRROR_CASK="$(curl -fsSL "$MIRROR_URL")"; then
    echo "Could not read the cask from mirror $MIRROR_REPOSITORY ($MIRROR_URL)." >&2
    echo "The mirror is gone or was never populated." >&2
    exit 1
  fi
fi

MIRROR_FOUND="$(printf '%s\n' "$MIRROR_CASK" | cask_version)"

if [ "$MIRROR_FOUND" = "$EXPECTED" ]; then
  echo "Mirror $MIRROR_SOURCE is on $MIRROR_FOUND too."
  exit 0
fi

# The mirror is behind. Whether that is a fault depends on how long it has had
# to catch up, so ask the release when it was published.
PUBLISHED="${RELEASE_PUBLISHED_AT:-}"
if [ -z "$PUBLISHED" ]; then
  PUBLISHED="$(curl -fsSL "$API/repos/$SOURCE_REPOSITORY/releases/tags/$TAG" \
    | tr ',' '\n' | sed -n 's/.*"published_at":"\([^"]*\)".*/\1/p' | head -n1)"
fi

AGE_HOURS=""
if [ -n "$PUBLISHED" ]; then
  if PUBLISHED_EPOCH="$(iso_to_epoch "$PUBLISHED")"; then
    AGE_HOURS="$((($(date -u +%s) - PUBLISHED_EPOCH) / 3600))"
  fi
fi

if [ -n "$AGE_HOURS" ] && [ "$AGE_HOURS" -lt "$MIRROR_GRACE_HOURS" ]; then
  echo "Mirror $MIRROR_SOURCE is still on ${MIRROR_FOUND:-nothing}, but $TAG is"
  echo "only ${AGE_HOURS}h old (grace: ${MIRROR_GRACE_HOURS}h) -- push-mirroring is"
  echo "asynchronous, so this is not yet a fault."
  exit 0
fi

echo "Mirror $MIRROR_SOURCE is stale: it says ${MIRROR_FOUND:-nothing}, the release" >&2
echo "is $EXPECTED and is ${AGE_HOURS:-?}h old. The forge tap is correct, so the" >&2
echo "push-mirror on the tap repo has stopped syncing -- check its settings and" >&2
echo "its credentials. Users on the GitHub shorthand are being served a stale cask." >&2
exit 1
