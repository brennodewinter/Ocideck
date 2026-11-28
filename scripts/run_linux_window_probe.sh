#!/usr/bin/env bash
set -euo pipefail
backend=${1:?X11 or Wayland backend required}
executable=$(realpath -- "${2:?App executable required}")
mkdir -p -- "${3:?Evidence path required}"
evidence=$(realpath -- "$3")
shift 3
script="$(cd -- "$(dirname -- "$0")" && pwd)/linux_window_probe.py"
launcher=()
if (( EUID == 0 )); then
  chown nobody "$evidence"
  launcher=(runuser -u nobody --)
  bundle=$(dirname -- "$executable")
  if ! "${launcher[@]}" test -x "$executable" ||
      ! "${launcher[@]}" test -x "$bundle/lib" ||
      ! "${launcher[@]}" test -x "$bundle/data"; then
    staging=$(mktemp -d)
    trap 'rm -rf -- "$staging"' EXIT
    cp -a --reflink=auto -- "$bundle" "$staging/bundle"
    chown -R nobody "$staging"
    executable="$staging/bundle/$(basename -- "$executable")"
  fi
fi
case "$backend" in
  x11)
    "${launcher[@]}" xvfb-run -a -s '-screen 0 1800x1100x24' \
      dbus-run-session -- /usr/bin/python3 "$script" x11 "$executable" "$evidence" "$@"
    ;;
  wayland)
    if [[ -z "${OCIDECK_WAYLAND_POINTER:-}" ]]; then
      pointer_dir=$(mktemp -d)
      trap 'rm -rf -- "$pointer_dir" "${staging:-}"' EXIT
      chmod 755 "$pointer_dir"
      flags=$(pkg-config --cflags --libs wayland-client)
      read -r -a wayland_flags <<< "$flags"
      cc -Wall -Wextra -Werror "$(dirname -- "$script")/wayland_probe_pointer.c" \
        -o "$pointer_dir/pointer" "${wayland_flags[@]}"
      export OCIDECK_WAYLAND_POINTER="$pointer_dir/pointer"
    fi
    "${launcher[@]}" dbus-run-session -- /usr/bin/python3 "$script" wayland "$executable" "$evidence" "$@"
    ;;
  *) exit 2 ;;
esac
