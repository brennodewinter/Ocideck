.PHONY: dast sast check-secrets refresh-catalogs setup format format-check fix analyze test coverage test-contracts test-preview test-export test-state test-services test-presenter deps-outdated deps-check deps-verify-offline trivy check-actions catalogs-outdated refresh-lexicon licenses sbom sbom-verify check-conventions check-audience-boundary check-method-length check-dead-code check-hardcoded-text coverage-per-file add-l10n l10n-check mutate mutate-parsers build-web check-web build-macos build-windows build-linux build-all build-release check check-full help servicenormen doorlooptijd ratchets

# macOS (and some Linux setups) ship a low open-file-descriptor soft limit. The
# full test suite exhausts it and fails with "Too many open files" — worst under
# --coverage, which holds a VM-Service connection open per test until the run
# ends. Raise the soft limit for the whole-suite recipes below. The hard limit is
# normally unlimited; the `|| true` keeps the build working if a machine caps it
# lower than 8192 (there the limit simply stays where it was).
RAISE_FDS := ulimit -n 8192 2>/dev/null || true;

# De beeldcontrole (`image_face_scan_io.dart`) draait op OpenCV via FFI. Die
# native bibliotheek zit in de app-bundel, niet in `flutter test`: een testrun op
# de Dart-VM heeft haar dus niet, en de detectietests slaan zichzelf over.
#
# Dat is geen theoretisch probleem. Het is precies één keer misgegaan: de tests
# stonden groen terwijl de bibliotheek niet laadde, elke aanroep in de
# foutafhandeling viel en de scanner nul gezichten meldde. Groen om de verkeerde
# reden is erger dan rood.
#
# `dartcv` leest het pad uit DARTCV_LIB_PATH. Heeft deze werkkopie ooit een
# platformbuild gedaan, dan staat de bibliotheek in `build/` en zetten we hem
# hier — dan draaien de detectietests echt, zonder dat iemand een variabele hoeft
# te onthouden. Is er geen build, dan blijft alles zoals het was: de tests slaan
# zichzelf over en zeggen dat ook.
#
# Bewust gezocht op bestandsnaam en niet op een vast pad: dat verschilt per
# platform (framework/`.so`/`.dll`) én per bouwmodus (Debug/Release/Profile).
DARTCV_LIB := $(firstword $(wildcard   build/macos/Build/Products/*/DartCvMacOS/DartCvMacOS.framework/Versions/A/DartCvMacOS   build/linux/*/*/bundle/lib/libdartcv.so   build/windows/*/runner/*/dartcv.dll))
ifneq ($(DARTCV_LIB),)
export DARTCV_LIB_PATH := $(abspath $(DARTCV_LIB))
endif

help:
	@echo "OciDeck quality targets:"
	@echo "  make check           Format check + static analysis + full Flutter test suite + coverage floor."
	@echo "  make check-full      make check + secrets + SAST + licences, SBOM, deps, web hardening."
	@echo "  make coverage        Test suite with coverage: enforce the floor AND that every lib/ file is in some test."
	@echo "  make mutate          Mutation check for dead/untested branch operands (manual; FILE/TESTS overridable)."
	@echo "  make mutate-parsers  Mutation sweep over all markdown parsers/serializers (manual, slow)."
	@echo "  make test-golden     Slide-renderer visual-regression goldens (single platform; UPDATE=1 to accept)."
	@echo "  make test-contracts  Markdown/save-load contract and parsing tests."
	@echo "  make test-preview    Slide rendering, footer, TLP, inline markdown, and preview tests."
	@echo "  make test-export     Export and file-service smoke tests."
	@echo "  make test-state      Provider/state/recovery tests."
	@echo "  make test-services   Caption/description/image service tests."
	@echo "  make test-presenter  Fullscreen presenter interaction tests."
	@echo "  make deps-outdated   Advisory dependency freshness report."
	@echo "  make deps-check      Verify vendored JS bundles vs manifest + OSV CVEs."
	@echo "  make dast            Advisory ZAP baseline over a served build (DAST_URL=… for a real host)."
	@echo "  make sast            Semgrep over shipped Dart with the rules in semgrep/ (needs semgrep)."
	@echo "  make check-secrets   Sweep working tree and history for committed secrets (needs gitleaks + trufflehog)."
	@echo "  make trivy           Advisory supply-chain scan: Dart-dep CVEs + committed secrets (needs trivy)."
	@echo "  make check-actions   Advisory: exact-pinned CI Actions vs their latest release."
	@echo "  make servicenormen   Interne reactietermijnen op beveiligingsmeldingen (--quiet voor cron)."
	@echo "  make doorlooptijd    Doorlooptijd van gewone issues (adviserend; --quiet voor cron)."
	@echo "  make ratchets        Bewegen de basislijnen en de dekking de goede kant op (adviserend)."
	@echo "  make licenses        Verify all dependencies use open-source licences."
	@echo "  make sbom            Generate the SBOM (CycloneDX + SPDX) in sbom/."
	@echo "  make sbom-verify     Fail if the committed SBOM is stale (CRA staleness gate)."
	@echo "  make check-conventions  No print(); bare catch (_) & file-size ratchets."
	@echo "  make check-audience-boundary  Every output channel classified: audience (needs AudienceDeck) or source."
	@echo "  make check-method-length  Per-method length ratchet (AST-measured, max 150)."
	@echo "  make check-dead-code Fail on orphaned lib/ files (unreachable from any entrypoint)."
	@echo "  make check-hardcoded-text  Hard gate: no visible string in lib/ may bypass l10n.d()."
	@echo "  make coverage-per-file  Per-file coverage floor: budget of files below it (must reach 0)."
	@echo "  make add-l10n SPEC=… Add d('…') source strings to every language from a JSON spec."
	@echo "  make catalogs-outdated Advisory: bundled reference data vs upstream (run before a release build)."
	@echo "  make refresh-catalogs Regenerate WSTG/MASTG/MASWE from upstream (not in check)."
	@echo "  make refresh-lexicon  Regenerate the bundled health lexicon from Orphanet (read the term diff)."
	@echo "  make l10n-check      Fast l10n gate: duplicate keys, per-language coverage, and formatting."
	@echo "  make fix             Auto-apply 'dart fix' and reformat (local cleanup helper)."
	@echo "  make build-web       Build the hardened web bundle (self-hosted CanvasKit + CSP-safe loader)."
	@echo "  make check-web       Build the web bundle and assert its hardening (CSP, self-hosted, fonts)."
	@echo "  make build-macos     Build the macOS .app (macOS only)."
	@echo "  make build-windows   Build the Windows app (Windows only)."
	@echo "  make build-linux     Build the Linux bundle (Linux only)."
	@echo "  make build-all       Build web + this OS's native desktop target."
	@echo "  make build-release   Build verified web + macOS release artifacts."

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

# Local cleanup helper: apply every analyzer-suggested fix (removes unused
# imports, unreachable code, unnecessary_* etc.), then reformat. Curative, not a
# gate — run it before committing; `make analyze` still enforces the result.
fix:
	@echo "== OciDeck fix =="
	@echo "Purpose: apply 'dart fix' auto-fixes (dead code, unused imports, ...) then reformat."
	dart fix --apply
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
	$(RAISE_FDS) flutter test --test-randomize-ordering-seed random --exclude-tags golden

# Run the full test suite with coverage and summarise line coverage. The floor
# guards against large regressions; raise it as coverage improves.
#
# --require-instrumented is what makes the floor mean something: lcov omits a
# file no test imports, so such a file is not 0% — it is outside the fraction
# altogether, and a percentage alone can never catch it. This also enumerates
# lib/ from disk and fails on any non-baselined file that is in no test.
coverage:
	@echo "== OciDeck check: coverage =="
	@echo "Command: flutter test --coverage && dart run tool/coverage_summary.dart --min=80 --require-instrumented"
	@echo "Covers: line coverage over lib/, plus: every lib/ file is in at least one test."
	@echo "Failure means: coverage fell below the floor, or a lib/ file is in no test at all."
	$(RAISE_FDS) flutter test --coverage --test-randomize-ordering-seed random --exclude-tags golden
	dart run tool/coverage_summary.dart --min=80 --require-instrumented

# The per-file floor, over the report `coverage` just wrote (no second test run).
#
# Separate from the floor above because it answers a different question. The
# average says how much of lib/ runs; it says nothing about *where*. A file that
# a test imports but never calls sits at 0% inside an 80% average and no gate
# above notices — twenty-two files were in exactly that state. This one looks at
# the worst case per file, en er is geen budget meer: één zo'n bestand is rood.
coverage-per-file:
	@echo "== OciDeck check: per-file coverage floor =="
	@echo "Command: dart run tool/coverage_summary.dart --per-file-floor"
	@echo "Covers: how many lib/ files run less than a fifth of their own lines — the worst case per file, which the overall average cannot show."
	@echo "Failure means: minstens één lib/-bestand draait minder dan een vijfde van zijn eigen regels — schrijf er een test voor (of zet het met reden in uncoveredBaseline als het een platformhelft is)."
	dart run tool/coverage_summary.dart --per-file-floor

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
	$(RAISE_FDS) flutter test --tags golden $(if $(UPDATE),--update-goldens,)

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

# The full parser sweep: every parser/serializer with startsWith/endsWith
# predicates, each against its fastest relevant test set. Still manual (slow:
# one test run per predicate), but one command instead of five.
mutate-parsers:
	@echo "== OciDeck check: mutation sweep over the parsers =="
	@echo "Command: tool/mutation_check.dart over parse/serialize/body-blocks/inline/validator."
	@echo "Failure means: a predicate survived — it is dead or untested; review it."
	dart run tool/mutation_check.dart lib/services/markdown_service_parse.dart test/markdown_round_trip_test.dart test/markdown_service_test.dart
	dart run tool/mutation_check.dart lib/services/markdown_service_finding.dart test/markdown_round_trip_test.dart test/markdown_service_test.dart
	dart run tool/mutation_check.dart lib/models/finding_template.dart test/finding_template_test.dart
	dart run tool/mutation_check.dart lib/services/markdown_service_serialize.dart test/markdown_round_trip_test.dart test/markdown_service_test.dart
	dart run tool/mutation_check.dart lib/services/markdown_body_blocks.dart test/markdown_body_blocks_test.dart test/rich_text_layout_test.dart
	dart run tool/mutation_check.dart lib/widgets/slides/inline_markdown.dart test/inline_markdown_test.dart
	dart run tool/mutation_check.dart lib/services/markdown_validator.dart test/markdown_validator_test.dart

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

# Secrets sweep with two independent scanners. Both are wired into `check-full`
# but deliberately NOT into `check`: they need external binaries, and a missing
# tool should not redden the everyday gate. The PR procedure requires this
# target — see docs/CHECKS.md.
#
# Two scanners rather than one because they disagree in useful ways: gitleaks
# matches entropy and rule patterns, trufflehog carries per-provider detectors.
# Both are pointed at the working tree AND at history — a secret that was
# committed and then removed is still a leak.
#
# --no-verification is not optional here. Trufflehog otherwise sends candidate
# secrets to the issuing service to see whether they are live. That is outbound
# traffic carrying credentials to third parties, from a project whose whole
# premise is that nothing leaves the machine unasked. Verify by hand if ever
# needed, deliberately, on a single finding.
# Static analysis with Semgrep over the shipped Dart, using rules committed in
# semgrep/. Deliberately NOT `--config auto`: that fetches rules over the network
# at scan time and phones home with metrics. Local rules keep the gate offline
# and reproducible, which is the same reason `deps-verify-offline` exists.
#
# The ruleset does not repeat what tool/check_conventions.dart already does with
# real AST knowledge. Semgrep earns its place because it parses: a grep for
# `badCertificateCallback` returns three doc-comment hits in lib/, Semgrep
# returns none and would flag only a real assignment.
sast:
	@echo "== OciDeck check: SAST (Semgrep) =="
	@echo "Command: semgrep scan --config semgrep/ocideck.yaml --metrics=off --error"
	@echo "Covers: shipped Dart in lib/, plus tool/ and test/ where the rule applies."
	@echo "Failure means: a rule matched. Read it — every rule here is scoped to be quiet."
	@command -v semgrep >/dev/null 2>&1 || { echo "semgrep not found — install it (macOS: brew install semgrep)"; exit 2; }
	semgrep scan --config semgrep/ocideck.yaml --metrics=off --error lib/ tool/ test/

check-secrets:
	@echo "== OciDeck check: committed secrets =="
	@echo "Command: gitleaks (dir + git) and trufflehog (filesystem + git)"
	@echo "Covers: credential-shaped strings in the working tree and in all history."
	@echo "Failure means: a scanner found something outside the allowlist, or a tool is missing."
	@echo "        Triage by hand; see .gitleaks.toml for what is excluded and why."
	@command -v gitleaks >/dev/null 2>&1 || { echo "gitleaks not found — install it (macOS: brew install gitleaks)"; exit 2; }
	@command -v trufflehog >/dev/null 2>&1 || { echo "trufflehog not found — install it (macOS: brew install trufflehog)"; exit 2; }
	gitleaks dir . --redact --config .gitleaks.toml
	gitleaks git . --redact --config .gitleaks.toml
	trufflehog filesystem . --no-verification --no-update --exclude-paths .trufflehogignore --fail
	trufflehog git file://. --no-verification --no-update --exclude-paths .trufflehogignore --fail

# Advisory DAST: an OWASP ZAP baseline (passive) scan against a served build.
#
# ADVISORY, and not wired into any aggregate target. Be honest about what this
# can and cannot see:
#   - The CSP is already pinned exactly by `make check-web`, from the meta tag
#     in the built index.html. ZAP does not improve on that.
#   - ZAP's spider cannot traverse the UI: CanvasKit paints into a canvas, so
#     there are no links or forms to follow. Only the initial load is observed.
#   - Against the default local server, findings about response headers are
#     mostly about *that server*. zap/baseline.conf silences exactly those and
#     nothing else.
# Its real value arrives when DAST_URL points at a genuinely deployed instance:
# then the response headers are the host's, and they are the thing under test.
#
# Override the target: `make dast DAST_URL=https://example.org/ocideck/`.
# Without it, the local bundle is built, served on DAST_PORT, and torn down.
DAST_PORT ?= 8091
DAST_URL ?=
dast:
	@echo "== OciDeck advisory check: DAST (OWASP ZAP baseline) =="
	@echo "Command: zap-baseline.py against $(if $(DAST_URL),$(DAST_URL),a local server on port $(DAST_PORT))"
	@echo "Covers: passive checks over the initial load — headers, CSP delivery, cookies."
	@echo "Failure means: ZAP or the container runtime is missing. Findings are advisory;"
	@echo "        read them by hand. See zap/baseline.conf for what is silenced and why."
	@command -v docker >/dev/null 2>&1 || { echo "docker not found — install a runtime (macOS: brew install colima docker && colima start)"; exit 2; }
	@docker info >/dev/null 2>&1 || { echo "no container runtime reachable — start it (macOS: colima start)"; exit 2; }
ifeq ($(strip $(DAST_URL)),)
	$(MAKE) build-web
	@echo "-- serving build/web on :$(DAST_PORT) for the duration of the scan --"
	@cd build/web && python3 -m http.server $(DAST_PORT) >/dev/null 2>&1 & echo $$! > /tmp/ocideck-dast.pid
	@sleep 2
	-docker run --rm --add-host=host.docker.internal:host-gateway \
	  -v "$(PWD)/zap:/zap/wrk/conf:ro" zaproxy/zap-stable \
	  zap-baseline.py -t http://host.docker.internal:$(DAST_PORT) -c conf/baseline.conf -I
	@kill $$(cat /tmp/ocideck-dast.pid) 2>/dev/null || true; rm -f /tmp/ocideck-dast.pid
	@echo "-- local server stopped --"
else
	-docker run --rm -v "$(PWD)/zap:/zap/wrk/conf:ro" zaproxy/zap-stable \
	  zap-baseline.py -t "$(DAST_URL)" -c conf/baseline.conf -I
endif

# Advisory supply-chain scan with Trivy (github.com/aquasecurity/trivy). Scans
# the resolved Dart packages (pubspec.lock) for known CVEs and sweeps the repo
# for committed secrets — see trivy.yaml for the enabled scanners and rationale.
# Advisory, and NOT wired into `check`/`check-full`, because (a) it needs the
# external `trivy` binary which the gate can't assume, and (b) Dart/pub advisory
# coverage is still thin, so a finding is a prompt to review, not a build break.
# Container/IaC scanners are omitted: OciDeck ships no images or IaC.
trivy:
	@echo "== OciDeck advisory check: Trivy supply-chain =="
	@echo "Command: trivy fs --config trivy.yaml ."
	@echo "Covers: Dart package CVEs (pubspec.lock) + committed secrets across the repo."
	@echo "Failure means: trivy is missing or the scan errored — reported"
	@echo "        vulnerabilities/secrets are advisory; triage them by hand."
	@command -v trivy >/dev/null 2>&1 || { echo "trivy not found — install it (macOS: brew install trivy; docs: https://trivy.dev/latest/getting-started/installation/)"; exit 2; }
	@# This used to run with DOCKER_CONFIG pointed at an empty temp dir, to dodge a
	@# stale `credsStore: desktop` left behind by an uninstalled Docker Desktop.
	@# That workaround became the bug: ~/.docker/config.json also holds
	@# `currentContext`, so blanking the config drops the container context and
	@# docker falls back to /var/run/docker.sock — which does not exist under
	@# colima. Fix the cause instead: remove the dangling credsStore key. With
	@# empty `auths` no credential helper is needed for public registries.
	trivy fs --config trivy.yaml .

# Advisory freshness monitor for the third-party CI Actions we pin to an EXACT
# version. Reads .github/pinned-actions.json and asks each Action's release API
# whether a newer version exists — the Action analogue of deps-check for the
# vendored JS. Advisory (needs network, a bump is a prompt not a regression), so
# NOT wired into check/check-full. `--offline` validates the manifest only.
check-actions:
	@echo "== OciDeck advisory check: pinned CI Actions =="
	@echo "Command: dart run tool/check_pinned_actions.dart"
	@echo "Covers: every exact-pinned Action in .github/pinned-actions.json vs its latest release."
	@echo "Failure means: a pinned Action is behind (bump it + the manifest) or the release API was unreachable."
	dart run tool/check_pinned_actions.dart

# Interne servicenormen rond beveiligingsmeldingen: hoe snel er gereageerd,
# geoordeeld en opgelost wordt. Meet uit de tijdstempels die de meldingen in de
# forge toch al dragen — een handgeschreven lijst veroudert en niemand vult hem.
#
# Bewust in GEEN enkele verzameldoel opgenomen, ook niet in `check-full`. Twee
# redenen, en de tweede is de zwaarste:
#
#   1. Dit doel heeft een persoonlijke leessleutel voor de forge nodig. Een
#      medewerker zonder sleutel zou exit 2 krijgen — "kon niet meten" — en dat
#      leest als een defect in zijn wijziging terwijl het er geen is.
#   2. Zodra het in `check-full` hangt, moet docs/CHECKS.md het noemen, want die
#      beschrijft wat dat doel dekt. En dan staat "reactietermijnen" tóch in een
#      document dat als asset met de app meereist. Precies de sluiproute die
#      deze hele opzet vermijdt.
#
# De bewaking loopt daarom niet via een verzameldoel maar via de
# --quiet-variant in cron: die zwijgt tot er iets te melden valt. Zie de kop van
# tool/check_service_norms.dart.
#
# De normen zelf staan in dat bestand en nergens anders. Ze zijn intern:
# alarmdrempels waarop dit project zichzelf wekt, geen toezegging aan derden.
# Daarom staan ze niet in docs/ (dat reist als asset mee in de app) en niet in
# SECURITY.md. Zie de kop van het gereedschap voor de redenering.
servicenormen:
	@echo "== OciDeck check: servicenormen (intern) =="
	@echo "Command: dart run tool/check_service_norms.dart"
	@echo "Covers: eerste reactie, oordeel echt-of-ruis en oplostermijn over de"
	@echo "        meldingen met een beveiligingslabel in de forge."
	@echo "Failure means: een interne alarmdrempel is overschreden — kijk of de"
	@echo "        praktijk of de norm moet veranderen. Exit 2 betekent iets"
	@echo "        anders: er kón niet gemeten worden (geen leessleutel, geen"
	@echo "        netwerk). Dat is geen normoverschrijding maar wél een defect."
	dart run tool/check_service_norms.dart

# Doorlooptijd van de GEWONE tracker: leeftijd, tijd tot eerste reactie, hoeveel
# er open staan zonder enig antwoord, en triage-issues die nooit verder kwamen.
#
# Adviserend, en dat is hier de standaard en niet een vlag. Voor gewone issues
# bestaat geen afgesproken termijn — bewust niet, want een zelf opgelegde
# deadline die je op een rustige week mist, maakt van een leermoment een
# verwijt. Er valt dus niets te falen; `--strict` bestaat voor wie er later wél
# een norm bij afspreekt.
#
# Om dezelfde reden als servicenormen hierboven staat dit in geen enkel
# verzameldoel: het heeft een persoonlijke leessleutel nodig, en exit 2 ("kon
# niet meten") zou bij een medewerker zonder sleutel als defect lezen.
doorlooptijd:
	@echo "== OciDeck meting: doorlooptijd gewone issues (adviserend) =="
	@echo "Command: dart run tool/check_issue_turnaround.dart"
	@echo "Covers: leeftijd per open issue, tijd tot eerste reactie, issues"
	@echo "        zonder enige reactie, en stilstand op het label triage."
	@echo "Failure means: niets — dit meet en oordeelt niet. Exit 2 betekent wel"
	@echo "        iets: er kón niet gemeten worden (geen leessleutel, geen"
	@echo "        netwerk). Dat is geen signaal maar een defect."
	dart run tool/check_issue_turnaround.dart

# Bewegen de ratchets de goede kant op? De poorten meten of iets wérkt; ze meten
# niet of het beter wordt. Dit zet elke basislijn naast zijn waarde van een
# ijkpunt terug, laat zien welke basislijnregels er het langst in staan, en
# splitst de dekking uit per map in plaats van één getal.
#
# Adviserend, en dat is hier de standaard: stilstand tot een rode bouw maken
# straft een rustige maand. Daarom ook in geen verzameldoel — het antwoord is
# een gesprek, geen poort.
#
# Draai `make coverage` eerst als je het dekkingsblok gevuld wilt zien; zonder
# coverage/lcov.info zegt het rapport dat dát deel niet gemeten is.
ratchets:
	@echo "== OciDeck meting: ratchets en dekking (adviserend) =="
	@echo "Command: dart run tool/check_ratchet_trend.dart"
	@echo "Covers: elke basislijn nu vs. het ijkpunt, de langst staande"
	@echo "        basislijnregels, en de dekking per map."
	@echo "Failure means: niets — dit meet en oordeelt niet. Exit 2 betekent wel"
	@echo "        iets: er kón niet gemeten worden (geen git, geen bronbestand)."
	dart run tool/check_ratchet_trend.dart

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
	@echo ""
	@echo "== OciDeck check: bundled reference standards =="
	@echo "Command: dart run tool/check_reference_data.dart"
	@echo "Covers: WSTG, CWE, MIAUW and CVSS — bundled version vs upstream, plus"
	@echo "        whether the bundled CWE list is still complete."
	@echo "Failure means: a standard we bundle has moved on. Update the catalogue,"
	@echo "        the version in lib/services/reference_standards.dart and"
	@echo "        docs/LICENSE_COMPLIANCE.md, and re-check the source licence."
	dart run tool/check_reference_data.dart


# Regenerate the bundled reference catalogues from their upstream sources.
# Downloads into a scratch dir, runs each generator, and leaves the diff for a
# human to read — this is deliberately NOT part of `make check`: updating a
# standard changes what a report cites, so it is a decision, not a build step.
#
# Afterwards: bump the version in lib/services/reference_standards.dart (and in
# the catalogue's own const), update docs/LICENSE_COMPLIANCE.md, and re-run
# `make deps-check` so the staleness gate agrees.
refresh-lexicon:
	@echo "== OciDeck: gebundelde lexicons opnieuw genereren =="
	@echo "Bronnen: Orphanet (CC BY 4.0) en EuroVoc (Besluit 2011/833/EU)."
	@echo "Dit herschrijft assets/privacy/health_lexicon.json en belief_lexicon.json."
	@echo ""
	@echo "LEES DE TERMDIFF. Bij een lexicon vuurt elke term, dus een nieuwe"
	@echo "        uitgave kan valse positieven binnenbrengen die een catalogus"
	@echo "        nooit zou opleveren. Draai daarna 'make check' en let op"
	@echo "        privacy_false_positive_corpus_test — die laadt de bundels."
	@set -e; \
	tmp=$$(mktemp -d); \
	echo "-- Orphanet"; \
	for l in nl en de fr es it pl pt cs; do \
	  curl -sfL "https://www.orphadata.com/data/xml/$${l}_product1.xml" -o "$$tmp/$$l.xml"; \
	done; \
	dart run tool/build_privacy_lexicon.dart "$$tmp"; \
	echo "-- EuroVoc"; \
	curl -sfG "https://publications.europa.eu/webapi/rdf/sparql" \
	  --data-urlencode "query=$$EUROVOC_QUERY" \
	  --data-urlencode "format=application/sparql-results+json" \
	  -o "$$tmp/eurovoc.json"; \
	dart run tool/build_eurovoc_lexicon.dart "$$tmp/eurovoc.json"; \
	rm -rf "$$tmp"
	@echo ""
	@echo "Werk orphanetBundledVersion bij in lib/services/reference_standards.dart"
	@echo "als de datum is opgeschoven."

# De subbomen onder godsdienst (3257), politieke ideologie (1282), vakbond
# (3575) en etnische groep (1202). Zie tool/build_eurovoc_lexicon.dart voor
# waarom het de hiërarchie is en geen trefwoordzoekopdracht.
export EUROVOC_QUERY = PREFIX skos:<http://www.w3.org/2004/02/skos/core\#> SELECT ?anchor ?c ?lang ?label ?kind WHERE { VALUES ?anchor { <http://eurovoc.europa.eu/3257> <http://eurovoc.europa.eu/1282> <http://eurovoc.europa.eu/3575> <http://eurovoc.europa.eu/1202> } { ?c skos:broader+ ?anchor } UNION { BIND(?anchor AS ?c) } { ?c skos:prefLabel ?label BIND("pref" AS ?kind) } UNION { ?c skos:altLabel ?label BIND("alt" AS ?kind) } BIND(lang(?label) AS ?lang) }

catalogs-outdated:
	@echo "== OciDeck: is er upstream iets nieuws? (adviserend) =="
	@echo "Command: dart run tool/check_reference_data.dart --advisory"
	@echo "Covers: dezelfde bronnen als 'make deps-check', maar dit breekt niets."
	@echo "Bedoeld vóór een release-build: je wilt weten wat je inpakt, en een"
	@echo "        nieuwe upstreamversie is geen defect in wat je bouwt."
	@echo "Daarna: 'make refresh-catalogs' om ze op te halen."
	dart run tool/check_reference_data.dart --advisory

refresh-catalogs:
	@echo "== OciDeck: refresh bundled reference catalogues =="
	@echo "Sources: OWASP WSTG + MASTG + MASWE, MITRE CWE."
	@echo "This rewrites generated files under lib/services/ — read the diff."
	@set -e; 	tmp=$$(mktemp -d); 	echo "-- WSTG"; 	curl -sfL "https://raw.githubusercontent.com/OWASP/wstg/v$(WSTG_VERSION)/checklist/checklist.json" -o $$tmp/wstg.json; 	dart run tool/build_wstg_catalog.dart $$tmp/wstg.json $(WSTG_VERSION); 	echo "-- MASTG"; 	curl -sfL "https://github.com/OWASP/mastg/archive/refs/tags/v$(MASTG_VERSION).tar.gz" | tar xz -C $$tmp; 	dart run tool/build_mastg_catalog.dart $$tmp/mastg-$(MASTG_VERSION) $(MASTG_VERSION); 	echo "-- MASWE"; 	curl -sfL "https://github.com/OWASP/maswe/archive/refs/heads/main.tar.gz" | tar xz -C $$tmp; 	dart run tool/build_maswe_catalog.dart $$tmp/maswe-main $(MASWE_DATE); 	rm -rf $$tmp
	@echo ""
	@echo "CWE is not refreshed here: its source is a ~30 MB zip behind a dated"
	@echo "URL. Run tool/build_cwe_catalog.dart by hand (see its header)."
	@dart format lib/ >/dev/null
	@echo "Done. Read 'git diff', bump the versions, update LICENSE_COMPLIANCE.md."

# The upstream versions the generators pull. Bump these, run refresh-catalogs,
# then mirror them into lib/services/reference_standards.dart.
WSTG_VERSION ?= 4.2
MASTG_VERSION ?= 2.0.0
MASWE_DATE ?= 2026-06-12

# Open-source licence compliance check for all resolved dependencies.
licenses:
	@echo "== OciDeck check: licences =="
	@echo "Command: dart run tool/check_licenses.dart"
	@echo "Covers: licence of every resolved Dart/Flutter package (direct + transitive)."
	@echo "Failure means: a dependency uses an unrecognised or non-open-source licence — review it."
	dart run tool/check_licenses.dart

# Software Bill of Materials. Regenerates the machine-readable inventory the EU
# Cyber Resilience Act (Reg. (EU) 2024/2847, Annex I Part II §1) requires, in
# both common formats, from the files that are already the source of truth
# (pubspec.lock, MANIFEST.json, pubspec.yaml, .tool-versions). Commit the result.
sbom:
	@echo "== OciDeck build: Software Bill of Materials =="
	@echo "Command: dart run tool/generate_sbom.dart"
	@echo "Output: sbom/ocideck.cdx.json (CycloneDX 1.6), sbom/ocideck.spdx.json (SPDX 2.3),"
	@echo "        and sbom/ocideck.sbom.md (human-readable)."
	dart run tool/generate_sbom.dart

# Staleness gate: regenerate in memory and fail if the committed SBOM drifted
# from the current dependency set (volatile timestamp/serial fields ignored).
# Same role as deps-verify-offline for the JS bundles — keeps the CRA artefact
# from silently going out of date. Wired into CI and check-full.
sbom-verify:
	@echo "== OciDeck check: SBOM up to date =="
	@echo "Command: dart run tool/generate_sbom.dart --check"
	@echo "Failure means: dependencies changed but the SBOM wasn't regenerated —"
	@echo "        run 'make sbom' and commit sbom/ocideck.cdx.json + .spdx.json."
	dart run tool/generate_sbom.dart --check

# Project-convention guard: no print() (use the logger in lib/utils/log.dart) and
# no NEW bare `catch (_)` (a downward-only ratchet; see the script's baseline).
check-conventions:
	@echo "== OciDeck check: conventions =="
	@echo "Command: dart run tool/check_conventions.dart"
	@echo "Covers: no print(); no plain writeAsString/writeAsBytes (use the atomic"
	@echo "        helpers in lib/utils/atomic_file.dart); bare catch (_) ratchet;"
	@echo "        file-size ratchet (no file over 1000 lines except baselined"
	@echo "        ceilings, which may only shrink)."
	@echo "Failure means: route diagnostics through logError, use writeStringAtomic/"
	@echo "        writeBytesAtomic, split the oversized file, or adjust the baseline"
	@echo "        in tool/check_conventions.dart."
	dart run tool/check_conventions.dart

check-audience-boundary:
	@echo "== OciDeck check: privacy projection boundary =="
	@echo "Command: dart run tool/check_audience_boundary.dart"
	@echo "Covers: every function that pairs slide content with an artefact"
	@echo "        primitive (saveFile/clipboard/raster/atomic write) must be"
	@echo "        classified: audience surface (needs AudienceDeck) or"
	@echo "        source-fidelity (must NOT redact). AST-measured."
	@echo "Failure means: a new output channel is unclassified, a registered"
	@echo "        audience surface accepts a raw Deck, or a registration went"
	@echo "        stale. Adjust _registry in tool/check_audience_boundary.dart."
	dart run tool/check_audience_boundary.dart

check-method-length:
	@echo "== OciDeck check: method length =="
	@echo "Command: dart run tool/check_method_length.dart"
	@echo "Covers: per-method/function-length ratchet (no declaration over 150 lines"
	@echo "        except baselined ceilings, which may only shrink). AST-measured."
	@echo "Failure means: extract helpers/sub-widgets to shrink the method, or adjust"
	@echo "        the baseline in tool/check_method_length.dart."
	dart run tool/check_method_length.dart

# Dead-file guard: walks the lib/ import graph from the entrypoint(s) and fails
# on any .dart file reachable from none of them — the analyzer's blind spot
# (whole orphaned files and cross-library public symbols it can't see).
check-dead-code:
	@echo "== OciDeck check: dead code =="
	@echo "Command: dart run tool/check_dead_code.dart"
	@echo "Covers: orphaned lib/ files — unreachable via import/export/part from any"
	@echo "        top-level main() (both branches of conditional imports counted)."
	@echo "Failure means: delete the orphaned file, wire it in, or (for a deliberate"
	@echo "        dynamic entrypoint) add it to deadCodeAllowlist in"
	@echo "        tool/check_dead_code.dart."
	dart run tool/check_dead_code.dart

# De andere helft van de vertaalbelofte. app_localizations_test controleert dat
# elke bronstring in alle 31 talen bestaat; deze poort controleert dat een
# zichtbare string ook DÓÓR `d()` gaat. Het gat zat in de doorgeefluiken —
# `EditorField(label: 'Titel (H1)')` gaat via `l10n.d(widget.label)` en was voor
# een letterlijke scanner onzichtbaar. De poort splitst die twee gevallen:
# gaat de literal onderweg door `d()`, dan is hij een BRONSLEUTEL (geen
# overtreding, wél vertaalplicht — bewaakt in app_localizations_test); gaat hij
# er niet doorheen, dan is het een echte overtreding en faalt de poort.
check-hardcoded-text:
	@echo "== OciDeck check: hardgecodeerde tekst =="
	@echo "Command: dart run tool/check_hardcoded_text.dart"
	@echo "Covers: elke zichtbare letterlijke tekst in lib/ die niet door l10n.d()"
	@echo "        loopt — knoplabels, veldlabels, hints, tooltips, meldingen, en de"
	@echo "        indirecte doorgeefluiken (AST + datastroom, dus ook"
	@echo "        EditorField(label: '…')). Bronsleutels die wél door d() gaan"
	@echo "        tellen niet mee; hun vertaaldekking bewaakt make l10n-check."
	@echo "        Harde poort: geen plafond, elke overtreding faalt."
	@echo "Failure means: haal de string door l10n.d('…') (make add-l10n SPEC=… zet de"
	@echo "        31 vertalingen erbij). Een merknaam, identifier of voorbeeldwaarde"
	@echo "        gaat óók door d() en komt op unchangedInAllLanguages in"
	@echo "        test/app_localizations_test.dart — niet om de poort heen."
	@echo "        Volledige lijst: dart run tool/check_hardcoded_text.dart --list"
	dart run tool/check_hardcoded_text.dart

# Add new d('…') source strings to every language's additions overlay from a
# JSON spec (format documented in tool/add_l10n.dart). Inserts, dart-formats and
# de-duplicates across all 30 language files in one step, and whitelists any
# "unchanged" loanwords — so a new translatable string is one command, not 30
# hand-edits. Re-running is safe (already-present entries are skipped).
add-l10n:
	@echo "== OciDeck l10n: add strings =="
	@[ -n "$(SPEC)" ] || { echo "Usage: make add-l10n SPEC=path/to/spec.json"; exit 2; }
	dart run tool/add_l10n.dart "$(SPEC)"

# Fast localisation gate — the subset of `make check` that touches l10n, so a
# translation change can be validated without the full suite: no duplicate keys,
# every d()/t() literal covered in every language, and the language files are
# dart-format-clean (the exact failures that used to slip through by hand).
l10n-check:
	@echo "== OciDeck check: l10n =="
	@echo "Covers: duplicate keys, per-language d()/t() coverage, and l10n formatting."
	@echo "Failure means: run 'make add-l10n' / 'dart format lib/l10n', or fill the gap."
	dart format --output=none --set-exit-if-changed lib/l10n
	flutter test test/l10n_duplicate_keys_test.dart test/app_localizations_test.dart

# Build the hardened web bundle. Two flags do the security work:
#   --no-web-resources-cdn  Self-host CanvasKit instead of fetching it from the
#                           gstatic CDN, so the running app pulls ZERO third-party
#                           origins (air-gappable, reproducible, fits the pinned
#                           bundled-JS policy in deps-check).
#   --csp                   Emit a CSP-compliant loader: no eval()/inline scripts
#                           in the Flutter bootstrap, so script-src needs neither
#                           'unsafe-eval' nor 'unsafe-inline'. Pairs with the
#                           Content-Security-Policy meta tag in web/index.html.
# Integrity-only variant of deps-check: verifies the vendored bundles still
# match their manifest hashes without touching the network. Wired into
# build-web so a locally tampered bundle can't be baked into a build even when
# the full (online) deps-check hasn't run.
deps-verify-offline:
	@echo "== OciDeck check: bundled JavaScript integrity (offline) =="
	dart run tool/check_bundled_js.dart --offline

build-web: deps-verify-offline sbom-verify
	@echo "== OciDeck build: hardened web bundle =="
	@echo "Command: flutter build web --release --no-web-resources-cdn --csp"
	@echo "Covers: self-hosted CanvasKit (no third-party CDN) and a CSP-safe loader."
	@echo "Output: build/web — serve behind the CSP declared in web/index.html."
	flutter build web --release --no-web-resources-cdn --csp
	@# Ship the SBOM alongside the product so the CRA artefact travels with the
	@# distributed bundle (served under /sbom/ from the same origin): both
	@# machine-readable formats and the human-readable Markdown view.
	mkdir -p build/web/sbom
	cp sbom/ocideck.cdx.json sbom/ocideck.spdx.json sbom/ocideck.sbom.md build/web/sbom/
	@# Flutter kopieert assets mét hun bronpermissies. Een bestand dat lokaal
	@# 600 staat wordt dan op de webserver onleesbaar (stil 403 → "onzichtbaar"
	@# logo). Normaliseer daarom de hele bundel naar world-readable.
	find build/web -type d -exec chmod 755 {} +
	find build/web -type f -exec chmod 644 {} +

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

# Human release build for the two artifacts currently published by hand:
# the hardened web bundle (with post-build hardening verification) and the
# macOS .app. Prefer this over running raw `flutter build ...` commands.
build-release:
	@echo "== OciDeck release build: web + macOS =="
	scripts/build_release.sh

# Full local quality gate. Intended for humans, CI logs, and LLM-assisted debugging.
# `coverage` rather than `test`: it runs the same suite (one run, instrumented)
# and additionally enforces the floor and the every-file-is-in-a-test rule.
# Those two gates existed but no aggregate target invoked them, so in practice
# nothing ran them — and the GitHub workflow that did cannot fire on a Forgejo
# remote without a runner. `make check` is the real gate; it should contain the
# gates.
check: format-check analyze check-conventions check-audience-boundary check-method-length check-dead-code check-hardcoded-text coverage coverage-per-file
	@echo "== OciDeck check complete =="
	@echo "Validated: formatting, static analysis, conventions, the privacy projection boundary, method length, dead-code, hardcoded visible text, the full Flutter test suite, the coverage floor, and the per-file coverage floor."

# Extended local check: the gate plus licence/compliance, bundled-JS CVEs, the
# web-hardening assertion (rebuilds the web bundle), and a freshness report.
check-full: check check-secrets sast licenses sbom-verify deps-check check-web deps-outdated
	@echo "== OciDeck extended check complete =="
	@echo "Validated: required quality gate, licence compliance, SBOM freshness, bundled-JS CVEs, web hardening, and dependency freshness."
