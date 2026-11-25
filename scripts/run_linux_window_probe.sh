#!/usr/bin/env bash
set -euo pipefail
backend=${1:?X11 or Wayland backend required}
executable=$(realpath -- "${2:?App executable required}")
mkdir -p -- "${3:?Evidence path required}"
evidence=$(realpath -- "$3")
script="$(cd -- "$(dirname -- "$0")" && pwd)/linux_window_probe.py"
launcher=()
if (( EUID == 0 )); then
  chown nobody "$evidence"
  launcher=(runuser -u nobody --)
  if ! "${launcher[@]}" test -x "$executable"; then
    staging=$(mktemp -d)
    trap 'rm -rf -- "$staging"' EXIT
    cp -a --reflink=auto -- "$(dirname -- "$executable")" "$staging/bundle"
    chown -R nobody "$staging"
    executable="$staging/bundle/$(basename -- "$executable")"
  fi
fi
case "$backend" in
  x11)
    "${launcher[@]}" xvfb-run -a -s '-screen 0 1800x1100x24' \
      dbus-run-session -- /usr/bin/python3 "$script" x11 "$executable" "$evidence"
    ;;
  wayland)
    "${launcher[@]}" dbus-run-session -- /usr/bin/python3 "$script" wayland "$executable" "$evidence"
    ;;
  *) exit 2 ;;
esac
