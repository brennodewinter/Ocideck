#!/usr/bin/env bash
# Publish one already-built OciDeck .deb to the public Forgejo APT registry.
#
# The registry signs its Release metadata with the instance repository key. The
# upload credential is deliberately separate from the release token and needs
# only the `write:package` scope. A repeated release is accepted only when the
# registry already contains these exact package bytes; a conflicting package
# with the same version fails closed.
set -euo pipefail

PACKAGE_FILE="${1:-}"
SERVER_URL="${FORGEJO_SERVER_URL:-https://pawprint.vigilis.online}"
OWNER="${DEBIAN_PACKAGE_OWNER:-LibreKAT}"
DISTRIBUTION="${DEBIAN_DISTRIBUTION:-stable}"
COMPONENT="${DEBIAN_COMPONENT:-main}"
TOKEN="${PACKAGE_TOKEN:-}"

if [ -z "$PACKAGE_FILE" ] || [ ! -f "$PACKAGE_FILE" ]; then
  echo "usage: PACKAGE_TOKEN=... $0 <ocideck.deb>" >&2
  exit 1
fi
if [ -z "$TOKEN" ]; then
  echo "PACKAGE_TOKEN is required (use a Forgejo token with write:package)." >&2
  exit 1
fi
if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "dpkg-deb is required to validate the package before publication." >&2
  exit 1
fi

PACKAGE_NAME="$(dpkg-deb -f "$PACKAGE_FILE" Package)"
PACKAGE_VERSION="$(dpkg-deb -f "$PACKAGE_FILE" Version)"
PACKAGE_ARCH="$(dpkg-deb -f "$PACKAGE_FILE" Architecture)"
if [ "$PACKAGE_NAME" != "ocideck" ] || [ "$PACKAGE_ARCH" != "amd64" ]; then
  echo "Refusing to publish $PACKAGE_NAME/$PACKAGE_ARCH; expected ocideck/amd64." >&2
  exit 1
fi
if [ -z "$PACKAGE_VERSION" ]; then
  echo "Refusing to publish a package without a version." >&2
  exit 1
fi

EXPECTED_SHA256="$(sha256sum "$PACKAGE_FILE" | cut -d ' ' -f 1)"
UPLOAD_URL="$SERVER_URL/api/packages/$OWNER/debian/pool/$DISTRIBUTION/$COMPONENT/upload"
RESPONSE="$(mktemp)"
trap 'rm -f "$RESPONSE"' EXIT

HTTP_CODE="$(curl -sS -o "$RESPONSE" -w '%{http_code}' -X PUT \
  -H "Authorization: token $TOKEN" \
  --upload-file "$PACKAGE_FILE" \
  "$UPLOAD_URL")"

if [ "$HTTP_CODE" = "201" ]; then
  echo "Published ocideck $PACKAGE_VERSION to $DISTRIBUTION/$COMPONENT."
  exit 0
fi

if [ "$HTTP_CODE" = "409" ]; then
  FILES_URL="$SERVER_URL/api/v1/packages/$OWNER/debian/$PACKAGE_NAME/$PACKAGE_VERSION/files"
  REMOTE_SHA256="$(curl -fsSL -H "Authorization: token $TOKEN" "$FILES_URL" \
    | jq -r --arg expected "$EXPECTED_SHA256" \
      '.[] | select(.sha256 == $expected) | .sha256' \
    | head -n 1)"
  if [ "$REMOTE_SHA256" = "$EXPECTED_SHA256" ]; then
    echo "OciDeck $PACKAGE_VERSION is already published with the same sha256."
    exit 0
  fi
  echo "OciDeck $PACKAGE_VERSION already exists with different package bytes." >&2
  exit 1
fi

echo "Debian registry upload failed with HTTP $HTTP_CODE:" >&2
cat "$RESPONSE" >&2
exit 1
