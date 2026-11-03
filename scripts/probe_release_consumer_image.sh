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
# This is an explicit infrastructure smoke test, not an automatic release retry.
docker run --rm --platform linux/amd64 --cpus 2 --memory 4g \
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
    if [ "$profile" = deb ]; then
      apt-get update
      cp /dist/artifact /tmp/ocideck.deb
      DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/ocideck.deb
    else
      cp /dist/artifact /tmp/ocideck.rpm
      dnf install -y /tmp/ocideck.rpm
    fi
    binary=/usr/lib/ocideck/ocideck
    command=(ocideck)
    ;;
  tar|debian12)
    mkdir /tmp/ocideck-test
    tar -xzf /dist/artifact -C /tmp/ocideck-test
    if [ "$profile" = debian12 ]; then
      cd /tmp/ocideck-test/ocideck-linux-debian12-*
    else
      cd "/tmp/ocideck-test/ocideck-$version"
    fi
    binary=./ocideck
    command=(./ocideck)
    ;;
  appimage)
    cd /tmp
    cp /dist/artifact ocideck.AppImage
    chmod +x ocideck.AppImage
    ./ocideck.AppImage --appimage-extract >/dev/null
    binary=squashfs-root/ocideck
    command=(squashfs-root/AppRun)
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
test -x "$binary"
if ldd "$binary" | grep 'not found'; then
  echo 'Artifact misses a runtime dependency' >&2
  exit 1
fi
set +e
timeout 20 xvfb-run -a "${command[@]}"
result=$?
set -e
test "$result" -eq 124 || { echo "Application did not survive the 20-second start probe: $result" >&2; exit 1; }
PROBE
printf 'Verified consumer profile=%s image=%s artifact_sha256=%s\n' "$PROFILE" "$IMAGE" "$EXPECTED_SHA"
