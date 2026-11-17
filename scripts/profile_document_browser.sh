#!/usr/bin/env bash
# Same integration harness on a real profile-mode browser, under the gate lock.
# Start a matching chromedriver on localhost:4444 before invoking this script.
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if [[ ${OCIDECK_BROWSER_PROFILE_LOCKED:-0} != 1 ]]; then
  exec scripts/gate_lock.sh env OCIDECK_BROWSER_PROFILE_LOCKED=1 "$0" "$@"
fi
RESULT_FILE=$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "${1:?Provide a fresh result JSON path}")
[[ ! -e "$RESULT_FILE" ]] || { echo 'Result exists; preserve it and use a fresh path.' >&2; exit 2; }
mkdir -p "$(dirname "$RESULT_FILE")"
curl --fail --silent http://localhost:4444/status >/dev/null
BACKUP=$(mktemp "${TMPDIR:-/tmp}/ocideck-browser-profile.XXXXXX")
cp web/index.html "$BACKUP"
restore_index() { cp "$BACKUP" web/index.html; rm -f "$BACKUP"; }
trap restore_index EXIT HUP INT TERM
# flutter drive requires an absolute base; deployments intentionally use ./.
# Keep the production CSP unchanged and use the matching local renderer files.
python3 - <<'PY'
p='web/index.html'
s=open(p).read()
assert '<base href="./">' in s or '<base href="/">' in s
s=s.replace('<base href="./">','<base href="/">')
open(p,'w').write(s)
PY
BROWSER_ARGS=()
if [[ -n ${CHROME_EXECUTABLE:-} ]]; then
  BROWSER_ARGS+=("--chrome-binary=$CHROME_EXECUTABLE")
fi
NAVIGATION_RESULT_FILE="$RESULT_FILE" flutter drive --profile --no-web-resources-cdn \
  -d web-server --headless --browser-name=chrome "${BROWSER_ARGS[@]}" \
  --driver=test_driver/document_navigation_driver.dart \
  --target=integration_test/document_navigation_profile_test.dart
# An interrupted driver can exit without a result. Do not accept stale/empty
# evidence as a successful platform run.
python3 - "$RESULT_FILE" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
assert len(x['pagination_scaling']) == 3
for r in x['pagination_scaling']:
    assert r['load_us'] > 0 and r['mounted_document_trees_max'] > 0
for n in [10,40,100]:
    assert x[f'pagination_{n}_frames']['samples_ms']
PY
