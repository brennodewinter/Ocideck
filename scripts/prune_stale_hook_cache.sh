#!/bin/sh
# Ruimt CMake-caches op die nog bij een vórige versie van een pakket horen.
#
# `hooks_runner` (native assets) sleutelt zijn buildmappen op een hash van de
# bouwconfiguratie — doelplatform, architectuur, compiler, deployment target —
# en niet op de pakketversie. Bump je een pakket met een CMake-build-hook
# (dartcv4), dan draait de hook opnieuw (package_config.json is een van zijn
# afhankelijkheden) maar vindt cmake in de gedeelde buildmap nog de cache van
# de oude bron, en weigert hard:
#
#   CMake Error: The source ".../dartcv4-2.3.1/src/CMakeLists.txt" does not
#   match the source ".../dartcv4-2.3.0/src/CMakeLists.txt" used to generate
#   cache.  Re-run cmake with a different source directory.
#
# Omdat élke configuratie zijn eigen hash heeft, zegt een groene `dart run` of
# `flutter test` (hash A) niets over `flutter build macos` (hash B). Zo stierf
# de 0.6.6-releaserun op 20-09-2026 pas in `make build-release`, ná anderhalf
# uur groene `make check-release`. Dit script kijkt vóór het bouwen naar alle
# hashes tegelijk en wist alleen wat aantoonbaar bij een andere pakketwortel
# hoort.
#
# Wat er weggaat is precies wat het poortslot (gate_lock.sh) ook wist bij een
# cache op naam van een andere worktree: `CMakeCache.txt` en `CMakeFiles/`.
# `_deps` blijft staan, dus het OpenCV-archief wordt niet opnieuw gedownload
# (GitHub weigert dat geregeld met een 429).
#
# Gebruik: scripts/prune_stale_hook_cache.sh [--check] [WORKTREE]
#   --check    alleen melden; exit 1 zodra er een verouderde cache staat
#   WORKTREE   de werkboom (standaard: de huidige map)
# Zonder `.dart_tool/package_config.json` valt er niets te beoordelen en
# gebeurt er niets (exit 0): de cache is dan niet aantoonbaar verouderd.
set -eu

check=0
root=""
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    -h|--help)
      sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "prune_stale_hook_cache: onbekend argument: $arg" >&2; exit 2 ;;
    *) root="$arg" ;;
  esac
done
[ -n "$root" ] || root="$(pwd)"
root="$(cd "$root" && pwd)"

pkg_config="$root/.dart_tool/package_config.json"
shared="$root/.dart_tool/hooks_runner/shared"
[ -d "$shared" ] || exit 0
if [ ! -f "$pkg_config" ]; then
  echo "prune_stale_hook_cache: geen $pkg_config — cache niet te beoordelen, niets gedaan." >&2
  exit 0
fi

# Zoals gate_lock.sh: `shared` is in een worktree meestal een symlink naar de
# cache van de hoofdboom; kijk in de fysieke map.
shared_abs="$(cd "$shared" && pwd -P)"

# Pakketnaam → wortelmap, uit package_config.json. `rootUri` is een file-URI
# (percent-gecodeerd) of een pad relatief aan .dart_tool/. Alleen de twee
# sleutels die we nodig hebben; de rest van het JSON blijft ongemoeid.
resolved="$(awk -v dt="$root/.dart_tool" '
  function pct_decode(s,   out, i, h) {
    out = ""
    while ((i = index(s, "%")) > 0) {
      out = out substr(s, 1, i - 1)
      h = toupper(substr(s, i + 1, 2))
      if (h in hexchar) { out = out hexchar[h]; s = substr(s, i + 3) }
      else { out = out "%"; s = substr(s, i + 1) }
    }
    return out s
  }
  function strip(s) { sub(/^[^:]*:[[:space:]]*"/, "", s); sub(/".*$/, "", s); return s }
  BEGIN { for (i = 1; i < 256; i++) hexchar[sprintf("%02X", i)] = sprintf("%c", i) }
  /"name"[[:space:]]*:/ { name = strip($0); next }
  /"rootUri"[[:space:]]*:/ {
    uri = pct_decode(strip($0))
    if (uri ~ /^file:\/\//) { sub(/^file:\/\//, "", uri) }
    else if (uri !~ /^\//) { uri = dt "/" uri }
    sub(/\/+$/, "", uri)
    if (name != "") print name "\t" uri
    name = ""
  }
' "$pkg_config")"

if [ -z "$resolved" ]; then
  echo "prune_stale_hook_cache: kon geen pakketten lezen uit $pkg_config — niets gedaan." >&2
  [ "$check" -eq 1 ] && exit 2
  exit 0
fi

resolved_root() { # PKG → wortelmap zoals pub hem nu oplost, leeg als onbekend
  printf '%s\n' "$resolved" | awk -F '\t' -v p="$1" '$1 == p { print $2; exit }'
}
physical() { # PAD → fysiek pad als de map bestaat, anders het pad zelf
  (cd "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"
}

stale=0
for cache in "$shared_abs"/*/build/*/CMakeCache.txt; do
  [ -f "$cache" ] || continue
  source_dir=$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$cache" 2>/dev/null || true)
  [ -n "$source_dir" ] || continue
  build_dir="$(dirname "$cache")"
  hash="$(basename "$build_dir")"
  pkg="$(basename "$(dirname "$(dirname "$build_dir")")")"
  want="$(resolved_root "$pkg")"
  if [ -n "$want" ]; then
    want_real="$(physical "$want")"
    src_real="$(physical "$source_dir")"
    case "$src_real" in
      "$want_real"|"$want_real"/*) continue ;;
    esac
  fi
  stale=$((stale + 1))
  if [ "$check" -eq 1 ]; then
    echo "prune_stale_hook_cache: VEROUDERD $pkg/$hash — gebouwd uit $source_dir, pub lost nu op naar ${want:-(geen afhankelijkheid meer)}." >&2
    continue
  fi
  rm -f "$cache"
  rm -rf "$build_dir/CMakeFiles"
  echo "prune_stale_hook_cache: cache $pkg/$hash stond op naam van $source_dir (nu ${want:-geen afhankelijkheid meer}); CMakeCache.txt en CMakeFiles/ gewist, de volgende bouw configureert opnieuw." >&2
done

if [ "$check" -eq 1 ] && [ "$stale" -gt 0 ]; then
  echo "prune_stale_hook_cache: $stale verouderde cache(s); draai scripts/prune_stale_hook_cache.sh om ze op te ruimen." >&2
  exit 1
fi
exit 0
