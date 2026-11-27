#!/usr/bin/env bash
# Een eigen SDK-bronboom per native CI-reis; de gedeelde SDK blijft onaangeroerd.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_sdk="$(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["flutterRoot"])')"
journey_sdk="$(mktemp -d "${RUNNER_TEMP:?}/flutter-app-journey.XXXXXX")"
journey_sdk="$(cd "$journey_sdk" && pwd -P)"
# Registreer meteen voor de always()-opruimstap, ook bij een mislukte kopie.
printf 'APP_JOURNEY_SDK=%s\n' "$journey_sdk" >> "${GITHUB_ENV:?}"
# APFS deelt de onveranderde blokken. Buiten APFS is een gewone kopie correct.
cp -cR "$source_sdk/." "$journey_sdk" 2>/dev/null || cp -R "$source_sdk/." "$journey_sdk"
# Controleer vóór elke ingreep dat cache en git-werkboom werkelijk van de kopie zijn.
[[ "$(cd "$journey_sdk/bin/cache" && pwd -P)" == "$journey_sdk/bin/cache" ]]
[[ "$(git -C "$journey_sdk" rev-parse --show-toplevel)" == "$journey_sdk" ]]
patch_file="$project_root/third_party/flutter_patches/3.50.0-semantics-b304cf1.patch"
patch_inventory="$journey_sdk/bin/cache/app-journey-patch-files"
git -C "$journey_sdk" apply --numstat "$patch_file" > "$patch_inventory"
test -s "$patch_inventory"
# Haal uitsluitend de bekende backportbestanden uit de gepinde git-objecten.
# Dat werkt ook als de gedeelde SDK tijdens de kopie zijn patch terugdraait.
while IFS=$'\t' read -r _added _deleted source_file; do
  git -C "$journey_sdk" restore --source=HEAD -- "$source_file"
done < "$patch_inventory"
rm "$patch_inventory"
# Onbekende wijzigingen elders in de SDK mogen niet ongemerkt meekomen.
git -C "$journey_sdk" diff --exit-code
# Dit is uitsluitend het meegekopieerde slot in onze eigen tijdelijke SDK.
rm -rf -- "$journey_sdk/bin/cache/ocideck-macos-semantics.lock"
actual_root="$("$journey_sdk/bin/flutter" --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["flutterRoot"])')"
if [[ "$actual_root" != "$journey_sdk" ]]; then
  echo 'Copied Flutter must resolve its own isolated SDK root' >&2
  exit 1
fi
printf '%s/bin\n' "$journey_sdk" >> "${GITHUB_PATH:?}"
echo "Native app journey uses isolated SDK: $journey_sdk"
