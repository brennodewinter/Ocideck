# Refresh on the Linux image builder; release workflows use the published digest.
FROM ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3
ARG SOURCE_REVISION
LABEL org.opencontainers.image.revision=$SOURCE_REVISION
LABEL online.vigilis.ocideck.consumer="flatpak"
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends nodejs ca-certificates flatpak \
    && mkdir -p /usr/share/ocideck-consumer \
    && dpkg-query -W -f='${Package}=${Version}\n' | sort > /usr/share/ocideck-consumer/packages.txt \
    && rm -rf /var/lib/apt/lists/*
RUN flatpak --system remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
    && flatpak --system install -y --noninteractive flathub org.gnome.Platform/x86_64/50 \
    && flatpak --system info --show-commit org.gnome.Platform/x86_64/50 > /usr/share/ocideck-consumer/runtime-commit
