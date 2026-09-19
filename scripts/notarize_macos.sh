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
# Nodig voor het normaliseren van het PDFium-framework, verderop.
require_cmd otool
require_cmd install_name_tool

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

# ---------------------------------------------------------------------------
# PDFium-framework normaliseren, vóór het tekenen.
#
# pdfium_flutter linkt zijn Swift-plugin tegen "-framework PDFium", terwijl de
# native-assets-stap van Flutter datzelfde framework als pdfium.framework
# wegschrijft: install name @rpath/pdfium.framework/pdfium, CFBundleExecutable
# "pdfium". Op een hoofdletterongevoelige buildschijf komen die twee in dezelfde
# map terecht. De mapnaam houdt dan de hoofdletters van de linker en de inhoud
# de kleine letters van de native asset, en de bundel vertrekt met
# PDFium.framework/Versions/A/pdfium erin.
#
# Oudere dyld-versies laadden dat alsnog, juist omdat APFS hoofdletterongevoelig
# is. Op macOS 27 eist dyld bij een hardened, genotariseerde binary dat de
# bladnaam exact klopt. De app stopt dan bij het starten met "Library not
# loaded: @rpath/PDFium.framework/PDFium ... security level requires its leaf
# name to match". Zo strandde de gedownloade v0.6.4 op macOS 27.2; macOS 26.6
# (de bouwmachine) laadt dezelfde bundel nog, dus lokaal starten bewijst niets.
#
# Er wordt naar kleine letters genormaliseerd. Alles behalve dat ene load
# command in het hoofdbinary draagt die schrijfwijze al: de install name van het
# framework, zijn Info.plist en de native-assets-mapping van Dart. Hernoemen
# gaat in twee stappen, want op een hoofdletterongevoelig volume is "PDFium"
# naar "pdfium" hernoemen geen wijziging.
#
# Deze stap hoort vóór het tekenen: hernoemen en install_name_tool breken het
# zegel van de bundel.
# ---------------------------------------------------------------------------
section "PDFium-framework normaliseren"
FRAMEWORKS="$APP/Contents/Frameworks"
MAIN_BINARY="$APP/Contents/MacOS/OciDeck"
PDFIUM_REF_UPPER='@rpath/PDFium.framework/PDFium'
PDFIUM_REF_LOWER='@rpath/pdfium.framework/pdfium'

# Hernoemt alleen als de naam op schijf werkelijk afwijkt. De omweg via een
# tijdelijke naam is nodig omdat een rechtstreekse mv op dit volume niets doet.
rename_exact() {
  local path="$1" want="$2" dir base
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  if [[ "$base" == "$want" ]]; then
    return 0
  fi
  mv "$path" "$dir/.$want.rename"
  mv "$dir/.$want.rename" "$dir/$want"
  echo "  hernoemd: $base -> $want"
}

# -iname geeft de naam die er werkelijk staat; een test op het pad zou op dit
# volume ook bij de verkeerde schrijfwijze slagen en dus niets bewaken.
PDFIUM_FW="$(find "$FRAMEWORKS" -maxdepth 1 -iname 'pdfium.framework' -print -quit)"
if [[ -z "$PDFIUM_FW" ]]; then
  echo "Geen pdfium-framework in $FRAMEWORKS gevonden." >&2
  echo "Is de PDF-bewijsviewer uit de build gevallen? Zonder dit framework start de app niet." >&2
  exit 1
fi
rename_exact "$PDFIUM_FW" 'pdfium.framework'
PDFIUM_FW="$FRAMEWORKS/pdfium.framework"

PDFIUM_BIN="$(find "$PDFIUM_FW/Versions/A" -maxdepth 1 -iname 'pdfium' -print -quit)"
if [[ -z "$PDFIUM_BIN" ]]; then
  echo "Geen pdfium-binary in $PDFIUM_FW/Versions/A." >&2
  exit 1
fi
rename_exact "$PDFIUM_BIN" 'pdfium'
PDFIUM_BIN="$PDFIUM_FW/Versions/A/pdfium"

# De symlink bovenin de framework-map draagt dezelfde naam als de binary en
# wijst ernaar. Hier niet hernoemen maar opnieuw zetten: bij een hernoemde
# binary klopt ook het doel van de bestaande symlink niet meer.
PDFIUM_LINK="$(find "$PDFIUM_FW" -maxdepth 1 -iname 'pdfium' -print -quit)"
if [[ -n "$PDFIUM_LINK" ]]; then
  rm -f "$PDFIUM_LINK"
fi
ln -s 'Versions/Current/pdfium' "$PDFIUM_FW/pdfium"

# Info.plist en install name gelijktrekken, zodat de identiteit van het
# framework op elk niveau dezelfde schrijfwijze heeft.
PDFIUM_PLIST="$PDFIUM_FW/Versions/A/Resources/Info.plist"
if [[ -f "$PDFIUM_PLIST" ]]; then
  for key in CFBundleExecutable CFBundleName; do
    if [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$PDFIUM_PLIST" 2>/dev/null)" != "pdfium" ]]; then
      /usr/libexec/PlistBuddy -c "Set :$key pdfium" "$PDFIUM_PLIST"
      echo "  Info.plist: $key -> pdfium"
    fi
  done
fi
if [[ "$(otool -D "$PDFIUM_BIN" | tail -n1)" != "$PDFIUM_REF_LOWER" ]]; then
  install_name_tool -id "$PDFIUM_REF_LOWER" "$PDFIUM_BIN"
  echo "  install name -> $PDFIUM_REF_LOWER"
fi

# Het hoofdbinary is in v0.6.4 de enige plek met de hoofdlettervariant.
if otool -L "$MAIN_BINARY" | grep -qF "$PDFIUM_REF_UPPER"; then
  install_name_tool -change "$PDFIUM_REF_UPPER" "$PDFIUM_REF_LOWER" "$MAIN_BINARY"
  echo "  load command in OciDeck -> $PDFIUM_REF_LOWER"
fi

echo "  in orde: pdfium.framework/pdfium, overal dezelfde schrijfwijze"

# ---------------------------------------------------------------------------
# Bundelkoppelingen toetsen, vóór het tekenen.
#
# De PDFium-normalisatie hierboven repareert het ene geval dat v0.6.4 brak. Deze
# controle bewaakt de hele klasse: élke @rpath-, @executable_path- of
# @loader_path-verwijzing in élk Mach-O-bestand van de bundel moet oplossen naar
# een bestand dat er is, met exact dezelfde schrijfwijze per padcomponent. Op een
# hoofdletterongevoelig volume slaagt `test -e` ook bij de verkeerde
# schrijfwijze; `find -name` vergelijkt tegen de directory-entries zelf en ziet
# het verschil wél. Daarom loopt de controle component voor component.
#
# Waarom hier en niet pas bij het starten: v0.6.4 is getekend, genotariseerd en
# gestapeld met een verwijzing die dyld op macOS 27 weigert. Een geldige
# handtekening zegt niets over laden. Deze stap faalt de release op de
# bouwmachine, niet op de Mac van een gebruiker.
# ---------------------------------------------------------------------------
section "Bundelkoppelingen toetsen (exacte schrijfwijze)"

# Loopt REL component voor component onder ROOT af en eist per stap een
# directory-entry met precies die naam. Symlinks (Versions/Current) worden
# gevolgd; de bladnaam moet ook ná het volgen exact kloppen, want dyld
# vergelijkt de gevraagde bladnaam met de naam van het bestand dat hij opent.
resolve_exact() { # resolve_exact ROOT REL -> pad op stdout, of status 1
  local cur="$1" rel="$2" comp hit parts
  IFS='/' read -r -a parts <<<"$rel"
  for comp in "${parts[@]}"; do
    [[ -n "$comp" && "$comp" != "." ]] || continue
    # '..' is geen directory-entry en heeft geen schrijfwijze; gewoon omhoog.
    [[ "$comp" != ".." ]] || { cur="$cur/.."; continue; }
    hit="$(find "$cur/" -maxdepth 1 -mindepth 1 -name "$comp" -print -quit 2>/dev/null)"
    [[ -n "$hit" ]] || return 1
    cur="$hit"
  done
  [[ -e "$cur" ]] || return 1
  [[ "$(basename "$(realpath "$cur")")" == "${parts[${#parts[@]}-1]}" ]] || return 1
  printf '%s\n' "$cur"
}

# Alle LC_RPATH-paden van een Mach-O, met @executable_path en @loader_path al
# ingevuld. Het hoofdbinary levert de rpaths die dyld voor de hele keten
# hanteert; een framework voegt hoogstens zijn eigen toe.
rpaths_of() { # rpaths_of MACHO EXEC_DIR
  local f="$1" exec_dir="$2" loader_dir
  loader_dir="$(dirname "$f")"
  otool -l "$f" 2>/dev/null \
    | awk '/^ *cmd LC_RPATH/{r=1} r && /^ *path /{print $2; r=0}' \
    | sed -e "s|^@executable_path|$exec_dir|" -e "s|^@loader_path|$loader_dir|"
}

# Toetst één bundel. Schrijft per fout één regel naar stderr en geeft het aantal
# fouten terug als status, zodat de aanroeper in één keer alles ziet.
check_bundle_links() { # check_bundle_links APP
  local app="$1" exec_dir main_bin f dep rest hit root found errors=0
  exec_dir="$app/Contents/MacOS"
  main_bin="$(find "$exec_dir" -maxdepth 1 -type f -perm -u+x -print -quit)"
  local main_rpaths
  main_rpaths="$(rpaths_of "$main_bin" "$exec_dir")"
  while IFS= read -r -d '' f; do
    file -b "$f" 2>/dev/null | grep -q 'Mach-O' || continue
    while IFS= read -r dep; do
      case "$dep" in
        @rpath/*)           rest="${dep#@rpath/}" ;;
        @executable_path/*) rest="${dep#@executable_path/}" ;;
        @loader_path/*)     rest="${dep#@loader_path/}" ;;
        *) continue ;;
      esac
      found=0
      case "$dep" in
        @rpath/*)
          while IFS= read -r root; do
            [[ -n "$root" ]] || continue
            if [[ "$root" != "$app"/* ]]; then
              # Een rpath buiten de bundel (/usr/lib/swift) hoort bij het
              # systeem; als het daar staat, is het geen zaak van deze bundel.
              [[ -e "$root/$rest" ]] && { found=1; break; }
              continue
            fi
            hit="$(resolve_exact "$root" "$rest")" && { found=1; break; }
          done < <(printf '%s\n' "$main_rpaths"; rpaths_of "$f" "$exec_dir")
          ;;
        @executable_path/*) hit="$(resolve_exact "$exec_dir" "$rest")" && found=1 ;;
        @loader_path/*)     hit="$(resolve_exact "$(dirname "$f")" "$rest")" && found=1 ;;
      esac
      if [[ $found -eq 0 ]]; then
        errors=$((errors + 1))
        echo "  FOUT ${f#"$app"/}: $dep" >&2
        # Diagnose: bestaat het wel, maar anders geschreven? Dan is dít de
        # v0.6.4-klasse en niet een ontbrekend framework.
        hit="$(find "$app/Contents/Frameworks" -ipath "$app/Contents/Frameworks/$rest" -print -quit 2>/dev/null)"
        if [[ -n "$hit" ]]; then
          echo "       bestaat als ${hit#"$app"/} (andere schrijfwijze; dyld weigert dat op macOS 27)" >&2
        else
          echo "       lost binnen de bundel nergens op" >&2
        fi
      fi
    done < <(otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}')
  done < <(find "$app" -type f \( -perm -u+x -o -name '*.dylib' \) -print0)
  return "$errors"
}

if ! check_bundle_links "$APP"; then
  echo "Bundelkoppelingen kloppen niet (zie boven). Deze app zou getekend en" >&2
  echo "genotariseerd raken maar op macOS 27 niet starten; zo verging het v0.6.4." >&2
  exit 1
fi
echo "  in orde: elke verwijzing lost op met exact dezelfde schrijfwijze"

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

# ---------------------------------------------------------------------------
# Opstartproef: de app die zo de deur uitgaat écht starten.
#
# Handtekening, notarisatie en de koppelingscontrole hierboven zijn allemaal
# statisch. Wat dyld en het hardened runtime bij het laden doen, blijkt alleen
# door te laden. Het hoofdbinary wordt rechtstreeks gestart (niet via `open`,
# dan is de exitstatus van de app zelf zichtbaar), krijgt een paar seconden en
# wordt dan netjes beëindigd. Een dyld-weigering komt binnen een seconde met
# een niet-nul status en "Library not loaded" op stderr; die gaat hier de
# release in als fout, niet als klacht van een gebruiker.
#
# Alleen in een grafische sessie: zonder WindowServer kan een Cocoa-app niet
# opkomen, en dat zou een valse rode uitslag zijn. De Mac-runner draait als
# LaunchAgent in de gebruikerssessie en komt dus door deze poort; de proef
# toont daar enkele seconden een venster. OCIDECK_SKIP_LAUNCH_PROBE=1 slaat
# hem bewust over.
# ---------------------------------------------------------------------------
section "Opstartproef"
if [[ "${OCIDECK_SKIP_LAUNCH_PROBE:-0}" == "1" ]]; then
  echo "  overgeslagen (OCIDECK_SKIP_LAUNCH_PROBE=1)"
elif [[ "$(launchctl managername 2>/dev/null)" != "Aqua" ]]; then
  echo "  overgeslagen: geen grafische sessie (launchctl managername != Aqua)"
else
  PROBE_LOG="$(mktemp -t ocideck-opstartproef)"
  "$APP/Contents/MacOS/OciDeck" >"$PROBE_LOG" 2>&1 &
  PROBE_PID=$!
  # Zes seconden is ruim: een dyld-fout valt binnen één seconde, en een app die
  # zo lang leeft heeft al zijn frameworks geladen en zijn venster gebouwd.
  sleep 6
  if kill -0 "$PROBE_PID" 2>/dev/null; then
    kill "$PROBE_PID" 2>/dev/null || true
    wait "$PROBE_PID" 2>/dev/null || true
    rm -f "$PROBE_LOG"
    echo "  in orde: de app start en blijft draaien"
  else
    PROBE_RC=0
    wait "$PROBE_PID" || PROBE_RC=$?
    echo "De app stopte binnen zes seconden na het starten (exit $PROBE_RC):" >&2
    sed 's/^/   /' "$PROBE_LOG" >&2
    rm -f "$PROBE_LOG"
    echo "Een getekende en genotariseerde app die niet start, mag niet uit; zo verging het v0.6.4." >&2
    exit 1
  fi
fi

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
