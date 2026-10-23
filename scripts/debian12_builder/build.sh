#!/usr/bin/env bash
set -Eeuo pipefail

builder_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace_dir="$(cd -- "${builder_dir}/../.." && pwd)"
source_dir="${OCIDECK_SOURCE_DIR:-${workspace_dir}/work/ocideck-src}"
result_dir="${OCIDECK_OUTPUT_DIR:-${workspace_dir}/outputs/ocideck-local-builds}"
pub_cache_dir="${OCIDECK_PUB_CACHE_DIR:-${workspace_dir}/work/ocideck-pub-cache}"

read -r -a engine <<< "${CONTAINER_ENGINE:-docker}"
if ! "${engine[@]}" info >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Geen toegang tot de containerengine.

Voer dit script uit met een werkende Docker-opdracht, bijvoorbeeld:
  CONTAINER_ENGINE="sudo docker" ./build.sh

Of voeg je gebruiker blijvend aan de docker-groep toe en log daarna opnieuw in:
  sudo usermod -aG docker "$USER"
EOF
  exit 1
fi

if [[ ! -e "${source_dir}/.git" ]]; then
  mkdir -p "$(dirname -- "${source_dir}")"
  git clone https://github.com/brennodewinter/Ocideck.git "${source_dir}"
elif [[ "${UPDATE_SOURCE:-0}" == "1" ]]; then
  git -C "${source_dir}" pull --ff-only
fi

flutter_version="$(awk '$1 == "flutter" { print $2; exit }' "${source_dir}/.tool-versions")"
if [[ -z "${flutter_version}" ]]; then
  echo "Fout: Flutter-versie ontbreekt in ${source_dir}/.tool-versions" >&2
  exit 1
fi

# The pinned Flutter Linux SDK is available for x86-64; Docker can emulate it
# on an ARM host, so the output stays the same architecture as the release.
target_arch="amd64"

mkdir -p "${result_dir}" "${pub_cache_dir}"
image="ocideck-debian12-builder:flutter-${flutter_version}"

"${engine[@]}" build \
  --platform linux/amd64 \
  --build-arg "FLUTTER_VERSION=${flutter_version}" \
  --build-arg "TARGETARCH=${target_arch}" \
  --tag "${image}" \
  "${builder_dir}"

"${engine[@]}" run --rm \
  --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  --env HOME=/tmp/build-home \
  --volume "${source_dir}:/src" \
  --volume "${result_dir}:/out" \
  --volume "${pub_cache_dir}:/opt/pub-cache" \
  "${image}"

echo "Resultaten staan in: ${result_dir}"
