#!/usr/bin/env bash
# Pinned real-Marp CLI regression check — OciDeck theme loading (#1804).
#
# A saved OciDeck project puts `themes/<name>.css` beside the deck and, since
# #1804, a `.marprc.yml` that registers it via `themeSet`. Marp CLI does NOT
# auto-discover a stylesheet placed beside the deck, so without that config a
# plain `marp deck.md` falls back to the default theme and the `section.split`
# two-column layout is lost. This check renders the deck with the REAL pinned
# Marp CLI and asserts the layout survives — in DOM/CSS and in a screenshot.
#
# It also documents the limitation honestly: with `--no-config-file` the split
# layout is absent, which is exactly why OciDeck writes the config.
#
# Offline after `npm ci` has prepared node_modules. Exits non-zero on any hard
# assertion failure. If Node is absent, exits 0 with a clear skip message
# (this is a check-full gate, not a static-gate one; a machine without Node
# cannot run it, same shape as DAST without a container runtime).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
MARP="$HERE/node_modules/.bin/marp"

# --- tool availability -------------------------------------------------------
if ! command -v node >/dev/null 2>&1; then
  echo "marp-check: node not found — skipped (install Node to run this gate)."
  exit 0
fi

# --- prepare pinned Marp CLI (offline once node_modules exists) --------------
if [ ! -x "$MARP" ]; then
  echo "marp-check: preparing pinned Marp CLI (npm ci, one-time, needs network)…"
  (cd "$HERE" && npm ci --no-audit --no-fund)
fi
echo "marp-check: $("$MARP" --version 2>&1 | head -1)"

# --- build a minimal bullets+image (split) fixture from real repo assets -----
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
THEME_CSS="$REPO/assets/themes/ocideck.css"
if [ ! -f "$THEME_CSS" ]; then
  echo "marp-check: FAIL — bundled theme asset not found at $THEME_CSS" >&2
  exit 1
fi

# A 1×1 PNG (valid, opaque) so `![](images/photo.png)` resolves without network.
# Written via base64 to avoid shell null-byte handling on the binary content.
PNG1x1_B64='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAADAAFdzNuSAAAAAElFTkSuQmCC'

build_fixture() {
  local dir="$1"
  mkdir -p "$dir/themes" "$dir/images"
  cp "$THEME_CSS" "$dir/themes/ocideck.css"
  printf '%s' "$PNG1x1_B64" | base64 -d > "$dir/images/photo.png"
  # The exact `.marprc.yml` OciDeck writes (file_service_project.dart).
  cat > "$dir/.marprc.yml" <<'CFG'
# OciDeck Marp CLI configuration.
# Registers the generated theme so a plain `marp deck.md -o out.html`
# (run from this folder) loads it. Marp does not auto-discover a
# stylesheet placed beside the deck; this config is the standard route.
themeSet:
  - themes/ocideck.css
CFG
  cat > "$dir/deck.md" <<'MD'
---
marp: true
theme: ocideck
paginate: true
---

<!-- _class: title -->

# Callout fixture

---

<!-- _class: split -->

## Split slide

<div class="split-text">

- Bullet one
- Bullet two

</div>

<div class="split-image">

![](images/photo.png)

</div>
MD
}

fail=0
assert_contains() { # file pattern message
  if ! grep -q "$2" "$1"; then
    echo "marp-check: FAIL — $3 (pattern '$2' absent in $1)" >&2
    fail=1
  fi
}
assert_absent() { # file pattern message
  if grep -q "$2" "$1"; then
    echo "marp-check: FAIL — $3 (pattern '$2' unexpectedly present in $1)" >&2
    fail=1
  fi
}

# --- A. supported invocation: plain `marp deck.md` loads the theme -----------
build_fixture "$WORK/proj"
( cd "$WORK/proj" && "$MARP" --no-parallel deck.md -o out.html ) >/dev/null 2>&1
assert_contains "$WORK/proj/out.html" 'section\.split' \
  "supported invocation must carry the split layout CSS"
assert_contains "$WORK/proj/out.html" 'split-text' \
  "supported invocation must render the split-text container"
assert_contains "$WORK/proj/out.html" 'split-image' \
  "supported invocation must render the split-image container"

# --- B. screenshot: a real raster of the split slide -------------------------
# `--allow-local-files` so the local image resolves. PNG export needs Chromium
# (bundled via puppeteer at install time); if it is unavailable the screenshot
# step is advisory — the DOM/CSS assertion above is the hard gate.
shot_ok=0
( cd "$WORK/proj" && "$MARP" --no-parallel deck.md --png --allow-local-files -o shot.png ) >/dev/null 2>&1 && shot_ok=1
if [ "$shot_ok" = 1 ] && [ -f "$WORK/proj/shot.png" ]; then
  # Marp exports 16:9 slides at 1280×720 by default.
  dim="$(file "$WORK/proj/shot.png" 2>/dev/null || true)"
  case "$dim" in
    *1280*720*) echo "marp-check: screenshot OK (1280×720)";;
    *) echo "marp-check: FAIL — screenshot produced but unexpected dimensions: $dim" >&2; fail=1;;
  esac
else
  echo "marp-check: screenshot skipped — Chromium unavailable (DOM/CSS gate still ran)."
fi

# --- C. documented limitation: --no-config-file loses the split layout -------
( cd "$WORK/proj" && "$MARP" --no-parallel deck.md --no-config-file -o out-default.html ) >/dev/null 2>&1
assert_absent "$WORK/proj/out-default.html" 'section\.split' \
  "default invocation (no config) must NOT carry the split layout — this is the documented limitation"

# --- D. moving the project directory does not break theme discovery ----------
cp -R "$WORK/proj" "$WORK/moved"
( cd "$WORK/moved" && "$MARP" --no-parallel deck.md -o out.html ) >/dev/null 2>&1
assert_contains "$WORK/moved/out.html" 'section\.split' \
  "moved project must still load the theme (relative path)"

# --- E. paths containing spaces work -----------------------------------------
cp -R "$WORK/proj" "$WORK/with spaces"
( cd "$WORK/with spaces" && "$MARP" --no-parallel deck.md -o out.html ) >/dev/null 2>&1
assert_contains "$WORK/with spaces/out.html" 'section\.split' \
  "project path with spaces must still load the theme"

# --- F. directive list stays in sync with the pinned Marp (#1817) -------------
# kMarpitDirectiveNames in lib/services/marp_source_preservation.dart is a
# hand-maintained list of every Marpit/Marp-Core/Marp-CLI directive name. If
# Marp adds a directive and we don't, OciDeck silently drops it on save. This
# gate extracts the real directive names from the *pinned* packages in
# node_modules and fails on any mismatch — in either direction.
marp_directives="$(cd "$HERE" && node -e '
    const fs = require("fs");
    const path = require("path");

    // 1. Marpit built-in directives (globals + locals).
    const d = require("@marp-team/marpit/lib/markdown/directives/directives");
    const names = new Set([...Object.keys(d.globals), ...Object.keys(d.locals)]);

    // 2. marp-core custom directives (math, size — non-enumerable, set via
    //    Object.defineProperty during construction, so render first).
    const Marp = require("@marp-team/marp-core/lib/marp.js").default;
    const marp = new Marp();
    marp.render("<!-- paginate: true -->\n\n# x\n");
    for (const scope of ["global", "local"])
      for (const k of Object.getOwnPropertyNames(marp.customDirectives[scope]))
        if (k !== "length" && k !== "prototype")
          names.add(k);

    // 3. Marp CLI custom directives (e.g. transition — registered dynamically
    //    in the CLI engine, not in marp-core). Grep the bundled source.
    const cliDir = path.dirname(require.resolve("@marp-team/marp-cli/package.json"));
    for (const f of fs.readdirSync(cliDir + "/lib")) {
      if (!f.endsWith(".js") || f.includes(".map")) continue;
      const src = fs.readFileSync(cliDir + "/lib/" + f, "utf8");
      const re = /customDirectives\.(?:global|local)\.(\w+)\s*=/g;
      let m;
      while ((m = re.exec(src)) !== null) names.add(m[1]);
    }

    // 4. "marp" is the CLI meta-directive that enables the Marpit engine. It is
    //    not in any directive list — it is recognised at the CLI level.
    names.add("marp");

    console.log([...names].sort().join("\n"));
  ' 2>/dev/null
)"
if [ -z "$marp_directives" ]; then
  echo "marp-check: FAIL — could not extract directive names from pinned Marp" >&2
  fail=1
else
  # Extract kMarpitDirectiveNames from the Dart source — only the quoted
  # strings inside the set literal, skipping comment lines.
  ocideck_directives="$(
    sed -n '/const kMarpitDirectiveNames/,/^};/p' "$REPO/lib/services/marp_source_preservation.dart" |
      grep -v '^\s*//' |
      grep -o "'[A-Za-z][A-Za-z0-9_-]*'" | tr -d "'" | sort -u
  )"
  # Compare both directions.
  only_marp="$(comm -23 <(echo "$marp_directives") <(echo "$ocideck_directives"))"
  only_us="$(comm -13 <(echo "$marp_directives") <(echo "$ocideck_directives"))"
  if [ -n "$only_marp" ]; then
    echo "marp-check: FAIL — pinned Marp knows directives OciDeck does not:" >&2
    echo "$only_marp" | sed 's/^/  /' >&2
    echo "  Add them to kMarpitDirectiveNames in lib/services/marp_source_preservation.dart" >&2
    fail=1
  fi
  if [ -n "$only_us" ]; then
    echo "marp-check: FAIL — kMarpitDirectiveNames has directives the pinned Marp does not know:" >&2
    echo "$only_us" | sed 's/^/  /' >&2
    echo "  Remove them, or bump the pinned Marp version in tool/marp-check/package.json" >&2
    fail=1
  fi
fi

if [ "$fail" = 0 ]; then
  echo "marp-check: PASS — theme loads, split survives, move + spaces work, default invocation documented, directive list in sync with pinned Marp."
  exit 0
fi
exit 1
