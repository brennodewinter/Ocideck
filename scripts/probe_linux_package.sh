#!/usr/bin/env bash
# Install or extract one trusted build artifact inside its consumer image.
set -euo pipefail
[[ $# -eq 3 ]] || { echo 'Usage: probe_linux_package.sh PROFILE ARTIFACT EVIDENCE_DIR' >&2; exit 2; }
profile=$1
artifact=$(realpath -- "$2")
test -f "$artifact"
mkdir -p -- "$3"
evidence=$(realpath -- "$3")
helpers=$(cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export DEBIAN_FRONTEND=noninteractive

if [[ "$profile" != rpm ]]; then apt-get update; fi
case "$profile" in
  deb)
    apt-get install -y "$artifact"
    root=/usr/lib/ocideck
    launch=(ocideck)
    ;;
  rpm)
    dnf install -y "$artifact"
    root=/usr/lib/ocideck
    launch=(ocideck)
    ;;
  appimage)
    "$helpers/prepare_linux_probe.sh" appimage
    cd -- "$work"
    cp -- "$artifact" ocideck.AppImage
    chmod +x ocideck.AppImage
    ./ocideck.AppImage --appimage-extract >/dev/null
    root="$work/squashfs-root"
    launch=("$root/AppRun")
    ;;
  tar|debian12)
    if [[ "$profile" = debian12 ]]; then "$helpers/prepare_linux_probe.sh" debian12; fi
    tar -xzf "$artifact" -C "$work"
    shopt -s nullglob
    roots=("$work"/ocideck-*/)
    [[ ${#roots[@]} -eq 1 ]] || { echo 'Expected one OciDeck bundle' >&2; exit 1; }
    root=${roots[0]%/}
    launch=("$root/ocideck")
    ;;
  *) exit 2 ;;
esac
test -x "$root/ocideck"

"$helpers/prepare_linux_probe.sh" elf
elf_profile=standard
if [[ "$profile" = appimage ]]; then elf_profile=appimage; fi
"$helpers/check_linux_runtime_elf.sh" "$root" "$elf_profile" 2>&1 | tee "$evidence/elf.log"
"$helpers/prepare_linux_probe.sh" desktop
"$helpers/linux_start_probe.sh" "$evidence" "${launch[@]}"
