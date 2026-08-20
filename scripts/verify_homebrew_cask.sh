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
# Without a tag it checks the newest release — the same by-hand comparison in
# one command. Set CASK_FILE to read a local cask instead of querying the tap
# (used by the test).
set -euo pipefail

FORGE_URL="${GITHUB_SERVER_URL:-https://pawprint.vigilis.online}"
API="$FORGE_URL/api/v1"
TAP_REPOSITORY="${HOMEBREW_TAP_REPOSITORY:-LibreKAT/homebrew-ocideck}"
SOURCE_REPOSITORY="${OCIDECK_REPOSITORY:-LibreKAT/Ocideck}"

TAG="${1:-}"

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

FOUND="$(printf '%s\n' "$CASK" \
  | sed -n 's/^[[:space:]]*version "\([^"]*\)".*/\1/p' | head -n1)"

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
