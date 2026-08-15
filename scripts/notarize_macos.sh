#!/usr/bin/env bash
set -Eeuo pipefail

# Teken en notariseer de macOS-release voor verspreiding buiten de App Store
# (Developer ID + notarytool). Zonder deze stappen meldt Gatekeeper de app als
# "beschadigd" op elke Mac behalve die van de bouwer.
#
# Waarom een apart script en niet 'flutter build' laten tekenen: een
# verspreidbare app moet aan vier eisen tegelijk voldoen, en Flutter's kale
# release-build (ad-hoc, CODE_SIGN_IDENTITY = "-") voldoet aan geen ervan:
#   1. getekend met een Developer ID Application-certificaat,
#   2. mét hardened runtime (--options runtime) op élk uitvoerbaar onderdeel,
#   3. mét een veilige tijdstempel (--timestamp),
#   4. genotariseerd door Apple en het ticket erin gestapeld.
# Een Flutter-app draagt ~18 ingebedde frameworks plus een dylib; die moeten van
# binnen naar buiten getekend worden — eerst elk framework, dan pas de bundel.
#
# Vereisten (eenmalig op te zetten, zie docs/BUILD.md):
#   - Een 'Developer ID Application'-certificaat in de keychain
#     (Xcode → Settings → Accounts → Manage Certificates).
#   - Een notarytool-keychain-profiel in de FILE-based login-keychain. Let op:
#     zónder --keychain bewaart notarytool in de sessie-gebonden data-protection
#     ("Local Items") keychain, die na een sessie-/runnerherstart onvindbaar
#     wordt (zo faalde v0.1.3-rc1). Forceer daarom de login-keychain:
#       xcrun notarytool store-credentials \
#         --keychain "$HOME/Library/Keychains/login.keychain-db" ocideck-notary \
#         --apple-id "<apple-id>" --team-id <TEAM_ID>
#
# Overschrijfbaar via de omgeving (voor CI of een andere ondertekenaar):
#   OCIDECK_SIGN_IDENTITY   standaard: Developer ID Application: Brenno de Winter (AMT83P4B3L)
#   OCIDECK_NOTARY_PROFILE  standaard: ocideck-notary
#
# Gebruik:
#   scripts/notarize_macos.sh              # schoon bouwen, tekenen, notariseren, staplen, verpakken
#   scripts/notarize_macos.sh --skip-build # de bestaande build/-uitvoer gebruiken (geen herbouw)
#   scripts/notarize_macos.sh --no-package # stop na staplen (CI verpakt zelf onder de release-naam)
# De twee vlaggen zijn combineerbaar en volgordeonafhankelijk.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IDENTITY="${OCIDECK_SIGN_IDENTITY:-Developer ID Application: Brenno de Winter (AMT83P4B3L)}"
PROFILE="${OCIDECK_NOTARY_PROFILE:-ocideck-notary}"
# Lees het notary-profiel expliciet uit de FILE-based default keychain
# (login.keychain-db), niet uit de sessie-gebonden data-protection keychain waar
# notarytool standaard in kijkt — die is na een sessiewissel onvindbaar, zoals
# v0.1.3-rc1 aantoonde. `security default-keychain` geeft het pad los van HOME.
KEYCHAIN="${OCIDECK_NOTARY_KEYCHAIN:-$(security default-keychain -d user 2>/dev/null | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')}"
[ -n "$KEYCHAIN" ] || KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
ENTITLEMENTS="macos/Runner/Release.entitlements"
APP="build/macos/Build/Products/Release/OciDeck.app"
DIST_DIR="build/macos/dist"
ZIP="$DIST_DIR/OciDeck.zip"

SKIP_BUILD=0
NO_PACKAGE=0
PREFLIGHT=0
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=1 ;;
    --no-package) NO_PACKAGE=1 ;;
    --preflight) PREFLIGHT=1 ;;
    *) echo "Onbekende optie: $arg" >&2; exit 2 ;;
  esac
done

section() { printf '\n== %s ==\n' "$1"; }
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Ontbrekend commando: $1" >&2; exit 127; }
}

# Een macOS-app tekenen kan alleen op macOS.
[[ "$(uname -s)" == "Darwin" ]] || {
  echo "Dit script tekent een macOS-app en draait dus op macOS." >&2
  exit 1
}
require_cmd flutter
require_cmd xcrun
require_cmd codesign
require_cmd ditto
require_cmd security

# Vroeg en duidelijk stoppen als de identiteit ontbreekt. Anders faalt codesign
# pas halverwege met een cryptische melding, na een build van minuten.
if ! security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
  echo "Geen geldige ondertekenidentiteit gevonden: $IDENTITY" >&2
  echo "Aanwezige identiteiten:" >&2
  security find-identity -v -p codesigning >&2 || true
  exit 1
fi

# --preflight (voor scripts/release_auto.sh): de ondertekenidentiteit is hierboven
# geverifieerd; toets nu óók het notary-profiel en stop. Zo faalt een verdwenen
# profiel (bv. na een sessieherstart, zoals v0.1.3-rc1) vóór de ~10 min build i.p.v.
# pas bij het inzenden. 'notarytool history' valideert profiel én Apple-verbinding.
if [[ $PREFLIGHT -eq 1 ]]; then
  section "Pre-flight — ondertekenidentiteit en notary-profiel"
  # 'notarytool history' valideert het profiel én de Apple-verbinding read-only.
  # Toon bij falen de ECHTE fout, niet een generieke tekst: een eerdere versie gaf
  # '--limit 1' mee — dat kent notarytool niet (exit 64), waardoor élke release
  # onterecht op "profiel verdwenen" strandde. De echte fout tonen maakt zo'n vals
  # alarm meteen zichtbaar.
  if ! NOTARY_OUT="$(xcrun notarytool history --keychain "$KEYCHAIN" --keychain-profile "$PROFILE" 2>&1)"; then
    echo "Notary-profiel '$PROFILE' in keychain '$KEYCHAIN' werkt niet:" >&2
    printf '%s\n' "$NOTARY_OUT" | sed 's/^/   /' >&2
    echo "Mogelijk na een sessieherstart verdwenen — herstel met 'xcrun notarytool store-credentials' (zie de kop van dit script en docs/BUILD.md)." >&2
    exit 1
  fi
  echo "Pre-flight OK: identiteit '$IDENTITY' aanwezig, notary-profiel '$PROFILE' geldig."
  exit 0
fi

if [[ $SKIP_BUILD -eq 0 ]]; then
  # Schoon bouwen. Incrementeel bouwen breekt stil het zegel van App.framework,
  # waarna het tekenen of de notarisatie op een verwarrende plek faalt.
  section "Schoon bouwen"
  flutter clean
  # `flutter clean` méldt een mislukte verwijdering ("Failed to remove …:
  # Directory not empty") maar eindigt met exit 0. Blijft .dart_tool staan — het
  # klassieke geval is een tweede flutter-proces in dezelfde werkboom dat de map
  # blijft aanvullen — dan is de eerstvolgende dart-aanroep kansloos: de
  # hooks_runner-cache is half weg en `dart run` valt met een PathNotFoundException
  # op een stdout.txt die er niet meer is. Dat gebeurde in de v0.4.4-run van
  # 15-08-2026: de release strandde op `sbom-verify`, een stap die niets met de
  # oorzaak te maken had. Toets daarom de invariant zelf, niet de exitstatus.
  if [[ -d .dart_tool ]]; then
    echo "flutter clean liet .dart_tool staan — deze bouw is niet schoon." >&2
    echo "Draait er nog een flutter/dart-proces in deze werkboom (flutter run," >&2
    echo "flutter test, een IDE-sessie)? Sluit dat af en draai opnieuw." >&2
    # ps, niet 'pgrep -af': die -a drukt op macOS alleen pid's af.
    # shellcheck disable=SC2009 # zie hierboven; pgrep geeft hier geen commandoregel.
    ps -Ao pid=,command= \
      | grep -E 'flutter_tools\.snapshot|frontend_server|flutter_tester' \
      | grep -v ' grep ' | cut -c1-140 | sed 's/^/   /' >&2 || true
    exit 1
  fi
  make build-macos
else
  section "Herbouw overgeslagen (--skip-build) — bestaande build/-uitvoer wordt gebruikt"
fi

[[ -d "$APP" ]] || {
  echo "Geen app gevonden op $APP — bouw eerst (laat --skip-build weg)." >&2
  exit 1
}

# Inside-out tekenen: eerst elk ingebed framework/dylib, dan pas de app-bundel.
# Hardened runtime en een veilige tijdstempel zijn allebei voorwaarden voor
# notarisatie; de entitlements horen alleen op de buitenste bundel.
section "Tekenen (Developer ID + hardened runtime)"
while IFS= read -r -d '' f; do
  echo "  ${f#"$APP"/Contents/Frameworks/}"
  codesign --force --options runtime --timestamp -s "$IDENTITY" "$f"
done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -mindepth 1 \
  \( -name '*.framework' -o -name '*.dylib' \) -print0)
codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" -s "$IDENTITY" "$APP"

section "Handtekening lokaal verifiëren"
codesign --verify --deep --strict --verbose=2 "$APP"

# Zippen en notariseren. --wait blokkeert tot Apple klaar is; bij afkeuring
# halen we het logboek op zodat de reden zichtbaar is en niet in de melding
# "Invalid" verdwijnt.
section "Notariseren bij Apple (wachten op uitslag)"
mkdir -p "$DIST_DIR"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
OUT="$(xcrun notarytool submit "$ZIP" --keychain "$KEYCHAIN" --keychain-profile "$PROFILE" --wait 2>&1)" || true
echo "$OUT"
if ! grep -q "status: Accepted" <<<"$OUT"; then
  SUBID="$(awk -F': ' '/^  id:/{print $2; exit}' <<<"$OUT")"
  echo "Notarisatie niet geaccepteerd." >&2
  [[ -n "$SUBID" ]] && xcrun notarytool log "$SUBID" --keychain "$KEYCHAIN" --keychain-profile "$PROFILE" >&2 || true
  exit 1
fi

# Ticket in de app stapelen, zodat ook een offline Mac de notarisatie ziet.
section "Ticket stapelen en eindcontrole"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -t exec -vvv "$APP"

# De notarisatie-zip ging vóór het staplen de deur uit; die hebben we niet meer nodig.
rm -f "$ZIP"

# In CI verpakt de workflow zelf onder de release-artefactnaam; dan stoppen we
# hier, mét een gestapelde app op schijf.
if [[ $NO_PACKAGE -eq 1 ]]; then
  section "Klaar (getekend, genotariseerd en gestapeld — verpakken overgeslagen)"
  echo "Genotariseerde app : $APP"
  exit 0
fi

# Verspreidbaar pakket: zippen mét het gestapelde ticket, onder een versienaam,
# met een sha256 ernaast zodat een download te controleren is.
section "Verspreidbaar pakket schrijven"
VERSION="$(awk -F'[ +]' '/^version:/{print $2; exit}' pubspec.yaml)"
DIST_ZIP="$DIST_DIR/OciDeck-${VERSION}-macos.zip"
rm -f "$DIST_ZIP"
ditto -c -k --keepParent "$APP" "$DIST_ZIP"
( cd "$DIST_DIR" && shasum -a 256 "$(basename "$DIST_ZIP")" > SHA256SUMS )

section "Klaar"
echo "Genotariseerde app  : $APP"
echo "Verspreidbaar pakket: $DIST_ZIP"
echo "Checksum            : $DIST_DIR/SHA256SUMS"
cat "$DIST_DIR/SHA256SUMS"
