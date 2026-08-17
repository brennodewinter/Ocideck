#!/bin/sh
# Serialiseert zware poortruns die één native-assets-cache delen.
#
# Elke git-worktree van deze repo laat `.dart_tool/hooks_runner/shared` naar
# dezelfde map wijzen, zodat een verse worktree de native OpenCV-laag niet
# opnieuw hoeft te bouwen (en niet stukloopt wanneer GitHub het archief met een
# 429 weigert). De prijs is dat twee gelijktijdige runs één lock en één
# CMake-buildmap delen. Waargenomen bij vier tegelijk:
#
#   * CMake weigert omdat de cache op naam staat van een ándere worktree, en
#     bouwt OpenCV volledig opnieuw;
#   * die herbouw houdt `dartcv4/.lock` zo lang vast dat de andere runs
#     sneuvelen op "Could not acquire the lock … TimeoutException after
#     0:05:00" — en dan faalt `make check` op een wíllekeurige poort, zonder
#     dat er iets mis is met de wijziging. Dat laatste is het ergst: de poort
#     wijst naar de verkeerde plek.
#
# Dit script laat runs op elkaar wachten in plaats van elkaars lock te laten
# aflopen, en ruimt daarna twee dingen op die het wachten alleen niet oplost.
#
# 1. De CMake-stempel. Elke worktree noemt dezelfde fysieke buildmap met een
#    ánder pad (via de `shared`-symlink), en CMake weigert dan HARD:
#    "The current CMakeCache.txt directory … is different than the directory …
#    where CMakeCache.txt was created". Niet traag-maar-correct, zoals hier
#    eerder stond: gewoon fout. Serialiseren maakt het zelfs voorspelbaar —
#    elke run stempelt op zijn eigen pad, dus de vólgende faalt gegarandeerd.
#    Daarom wissen we, binnen het slot, een cache die op naam van een andere
#    worktree staat. `_deps` blijft staan, dus geen herdownload.
#
# 2. De rem. Zonder begrenzing bouwt CMake met zoveel taken als er kernen zijn.
#    Op een laptop trok dat meer stroom dan de adapter kon leveren — de accu
#    liep leeg terwijl hij aan de lader lag. `CMAKE_BUILD_PARALLEL_LEVEL` houdt
#    daarom vier kernen vrij. Dit is bewust géén `nice`: prioriteit verdeelt
#    rekentijd, maar verlaagt het opgenomen vermogen niet.
#
# Waarom een shellscript en geen `dart run tool/…`: elke `dart run` in dit
# pakket start zélf de native-assets-hook, en die grijpt naar precies de lock
# waar we op staan te wachten. Het slot mag dus niets van Dart nodig hebben.
#
# Gebruik:  scripts/gate_lock.sh <commando> [argumenten...]
# Overslaan: OCIDECK_NO_GATE_LOCK=1 (bijv. op een runner met één worktree)
# Wachttijd: OCIDECK_GATE_LOCK_TIMEOUT (seconden, standaard 5400 = 90 min)
# Rem:       CMAKE_BUILD_PARALLEL_LEVEL (zelf gezet? dan blijft die staan)

set -eu

if [ "$#" -eq 0 ]; then
  echo "gate_lock.sh: geen commando meegegeven" >&2
  exit 2
fi

if [ "${OCIDECK_NO_GATE_LOCK:-0}" = "1" ]; then
  exec "$@"
fi

# De reikwijdte van het slot volgt de reikwijdte van de gedeelde cache: is
# `shared` een symlink, dan is de contentie machinebreed en hoort het slot bij
# het doel van die symlink. Is het een echte map, dan deelt deze worktree niets
# en volstaat een eigen slot — dan wacht niemand op niemand.
shared=".dart_tool/hooks_runner/shared"
# Zoals CMake de map noemt wanneer hij vanuit déze worktree wordt aangeroepen.
# Dat pad, niet het doel van de symlink, staat straks in de cache.
own_shared="$(pwd)/$shared"
if [ -L "$shared" ]; then
  target=$(cd "$(dirname "$shared")" && readlink "$(basename "$shared")")
  case "$target" in
    /*) lock_base="$target" ;;
    *) lock_base="$(cd "$(dirname "$shared")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")" ;;
  esac
  shared_abs="$lock_base"
else
  lock_base="$(pwd)/.dart_tool"
  shared_abs="$own_shared"
fi
mkdir -p "$lock_base" 2>/dev/null || true
lock="$lock_base/ocideck-gate.lock"
info="$lock/holder"

timeout="${OCIDECK_GATE_LOCK_TIMEOUT:-5400}"
waited=0
announced=0

# shellcheck disable=SC2329  # wordt via `trap` aangeroepen, niet met de naam.
cleanup() {
  # Alleen ons eigen slot opruimen: een run die zijn beurt afwacht en wordt
  # afgebroken mag het slot van de houder niet weghalen.
  if [ "${held:-0}" = "1" ]; then
    rm -rf "$lock"
  fi
}
held=0
trap cleanup EXIT INT TERM

while :; do
  # `mkdir` is atomair: precies één proces wint, ook over worktrees heen.
  if mkdir "$lock" 2>/dev/null; then
    held=1
    printf 'pid=%s\nworktree=%s\nstart=%s\ncommando=%s\n' \
      "$$" "$(pwd)" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >"$info" 2>/dev/null || true
    break
  fi

  holder_pid=$(sed -n 's/^pid=//p' "$info" 2>/dev/null || true)
  holder_tree=$(sed -n 's/^worktree=//p' "$info" 2>/dev/null || true)

  # Een slot van een verdwenen proces is geen slot. Zonder deze tak blijft een
  # afgebroken run iedereen tegenhouden tot iemand het met de hand weghaalt.
  if [ -n "$holder_pid" ] && ! kill -0 "$holder_pid" 2>/dev/null; then
    echo "poortslot: houder (pid $holder_pid) bestaat niet meer, slot vrijgegeven" >&2
    rm -rf "$lock"
    continue
  fi

  if [ "$waited" -ge "$timeout" ]; then
    echo "poortslot: na $((timeout / 60)) minuten nog steeds bezet door ${holder_tree:-onbekend} (pid ${holder_pid:-?})." >&2
    echo "poortslot: draait daar echt nog een poort? Zo niet, verwijder $lock." >&2
    exit 75
  fi

  if [ "$announced" -eq 0 ]; then
    echo "poortslot: wachten op een poortrun in ${holder_tree:-een andere worktree} (pid ${holder_pid:-?})…" >&2
    announced=1
  elif [ $((waited % 300)) -eq 0 ] && [ "$waited" -gt 0 ]; then
    echo "poortslot: nog steeds wachten, $((waited / 60)) min…" >&2
  fi

  sleep 5
  waited=$((waited + 5))
done

if [ "$waited" -gt 0 ]; then
  echo "poortslot: aan de beurt na $((waited / 60)) min $((waited % 60)) s." >&2
fi

# Vanaf hier houden we het slot vast; niemand anders bouwt mee.

# Een cache die op naam van een andere worktree staat, laat CMake hard falen.
# Wissen is goedkoop: alleen `CMakeCache.txt` en `CMakeFiles/` gaan eraan, de
# gedownloade bronnen in `_deps` blijven liggen.
for cache in "$shared_abs"/*/build/*/CMakeCache.txt; do
  [ -f "$cache" ] || continue
  stamped=$(sed -n 's/^CMAKE_CACHEFILE_DIR:INTERNAL=//p' "$cache" 2>/dev/null || true)
  [ -n "$stamped" ] || continue
  build_dir="$(dirname "$cache")"
  case "$build_dir" in
    "$own_shared"/*) mine="$build_dir" ;;
    "$shared_abs"/*) mine="$own_shared${build_dir#"$shared_abs"}" ;;
    *) mine="$build_dir" ;;
  esac
  # Vergelijk fysieke paden: /var en /private/var zijn op macOS dezelfde map,
  # en onnodig wissen kost een volledige herbouw van OpenCV.
  stamped_real=$( (cd "$stamped" 2>/dev/null && pwd -P) || echo "$stamped" )
  mine_real=$( (cd "$mine" 2>/dev/null && pwd -P) || echo "$mine" )
  [ "$stamped_real" = "$mine_real" ] && continue
  echo "poortslot: CMake-cache stond op naam van $stamped, opgeruimd voor deze worktree" >&2
  rm -f "$cache"
  rm -rf "$build_dir/CMakeFiles"
done

# De rem: houd vier kernen vrij, zodat één poortrun de machine (en op een
# laptop de adapter) niet volledig opeist. Een eigen waarde blijft staan.
if [ -z "${CMAKE_BUILD_PARALLEL_LEVEL:-}" ]; then
  cores=$(sysctl -n hw.logicalcpu 2>/dev/null || nproc 2>/dev/null || echo 4)
  if [ "$cores" -gt 6 ]; then
    CMAKE_BUILD_PARALLEL_LEVEL=$((cores - 4))
  else
    CMAKE_BUILD_PARALLEL_LEVEL=2
  fi
  export CMAKE_BUILD_PARALLEL_LEVEL
fi

status=0
"$@" || status=$?
exit "$status"
