# OciDeck scan-basisimage — de secrets-/SAST-poortomgeving, één keer voorgebakken.
#
# WAAROM. `scans.yml` draaide in een kaal `ubuntu:24.04` en bouwde bij ÉLKE pull
# request de omgeving opnieuw op: apt-tools installeren en drie beveiligings-
# scanners van het net halen (gitleaks + trufflehog als release-tarball,
# semgrep uit een verse pip-venv). Gemeten kostte dat ~3 minuten per run, waarvan
# vrijwel alles installeren was en amper 19 seconden scannen (#778). Erger dan de
# klok was het net: drie downloads per run zijn drie kansen op een storing die
# niets met deze repo te maken heeft (op 2026-07-24 twee keer een `curl 504` op
# één middag). Dit image draagt de traag-veranderende scanners, zodat elke poort-
# run warm start en niets meer het net op hoeft.
#
# WAAROM DIT MOCHT, TERWIJL SCANNERS CACHEN NIET MOCHT. `scans.yml` weigerde ooit
# bewust een `actions/cache` op de scanner-binaries (CHECKS.md): een cache-restore
# vervangt een sha256-geverifieerde download van een BEVEILIGINGSscanner door een
# artefact dat een eerdere run schreef, en — anders dan bij de Flutter-toolchain,
# waar `check-toolchain` de herstelde boom hertoetst — was er geen hercontrole die
# borgde dat "groen" hetzelfde bleef betekenen. Een voorgebakken image neemt dat
# bezwaar op TWEE punten weg, en pas dan is het verdedigbaar:
#   1. De sha256-verificatie is niet weg, maar verplaatst naar BOUWTIJD (hieronder,
#      exact de controle die de workflow bij het downloaden deed). Faalt de toets,
#      dan faalt de image-build — het image kan geen ongeverifieerde scanner dragen.
#   2. `scans.yml` krijgt de ontbrekende hercontrole: het toetst in de poort of de
#      ingebakken scanner-versies gelijk zijn aan de pins (fail-closed), net zoals
#      `check-toolchain` dat voor Flutter doet. Een image met iets anders valt daar
#      om. Zie de kop van `scans.yml`.
#
# PIN-KOPPELING. De drie versies komen als build-args uit de ENIGE pinbron,
# `.github/pinned-ci-versions.json` (de publiceer-workflow leest ze), en het
# image-tag ÍS die drie pins (`gl<gitleaks>-th<trufflehog>-sg<semgrep>`). Een
# pin-bump is dus automatisch een nieuw tag; geen tag blijft stil op een oude
# scanner staan, want de nieuwe pins verwijzen naar een tag die pas bestaat nadat
# het image ermee herbouwd is. `scans.yml` verwijst naar datzelfde tag.
#
# VERTROUWENSGRENS. Zelfde als het Flutter-image, de runner en de bestaande
# `actions/cache`: onze eigen job bouwt dit op onze eigen runner en duwt het naar
# onze eigen Forgejo-registry — geen nieuwe partij. De tarballs worden sha256
# getoetst tegen het uitgever-manifest vóór uitpakken; dat vangt een beschadigde
# of onderweg gewijzigde download, geen bewijs over de uitgever (het manifest komt
# van diezelfde uitgever).
FROM ubuntu:24.04

# Verplicht: doorgegeven door de publiceer-workflow/Makefile uit het pin-manifest.
ARG GITLEAKS_VERSION
ARG TRUFFLEHOG_VERSION
ARG SEMGREP_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# Gereedschap: `make`+`git` draaien `make check-secrets`/`make sast`, git ook voor
# de historie-scan; `python3`+`python3-venv` dragen de semgrep-venv (venv symlinkt
# naar de systeem-`python3`, dus die blijft nodig op runtime); `nodejs` omdat de
# actions-runner node nodig heeft voor `actions/checkout`; `curl`+`tar` om de
# scanner-tarballs hieronder te halen en uit te pakken.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates make git python3 python3-venv nodejs curl tar \
 && rm -rf /var/lib/apt/lists/*

# gitleaks volgens de pin: release-tarball binnenhalen en sha256 toetsen tegen het
# gepubliceerde manifest — exact de controle die `scans.yml` bij het downloaden
# deed, nu op bouwtijd. `test -n "$SHA"` houdt de faalreden leesbaar: zonder die
# regel struikelt de build over de *invoer* van sha256sum als een release-asset
# hernoemd is, in plaats van over de assetnaam zelf (#800).
RUN set -eu; \
    test -n "${GITLEAKS_VERSION}"; \
    BASE="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}"; \
    ARCHIVE="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"; \
    curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 15 -o "/tmp/${ARCHIVE}" "${BASE}/${ARCHIVE}"; \
    curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 15 -o /tmp/gitleaks_checksums.txt \
      "${BASE}/gitleaks_${GITLEAKS_VERSION}_checksums.txt"; \
    SHA="$(awk -v f="${ARCHIVE}" '$2 == f { print $1 }' /tmp/gitleaks_checksums.txt)"; \
    test -n "${SHA}"; \
    echo "${SHA}  /tmp/${ARCHIVE}" | sha256sum -c -; \
    tar -xzf "/tmp/${ARCHIVE}" -C /usr/local/bin gitleaks; \
    rm "/tmp/${ARCHIVE}" /tmp/gitleaks_checksums.txt; \
    gitleaks version

# trufflehog volgens de pin: zelfde discipline als gitleaks.
RUN set -eu; \
    test -n "${TRUFFLEHOG_VERSION}"; \
    BASE="https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VERSION}"; \
    ARCHIVE="trufflehog_${TRUFFLEHOG_VERSION}_linux_amd64.tar.gz"; \
    curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 15 -o "/tmp/${ARCHIVE}" "${BASE}/${ARCHIVE}"; \
    curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 15 -o /tmp/trufflehog_checksums.txt \
      "${BASE}/trufflehog_${TRUFFLEHOG_VERSION}_checksums.txt"; \
    SHA="$(awk -v f="${ARCHIVE}" '$2 == f { print $1 }' /tmp/trufflehog_checksums.txt)"; \
    test -n "${SHA}"; \
    echo "${SHA}  /tmp/${ARCHIVE}" | sha256sum -c -; \
    tar -xzf "/tmp/${ARCHIVE}" -C /usr/local/bin trufflehog; \
    rm "/tmp/${ARCHIVE}" /tmp/trufflehog_checksums.txt; \
    trufflehog --version

# Semgrep komt van PyPI (geen losse tarball), in een venv omdat Ubuntu 24.04
# systeem-pip afschermt (PEP 668). De versie is gepind; de transitieve
# afhankelijkheden zijn dat NIET — hash-pinnen zou een requirements-bestand met
# honderden hashes vragen, een grotere belofte dan hier wordt waargemaakt. Bewust
# genoteerd in plaats van stil gelaten (identiek aan de oude workflow-stap).
RUN set -eu; \
    test -n "${SEMGREP_VERSION}"; \
    python3 -m venv /opt/semgrep-venv; \
    /opt/semgrep-venv/bin/pip install --quiet --no-input "semgrep==${SEMGREP_VERSION}"; \
    /opt/semgrep-venv/bin/semgrep --version

ENV PATH="/opt/semgrep-venv/bin:${PATH}"

# De poort zet zelf nog `git config --global --add safe.directory $GITHUB_WORKSPACE`
# voor de werkkopie — die uid verschilt van root en is per run anders, dus die stap
# blijft in de workflow, niet hier.
