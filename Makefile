.PHONY: setup format format-check analyze test coverage test-contracts test-preview test-export test-state test-services test-presenter deps-outdated deps-check licenses check-conventions build-web check-web build-macos build-windows build-linux build-all check check-full help

help:
	@echo "OciDeck quality targets:"
	@echo "  make check           Format check + static analysis + full Flutter test suite."
	@echo "  make check-full      make check + dependency outdated report."
	@echo "  make coverage        Run the test suite with coverage and print a line-coverage summary."
	@echo "  make mutate          Mutation check for dead/untested branch operands (manual; FILE/TESTS overridable)."
	@echo "  make test-golden     Slide-renderer visual-regression goldens (single platform; UPDATE=1 to accept)."
	@echo "  make test-contracts  Markdown/save-load contract and parsing tests."
	@echo "  make test-preview    Slide rendering, footer, TLP, inline markdown, and preview tests."
	@echo "  make test-export     Export and file-service smoke tests."
	@echo "  make test-state      Provider/state/recovery tests."
	@echo "  make test-services   Caption/description/image service tests."
	@echo "  make test-presenter  Fullscreen presenter interaction tests."
	@echo "  make deps-outdated   Advisory dependency freshness report."
	@echo "  make deps-check      Verify vendored JS bundles vs manifest + OSV CVEs."
	@echo "  make licenses        Verify all dependencies use open-source licences."
	@echo "  make check-conventions  No print(); bare catch (_) & file-size ratchets."
	@echo "  make check-method-length  Per-method length ratchet (AST-measured, max 150)."
	@echo "  make build-web       Build the hardened web bundle (self-hosted CanvasKit + CSP-safe loader)."
	@echo "  make check-web       Build the web bundle and assert its hardening (CSP, self-hosted, fonts)."
	@echo "  make build-macos     Build the macOS .app (macOS only)."
	@echo "  make build-windows   Build the Windows app (Windows only)."
	@echo "  make build-linux     Build the Linux bundle (Linux only)."
	@echo "  make build-all       Build web + this OS's native desktop target."

# Install Flutter/Dart dependencies.
setup:
	@echo "== OciDeck setup =="
	@echo "Purpose: install Flutter/Dart dependencies with 'flutter pub get'."
	flutter pub get

# Auto-format all Dart code in-place.
format:
	@echo "== OciDeck format =="
	@echo "Purpose: rewrite Dart files using the repository formatter."
	dart format .

# Verify formatting without modifying files.
format-check:
	@echo "== OciDeck check: format =="
	@echo "Command: dart format --output=none --set-exit-if-changed ."
	@echo "Covers: all Dart source and test files tracked in this workspace."
	@echo "Failure means: at least one Dart file needs 'dart format .'."
	dart format --output=none --set-exit-if-changed .

# Static analysis. --fatal-infos makes info-level diagnostics fail the build too,
# so the strict-casts/strict-raw-types/strict-inference modes in
# analysis_options.yaml are actually enforced.
analyze:
	@echo "== OciDeck check: static analysis =="
	@echo "Command: flutter analyze --fatal-infos"
	@echo "Covers: analyzer/lint/type checks (incl. strict inference) for the app and tests."
	@echo "Failure means: inspect analyzer diagnostics above the final summary."
	flutter analyze --fatal-infos

# Run the full unit/widget test suite. Ordering is randomised so a test can't
# silently depend on another test running first.
test:
	@echo "== OciDeck check: tests =="
	@echo "Command: flutter test --test-randomize-ordering-seed random"
	@echo "Covers: all unit/widget tests under test/, including markdown round-trip, preview, export, provider, footer, and presenter tests."
	@echo "Failure means: inspect the named failing test file and test case in the Flutter output."
	flutter test --test-randomize-ordering-seed random --exclude-tags golden

# Run the full test suite with coverage and summarise line coverage. The floor
# guards against large regressions; raise it as coverage improves.
coverage:
	@echo "== OciDeck check: coverage =="
	@echo "Command: flutter test --coverage && dart run tool/coverage_summary.dart --min=60"
	@echo "Covers: line coverage across every lib/ file a test imports."
	@echo "Failure means: overall line coverage dropped below the required floor."
	flutter test --coverage --test-randomize-ordering-seed random --exclude-tags golden
	dart run tool/coverage_summary.dart --min=60

# Slide-renderer visual-regression goldens (test/golden/). Pixel- and
# platform-specific (default flutter-test font, so they catch layout/structure/
# colour regressions), hence excluded from the default suite and from CI. Run on
# ONE platform; regenerate after an intentional visual change:
#   make test-golden                 # compare against the committed PNGs
#   make test-golden UPDATE=1        # accept the new rendering
test-golden:
	@echo "== OciDeck check: golden (visual regression) =="
	@echo "Command: flutter test --tags golden $(if $(UPDATE),--update-goldens,)"
	@echo "Covers: SlidePreviewWidget layout/structure/colour per slide type."
	@echo "Failure means: a slide renders differently — inspect the *_testImage diff,"
	@echo "        then re-run with UPDATE=1 if the change is intentional."
	flutter test --tags golden $(if $(UPDATE),--update-goldens,)

# Mutation check for the "dead/untested boolean-operand" bug class that line
# coverage and `dart analyze` both miss: an `||`/`&&` operand that can never be
# true (e.g. a `startsWith('<!--')` on input whose comments were already
# stripped). Coverage can't see it — the line is still hit via another operand.
# Each String.startsWith/endsWith predicate is forced false and the tests rerun;
# a SURVIVING mutant is a dead or untested predicate. Slow and the survivor list
# needs triage (dead -> remove, untested -> add a test), so this is a manual
# tool, NOT part of `check`. Override FILE/TESTS to target another parser:
#   make mutate FILE=lib/services/markdown_service.dart \
#     TESTS="test/markdown_round_trip_test.dart test/markdown_service_test.dart"
FILE  ?= lib/services/markdown_validator.dart
TESTS ?= test/markdown_validator_test.dart
mutate:
	@echo "== OciDeck check: mutation (dead-branch) =="
	@echo "Command: dart run tool/mutation_check.dart $(FILE) $(TESTS)"
	@echo "Covers: every String.startsWith/endsWith predicate in FILE, forced false."
	@echo "Failure means: a predicate survived — it is dead or untested; review it."
	dart run tool/mutation_check.dart $(FILE) $(TESTS)

# Contract tests for persistence and parsing.
test-contracts:
	@echo "== OciDeck targeted check: contracts =="
	@echo "Command: flutter test test/markdown_round_trip_test.dart test/markdown_service_test.dart"
	@echo "Covers: Markdown generation/parsing, save-load round-trips, slide field migration defaults, theme profile metadata."
	@echo "Failure means: a UI/model field may not persist correctly, or old presentations may migrate incorrectly."
	flutter test test/markdown_round_trip_test.dart test/markdown_service_test.dart

# Visual/rendering-focused widget tests.
test-preview:
	@echo "== OciDeck targeted check: preview/rendering =="
	@echo "Command: flutter test preview-related widget tests"
	@echo "Covers: slide preview rendering, image panels, footer placement, TLP badge, inline markdown, text style regressions."
	@echo "Failure means: inspect visual layout/rendering logic before changing export or slide-preview code."
	flutter test test/bullets_image_preview_test.dart test/footer_preview_test.dart test/image_slides_preview_test.dart test/inline_markdown_test.dart test/slide_text_style_test.dart test/tlp_test.dart

# Export and filesystem integration smoke tests.
test-export:
	@echo "== OciDeck targeted check: export/files =="
	@echo "Command: flutter test test/export_service_test.dart test/file_service_test.dart"
	@echo "Covers: PDF/PPTX export smoke tests and project file-save behavior, including copied logo assets."
	@echo "Failure means: inspect export_service/file_service and generated artifact structure."
	flutter test test/export_service_test.dart test/file_service_test.dart

# State-management and recovery tests.
test-state:
	@echo "== OciDeck targeted check: state/recovery =="
	@echo "Command: flutter test provider and recovery tests"
	@echo "Covers: deck mutations, undo/redo, skip state, search/replace, settings profiles, recovery snapshots."
	@echo "Failure means: inspect provider state transitions or recovery serialization."
	flutter test test/deck_provider_test.dart test/settings_provider_test.dart test/recovery_service_test.dart

# Service-level tests.
test-services:
	@echo "== OciDeck targeted check: services =="
	@echo "Command: flutter test service tests"
	@echo "Covers: image path/copy behavior, captions, descriptions, and sidecar metadata services."
	@echo "Failure means: inspect service path handling, sidecar reads/writes, or filesystem assumptions."
	flutter test test/caption_service_test.dart test/description_service_test.dart test/image_service_test.dart

# Presenter interaction tests.
test-presenter:
	@echo "== OciDeck targeted check: presenter =="
	@echo "Command: flutter test test/fullscreen_presenter_test.dart"
	@echo "Covers: fullscreen presenter navigation, presenter view, keyboard shortcuts, grid navigation."
	@echo "Failure means: inspect fullscreen presenter keyboard/focus/navigation behavior."
	flutter test test/fullscreen_presenter_test.dart

# Advisory dependency freshness report; not part of normal check because it can
# depend on network availability and does not imply the current code is broken.
deps-outdated:
	@echo "== OciDeck advisory check: dependencies =="
	@echo "Command: flutter pub outdated"
	@echo "Covers: dependency freshness only. This is advisory and may require network access."
	@echo "Failure means: inspect network/tooling first; outdated packages are not necessarily regressions."
	flutter pub outdated

# Security gate for the vendored JS bundles inlined into the HTML export.
# Verifies each file still matches assets/web_export/MANIFEST.json (sha256) and
# queries the OSV database for known vulnerabilities in the pinned versions.
deps-check:
	@echo "== OciDeck check: bundled JavaScript =="
	@echo "Command: dart run tool/check_bundled_js.dart"
	@echo "Covers: integrity (sha256 vs manifest) + known CVEs (OSV) for marked,"
	@echo "        highlight.js, DOMPurify, mermaid and MathJax."
	@echo "Failure means: a bundle drifted from the manifest, or a pinned version"
	@echo "        now has a known vulnerability — upgrade it and refresh the manifest."
	dart run tool/check_bundled_js.dart

# Open-source licence compliance check for all resolved dependencies.
licenses:
	@echo "== OciDeck check: licences =="
	@echo "Command: dart run tool/check_licenses.dart"
	@echo "Covers: licence of every resolved Dart/Flutter package (direct + transitive)."
	@echo "Failure means: a dependency uses an unrecognised or non-open-source licence — review it."
	dart run tool/check_licenses.dart

# Project-convention guard: no print() (use the logger in lib/utils/log.dart) and
# no NEW bare `catch (_)` (a downward-only ratchet; see the script's baseline).
check-conventions:
	@echo "== OciDeck check: conventions =="
	@echo "Command: dart run tool/check_conventions.dart"
	@echo "Covers: no print(); bare catch (_) ratchet; file-size ratchet (no file"
	@echo "        over 1000 lines except baselined ceilings, which may only shrink)."
	@echo "Failure means: route diagnostics through logError, split the oversized file,"
	@echo "        or adjust the baseline in tool/check_conventions.dart."
	dart run tool/check_conventions.dart

check-method-length:
	@echo "== OciDeck check: method length =="
	@echo "Command: dart run tool/check_method_length.dart"
	@echo "Covers: per-method/function-length ratchet (no declaration over 150 lines"
	@echo "        except baselined ceilings, which may only shrink). AST-measured."
	@echo "Failure means: extract helpers/sub-widgets to shrink the method, or adjust"
	@echo "        the baseline in tool/check_method_length.dart."
	dart run tool/check_method_length.dart

# Build the hardened web bundle. Two flags do the security work:
#   --no-web-resources-cdn  Self-host CanvasKit instead of fetching it from the
#                           gstatic CDN, so the running app pulls ZERO third-party
#                           origins (air-gappable, reproducible, fits the pinned
#                           bundled-JS policy in deps-check).
#   --csp                   Emit a CSP-compliant loader: no eval()/inline scripts
#                           in the Flutter bootstrap, so script-src needs neither
#                           'unsafe-eval' nor 'unsafe-inline'. Pairs with the
#                           Content-Security-Policy meta tag in web/index.html.
build-web:
	@echo "== OciDeck build: hardened web bundle =="
	@echo "Command: flutter build web --release --no-web-resources-cdn --csp"
	@echo "Covers: self-hosted CanvasKit (no third-party CDN) and a CSP-safe loader."
	@echo "Output: build/web — serve behind the CSP declared in web/index.html."
	flutter build web --release --no-web-resources-cdn --csp

# Build the web bundle, then assert it kept its hardening: a strict CSP, a
# self-hosted CanvasKit, and the bundled UI font (no gstatic). Guards against a
# future change silently re-introducing a third-party origin or weakening the CSP.
check-web: build-web
	@echo "== OciDeck check: web hardening =="
	@echo "Command: dart run tool/check_web_hardening.dart"
	@echo "Covers: build/web CSP strictness, self-hosted CanvasKit, bundled font."
	@echo "Failure means: the web bundle lost a hardening invariant — see the list."
	dart run tool/check_web_hardening.dart

# Native desktop release builds. Each target only works on its own OS — Flutter
# cannot cross-compile a desktop bundle (a macOS .app needs macOS, a Windows
# .exe needs Windows, a Linux bundle needs Linux). Run the matching target on
# the matching machine, or use the release CI workflow to produce all at once.
build-macos:
	@echo "== OciDeck build: macOS app (.app) =="
	@echo "Command: flutter build macos --release"
	@echo "Output: build/macos/Build/Products/Release/*.app"
	flutter build macos --release

build-windows:
	@echo "== OciDeck build: Windows app (.exe) =="
	@echo "Command: flutter build windows --release"
	@echo "Output: build/windows/x64/runner/Release"
	flutter build windows --release

build-linux:
	@echo "== OciDeck build: Linux bundle =="
	@echo "Command: flutter build linux --release"
	@echo "Output: build/linux/x64/release/bundle"
	flutter build linux --release

# Build everything this machine CAN build: the hardened web bundle always, plus
# the desktop target native to the current OS. Windows/Linux desktop bundles for
# the other OSes come from the release CI workflow, not from here.
build-all:
	@echo "== OciDeck build: all targets for this OS =="
	$(MAKE) build-web
	@case "$$(uname -s)" in \
	  Darwin) $(MAKE) build-macos ;; \
	  Linux) $(MAKE) build-linux ;; \
	  *) echo "No native desktop build for '$$(uname -s)' here — run 'make build-windows' on Windows." ;; \
	esac
	@echo "== OciDeck build-all complete =="

# Full local quality gate. Intended for humans, CI logs, and LLM-assisted debugging.
check: format-check analyze check-conventions check-method-length test
	@echo "== OciDeck check complete =="
	@echo "Validated: formatting, static analysis, conventions, method length, and the full Flutter test suite."

# Extended local check: the gate plus licence/compliance, bundled-JS CVEs, the
# web-hardening assertion (rebuilds the web bundle), and a freshness report.
check-full: check licenses deps-check check-web deps-outdated
	@echo "== OciDeck extended check complete =="
	@echo "Validated: required quality gate, licence compliance, bundled-JS CVEs, web hardening, and dependency freshness."
