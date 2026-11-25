#!/usr/bin/env bash
# Resolve the dynamic dependencies of packaged ELF files in the target image.
set -euo pipefail
root=${1:?A package root is required}
profile=${2:-standard}
[[ "$profile" = standard || "$profile" = appimage ]] || exit 2
root=$(cd -- "$root" && pwd -P)
export LC_ALL=C
unset LD_PRELOAD LD_LIBRARY_PATH
if [[ "$profile" = appimage ]]; then
  # Match packaging/linux/AppRun once the host environment has been cleared.
  export LD_LIBRARY_PATH="$root/lib"
fi

inventory=$(mktemp)
trap 'rm -f -- "$inventory"' EXIT
find "$root" -type f -print0 > "$inventory"
result=0
checked=0
while IFS= read -r -d '' file; do
  if ! IFS= read -r -N 4 magic < "$file" || [[ "$magic" != $'\x7fELF' ]]; then
    continue
  fi
  relative=${file#"$root"/}
  if ! dynamic=$(readelf -d -- "$file" 2>&1); then
    printf '%s: ELF inspection failed\n%s\n' "$relative" "$dynamic" >&2
    result=1
    continue
  fi
  if [[ "$dynamic" != *'(NEEDED)'* ]]; then continue; fi
  checked=$((checked + 1))
  if ! resolved=$(ldd "$file" 2>&1); then
    printf '%s: loader inspection failed\n%s\n' "$relative" "$resolved" >&2
    result=1
  elif missing=$(grep -E '=> not found([[:space:]]|$)' <<< "$resolved"); then
    printf '%s: unresolved runtime dependencies\n%s\n' "$relative" "$missing" >&2
    result=1
  fi
done < "$inventory"

if (( checked == 0 )); then
  echo "No ELF files with dynamic dependencies found under $root" >&2
  exit 1
fi
printf 'Inspected %s ELF objects under %s\n' "$checked" "$root"
exit "$result"
