#!/usr/bin/env bash
# Flutter roept Ninja rechtstreeks aan; CMake's parallelvariabele begrenst dat niet.
set -euo pipefail
REAL_NINJA="$(command -v ninja)"
[[ "$REAL_NINJA" == /* && -x "$REAL_NINJA" ]] || { echo 'Ninja executable ontbreekt' >&2; exit 1; }
export OCIDECK_RELEASE_NINJA="$REAL_NINJA"
# De shim staat op een stabiel pad: CMake bewaart zijn absolute pad in
# CMAKE_MAKE_PROGRAM en een volgende bouw op dezelfde cache verwacht hem
# daar nog — een mktemp-shim is dan allang weg (#2798). De inhoud is per
# installatie identiek, dus herschrijven is onschuldig; atomair via mv zodat
# een gelijktijdig CMake-proces nooit een halve shim leest.
SHIM="${XDG_CACHE_HOME:-$HOME/.cache}/ocideck/ninja-j2"
mkdir -p "$SHIM"
cat > "$SHIM/.ninja.$$" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args=()
while (( $# )); do
  case "$1" in
    -t) args+=("$@"); break ;; # Toolargumenten zijn geen bouwopties.
    -j|--jobs) shift; (( $# )) || exit 2 ;;
    -j*|--jobs=*) ;;
    *) args+=("$1") ;;
  esac
  shift
done
exec "$OCIDECK_RELEASE_NINJA" -j2 "${args[@]}"
SH
chmod 700 "$SHIM/.ninja.$$"
mv -f "$SHIM/.ninja.$$" "$SHIM/ninja"
export PATH="$SHIM:$PATH"
export CMAKE_BUILD_PARALLEL_LEVEL=2
"$@"
