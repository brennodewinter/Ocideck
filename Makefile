.PHONY: setup format format-check analyze test test-contracts test-preview test-export test-state test-services test-presenter deps-outdated check check-full help

help:
	@echo "OciDeck quality targets:"
	@echo "  make check           Format check + static analysis + full Flutter test suite."
	@echo "  make check-full      make check + dependency outdated report."
	@echo "  make test-contracts  Markdown/save-load contract and parsing tests."
	@echo "  make test-preview    Slide rendering, footer, TLP, inline markdown, and preview tests."
	@echo "  make test-export     Export and file-service smoke tests."
	@echo "  make test-state      Provider/state/recovery tests."
	@echo "  make test-services   Caption/description/image service tests."
	@echo "  make test-presenter  Fullscreen presenter interaction tests."
	@echo "  make deps-outdated   Advisory dependency freshness report."

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

# Static analysis.
analyze:
	@echo "== OciDeck check: static analysis =="
	@echo "Command: flutter analyze"
	@echo "Covers: analyzer/lint/type checks for the Flutter app and tests."
	@echo "Failure means: inspect analyzer diagnostics above the final summary."
	flutter analyze

# Run the full unit/widget test suite.
test:
	@echo "== OciDeck check: tests =="
	@echo "Command: flutter test"
	@echo "Covers: all unit/widget tests under test/, including markdown round-trip, preview, export, provider, footer, and presenter tests."
	@echo "Failure means: inspect the named failing test file and test case in the Flutter output."
	flutter test

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

# Full local quality gate. Intended for humans, CI logs, and LLM-assisted debugging.
check: format-check analyze test
	@echo "== OciDeck check complete =="
	@echo "Validated: formatting, static analysis, and the full Flutter test suite."

# Extended local check with advisory dependency freshness after the required gate.
check-full: check deps-outdated
	@echo "== OciDeck extended check complete =="
	@echo "Validated: required quality gate plus dependency freshness report."
