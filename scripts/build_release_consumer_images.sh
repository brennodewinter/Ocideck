#!/usr/bin/env bash
# Explicit infrastructure operation, never called by a release or on the laptop.
set -euo pipefail
REGISTRY="${1:?usage: build_release_consumer_images.sh REGISTRY REVISION OUTPUT.json}"
REVISION="${2:?full source SHA required}"
OUTPUT="${3:?new output JSON required}"
[[ "$REGISTRY" =~ ^[a-z0-9][a-z0-9./:-]*$ ]] || exit 2
[[ "$REVISION" =~ ^[0-9a-f]{40}$ && "$REVISION" != 0000000000000000000000000000000000000000 ]] || exit 2
[[ ! -e "$OUTPUT" ]] || { echo 'Output exists; preserve the previous image receipt' >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# A revision label must describe the actual build context, not operator input.
[[ "$(git -C "$ROOT" rev-parse HEAD)" == "$REVISION" ]] || { echo 'Build from the requested Git revision' >&2; exit 1; }
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all -- scripts/build_release_consumer_images.sh scripts/release_consumers)" ]] || { echo 'Consumer build context must be clean' >&2; exit 1; }
[[ -z "$(git -C "$ROOT" ls-files --others --ignored --exclude-standard -- scripts/release_consumers)" ]] || { echo 'Ignored files in consumer build context' >&2; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
for profile in deb rpm tar debian12 appimage flatpak; do
  image="$REGISTRY/ocideck-consumer-$profile:$REVISION"
  DOCKER_BUILDKIT=0 docker build --platform linux/amd64 \
    --cpu-period 100000 --cpu-quota 200000 --memory 4g --build-arg "SOURCE_REVISION=$REVISION" \
    -f "$ROOT/scripts/release_consumers/$profile.Dockerfile" -t "$image" "$ROOT/scripts/release_consumers"
  docker run --rm --platform linux/amd64 "$image" sh -ec \
    'test -s /usr/share/ocideck-consumer/packages.txt; command -v node; command -v sha256sum'
  # Registry credentials come from Docker's credential store; never argv or Git.
  docker push "$image"
  docker pull "$image"
  docker image inspect "$image" --format '{{json .RepoDigests}}' > "$WORK/$profile.json"
done
python3 - "$WORK" "$REGISTRY" "$REVISION" "$OUTPUT" <<'PY'
import json,pathlib,re,sys
work,registry,revision,output=sys.argv[1:]
images={}
for profile in ('deb','rpm','tar','debian12','appimage','flatpak'):
    prefix=f'{registry}/ocideck-consumer-{profile}@sha256:'
    values=json.loads((pathlib.Path(work)/(profile+'.json')).read_text())
    matches=[value for value in values if value.startswith(prefix) and re.fullmatch(r'[0-9a-f]{64}',value[len(prefix):])]
    if len(matches)!=1:
        raise SystemExit('missing or ambiguous pushed image digest')
    images[profile]=matches[0]
with pathlib.Path(output).open('x') as target:
    json.dump(dict(schema=1,source=revision,images=images),target,sort_keys=True,indent=2)
    target.write('\n')
PY
