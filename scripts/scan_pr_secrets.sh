#!/usr/bin/env bash
# Scan van git-objecten vanuit de vertrouwde doelbranch. De PR blijft data.
set -euo pipefail

base=${1:?Gebruik: scan_pr_secrets.sh BASE HEAD}
head=${2:?Gebruik: scan_pr_secrets.sh BASE HEAD}
if [[ ! $base =~ ^[0-9a-f]{40}$ || ! $head =~ ^[0-9a-f]{40}$ ]]; then
  echo 'De scan verwacht twee volledige Git-hashes.' >&2
  exit 2
fi
test "$(git rev-parse HEAD)" = "$base"
git cat-file -e "${base}^{commit}"
git cat-file -e "${head}^{commit}"

# De checkout, regels en ignore-bestanden zijn afkomstig van de doelbranch.
# TruffleHog-resultaten kunnen volledige waarden bevatten. Alleen de exitcode
# verlaat die scanner, ook bij een positief resultaat op de publieke runner.
if gitleaks git --redact=100 --config .gitleaks.toml --log-opts="$base..$head" . >/dev/null 2>&1; then
  echo 'Gitleaks: scan geslaagd.'
else
  result=$?
  echo "Gitleaks gaf exitcode $result. Herhaal de scan lokaal voor triage." >&2
  exit "$result"
fi
common=$(git merge-base "$base" "$head")
scan_ref=refs/heads/ocideck-pr-secret-scan
git update-ref "$scan_ref" "$head" 0000000000000000000000000000000000000000
trap 'git update-ref -d "$scan_ref" "$head"' EXIT
if trufflehog git file://. --branch=ocideck-pr-secret-scan --since-commit="$common" \
    --no-verification --no-update --exclude-paths .trufflehogignore \
    --fail --fail-on-scan-errors --json >/dev/null 2>&1; then
  echo 'TruffleHog: scan geslaagd.'
else
  result=$?
  echo "TruffleHog gaf exitcode $result. Herhaal de scan lokaal voor triage." >&2
  exit "$result"
fi
