#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
expected=.forgejo/main-branch-protection.json
endpoint=https://pawprint.vigilis.online/api/v1/repos/LibreKAT/Ocideck/branch_protections
token=${OCIDECK_FORGE_TOKEN:-}
if [[ -z $token ]] && command -v security >/dev/null; then
  token=$(security find-generic-password -s forgejo-pawprint-api -w 2>/dev/null || true)
fi

if [[ -n $token ]]; then
  # De autorisatieheader staat in een pipe en verschijnt niet in procesargumenten.
  live=$(curl --fail --silent --show-error --connect-timeout 10 --max-time 25 \
    --config <(printf 'header = "Authorization: token %s"\n' "$token") "$endpoint")
else
  live=$(tea api --repo LibreKAT/Ocideck --login pawprint.vigilis.online "$endpoint")
fi

actual=$(jq -e --slurpfile expected "$expected" '
  $expected[0] as $policy
  | map(select(.rule_name == $policy.rule_name))
  | if length != 1 then error("Verwacht precies één branchregel") else .[0] end
  | with_entries(select(.key as $key | $policy | has($key)))
' <<<"$live")

diff -u --label "$expected" --label "Pawprint main" \
  <(jq -S . "$expected") <(jq -S . <<<"$actual")
echo 'De branchregel voor main komt overeen met Pawprint.'
