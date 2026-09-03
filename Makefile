.PHONY: check-locked check-full-locked l10n-export l10n-import template-l10n-export template-l10n-import template-l10n-skeleton template-l10n-auto dast sast check-secrets check-marp refresh-catalogs translate-docs translate-docs-check setup format format-check fix analyze test coverage test-contracts test-preview test-export test-state test-services test-presenter test-xmpp-integration deps-outdated deps-check deps-verify-offline trivy check-pins bump-scanner-pins catalogs-outdated refresh-lexicon licenses sbom sbom-verify check-conventions check-audience-boundary check-method-length check-dead-code check-hardcoded-text check-toolchain check-comment-language check-dated-claims check-improvement-templates check-version-bump check-sbom-version check-collab-field-parity check-translated-mermaid check-untranslated-templates check-l10n-orphans check-l10n-parity check-l10n-passthrough coverage-per-file add-l10n l10n-check mutate mutate-parsers build-web check-web build-macos build-windows build-windows-installer build-linux package-linux build-all build-release release notarize-macos deploy-web check check-no-coverage check-static check-full check-release help servicenormen doorlooptijd ratchets clean-test-cache ci-image-publish ci-image-scans-publish

# macOS (and some Linux setups) ship a low open-file-descriptor soft limit. The
# full test suite exhausts it and fails with "Too many open files" — worst under
# --coverage, which holds a VM-Service connection open per test until the run
# ends. Raise the soft limit for the whole-suite recipes below. The hard limit is
# normally unlimited; the `|| true` keeps the build working if a machine caps it
# lower than 8192 (there the limit simply stays where it was).
RAISE_FDS := ulimit -n 8192 2>/dev/null || true;

# De rem op de suite. `flutter test` start standaard één werkproces per kern;
# op een laptop trok dat samen met de native bouw meer stroom dan de adapter
# kon leveren. Vier kernen blijven daarom vrij. Zelf sturen kan: `make test
# TEST_JOBS=18`, en op een runner die niets anders doet is dat ook zinnig.
TEST_JOBS ?= $(shell n=$$(sysctl -n hw.logicalcpu 2>/dev/null || nproc 2>/dev/null || echo 4); if [ $$n -gt 6 ]; then echo $$((n - 4)); else echo 2; fi)
TEST_JOBS_FLAG := $(if $(TEST_JOBS),--concurrency=$(TEST_JOBS),)

# De beeldcontrole (`image_face_scan_io.dart`) draait op OpenCV via de native laag
# van dartcv4 2.x. Die laadt NIET onder `flutter test`: de `@Native`/`@DefaultAsset`
# code-assets worden niet in de test-VM gebouwd, en dartcv4 2.x leest
# `DARTCV_LIB_PATH` nergens meer. De env-var-steiger die hier stond (een `wildcard`
# over build/ die DARTCV_LIB_PATH zette) deed sinds de migratie dus niets en is weg.
# `test/image_face_scan_test.dart` bewaakt onder `make check` alleen het contract;
# dat de native scan écht werkt, toont `integration_test/native_face_scan_test.dart`
# op een echt platform (zie ci.yml en OCIWACHT.md §13.8).

# Náást de gewone uitvoer schrijft elke suiteaanroep een machineleesbaar
# rapport. Dat is het zijkanaal waar de verklaring hieronder uit leest: de
# terminaluitvoer blijft onaangeraakt — een pipe zou `flutter test` zijn
# voortgangsregel kosten en er duizenden regels van maken — en een zijkanaal kan
# per definitie geen echte fout wegpoetsen. Het bestand staat onder build/ en
# gaat dus niet mee in de repository.
TEST_REPORT := build/test-report.json
SUITE_REPORT := --file-reporter json:$(TEST_REPORT)

# Elke `flutter test`-aanroep in dit bestand sluit hiermee af, zonder
# uitzondering. Valt de suite om, dan zegt tool/explain_suite_failure.dart welke
# bestanden niet GELADEN konden worden — de fout die naar de verkeerde plek
# wijst (#798) — en of dat de bekende kanaalstoring is of een echte laadfout.
# Zwijgt wanneer er niets te verklaren valt.
#
# Als variabele en niet tien keer uitgeschreven, om dezelfde reden als
# STATIC_GATES verderop: tien kopieën lopen uit elkaar, en dan hangt het van je
# doel af of je de verklaring ziet. `test/explain_suite_failure_test.dart` staat
# erop dat er geen aanroep buiten valt.
ON_SUITE_FAILURE := || { dart run tool/explain_suite_failure.dart $(TEST_REPORT); exit 1; }

help:
	@echo "OciDeck quality targets:"
	@echo "  make check           Format check + static analysis + full Flutter test suite + coverage floor."
	@echo "  make check-full      make check + secrets + SAST + licences, SBOM, deps, web hardening."
	@echo "  make check-release   Ready-for-tagging pass: make check-full + an advisory ZAP/DAST scan of the live host. Run before 'git push origin v*'."
	@echo "  make check-no-coverage  make check zonder de dekkingsmeting (uitbrengpoort in CI; niet lokaal gebruiken)."
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
	@echo "  make test-xmpp-integration  XMPP collab over real Prosody (needs Docker; not in check)."
	@echo "  make deps-outdated   Advisory dependency freshness report."
	@echo "  make deps-check      Verify vendored JS bundles vs manifest + OSV CVEs."
	@echo "  make dast            Advisory ZAP baseline over a served build (DAST_URL=… for a real host)."
	@echo "  make sast            Semgrep over shipped Dart with the rules in semgrep/ (needs semgrep)."
	@echo "  make check-secrets   Sweep working tree and history for committed secrets (needs gitleaks + trufflehog)."
	@echo "  make shellcheck      ShellCheck over the committed shell scripts (needs shellcheck)."
	@echo "  make trivy           Advisory supply-chain scan: Dart-dep CVEs + committed secrets (needs trivy)."
	@echo "  make check-pins      Advisory: exact-pinned CI versions (actions + scanners) vs their latest release."
	@echo "  make bump-scanner-pins  Bumpt gitleaks/trufflehog/semgrep overal (manifest+workflows+image-tag). DRY_RUN=1 toont het."
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
	@echo "  make l10n-export LANG_=ga OUT=ga.json  One language out as flat JSON (for translators)."
	@echo "  make l10n-import LANG_=ga IN=ga.json   …and back in. Refuses unknown keys."
	@echo "  make catalogs-outdated Advisory: bundled reference data vs upstream (run before a release build)."
	@echo "  make refresh-catalogs Regenerate WSTG/MASTG/MASWE from upstream (not in check)."
	@echo "  make refresh-lexicon  Regenerate the bundled health lexicon from Orphanet (read the term diff)."
	@echo "  make l10n-check      Fast l10n gate: duplicate keys, per-language coverage, and formatting."
	@echo "  make check-l10n-orphans  Ratchet: translation keys nothing looks up any more (in check-full)."
	@echo "  make check-l10n-parity   Every key present in one language table must exist in all (in check)."
	@echo "  make check-l10n-passthrough  Ratchet: values that are the Dutch source verbatim (in check-full)."
	@echo "  make fix             Auto-apply 'dart fix' and reformat (local cleanup helper)."
	@echo "  make clean-test-cache  Gooi alleen de kernelcache van 'flutter test' weg (bij een laadfout op een test die los groen is)."
	@echo "  make build-web       Build the hardened web bundle (self-hosted CanvasKit + CSP-safe loader)."
	@echo "  make check-web       Build the web bundle and assert its hardening (CSP, self-hosted, fonts)."
	@echo "  make build-macos     Build the macOS .app (macOS only)."
	@echo "  make build-windows   Build the Windows app (Windows only)."
	@echo "  make build-windows-installer  Wrap that build in an installer (Windows only)."
	@echo "  make build-linux     Build the Linux bundle (Linux only)."
	@echo "  make build-all       Build web + this OS's native desktop target."
	@echo "  make release TAG=vX.Y.Z  Orchestrate a release: tag-guard + Phase 1 (validate/build/sign); guides the irreversible steps."
	@echo "  make build-release   Build verified web + macOS release artifacts."
	@echo "  make notarize-macos  Sign (Developer ID) + notarize + staple the macOS .app for distribution."
	@echo "  make deploy-web      Put build/web live on the static host (atomic swap + verify)."

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

# Gooit de incrementele kernelcache weg die `flutter test` zelf aanlegt, en
# niets anders.
#
# **Waarom dit een doel is en geen zin in een reactie.** #798: twee keer op één
# dag viel `make check` om op een `Failed to load` bij een test die los groen
# was, en beide keren was het weg na precies dit — zonder verder een letter te
# wijzigen. Het recept zat daarna in het hoofd van wie erbij was. Nu niet meer.
#
# **Waarom `build/test_cache` en niet `flutter clean`.** Onder `build/` staat ook
# de gecompileerde native laag (dartcv4/OpenCV via de build-hooks) en de
# platformbuilds; `flutter clean` gooit die weg en dwingt een dure herbouw af
# (de OpenCV-modules compileren duurt minuten). Dit doel raakt alleen de testcache.
#
# **Wat het kost.** De eerstvolgende suite compileert van nul. Daarom is dit een
# doel dat je aanroept en geen stap die vóór elke draai meeloopt — dat laatste
# lost hetzelfde op en betaalt die prijs elke keer.
clean-test-cache:
	@echo "== OciDeck clean: test cache =="
	@echo "Command: rm -rf build/test_cache"
	@echo "Covers: de incrementele kernelcache van 'flutter test' (build/test_cache/build/<hash>.cache.dill[.track.dill])."
	@echo "Kosten: de eerstvolgende suite compileert weer van nul; de platformbuilds onder build/ blijven staan."
	rm -rf build/test_cache

# Run the full unit/widget test suite. Ordering is randomised so a test can't
# silently depend on another test running first.
test:
	@echo "== OciDeck check: tests =="
	@echo "Command: flutter test --test-randomize-ordering-seed random"
	@echo "Covers: all unit/widget tests under test/, including markdown round-trip, preview, export, provider, footer, and presenter tests."
	@echo "Failure means: inspect the named failing test file and test case in the Flutter output."
	$(RAISE_FDS) flutter test $(TEST_JOBS_FLAG) --test-randomize-ordering-seed random --exclude-tags golden $(SUITE_REPORT) $(ON_SUITE_FAILURE)

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
	$(RAISE_FDS) flutter test $(TEST_JOBS_FLAG) --coverage --test-randomize-ordering-seed random --exclude-tags golden $(SUITE_REPORT) $(ON_SUITE_FAILURE)
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
	@echo "Covers: how many lib/ files run less than a third of their own lines — the worst case per file, which the overall average cannot show."
	@echo "Failure means: minstens één lib/-bestand draait minder dan een derde van zijn eigen regels — schrijf er een test voor (of zet het met reden in uncoveredBaseline als het een platformhelft is)."
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
	$(RAISE_FDS) flutter test --tags golden $(if $(UPDATE),--update-goldens,) $(SUITE_REPORT) $(ON_SUITE_FAILURE)

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
	@echo "Failure means: een predicaat overleefde — het is dood of onbeproefd; beoordeel het."
	@# Alle zeven draaien en pas aan het eind falen. Eén regel per doel liet make
	@# stoppen bij de eerste overlever, waarna de resterende bestanden nooit aan
	@# bod kwamen — en dan lijkt "één overlever" het hele beeld terwijl je de rest
	@# niet gezien hebt (#660). Een sweep die zijn eigen uitkomst afkapt is een
	@# sweep waarvan je de uitslag niet kunt geloven.
	@fails=0; \
	run() { dart run tool/mutation_check.dart "$$@" || fails=$$((fails+1)); }; \
	run lib/services/markdown_service_parse.dart test/markdown_round_trip_test.dart test/markdown_service_test.dart; \
	run lib/services/markdown_service_finding.dart test/markdown_round_trip_test.dart test/markdown_service_test.dart test/checklist_spec_test.dart; \
	run lib/models/finding_template.dart test/finding_template_test.dart; \
	run lib/services/markdown_service_serialize.dart test/markdown_round_trip_test.dart test/markdown_service_test.dart; \
	run lib/services/markdown_body_blocks.dart test/markdown_body_blocks_test.dart test/rich_text_layout_test.dart; \
	run lib/widgets/slides/inline_markdown.dart test/inline_markdown_test.dart; \
	run lib/services/markdown_validator.dart test/markdown_validator_test.dart; \
	if [ $$fails -gt 0 ]; then echo "== $$fails van 7 doelen had overlevers =="; exit 1; fi; \
	echo "== mutatiesweep: alle 7 doelen schoon =="

# Contract tests for persistence and parsing.
test-contracts:
	@echo "== OciDeck targeted check: contracts =="
	@echo "Command: flutter test test/markdown_round_trip_test.dart test/markdown_service_test.dart"
	@echo "Covers: Markdown generation/parsing, save-load round-trips, slide field migration defaults, theme profile metadata."
	@echo "Failure means: a UI/model field may not persist correctly, or old presentations may migrate incorrectly."
	flutter test test/markdown_round_trip_test.dart test/markdown_service_test.dart $(SUITE_REPORT) $(ON_SUITE_FAILURE)

# Visual/rendering-focused widget tests.
test-preview:
	@echo "== OciDeck targeted check: preview/rendering =="
	@echo "Command: flutter test preview-related widget tests"
	@echo "Covers: slide preview rendering, image panels, footer placement, TLP badge, inline markdown, text style regressions."
	@echo "Failure means: inspect visual layout/rendering logic before changing export or slide-preview code."
	flutter test test/bullets_image_preview_test.dart test/footer_preview_test.dart test/image_slides_preview_test.dart test/inline_markdown_test.dart test/slide_text_style_test.dart test/tlp_test.dart $(SUITE_REPORT) $(ON_SUITE_FAILURE)

# Export and filesystem integration smoke tests.
test-export:
	@echo "== OciDeck targeted check: export/files =="
	@echo "Command: flutter test test/export_service_test.dart test/file_service_test.dart"
	@echo "Covers: PDF/PPTX export smoke tests and project file-save behavior, including copied logo assets."
	@echo "Failure means: inspect export_service/file_service and generated artifact structure."
	flutter test test/export_service_test.dart test/file_service_test.dart $(SUITE_REPORT) $(ON_SUITE_FAILURE)

# State-management and recovery tests.
test-state:
	@echo "== OciDeck targeted check: state/recovery =="
	@echo "Command: flutter test provider and recovery tests"
	@echo "Covers: deck mutations, undo/redo, skip state, search/replace, settings profiles, recovery snapshots."
	@echo "Failure means: inspect provider state transitions or recovery serialization."
	flutter test test/deck_provider_test.dart test/settings_provider_test.dart test/recovery_service_test.dart $(SUITE_REPORT) $(ON_SUITE_FAILURE)

# Service-level tests.
test-services:
	@echo "== OciDeck targeted check: services =="
	@echo "Command: flutter test service tests"
	@echo "Covers: image path/copy behavior, captions, descriptions, and sidecar metadata services."
	@echo "Failure means: inspect service path handling, sidecar reads/writes, or filesystem assumptions."
	flutter test test/caption_service_test.dart test/description_service_test.dart test/image_service_test.dart $(SUITE_REPORT) $(ON_SUITE_FAILURE)

# Presenter interaction tests.
test-presenter:
	@echo "== OciDeck targeted check: presenter =="
	@echo "Command: flutter test test/fullscreen_presenter_test.dart"
	@echo "Covers: fullscreen presenter navigation, presenter view, keyboard shortcuts, grid navigation."
	@echo "Failure means: inspect fullscreen presenter keyboard/focus/navigation behavior."
	flutter test test/fullscreen_presenter_test.dart $(SUITE_REPORT) $(ON_SUITE_FAILURE)

# XMPP integration test against a local Prosody (testbed/docker-jitsi-meet).
# NOT part of `make check` — requires a running Docker stack and the
# OCIDECK_XMPP_INTEGRATION env var. See testbed/docker-jitsi-meet/README.md.
test-xmpp-integration:
	@echo "== OciDeck integration: XMPP over real Prosody =="
	@echo "Command: OCIDECK_XMPP_INTEGRATION=1 flutter test test/xmpp/xmpp_docker_jitsi_integration_test.dart"
	@echo "Covers: two clients join, edit, lock, chat, disconnect→resync over a real XMPP server."
	@echo "Prerequisite: cd testbed/docker-jitsi-meet && docker compose up -d"
	@echo "Failure means: the Prosody stack is not running, or a collab flow broke against a real server."
	OCIDECK_XMPP_INTEGRATION=1 flutter test test/xmpp/xmpp_docker_jitsi_integration_test.dart $(SUITE_REPORT) $(ON_SUITE_FAILURE)

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

shellcheck:
	@echo "== OciDeck check: shell scripts (ShellCheck) =="
	@echo "Command: shellcheck scripts/*.sh"
	@echo "Covers: every committed shell script — the release build, the web deploy, and the icon generator."
	@echo "Failure means: ShellCheck found a defect. Most of its findings are the"
	@echo "        classics that only bite on the day it matters: an unquoted"
	@echo "        variable that splits on a path with a space, a glob that"
	@echo "        silently matches nothing, an exit code swallowed by a pipe."
	@echo "        Dart has a compiler and an analyzer for this; shell has this."
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found — install it (macOS: brew install shellcheck)"; exit 2; }
	shellcheck scripts/*.sh

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

# Real-Marp CLI regression check for theme loading (#1804). A saved project
# writes `.marprc.yml` so a plain `marp deck.md` loads the generated theme;
# without it Marp falls back to the default theme and the `section.split`
# layout is lost. This renders a minimal split fixture with the REAL pinned
# Marp CLI and asserts the layout survives in DOM/CSS and a screenshot.
#
# NOT in `make check`/`check-static`: it needs Node + a pinned Marp CLI
# (installed offline once `node_modules` exists), like `check-secrets` needs
# gitleaks. It runs in `make check-full`. If Node is absent it skips with a
# clear message rather than reddening the pass — same shape as DAST without a
# container runtime. See `tool/marp-check/run.sh`.
check-marp:
	@echo "== OciDeck check: real-Marp CLI theme loading =="
	@echo "Command: pinned @marp-team/marp-cli (tool/marp-check)"
	@echo "Covers: a plain 'marp deck.md' loads the generated OciDeck theme; split layout survives; move + spaces work; default invocation documented."
	@echo "Failure means: the supported invocation lost the split layout, or the documented limitation changed."
	bash tool/marp-check/run.sh

# Advisory DAST: an OWASP ZAP baseline (passive) scan against a served build.
#
# ADVISORY, and not a gate. It runs, advisory and non-blocking, as part of
# `make check-release` — the quality pass BEFORE cutting a `v*` tag — with
# DAST_URL pointing at the live host, the one place the headers under test are
# the real host's and not a throwaway server's. Pre-tag is deliberate: a finding
# there can still hold back a release, whereas a post-deploy scan only speaks
# after the site is already live. Be honest about what this can and cannot see:
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
#
# DAST_WORKDIR: `/zap/wrk` does not exist in the image, so mounting the config
# *into* it makes the daemon create that parent root-owned — after which ZAP,
# which runs as uid 1000, cannot write its generated Automation Framework plan
# and reports "Unable to copy yaml file to /zap/wrk/zap.yaml". The scan still
# ran, but a red line at the top of a release run is exactly what teaches people
# to skim past output. A tmpfs owned by the zap user gives it a writable working
# directory; the read-only config mounts on top of it.
DAST_WORKDIR = --tmpfs /zap/wrk:uid=1000,gid=1000,mode=0755 \
	  -v "$(PWD)/zap:/zap/wrk/conf:ro"
DAST_PORT ?= 8091
DAST_URL ?=
dast:
	@echo "== OciDeck advisory check: DAST (OWASP ZAP baseline) =="
	@echo "Command: zap-baseline.py against $(if $(DAST_URL),$(DAST_URL),a local server on port $(DAST_PORT))"
	@echo "Covers: passive checks over the initial load — headers, CSP delivery, cookies."
	@echo "Failure means: ZAP or the container runtime is missing. Findings are advisory;"
	@echo "        read them by hand. See zap/baseline.conf for what is silenced and why."
	@command -v docker >/dev/null 2>&1 || { echo "docker not found — install a runtime (macOS: brew install colima docker && colima start)"; exit 2; }
	@if ! docker info >/dev/null 2>&1 && command -v colima >/dev/null 2>&1; then \
	  echo "-- container runtime not reachable, starting colima --"; \
	  colima start; \
	fi
	@docker info >/dev/null 2>&1 || { echo "no container runtime reachable — start it (macOS: colima start)"; exit 2; }
ifeq ($(strip $(DAST_URL)),)
	$(MAKE) build-web
	@echo "-- serving build/web on :$(DAST_PORT) for the duration of the scan --"
	@cd build/web && python3 -m http.server $(DAST_PORT) >/dev/null 2>&1 & echo $$! > /tmp/ocideck-dast.pid
	@sleep 2
	-docker run --rm --add-host=host.docker.internal:host-gateway \
	  $(DAST_WORKDIR) zaproxy/zap-stable \
	  zap-baseline.py -t http://host.docker.internal:$(DAST_PORT) -c conf/baseline.conf -I
	@kill $$(cat /tmp/ocideck-dast.pid) 2>/dev/null || true; rm -f /tmp/ocideck-dast.pid
	@echo "-- local server stopped --"
else
	-docker run --rm $(DAST_WORKDIR) zaproxy/zap-stable \
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

# Advisory freshness monitor for the third-party CI versions we pin to an EXACT
# value: both the `uses: …@vX.Y.Z` actions and the scanner binaries a `run:`
# block downloads by version. Reads .github/pinned-ci-versions.json and asks
# each upstream whether a newer version exists — the CI analogue of deps-check
# for the vendored JS. Advisory (needs network, a bump is a prompt not a
# regression), so NOT wired into check/check-full. `--offline` validates the
# manifest only.
#
# That the manifest still MATCHES the workflows is a separate, offline question,
# and it is a hard gate: test/pinned_versions_manifest_test.dart runs in the
# suite and fails on a drifted or unlisted pin (#802).
check-pins:
	@echo "== OciDeck advisory check: pinned CI versions =="
	@echo "Command: dart run tool/check_pinned_versions.dart"
	@echo "Covers: every exact-pinned action and scanner in .github/pinned-ci-versions.json vs its latest release."
	@echo "Failure means: a pin is behind (bump it in every workflow + the manifest) or an upstream API was unreachable."
	dart run tool/check_pinned_versions.dart

# Bumpt de scanner-pins (gitleaks/trufflehog/semgrep) naar hun laatste upstream op
# alle plekken tegelijk: het manifest, de *_VERSION-env in elke workflow, en de
# tag van het voorgebakken scans-image. Idempotent (no-op als alles actueel is);
# leunt op check-pins voor "wat is de laatste". Publiceert het nieuwe scans-image
# NIET — draai daarna een ci-image-scans-dispatch of `make ci-image-scans-publish`
# vóór een workflow naar het nieuwe tag wijst. `DRY_RUN=1` toont wat zou wijzigen.
bump-scanner-pins:
	@echo "== OciDeck: scanner-pins bumpen naar de laatste upstream =="
	scripts/bump_scanner_pins.sh

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


# Regenerate the bundled lexicons. Like refresh-catalogs this is deliberately
# NOT part of `make check`: a new edition changes what the privacy check fires
# on, so it is a decision, not a build step.
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
	@echo "Sources: OWASP WSTG + MASTG + MASWE (CWE is manual, see below)."
	@echo "This rewrites the generated files under lib/services/ AND the version"
	@echo "        each one records — in the catalogue itself and in"
	@echo "        docs/LICENSE_COMPLIANCE.md. Read the diff before committing."
	@echo "Which version: whatever upstream says is the latest, asked through the"
	@echo "        same probes the staleness gate uses. Pin one by hand with"
	@echo "        'make refresh-catalogs WSTG_VERSION=5.0' if you need to."
	scripts/refresh_catalogs.sh
	@echo ""
	@echo "CWE is not refreshed here: its source is a ~30 MB zip behind a dated"
	@echo "URL. Run tool/build_cwe_catalog.dart by hand (see its header)."

# Machine-translate the bundled user docs into every app language (#1181). The
# app resolves docs/NAME.<lang>.md automatically; this writes those variants.
# OciDeck ships no translation engine (local-first, network-free at runtime), so
# point TRANSLATOR at a command that reads Markdown on stdin and writes the
# translation on stdout (target language as $$1 and $$OCIDECK_TARGET_LANG).
# PRIVACY.md and SECURITY_DESIGN.md are never machine-translated.
#   make translate-docs TRANSLATOR='argos-translate --from en --to'
#   make translate-docs STUB=1     # identity copies, to smoke-test the wiring
translate-docs:
	@echo "== OciDeck: machine-translate the bundled user docs (#1181) =="
	@echo "Excluded (English-only): docs/PRIVACY.md, docs/SECURITY_DESIGN.md."
	@echo "This writes docs/NAME.<lang>.md and registers them in pubspec.yaml."
	dart run tool/translate_docs.dart $(if $(STUB),--stub,--translator '$(TRANSLATOR)')
	@dart format tool/ >/dev/null
	@echo "Done. Read 'git diff'; the English source stays authoritative."

translate-docs-check:
	@echo "== OciDeck: are all doc translations present + registered? =="
	@echo "Command: dart run tool/translate_docs.dart --check"
	dart run tool/translate_docs.dart --check

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
check-linux-deps:
	@echo "== OciDeck check: Linux-systeembibliotheken =="
	@echo "Command: dart run tool/check_linux_pkgconfig.dart"
	@echo "Covers: elke pkg-config-module die een plugin op Linux met REQUIRED"
	@echo "        opeist, tegen .github/linux-pkgconfig-modules.json: staat er een"
	@echo "        apt-pakket tegenover, installeert elke buildomgeving dat, en"
	@echo "        noemen het .deb en de PKGBUILD de runtime-bibliotheek."
	@echo "Failure means: een plugin vraagt om een systeembibliotheek die nergens"
	@echo "        geinstalleerd wordt. 'flutter build linux' faalt dan in CMake"
	@echo "        voordat er iets gecompileerd is — en dat merk je pas in de"
	@echo "        releaseketen, zoals bij v0.4.9 (geen release)."
	dart run tool/check_linux_pkgconfig.dart

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

# De commentaartaalregel uit CONTRIBUTING: Nederlands of Engels, maar nooit
# allebei in één blok. Alleen gewoon commentaar — dartdoc mag een Engelse
# samenvattingsregel boven een Nederlandse redenering dragen, want dát schrijft
# CONTRIBUTING zélf voor voor publieke types in lib/models en lib/services.
check-comment-language:
	@echo "== OciDeck check: commentaartaal =="
	@echo "Command: dart run tool/check_comment_language.dart"
	@echo "Covers: commentaarblokken in lib/ die halverwege van taal wisselen."
	@echo "        Dartdoc valt erbuiten (Engelse samenvatting + Nederlandse"
	@echo "        redenering is de voorgeschreven vorm). Ratchet: het aantal mag"
	@echo "        dalen, nooit stijgen."
	@echo "Failure means: kies één taal per blok en maak de gedachte daarin af."
	@echo "        Bewerk je een bestaand blok, volg dan de taal die er al staat —"
	@echo "        herschrijven puur om de taal te wijzigen is nadrukkelijk niet"
	@echo "        de bedoeling (CONTRIBUTING)."
	@echo "        Volledige lijst: dart run tool/check_comment_language.dart --list"
	dart run tool/check_comment_language.dart

# Een bewering over een *gemeten* grootheid verrot terwijl de boom stilstaat.
# `docs/CHECKS.md` beloofde op twee plekken "within ~half an hour" terwijl de
# meting op 54 minuten stond; er zat geen datum bij, dus er viel niets tegen te
# toetsen. Dit doel draait de structurele helft: staan de ankers er nog, en zijn
# er looptijduitdrukkingen bij gekomen die niemand heeft geregistreerd.
#
# De houdbaarheid zelf zit hier bewust níet in — die verandert zonder commit en
# draait tegen de klok in .forgejo/workflows/time-degrading-checks.yml. Zat ze
# hier, dan viel op een dag een willekeurige PR om op andermans bewering.
check-dated-claims:
	@echo "== OciDeck check: gedateerde beweringen =="
	@echo "Command: dart run tool/check_dated_claims.dart"
	@echo "Covers: de ankers van de geregistreerde metingen in de documentatie,"
	@echo "        en de basislijn van looptijduitdrukkingen in CHECKS.md,"
	@echo "        CONTRIBUTING.md en BUILD.md."
	@echo "Failure means: er is een gemeten bewering herschreven zonder het"
	@echo "        register bij te werken, of er staat een looptijdbelofte bij die"
	@echo "        niet geregistreerd is. Meet hem en zet de datum erbij, of werk"
	@echo "        looptijdBasislijn bij als het geschiedenis is."
	@echo "        Houdbaarheid: dart run tool/check_dated_claims.dart --tegen-de-klok"
	dart run tool/check_dated_claims.dart

# Elke groene poort is een uitspraak over de toolchain die hem draaide (#598).
# Eén Flutter per machine, de laatste stable uit het officiële kanaal, en de pin
# volgt die installatie — niet andersom.
check-toolchain:
	@echo "== OciDeck check: toolchain =="
	@echo "Command: dart run tool/check_toolchain.dart"
	@echo "Covers: kanaal stable, de officiële Flutter-repository, en de versie"
	@echo "        exact gelijk aan de pin in .tool-versions. Elk van de drie is"
	@echo "        apart fataal; alle gebreken worden in één run gemeld. Daarna"
	@echo "        moet de toolchain ook in docs/CHECKS.md staan, én moeten de"
	@echo "        negentien versie-eisen in tien bestanden het eens zijn (#721)."
	@echo "Failure means: repareer de machine, niet de tool. Installeer de laatste"
	@echo "        stable (sha256 toetsen vóór uitpakken) in ~/flutter en trek élke"
	@echo "        pin mee. Wint ~/flutter niet: kijk naar de PATH-volgorde in"
	@echo "        ~/.zshrc — een regel vóór die van Homebrew verliest alsnog."
	dart run tool/check_toolchain.dart

check-improvement-templates:
	@echo "== OciDeck check: improvement templates =="
	@echo "Command: dart run tool/check_improvement_templates.dart"
	@echo "Covers: assets/improvement/templates.json in sync with the generated floor."
	@echo "Failure means: run dart run tool/build_improvement_templates.dart"
	dart run tool/check_improvement_templates.dart

# Refuse a version bump that isn't a single canonical semver step. Born from the
# 0.2.0 → 1.2.1 accident: a real release moves one axis and zeroes the ones
# below it, so from X.Y.Z only X.Y.(Z+1), X.(Y+1).0 or (X+1).0.0 are legal.
check-version-bump:
	@echo "== OciDeck check: version bump =="
	@echo "Command: dart run tool/check_version_bump.dart"
	@echo "Covers: the version in pubspec.yaml against the last release tag —"
	@echo "        the only legal successors are the patch, minor or major step."
	@echo "        A no-op when the version is unchanged; a shallow clone without"
	@echo "        tags is skipped, not failed."
	@echo "Failure means: correct the version in pubspec.yaml, or (for a deliberate"
	@echo "        one-off) add the transition to sanctionedTransitions in"
	@echo "        tool/check_version_bump.dart with a reason."
	dart run tool/check_version_bump.dart

# The SBOM records the project version, so a version bump makes it stale. The
# full regenerate-and-diff lives in sbom_test (make check-registrations); this
# is the cheap version-only half, in the fast static tier, so a bump can't pass
# check-static green with a version-old SBOM (the gap the 0.3.0 bump exposed).
check-sbom-version:
	@echo "== OciDeck check: SBOM version =="
	@echo "Command: dart run tool/check_sbom_version.dart"
	@echo "Covers: every committed SBOM file names the current pubspec version"
	@echo "        (X.Y.Z+B). Fast string check; sbom_test still owns full"
	@echo "        dependency-set freshness."
	@echo "Failure means: regenerate the SBOM with 'make sbom' and commit sbom/."
	dart run tool/check_sbom_version.dart

check-collab-field-parity:
	@echo "== OciDeck check: collab field parity =="
	@echo "Command: dart run tool/check_collab_field_parity.dart"
	@echo "Covers: every field on Slide is accounted for in the syncable"
	@echo "        surface — in SlideField, on the deliberate-exclusion list"
	@echo "        with a reason, or on the shrink-only debt baseline. This is"
	@echo "        the direction the two existing parity tests never check."
	@echo "Failure means: classify the new field. Either sync it (SlideField +"
	@echo "        slideFieldValue + applyOp + the codec kind map + a case in"
	@echo "        test/deck_op_test.dart), or record why it is excluded, in"
	@echo "        tool/check_collab_field_parity.dart."
	dart run tool/check_collab_field_parity.dart

# A machine-translated doc must not carry an English mermaid diagram (#1278). The
# translator leaves code blocks — and so mermaid — untouched, so a diagram's
# labels stay in the source language while the prose around it is translated. This
# gate compares each ```mermaid block in a generated docs/NAME.<lang>.md against
# the same block in the English base and fails on a byte-identical (untranslated)
# one.
check-translated-mermaid:
	@echo "== OciDeck check: translated mermaid diagrams =="
	@echo "Command: dart run tool/check_translated_mermaid.dart"
	@echo "Covers: every generated docs/NAME.<lang>.md variant — a fenced mermaid"
	@echo "        block that is byte-identical to the English base is an untranslated"
	@echo "        diagram (the translator skips code blocks). Genuinely"
	@echo "        language-neutral diagrams are whitelisted explicitly."
	@echo "Failure means: translate the diagram's label text by hand (keep the node"
	@echo "        IDs and mermaid syntax), or — if it carries no prose — add its"
	@echo "        body to languageNeutralMermaidBlocks in"
	@echo "        tool/check_translated_mermaid.dart."
	dart run tool/check_translated_mermaid.dart

# Een vertaald sjabloon in assets/templates/ mag geen Engels dragen waar zijn
# eigen taal hoort. tool/template_l10n_po.dart pelt alleen `title:`, `# `, `## `,
# bullets en tabelrijen eruit; genummerde lijsten, citaten, `###`-koppen,
# alinea's, HTML-blokken en codeblokken reizen als `raw` mee en bleven dus staan
# zoals de Engelse bron ze schreef. Deze poort vergelijkt per regel tegen de
# Engelse bron én tegen de Nederlandse: wat in het Nederlands óók zo staat, is
# de bedoelde vorm en telt niet mee.
check-untranslated-templates:
	@echo "== OciDeck check: onvertaalde sjabloonregels =="
	@echo "Command: dart run tool/check_untranslated_templates.dart"
	@echo "Covers: elke assets/templates/<id>.<taal>.md — een regel die letterlijk"
	@echo "        in de Engelse bron staat en NIET in de Nederlandse is een"
	@echo "        vertaalgat. Vanaf twee woorden; Klingon staat bewust op de"
	@echo "        Engelse terugval (TemplateContentService.languagesWithContent)."
	@echo "Failure means: vertaal de regel ter plekke, of — als het Engelse woord"
	@echo "        het woord ván die taal is — zet het paar (taal, regel) in"
	@echo "        allowedCognates in tool/check_untranslated_templates.dart"
	@echo "        mét de reden."
	@echo "        Volledige lijst: dart run tool/check_untranslated_templates.dart --list"
	dart run tool/check_untranslated_templates.dart

# De ANDERE kant van de vertaalpoorten. `l10n-check` en app_localizations_test
# bewaken dat elke gebruikte sleutel in alle 32 talen bestaat; niets vroeg of
# een sleutel nog wordt opgehaald. Elke wees kost 32 regels onderhoud voor
# tekst die geen mens ooit ziet.
#
# WAAROM IN check-full EN NIET IN check. Het bewijs van gebruik is tekstueel,
# geen typecontrole: de poort weet dat een sleutel ergens vóórkomt, niet dat
# hij wordt uitgevoerd. Zo'n oordeel hoort niet in de poort die élke commit
# tegenhoudt — een valse melding daar kost iedereen tijd op iets wat geen bug
# is (er breekt niets van een ongebruikte sleutel; er verwatert alleen
# onderhoud). check-full draait bij een uitbrengronde en bij wie hem aanroept,
# en dat is het tempo waarop een opruimlijst nuttig is. De maatregel die wél
# élke commit raakt zit in de ratchet: hij mag dalen, nooit stijgen.
check-l10n-orphans:
	@echo "== OciDeck check: ongebruikte vertaalsleutels =="
	@echo "Command: dart run tool/check_l10n_orphans.dart"
	@echo "Covers: sleutels in lib/l10n/translations/en.dart die nergens meer"
	@echo "        worden opgehaald — via d(), t(), een doorgeefluik, of"
	@echo "        AppLocalizations.sourceFor() op een label uit assets/."
	@echo "        Bewijs = Dart-literal (AST) of letterlijke tekst in lib/,"
	@echo "        test/, tool/, assets/ of web/. Documentatie telt niet mee."
	@echo "        Ratchet: het aantal mag dalen, nooit stijgen."
	@echo "Failure means: er is een sleutel bijgekomen die niemand aanroept —"
	@echo "        roep hem aan of laat hem weg. Wordt hij wél gebruikt langs een"
	@echo "        weg die de poort niet ziet, breid dan useRoots/textExtensions"
	@echo "        in tool/check_l10n_orphans.dart uit — niet de basislijn."
	@echo "        Volledige lijst: dart run tool/check_l10n_orphans.dart --list"
	dart run tool/check_l10n_orphans.dart

# De DERDE vertaalpoort, en de enige die de tabellen ónderling vergelijkt.
# `l10n-check` en app_localizations_test redeneren vanuit het GEBRUIK in lib/;
# check-l10n-orphans vraagt of een sleutel nog wordt opgehaald. Een sleutel die
# wél in de tabellen staat maar even nergens wordt opgevraagd valt door beide
# mazen en mag dan in de ene taal bestaan en in de andere ontbreken. Bij #1520
# stond dat er al een tijd (zes talen misten vier bronsleutels) zonder dat
# iemand het zag.
#
# WAAROM IN check EN NIET IN check-full — anders dan haar zusterpoort
# check-l10n-orphans. Die leunt op tekstbewijs ("komt deze sleutel ergens voor
# in de boom?") en kan zich dus vergissen; daarom draagt ze een ratchet en
# draait ze in de trage ronde. Deze poort doet iets anders: ze vergelijkt twee
# verzamelingen sleutels op gelijkheid. Er valt niets te interpreteren, dus er
# is geen valse melding mogelijk en geen basislijn nodig — nul is de enige
# stand. Ze leest 32 bestanden en is in een seconde klaar. Een poort die exact,
# snel en niet te sussen is hoort in de ronde die élke commit tegenhoudt.
check-l10n-parity:
	@echo "== OciDeck check: gelijke sleutels in alle taaltabellen =="
	@echo "Command: dart run tool/check_l10n_table_parity.dart"
	@echo "Covers: elke sleutel die in één taaltabel staat moet in álle staan,"
	@echo "        ongeacht of hij nu wordt opgevraagd. Twee families: de"
	@echo "        t()-tabel (_strings*) en de d()-brontabellen (_dutchSource*"
	@echo "        plus _dutchSourceAdd*, samen één naamruimte). nl is de"
	@echo "        brontaal en heeft geen d()-tabellen — die uitzondering zit"
	@echo "        in de poort."
	@echo "Failure means: een taal loopt uit de pas. Vul het gat met de vertaling"
	@echo "        uit een taal die de sleutel wél heeft, of haal de sleutel"
	@echo "        overal weg als hij een restant is (staat hij nog maar in één"
	@echo "        taal, dan is dat het waarschijnlijkst). Geen basislijn."
	@echo "        Volledige lijst: dart run tool/check_l10n_table_parity.dart --list"
	dart run tool/check_l10n_table_parity.dart

# De DERDE kant van de vertaalpoorten. l10n-check vraagt "staat er een waarde
# bij deze sleutel", check-l10n-parity vraagt "staat de sleutel overal", en
# test/l10n_untranslated_test.dart vraagt "is die waarde niet gewoon de ENGELSE
# zin". Niemand vroeg of de waarde de NEDERLANDSE bron is. Bij #1524 bleek dat
# tlh.dart 44 zulke sleutels droeg — inclusief een compleet LibrePlan-blok van
# hele zinnen — en dat blok staat onvertaald in dertig talen.
#
# WAAROM IN check-full EN NIET IN check, net als haar zusterpoort
# check-l10n-orphans en anders dan check-l10n-parity. Twee redenen, en ze
# horen bij elkaar. (1) Het oordeel is een TEKSTHEURISTIEK: gelijkheid vanaf
# drie woorden. Dat is scherp genoeg om bruikbaar te zijn en te grof om
# onfeilbaar te zijn — precies het soort weging dat niet thuishoort in de ronde
# die élke commit tegenhoudt. (2) Bij invoering vindt hij er 394. Een poort die
# meteen rood staat kan niet in `check` zonder basislijn, en een basislijn ís
# hier het eerlijke antwoord: de opruimronde (#1526 e.v.) brengt hem naar nul
# en dan pas kan hij verhuizen. Tot die tijd houdt de ratchet tegen dat er nóg
# een taal of nóg een blok bijkomt — dat deel raakt wél elke commit, via
# test/l10n_dutch_passthrough_test.dart, dat in de suite meedraait.
check-l10n-passthrough:
	@echo "== OciDeck check: doorgelaten Nederlandse bronzinnen =="
	@echo "Command: dart run tool/check_l10n_dutch_passthrough.dart"
	@echo "Covers: vertaalregels die de Nederlandse bron letterlijk als"
	@echo "        vertaling dragen. Twee families: de d()-brontabellen (sleutel"
	@echo "        == waarde) en de t()-tabel (waarde == de Nederlandse waarde"
	@echo "        bij dezelfde sleutel). Alleen vanaf drie woorden — losse"
	@echo "        woorden zijn massaal identiek zonder dat er iets mis is."
	@echo "        Ratchet: het aantal mag dalen, nooit stijgen."
	@echo "Failure means: er is een taal of een blok bijgekomen dat de bron"
	@echo "        doorlaat. Vertaal het. Valt er niets te vertalen (eigennaam,"
	@echo "        vakterm, leenuitdrukking), zet de SLEUTEL dan in loanKeys in"
	@echo "        tool/check_l10n_dutch_passthrough.dart mét de reden — niet de"
	@echo "        basislijn omhoog."
	@echo "        Volledige lijst: dart run tool/check_l10n_dutch_passthrough.dart --list"
	dart run tool/check_l10n_dutch_passthrough.dart

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
# Eén taal eruit en er weer in, via plat JSON — zodat een moedertaalspreker die
# één zin wil verbeteren geen Dart hoeft aan te raken (#633). Voegt bewust geen
# sleutels toe: nieuwe strings gaan via add-l10n, dat alle 31 talen afdwingt.
#
# De variabele heet LANG_ en niet LANG, omdat make de omgeving erft: op vrijwel
# elke shell staat LANG al gezet (nl_NL.UTF-8), en dan draait `make l10n-export`
# stilzwijgend op de verkeerde taal in plaats van te vragen wat je bedoelt.
l10n-export:
	@[ -n "$(LANG_)" ] || { echo "Usage: make l10n-export LANG_=ga OUT=ga.json"; exit 2; }
	dart run tool/l10n_po.dart export $(LANG_) $(OUT)

l10n-import:
	@[ -n "$(LANG_)" ] || { echo "Usage: make l10n-import LANG_=ga IN=ga.json"; exit 2; }
	@[ -n "$(IN)" ] || { echo "Usage: make l10n-import LANG_=ga IN=ga.json"; exit 2; }
	dart run tool/l10n_po.dart import $(LANG_) $(IN)

template-l10n-export:
	@[ -n "$(TEMPLATE)" ] || { echo "Usage: make template-l10n-export TEMPLATE=afterActionReview [OUT=afterActionReview.pot.json]"; exit 2; }
	dart run tool/template_l10n_po.dart export $(TEMPLATE) $(OUT)

template-l10n-import:
	@[ -n "$(TEMPLATE)" ] || { echo "Usage: make template-l10n-import TEMPLATE=afterActionReview LANG_=it IN=it.json"; exit 2; }
	@[ -n "$(LANG_)" ] || { echo "Usage: make template-l10n-import TEMPLATE=afterActionReview LANG_=it IN=it.json"; exit 2; }
	@[ -n "$(IN)" ] || { echo "Usage: make template-l10n-import TEMPLATE=afterActionReview LANG_=it IN=it.json"; exit 2; }
	dart run tool/template_l10n_po.dart import $(TEMPLATE) $(LANG_) $(IN)

template-l10n-skeleton:
	@[ -n "$(TEMPLATE)" ] || { echo "Usage: make template-l10n-skeleton TEMPLATE=afterActionReview LANG_=it"; exit 2; }
	@[ -n "$(LANG_)" ] || { echo "Usage: make template-l10n-skeleton TEMPLATE=afterActionReview LANG_=it"; exit 2; }
	dart run tool/template_l10n_po.dart skeleton $(TEMPLATE) $(LANG_)

# Automatische vertaalstap: export → TRANSLATOR → import.
# TRANSLATOR wordt aangeroepen als: $(TRANSLATOR) en <LANG_> <pot.json> <out.json>
# Voorbeeld: make template-l10n-auto TEMPLATE=afterActionReview LANG_=it \
#   TRANSLATOR='python3 tool/translate_with_argos.py'
template-l10n-auto:
	@[ -n "$(TEMPLATE)" ] || { echo "Usage: make template-l10n-auto TEMPLATE=afterActionReview LANG_=it TRANSLATOR='...'"; exit 2; }
	@[ -n "$(LANG_)" ] || { echo "Usage: make template-l10n-auto TEMPLATE=afterActionReview LANG_=it TRANSLATOR='...'"; exit 2; }
	@[ -n '$(TRANSLATOR)' ] || { echo "Usage: make template-l10n-auto TEMPLATE=... LANG_=... TRANSLATOR='...'"; exit 2; }
	@POT=$$(mktemp -t template_l10n_pot); OUT=$$(mktemp -t template_l10n_out); \
	trap "rm -f $$POT $$OUT" EXIT; \
	dart run tool/template_l10n_po.dart export $(TEMPLATE) $$POT && \
	$(TRANSLATOR) en $(LANG_) $$POT $$OUT && \
	dart run tool/template_l10n_po.dart import $(TEMPLATE) $(LANG_) $$OUT

l10n-check:
	@echo "== OciDeck check: l10n =="
	@echo "Covers: duplicate keys, per-language d()/t() coverage, untranslated English, and l10n formatting."
	@echo "Failure means: run 'make add-l10n' / 'dart format lib/l10n', fill the gap, or translate a string that is still English."
	dart format --output=none --set-exit-if-changed lib/l10n
	flutter test test/l10n_duplicate_keys_test.dart test/app_localizations_test.dart test/l10n_untranslated_test.dart $(SUITE_REPORT) $(ON_SUITE_FAILURE)

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
	@# Ship the artefacts that must travel with a downloaded bundle: the licence
	@# and third-party notices (without them the bundle is not redistributable),
	@# and the SBOM (the CRA inventory belongs to the exact build you hand out,
	@# served under /sbom/ from the same origin). The step ends by writing
	@# SHA256SUMS over the finished bundle, so it must stay the LAST thing that
	@# touches file contents here.
	dart run tool/pack_web_release.dart
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
	@echo "== OciDeck check: release artefacts =="
	@echo "Command: dart run tool/pack_web_release.dart --check"
	@echo "Covers: LICENSE, THIRD_PARTY_NOTICES and the SBOM travel with the bundle,"
	@echo "        and SHA256SUMS describes exactly the files that are there."
	@echo "Failure means: something was added, changed or lost after packing."
	dart run tool/pack_web_release.dart --check
	@echo "== OciDeck check: bundled documentation is fresh =="
	@echo "Command: dart run tool/check_bundled_docs_fresh.dart build/web"
	@echo "Covers: the docs inside the built bundle match docs/ on disk, byte for byte."
	@echo "Failure means: an incremental build shipped stale documentation — clean-rebuild."
	dart run tool/check_bundled_docs_fresh.dart build/web

# Native desktop release builds. Each target only works on its own OS — Flutter
# cannot cross-compile a desktop bundle (a macOS .app needs macOS, a Windows
# .exe needs Windows, a Linux bundle needs Linux). Run the matching target on
# the matching machine, or use the release CI workflow to produce all at once.
build-macos: sbom-verify
	@echo "== OciDeck build: macOS app (.app) =="
	@echo "Command: flutter build macos --release"
	@echo "Output: build/macos/Build/Products/Release/*.app"
	flutter build macos --release
	@echo "== OciDeck check: bundled documentation is fresh =="
	dart run tool/check_bundled_docs_fresh.dart build/macos

build-windows: sbom-verify
	@echo "== OciDeck build: Windows app (.exe) =="
	@echo "Command: flutter build windows --release"
	@echo "Output: build/windows/x64/runner/Release"
	flutter build windows --release
	@echo "== OciDeck check: bundled documentation is fresh =="
	dart run tool/check_bundled_docs_fresh.dart build/windows

# Wrap the built Windows bundle in an Inno Setup installer (#1208): Start menu
# shortcut, the file associations from windows/file-associations.reg, and an
# uninstall entry in Programs and Features. Windows only, and deliberately NOT a
# prerequisite of build-windows — like package-linux, this packages exactly the
# bundle you just built and inspected rather than quietly making a new one.
#
# Signing is optional and off by default; the script says loudly when it
# produced an unsigned installer. See scripts/build_windows_installer.sh.
build-windows-installer:
	@echo "== OciDeck package: Windows installer (.exe) =="
	@echo "Command: scripts/build_windows_installer.sh"
	@echo "Output: dist/ocideck-windows-x64-setup-<version>.exe"
	scripts/build_windows_installer.sh

build-linux: sbom-verify
	@echo "== OciDeck build: Linux bundle =="
	@echo "Command: flutter build linux --release"
	@echo "Output: build/linux/x64/release/bundle"
	flutter build linux --release
	@echo "== OciDeck check: bundled documentation is fresh =="
	dart run tool/check_bundled_docs_fresh.dart build/linux

# Package the Linux bundle into portable, self-hostable formats — Phase 1 of the
# Linux install route (#1227, docs/design/LINUX_PACKAGING.md): AppImage, .deb and
# .rpm, alongside the tarball the release already ships. Needs a bundle from
# build-linux first (deliberately not a prerequisite, so the release job does not
# build twice); the script errors clearly if none is there. VERSION is required;
# FORMATS and OUT pass through to scripts/package_linux.sh.
#   make package-linux VERSION=0.3.2
package-linux:
	@echo "== OciDeck package: Linux (AppImage/.deb/.rpm) =="
	scripts/package_linux.sh $(VERSION)

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

# Put the built web bundle live. Deliberately NOT depending on build-web: this
# target should publish exactly the bundle you just verified, not silently
# rebuild one behind your back. Build first, look at it, then deploy it.
#
# The same script runs in the release workflow, so a hand deploy and a tag
# deploy are the same sequence — see scripts/deploy_web.sh for why the order
# (verify → unpack beside → atomic swap → verify live → drop backup) matters.
# Depends on build-web so `make deploy-web` always ships a freshly built,
# hardening-verified bundle. Without it the target deployed whatever happened to
# be in build/web/ — and after a `flutter clean` (as before a release build)
# that directory is gone, so deploy_web.sh died with "Geen build/web/index.html".
# The CI deploy path does not use this target: its job unpacks the already-built
# web artifact and calls scripts/deploy_web.sh directly.
deploy-web: build-web
	@echo "== OciDeck deploy: hardened web bundle =="
	@echo "Command: scripts/deploy_web.sh"
	@echo "Covers: bundle verification, upload, atomic swap, live verification."
	@echo "Target: \$$OCIDECK_DEPLOY_HOST:\$$OCIDECK_DEPLOY_ROOT (defaults: the public web demo)."
	scripts/deploy_web.sh

# Human release build for the two artifacts currently published by hand:
# the hardened web bundle (with post-build hardening verification) and the
# macOS .app. Prefer this over running raw `flutter build ...` commands.
build-release:
	@echo "== OciDeck release build: web + macOS =="
	scripts/build_release.sh

# One orchestrating command for cutting a release (#1161): the monotone
# tag-guard, then Phase 1 (local validation + build + sign). The irreversible,
# outward steps (tag push, /Applications, distribution) are printed as guided
# next steps, not auto-fired — see scripts/release.sh and docs/BUILD.md.
#   make release TAG=v0.2.2
release:
	@echo "== OciDeck release: orchestrate (guard + Phase 1) =="
	scripts/release.sh $(TAG)

# Sign the macOS release app with Developer ID, notarize it with Apple, and
# staple the ticket — the full chain that lets the .app open on other Macs
# without a Gatekeeper warning. `make build-macos` alone signs ad-hoc, which
# only runs on the machine that built it. Needs a Developer ID certificate and a
# notarytool keychain profile; see docs/BUILD.md. macOS only.
notarize-macos:
	@echo "== OciDeck release: sign + notarize macOS app =="
	scripts/notarize_macos.sh

# Sign the release manifest (SHA256SUMS) with a minisign detached signature, so
# the checksum chain gets a verifiable anchor — one signature over SHA256SUMS
# covers every artifact it lists (all four platforms + the SBOMs). A manual,
# local step by design: the private key stays off the runner, the same
# least-privilege choice as notarize-macos. Pass the path to SHA256SUMS, or run
# it where dist/SHA256SUMS lives. Needs minisign and a key pair; see docs/BUILD.md.
sign-release:
	@echo "== OciDeck release: minisign detached signature over SHA256SUMS =="
	scripts/sign_release.sh $(SHA256SUMS)

# Full local quality gate. Intended for humans, CI logs, and LLM-assisted debugging.
# `coverage` rather than `test`: it runs the same suite (one run, instrumented)
# and additionally enforces the floor and the every-file-is-in-a-test rule.
# Those two gates existed but no aggregate target invoked them, so in practice
# nothing ran them — and the GitHub workflow that did cannot fire on a Forgejo
# remote without a runner. `make check` is the real gate; it should contain the
# gates.
# De statische poorten die `check` en `check-no-coverage` allebei draaien. Eén
# lijst en geen twee: een nieuwe poort die maar aan één van de twee doelen wordt
# toegevoegd, is precies het soort stille afwijking waar niemand meer op let.
STATIC_GATES := format-check analyze check-toolchain check-linux-deps check-conventions check-audience-boundary check-method-length check-dead-code check-hardcoded-text check-comment-language check-dated-claims check-improvement-templates check-version-bump check-sbom-version check-collab-field-parity check-translated-mermaid check-untranslated-templates check-l10n-parity translate-docs-check

# De poort draait onder het poortslot (scripts/gate_lock.sh). Reden: elke
# worktree laat `.dart_tool/hooks_runner/shared` naar dezelfde map wijzen, dus
# twee gelijktijdige runs delen één native-assets-lock en één CMake-buildmap.
# Zonder slot lopen ze elkaars lock af en faalt `make check` op een wíllekeurige
# poort, zonder dat er iets mis is met de wijziging — de poort wees dan naar de
# verkeerde plek. Zie docs/CHECKS.md.
#
# `check-locked` is het echte werk en bestaat alleen om onder het slot te
# draaien; roep hem niet rechtstreeks aan tenzij je weet dat je alleen bent
# (dat is precies wat OCIDECK_NO_GATE_LOCK=1 doet).
check:
	@scripts/gate_lock.sh $(MAKE) check-locked

check-locked: $(STATIC_GATES) coverage coverage-per-file
	@case "$$(uname -s)" in \
	  Darwin) $(MAKE) test-golden ;; \
	esac
	@echo "== OciDeck check complete =="
	@echo "Validated: formatting, static analysis, conventions, the privacy projection boundary, method length, dead-code, hardcoded visible text, comment language, the full Flutter test suite, the coverage floor, the per-file coverage floor, and (on macOS) the golden visual-regression suite."

# Dezelfde poort, maar met `test` in plaats van `coverage` — de volledige suite
# draait onverkort, alleen ongeïnstrumenteerd.
#
# **Waarom dit doel bestaat.** `flutter test --coverage` houdt per test een
# VM-Service-verbinding open tot het eind van de run, en dat is de duurste en
# slechtst parallelliserende fase die we hebben. Nagemeten op de runner
# (taak 661): van een gate van 46 minuten ging 33 min 49 s naar die ene fase.
#
# **Wat dit oplevert, en wat níet.** Die 74% is niet de winst — de suite moet
# nog steeds draaien; alleen de instrumentatie gaat eraf. Lokaal nagemeten:
# `make test` 112 s wandklok / 595 s CPU tegen `make coverage` 147 s / 971 s,
# dus -24% wandklok en -39% CPU. Op vier kernen zit de run tegen zijn CPU aan
# en nadert de wandklokwinst die -39%: geschat 33 min 49 s → ~21 min, oftewel
# **~13 minuten van een gate van 46**. Reëel, maar geen factor.
#
# **Wat je hiermee inlevert, hardop:** de dekkingsvloer en de per-bestandsvloer
# draaien hier niet. Die twee blijven bestaan en blijven verplicht — in
# `make check`, op de machine van de committer, vóór main. Dit doel is bedoeld
# voor de uitbrengpoort in CI, waar de suite een tweede keer draait op andermans
# hardware en de vraag "draait alles nog" is, niet "hoeveel raakt het".
# Gebruik het niet als vervanging van `make check` in je eigen werkkopie.
check-no-coverage: $(STATIC_GATES) test
	@echo "== OciDeck check (zonder dekkingsmeting) complete =="
	@echo "Validated: formatting, static analysis, conventions, the privacy projection boundary, method length, dead-code, hardcoded visible text, comment language, and the full Flutter test suite."
	@echo "NOT validated here: the coverage floor and the per-file coverage floor — those run in 'make check'."

# De snelle statische deelverzameling van de poort: alleen $(STATIC_GATES), geen
# test-suite en geen dekkingsmeting. Bedoeld als per-PR-poort op de server
# (`.forgejo/workflows/static-gate.yml`). Zonder zo'n poort draaien deze
# controles pas op een `v*`-tag, en dan stapelt `main` tussen releases stille
# overschrijdingen op — precies wat #1118 blootlegde. Dezelfde $(STATIC_GATES)
# als `check`, dus geen tweede lijst die kan uiteenlopen. De dekkingsvloer, de
# per-bestandsvloer en de volledige suite blijven in `make check`, op de machine
# van de committer vóór main; die vangt dit doel bewust niet.
check-static: $(STATIC_GATES)
	@echo "== OciDeck static gate complete =="
	@echo "Validated: formatting, static analysis, the toolchain, conventions, the privacy projection boundary, method length, dead-code, hardcoded visible text, comment language, and improvement templates."
	@echo "NOT validated here: the full test suite, the coverage floor and the per-file coverage floor — those run in 'make check'."

# De registratie-invarianten: de handvol *snelle* tests die betrappen wanneer een
# nieuw bestand, docs-pagina, afhankelijkheid of UI-string niet geregistreerd is.
# Bedoeld als aanvulling op $(STATIC_GATES) in de per-PR-poort
# (`static-gate.yml`): $(STATIC_GATES) vangt de statische drift (bestands-/klasse-/
# methodegrootte, opmaak, hardgecodeerde tekst), maar deze poorten zíjn tests en
# draaiden dus nergens vóór de merge — precies waardoor #1123 (source_map) stil
# op main kon landen. Het zijn platte tests (geen widget-render), dus seconden per
# stuk; de volle suite en de dekkingsvloer blijven bewust in `make check`.
#
# LET OP — dit is een handmatige lijst, geen automatische. Komt er een nieuwe
# registratie-/invariantpoort bij als test, voeg hem hier toe; een gemiste test is
# opnieuw een stil gat. De vijf hieronder dekken: lib-bestand → SOURCE_MAP, docs
# → registratie, pubspec → SBOM, nieuwe `l10n.d`-string → vertaald, en de
# Windows-installer die niet uit de pas mag lopen met wat hij verpakt (#1208).
# Die laatste hoort hier omdat niets anders vóór de merge naar de installer kijkt:
# de volle suite draait pas ná de merge op `linux-gate`.
REGISTRATION_TESTS := \
	test/source_map_coverage_test.dart \
	test/docs_registration_test.dart \
	test/sbom_test.dart \
	test/l10n_untranslated_test.dart \
	test/windows_packaging_test.dart

check-registrations:
	@echo "== OciDeck registration invariants =="
	@echo "Command: flutter test $(REGISTRATION_TESTS)"
	@echo "Covers: new lib file in SOURCE_MAP, new docs registered, SBOM fresh vs pubspec, new l10n.d string translated, Windows installer in step with what it packages."
	@echo "Failure means: something new landed without its registration — the class of drift that is a *test*, not a static gate."
	flutter test $(REGISTRATION_TESTS) $(SUITE_REPORT) $(ON_SUITE_FAILURE)

# Extended local check: the gate plus licence/compliance, bundled-JS CVEs, the
# web-hardening assertion (rebuilds the web bundle), and a freshness report.
check-full:
	@scripts/gate_lock.sh $(MAKE) check-full-locked

check-full-locked: check-locked check-l10n-orphans check-l10n-passthrough check-secrets sast shellcheck licenses sbom-verify deps-check check-web deps-outdated check-marp
	@echo "== OciDeck extended check complete =="
	@echo "Validated: required quality gate, unused translation keys, untranslated Dutch source strings, licence compliance, SBOM freshness, bundled-JS CVEs, web hardening, shell scripts, dependency freshness, and real-Marp theme loading."

# The "ready for tagging" quality pass. Run this BY HAND before `git push origin
# v*`: it is the last moment a finding can hold back a release instead of ending
# up live. Pushing the tag is what triggers the whole release chain
# (.forgejo/workflows/release.yml), so the slag belongs before it, not inside it.
#
#   = check-full (BLOCKING: analysis, tests, format, secrets, SAST, licences,
#     SBOM, deps, web hardening)
#   + a DAST scan (OWASP ZAP baseline) against the LIVE host — ADVISORY.
#
# DAST is deliberately non-blocking: a ZAP warning is something to weigh and, if
# real, file as an issue (this is exactly how #849 came to be), not something
# that reddens the command. The blocking assurance is check-full; the DAST step
# is a prompt to look at the served surface one more time. If colima is
# installed but stopped, this starts it rather than making the committer
# remember a separate step before every tag (colima start is idempotent — a
# no-op with a warning if it is already running). Only if no runtime is
# reachable even after that does the DAST step skip itself, with a clear
# message rather than failing the release pass. Also worth doing by hand
# before a tag and NOT automated here: `make linux-gate` (the Linux half of
# the suite) and a look at open security/privacy issues on the tracker.
DAST_LIVE_URL ?= https://ocideck.librekat.nl/
check-release: check-full
	@echo "== OciDeck: DAST-kwaliteitsslag vóór de tag (adviserend, ready for tagging) =="
	@echo "Command: make dast DAST_URL=$(DAST_LIVE_URL)"
	@if ! docker info >/dev/null 2>&1 && command -v colima >/dev/null 2>&1; then \
	  echo "-- container runtime not reachable, starting colima --"; \
	  colima start; \
	fi
	@if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
	  $(MAKE) dast DAST_URL="$(DAST_LIVE_URL)" || \
	    echo "ZAP kon niet draaien — lees de uitvoer met de hand; leg echte bevindingen vast als issue."; \
	else \
	  echo "DAST overgeslagen — geen container-runtime (macOS: brew install colima docker && colima start), draai daarna 'make dast DAST_URL=$(DAST_LIVE_URL)'."; \
	fi
	@echo "== Klaar. Weeg de DAST-bevindingen; is alles vastgelegd of bewust aanvaard, dan is dit ready for tagging. =="

# --- Voorgebakken CI-basisimage (docs/CHECKS.md) -----------------------------
# Bouwt en publiceert .forgejo/ci-image/Dockerfile naar de eigen Forgejo-registry,
# getagd op de Flutter-pin. De betrouwbare handmatige route naast de
# ci-image.yml-workflow: cross-buildt naar linux/amd64 (de runner is amd64) via
# buildx, wat op een arm64-Mac met colima werkt. De pin komt uit .tool-versions,
# zodat image-tag en repo-pin niet uiteenlopen.
#
# Eenmalig vooraf: `docker login pawprint.vigilis.online` met een token dat
# `write:package` heeft. Zet het package daarna op PUBLIEK, anders kunnen de
# gate-workflows het niet pullen. Zie docs/CHECKS.md "Voorgebakken CI-image".
CI_IMAGE_REPO ?= pawprint.vigilis.online/librekat/ocideck-ci
CI_IMAGE_FLUTTER := $(shell sed -n 's/^flutter \(.*\)-stable$$/\1/p' .tool-versions)
ci-image-publish:
	@test -n "$(CI_IMAGE_FLUTTER)" || { echo "Geen Flutter-pin in .tool-versions"; exit 1; }
	@echo "== CI-image bouwen+pushen: $(CI_IMAGE_REPO):flutter-$(CI_IMAGE_FLUTTER) (linux/amd64) =="
	docker buildx build --platform linux/amd64 --push \
	  --build-arg FLUTTER_VERSION=$(CI_IMAGE_FLUTTER) \
	  -t $(CI_IMAGE_REPO):flutter-$(CI_IMAGE_FLUTTER) \
	  -f .forgejo/ci-image/Dockerfile .forgejo/ci-image
	@echo "== Gepubliceerd. Zet het package op publiek als dat nog niet zo is. =="

# Idem voor het scan-image (.forgejo/ci-image/scans.Dockerfile), getagd op de drie
# scanner-pins uit .github/pinned-ci-versions.json — de ENIGE bron, dezelfde die
# ci-image-scans.yml leest en waartegen scans.yml in de poort hertoetst. De
# handmatige route naast die workflow, met dezelfde buildx-cross-build.
SCANS_IMAGE_REPO ?= pawprint.vigilis.online/librekat/ocideck-scans
CI_PINS := .github/pinned-ci-versions.json
SCANS_GITLEAKS := $(shell jq -r '.tools[] | select(.name=="gitleaks") | .version' $(CI_PINS))
SCANS_TRUFFLEHOG := $(shell jq -r '.tools[] | select(.name=="trufflehog") | .version' $(CI_PINS))
SCANS_SEMGREP := $(shell jq -r '.tools[] | select(.name=="semgrep") | .version' $(CI_PINS))
SCANS_IMAGE_TAG := gl$(SCANS_GITLEAKS)-th$(SCANS_TRUFFLEHOG)-sg$(SCANS_SEMGREP)
ci-image-scans-publish:
	@test -n "$(SCANS_GITLEAKS)$(SCANS_TRUFFLEHOG)$(SCANS_SEMGREP)" || { echo "Scanner-pins niet leesbaar uit $(CI_PINS) (is jq geïnstalleerd?)"; exit 1; }
	@echo "== Scan-image bouwen+pushen: $(SCANS_IMAGE_REPO):$(SCANS_IMAGE_TAG) (linux/amd64) =="
	docker buildx build --platform linux/amd64 --push \
	  --build-arg GITLEAKS_VERSION=$(SCANS_GITLEAKS) \
	  --build-arg TRUFFLEHOG_VERSION=$(SCANS_TRUFFLEHOG) \
	  --build-arg SEMGREP_VERSION=$(SCANS_SEMGREP) \
	  -t $(SCANS_IMAGE_REPO):$(SCANS_IMAGE_TAG) \
	  -f .forgejo/ci-image/scans.Dockerfile .forgejo/ci-image
	@echo "== Gepubliceerd. Zet het package op publiek als dat nog niet zo is. =="
