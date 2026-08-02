# OciDeck CI-basisimage — de Linux-poortomgeving, één keer voorgebakken.
#
# WAAROM. `linux-gate`, `static-gate` en `scans` draaien elk in een kaal
# `ubuntu:24.04` en bouwden de omgeving per run opnieuw op: apt-build-tools
# installeren, de officiële Flutter ophalen+uitpakken, desktop-artefacten
# precachen. Dat is per definitie hetzelfde werk met hetzelfde resultaat —
# precies wat je één keer bakt in plaats van elke run herhaalt. Dit image draagt
# de TRAAG-veranderende toolchain (OS + apt + gepinde Flutter + precache), zodat
# elke poortrun warm start.
#
# WAT BEWUST NIÉT in dit image zit: de repo-GEKOPPELDE artefacten — de
# pub-pakketten en de dartcv native OpenCV-build. Die veranderen met
# `pubspec.lock` en horen op `actions/cache` (zie de gate-workflows), niet in een
# toolchain-image dat anders bij elke dep-wijziging opnieuw gebouwd zou moeten.
#
# PROVENANCE. De Flutter-tarball is de officiële stable-release, sha256-getoetst
# tegen het release-manifest — dezelfde controle die de workflows bij het
# downloaden deden, nu verplaatst naar bouwtijd. `check-toolchain` draait
# ONVERKORT in de poort op deze ingebakken Flutter en eist nog steeds kanaal
# `stable`, officiële herkomst en gelijkheid met de pin. Een image met iets
# anders valt dus om op dezelfde poort die ooit het cirruslabs-image afkeurde.
#
# PIN-KOPPELING. De Flutter-versie komt als build-arg uit `.tool-versions` (de
# publiceer-workflow leest de pin), en het image-tag ÍS die versie
# (`flutter-<versie>`). Een pin-bump is dus automatisch een nieuw tag; geen tag
# blijft stil bij een oude toolchain staan. De gate-workflows verwijzen naar
# datzelfde tag (vervolg-PR), bewaakt zodat tag en pin niet uiteenlopen.
#
# VERTROUWENSGRENS. Dit image wordt door onze eigen job op onze eigen runner
# gebouwd en naar onze eigen Forgejo-registry geduwd — dezelfde grens als de
# runner en de bestaande `actions/cache`, geen nieuwe partij (zie de kop van
# `linux-gate.yml`).
FROM ubuntu:24.04

# Verplicht: doorgegeven door de publiceer-workflow/Makefile uit `.tool-versions`.
ARG FLUTTER_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# Exact dezelfde vaste .deb-lijst die de poorten per run installeerden.
# `build-essential` (gcc/g++) omdat dartcv's native OpenCV-build (#870) de
# standaard gcc/g++ zoekt, niet de aanwezige clang; `nodejs` omdat de
# actions-runner node nodig heeft voor `actions/checkout` en `actions/cache`.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates make git curl xz-utils jq unzip \
      cmake ninja-build clang pkg-config libgtk-3-dev \
      build-essential nodejs \
 && rm -rf /var/lib/apt/lists/*

# Officiële Flutter volgens de pin, sha256 getoetst vóór uitpakken. Faalt de
# toets, dan faalt de image-build — het image kan geen niet-geverifieerde
# toolchain dragen.
RUN set -eu; \
    test -n "${FLUTTER_VERSION}"; \
    BASE="https://storage.googleapis.com/flutter_infra_release/releases"; \
    curl -fsSLo /tmp/releases.json "${BASE}/releases_linux.json"; \
    SHA="$(jq -r --arg v "${FLUTTER_VERSION}" \
      '.releases[] | select(.channel=="stable" and .version==$v) | .sha256' \
      /tmp/releases.json)"; \
    test -n "${SHA}"; \
    ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"; \
    curl -fsSLo "/tmp/${ARCHIVE}" "${BASE}/stable/linux/${ARCHIVE}"; \
    echo "${SHA}  /tmp/${ARCHIVE}" | sha256sum -c -; \
    tar -xJf "/tmp/${ARCHIVE}" -C /opt; \
    rm "/tmp/${ARCHIVE}" /tmp/releases.json; \
    git config --global --add safe.directory /opt/flutter

ENV PATH="/opt/flutter/bin:${PATH}"

# Geen telemetrie (projectwaarde: OciDeck belt niet naar huis), en de
# Linux-desktop-artefacten vooraf ophalen zodat het eerste poort-commando ze
# niet meer downloadt. Pin-stabiel: hetzelfde voor elke run op dit image.
RUN flutter config --no-analytics >/dev/null 2>&1 || true; \
    flutter --version; \
    flutter precache --linux \
      --no-android --no-ios --no-web --no-macos --no-windows --no-fuchsia

# De poort zet zelf nog `git config --global --add safe.directory
# $GITHUB_WORKSPACE` voor de werkkopie — die uid verschilt van root en is per
# run anders, dus die stap blijft in de workflow, niet hier.
