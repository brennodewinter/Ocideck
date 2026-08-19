#!/usr/bin/env bash
# Builds the Windows installer from an already-built Windows bundle (#1208).
#
# Run this on Windows, in a bash that has the repository on its path (Git Bash
# or MSYS2 — the same shell `make build-windows` runs in), after:
#
#   make build-windows            # -> build/windows/x64/runner/Release/
#   make build-windows-installer  # -> this script -> dist/ocideck-windows-x64-setup-<version>.exe
#
# Deliberately NOT a dependency of build-windows, for the same reason
# package-linux is not a dependency of build-linux: this should package exactly
# the bundle you just built and looked at, never quietly rebuild one behind your
# back.
#
# --- Signing ------------------------------------------------------------------
#
# Authenticode signing is optional here, and that is a considered position, not
# an oversight. #1013 weighed Windows signing and declined it: since March 2024
# no certificate type buys instant SmartScreen trust, so a certificate is a
# recurring cost for a benefit that accrues only with download volume. This
# script therefore builds a perfectly good unsigned installer for anyone without
# a certificate — and says so loudly, so nobody ships one believing otherwise.
#
# When a certificate does exist, set OCIDECK_WIN_SIGN_SHA1 to its thumbprint in
# the Windows certificate store and this script signs the executable, its DLLs
# and the finished installer. Note what is NOT configurable: there is no way to
# hand this script a .pfx and a password. Since June 2023 every publicly trusted
# code-signing key must live on a hardware token or an HSM, which prompts for
# its own PIN — so the signing material never becomes an environment variable,
# a file in the tree, or a runner secret. That is the same "no secret in CI"
# line scripts/notarize_macos.sh holds on macOS.
#
#   OCIDECK_WIN_SIGN_SHA1           certificate thumbprint (hex, no spaces).
#                                   Unset = build unsigned, with a warning.
#   OCIDECK_WIN_SIGN_TIMESTAMP_URL  RFC 3161 timestamp server. Default DigiCert.
#                                   Timestamping is not optional when signing:
#                                   without it every signature dies with the
#                                   certificate, which is now ~15 months.
#   OCIDECK_SIGNTOOL                path to signtool.exe, if it is not found.
#   OCIDECK_ISCC                    path to ISCC.exe, if it is not found.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

BUNDLE_DIR="${BUNDLE_DIR:-build/windows/x64/runner/Release}"
ISS="packaging/windows/ocideck.iss"
OUT="${OUT:-dist}"
TIMESTAMP_URL="${OCIDECK_WIN_SIGN_TIMESTAMP_URL:-http://timestamp.digicert.com}"

# --- The bundle to wrap -------------------------------------------------------

if [ ! -f "$BUNDLE_DIR/ocideck.exe" ]; then
  echo "No Windows bundle at $BUNDLE_DIR — run 'make build-windows' first." >&2
  exit 1
fi

# One version, read from the one place that holds it. `version: 0.4.6+20` -> 0.4.6
VERSION="${VERSION:-$(sed -n 's/^version:[[:space:]]*\([0-9][^+[:space:]]*\).*/\1/p' pubspec.yaml)}"
if [ -z "$VERSION" ]; then
  echo "Could not read the version from pubspec.yaml." >&2
  exit 1
fi

# --- Locating the Windows tooling ---------------------------------------------

# Both helpers print the path they found and fail (non-zero, nothing on stdout)
# when there is none, so the caller can turn that into one clear message.

find_iscc() {
  if [ -n "${OCIDECK_ISCC:-}" ]; then
    [ -x "$OCIDECK_ISCC" ] && { echo "$OCIDECK_ISCC"; return 0; }
    echo "ISCC.exe not found at '$OCIDECK_ISCC' (from the environment)." >&2
    return 1
  fi
  command -v iscc 2>/dev/null && return 0
  local candidate
  for candidate in "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
                   "/c/Program Files/Inno Setup 6/ISCC.exe"; do
    [ -x "$candidate" ] && { echo "$candidate"; return 0; }
  done
  return 1
}

find_signtool() {
  if [ -n "${OCIDECK_SIGNTOOL:-}" ]; then
    [ -x "$OCIDECK_SIGNTOOL" ] && { echo "$OCIDECK_SIGNTOOL"; return 0; }
    echo "signtool.exe not found at '$OCIDECK_SIGNTOOL' (from the environment)." >&2
    return 1
  fi
  command -v signtool 2>/dev/null && return 0
  # The Windows SDK installs one signtool.exe per SDK version side by side;
  # take the newest. `grep .` turns "no matches" into a non-zero exit.
  find "/c/Program Files (x86)/Windows Kits/10/bin" -maxdepth 3 \
       -path '*/x64/signtool.exe' 2>/dev/null | sort -Vr | head -n 1 | grep .
}

ISCC="$(find_iscc)" || {
  echo "Inno Setup 6 (ISCC.exe) not found." >&2
  echo "Install it from https://jrsoftware.org/isdl.php, or set OCIDECK_ISCC." >&2
  exit 1
}

# --- Signing (optional, see the header) ---------------------------------------

SIGN_SHA1="${OCIDECK_WIN_SIGN_SHA1:-}"
SIGNTOOL=""
if [ -n "$SIGN_SHA1" ]; then
  SIGNTOOL="$(find_signtool)" || {
    echo "OCIDECK_WIN_SIGN_SHA1 is set but signtool.exe was not found." >&2
    echo "Install the Windows SDK, or set OCIDECK_SIGNTOOL." >&2
    exit 1
  }
fi

sign() {
  # Signing is all-or-nothing: once a certificate is configured, a file that
  # fails to sign must fail the build. A half-signed installer is worse than an
  # honestly unsigned one, because it looks trustworthy in the places people check.
  [ -n "$SIGN_SHA1" ] || return 0
  "$SIGNTOOL" sign /sha1 "$SIGN_SHA1" /fd SHA256 \
    /tr "$TIMESTAMP_URL" /td SHA256 /q "$1"
}

if [ -n "$SIGN_SHA1" ]; then
  echo "Signing the application (certificate $SIGN_SHA1, timestamp $TIMESTAMP_URL)."
  # The .exe is what SmartScreen and the UAC prompt read, but the redistributed
  # DLLs beside it carry no upstream signature either, so they are signed too.
  sign "$BUNDLE_DIR/ocideck.exe"
  while IFS= read -r dll; do
    sign "$dll"
  done < <(find "$BUNDLE_DIR" -maxdepth 1 -name '*.dll' -print)
fi

# --- Build the installer ------------------------------------------------------

mkdir -p "$OUT"
echo "Building the installer with $ISCC (version $VERSION)."
"$ISCC" "/DAppVersion=$VERSION" "$ISS"

INSTALLER="$OUT/ocideck-windows-x64-setup-$VERSION.exe"
if [ ! -f "$INSTALLER" ]; then
  echo "Inno Setup reported success but $INSTALLER is not there." >&2
  exit 1
fi

sign "$INSTALLER"

echo
echo "Installer: $INSTALLER"
if [ -n "$SIGN_SHA1" ]; then
  echo "Signed and timestamped."
else
  cat <<'WARN'

  WARNING — this installer is NOT code-signed.

  Windows will show SmartScreen ("Windows protected your PC") and an "Unknown
  publisher" elevation prompt. That is expected and documented for OciDeck
  releases (SECURITY.md, docs/KNOWN_LIMITATIONS.md); the download is attested by
  the minisign signature over SHA256SUMS instead of by a per-binary certificate.
  Set OCIDECK_WIN_SIGN_SHA1 to sign — see the header of this script.
WARN
fi
