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
# aflopen. Wat het NIET oplost: wisselen tussen worktrees stempelt de
# CMake-cache opnieuw, dus de eerste run ná een wissel herbouwt OpenCV. Dat is
# traag maar correct — zie docs/CHECKS.md.
#
# Waarom een shellscript en geen `dart run tool/…`: elke `dart run` in dit
# pakket start zélf de native-assets-hook, en die grijpt naar precies de lock
# waar we op staan te wachten. Het slot mag dus niets van Dart nodig hebben.
#
# Gebruik:  tool/gate_lock.sh <commando> [argumenten...]
# Overslaan: OCIDECK_NO_GATE_LOCK=1 (bijv. op een runner met één worktree)
# Wachttijd: OCIDECK_GATE_LOCK_TIMEOUT (seconden, standaard 5400 = 90 min)

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
if [ -L "$shared" ]; then
  target=$(cd "$(dirname "$shared")" && readlink "$(basename "$shared")")
  case "$target" in
    /*) lock_base="$target" ;;
    *) lock_base="$(cd "$(dirname "$shared")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")" ;;
  esac
else
  lock_base="$(pwd)/.dart_tool"
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

status=0
"$@" || status=$?
exit "$status"
