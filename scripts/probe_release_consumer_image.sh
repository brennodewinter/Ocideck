#!/usr/bin/env bash
# Probe an already verified artifact in a prepared image; never builds an app.
set -euo pipefail
PROFILE="${1:?profile required}"
IMAGE="${2:?immutable image reference required}"
VERSION="${3:?stable version required}"
ARTIFACT="${4:?existing artifact required}"
EXPECTED_SHA="${5:?verified artifact SHA256 required}"
SBOM="${6:-}"
SBOM_SHA="${7:-}"
[[ "$PROFILE" =~ ^(deb|rpm|tar|debian12|appimage|flatpak)$ ]] || exit 2
[[ "$IMAGE" =~ ^[a-z0-9][a-z0-9./:_-]*@sha256:[0-9a-f]{64}$ ]] || exit 2
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 2
[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{64}$ ]] || exit 2
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
python3 - "$ARTIFACT" "$EXPECTED_SHA" "$WORK/artifact" "$PROFILE" "$SBOM" "$SBOM_SHA" <<'PY'
import hashlib,pathlib,shutil,sys
source,expected,target,profile,sbom,sbom_hash=sys.argv[1:]
def digest(path):
    value=hashlib.sha256()
    with open(path,'rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):
            value.update(block)
    return value.hexdigest()
def copy_verified(source, expected, target):
    path=pathlib.Path(source)
    if path.is_symlink() or not path.is_file():
        raise SystemExit('artifact is not regular')
    actual=digest(path)
    if actual!=expected:
        raise SystemExit('artifact differs from verified hash')
    shutil.copyfile(path,target)
    if digest(target)!=expected:
        raise SystemExit('artifact changed while staging')
copy_verified(source,expected,target)
if profile=='flatpak':
    copy_verified(sbom,sbom_hash,str(pathlib.Path(target).parent/'components.cdx.json'))
PY
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$WORK/scripts/release_consumers"
for helper in probe_linux_package prepare_linux_probe check_linux_runtime_elf linux_start_probe; do
  cp "$ROOT/$helper.sh" "$WORK/scripts/"
done
cp "$ROOT/release_consumers/appimage-runtime.txt" "$WORK/scripts/release_consumers/"
# This is an explicit infrastructure smoke test, not an automatic release retry.
docker run --interactive --rm --platform linux/amd64 --cpus 2 --memory 4g \
  --mount "type=bind,source=$WORK,target=/dist,readonly" "$IMAGE" bash -s -- "$PROFILE" "$VERSION" <<'PROBE'
set -euo pipefail
profile="$1"
version="$2"
test -s /usr/share/ocideck-consumer/packages.txt
node --version
case "$profile" in
  deb|rpm)
    # A prepared tool image must not hide broken package runtime declarations.
    if ldconfig -p | grep -E 'libgtk-3|libsecret-1|libayatana-appindicator'; then
      echo 'Package consumer image preinstalls application runtime dependencies' >&2
      exit 1
    fi
    cp /dist/artifact "/tmp/ocideck.$profile"
    /dist/scripts/probe_linux_package.sh "$profile" "/tmp/ocideck.$profile" /tmp/probe-evidence
    ;;
  tar|debian12|appimage)
    /dist/scripts/probe_linux_package.sh "$profile" /dist/artifact /tmp/probe-evidence
    ;;
  flatpak)
    test "$(flatpak --system info --show-commit org.gnome.Platform/x86_64/50)" = "$(cat /usr/share/ocideck-consumer/runtime-commit)"
    flatpak --system install -y --noninteractive --no-deps --no-related --bundle /dist/artifact
    app="$(flatpak --system info --show-location com.dewinter.ocideck)"
    flatpak --system info --show-metadata com.dewinter.ocideck | grep -Fx 'runtime=org.gnome.Platform/x86_64/50'
    test -x "$app/files/bin/ocideck"
    test -x "$app/files/bin/git"
    test -x "$app/files/lib/ocideck/ocideck"
    test -x "$app/files/libexec/git-core/git-remote-https"
    sh -n "$app/files/bin/ocideck"
    (cd "$app/files" && sha256sum -c share/doc/ocideck-flatpak/FILES.sha256)
    cmp "$app/files/share/doc/ocideck-flatpak/components.cdx.json" /dist/components.cdx.json
    exit 0
    ;;
esac
PROBE
printf 'Verified consumer profile=%s image=%s artifact_sha256=%s\n' "$PROFILE" "$IMAGE" "$EXPECTED_SHA"
