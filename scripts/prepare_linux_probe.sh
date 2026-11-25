#!/usr/bin/env bash
# Install probe tooling separately from the packaged application's dependencies.
set -euo pipefail
mode=${1:?Use appimage, debian12, elf, or desktop}
if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  install=(apt-get install -y --no-install-recommends)
  desktop=(xvfb xauth fonts-dejavu-core dbus-daemon libglib2.0-bin gnome-keyring)
else
  install=(dnf install -y --setopt=install_weak_deps=False)
  desktop=(xorg-x11-server-Xvfb xorg-x11-xauth dejavu-sans-fonts dbus-daemon glib2 gnome-keyring)
fi

case "$mode" in
  elf) "${install[@]}" binutils ;;
  desktop) "${install[@]}" "${desktop[@]}" ;;
  debian12)
    "${install[@]}" libgtk-3-0 libsecret-1-0 liblzma5 libayatana-appindicator3-1 \
      libgles2 libegl1 libgl1-mesa-dri libegl-mesa0 libpulse0 libwebkit2gtk-4.1-0 libmpv2 \
      gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav
    ;;
  appimage)
    script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
    runtime=()
    while read -r package _; do
      [[ -n "$package" && "$package" != \#* ]] || continue
      runtime+=("$package")
    done < "$script_dir/release_consumers/appimage-runtime.txt"
    (( ${#runtime[@]} > 0 ))
    "${install[@]}" "${runtime[@]}"
    cache=$(ldconfig -p)
    if grep -Ei 'lib(ayatana|dbusmenu)' <<< "$cache"; then
      echo 'The AppImage consumer host supplies libraries that must come from AppDir' >&2
      exit 1
    fi
    ;;
  *) exit 2 ;;
esac
