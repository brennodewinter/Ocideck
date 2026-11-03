# Refresh on the Linux image builder; release workflows use the published digest.
FROM debian:12-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8
ARG SOURCE_REVISION
LABEL org.opencontainers.image.revision=$SOURCE_REVISION
LABEL online.vigilis.ocideck.consumer="debian12"
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends nodejs ca-certificates xvfb xauth fonts-dejavu-core libgtk-3-0 libsecret-1-0 liblzma5 libayatana-appindicator3-1 libgles2 libegl1 libpulse0 \
    && mkdir -p /usr/share/ocideck-consumer \
    && dpkg-query -W -f='${Package}=${Version}\n' | sort > /usr/share/ocideck-consumer/packages.txt \
    && rm -rf /var/lib/apt/lists/*
