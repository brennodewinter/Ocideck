#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p "${HOME}"
git config --global --add safe.directory /src

if [[ ! -f pubspec.yaml ]]; then
  echo "Fout: /src bevat geen OciDeck-broncode (pubspec.yaml ontbreekt)." >&2
  exit 1
fi

version="$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)"
if [[ -z "${version}" ]]; then
  version="unknown"
fi
safe_version="${version//+/-}"
destination="/out/ocideck-linux-debian12-${safe_version}"

if [[ -e "${destination}" || -e "${destination}.tar.gz" ]]; then
  echo "Fout: uitvoer bestaat al: ${destination}" >&2
  echo "Verplaats of verwijder die specifieke uitvoer en start opnieuw." >&2
  exit 1
fi

flutter --version
flutter pub get --enforce-lockfile
flutter build linux --release

bundle="build/linux/x64/release/bundle"
if [[ "$(uname -m)" == "aarch64" ]]; then
  bundle="build/linux/arm64/release/bundle"
fi
if [[ ! -d "${bundle}" ]]; then
  echo "Fout: verwachte Flutter-bundle ontbreekt: ${bundle}" >&2
  exit 1
fi

mkdir -p "${destination}"
cp -a "${bundle}/." "${destination}/"

report="${destination}/BUILD-COMPATIBILITY.txt"
{
  echo "OciDeck lokaal gecompileerd in Debian 12 (bookworm)"
  echo "Projectversie: ${version}"
  echo "Flutter: $(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])')"
  echo "Buildtijd (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Hoogste aangetroffen vereisten in ELF-bestanden:"
  find "${destination}" -type f -print0 \
    | while IFS= read -r -d '' candidate; do
        if file "${candidate}" | grep -q 'ELF'; then
          readelf --version-info "${candidate}" 2>/dev/null || true
        fi
      done \
    | grep -oE 'GLIBCXX_[0-9.]+|GLIBC_[0-9.]+' \
    | sort -Vu \
    | tail -n 20
} > "${report}"

tar -C /out -czf "${destination}.tar.gz" "$(basename "${destination}")"

echo
echo "Build voltooid:"
echo "  ${destination}"
echo "  ${destination}.tar.gz"
