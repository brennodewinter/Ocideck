FROM debian:12-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8

ARG FLUTTER_VERSION
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}
ENV PUB_CACHE=/opt/pub-cache

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        binutils \
        build-essential \
        ca-certificates \
        clang \
        cmake \
        curl \
        file \
        git \
        jq \
        libasound2-dev \
        libayatana-appindicator3-dev \
        libblkid-dev \
        libclang-dev \
        libcurl4-openssl-dev \
        libgstreamer-plugins-base1.0-dev \
        libgstreamer1.0-dev \
        libgtk-3-dev \
        libjsoncpp-dev \
        liblzma-dev \
        libmpv-dev \
        libpipewire-0.3-dev \
        libpulse-dev \
        libsecret-1-dev \
        libsqlite3-dev \
        libssl-dev \
        libstdc++-12-dev \
        libunwind-dev \
        libwebkit2gtk-4.1-dev \
        make \
        nasm \
        ninja-build \
        pkg-config \
        python3 \
        unzip \
        xz-utils \
        zip \
    && rm -rf /var/lib/apt/lists/*

RUN test -n "${FLUTTER_VERSION}" \
    && architecture="${TARGETARCH:-$(dpkg --print-architecture)}" \
    && test "${architecture}" = amd64 \
    && archive_version="${FLUTTER_VERSION%-stable}" \
    && archive="flutter_linux_${archive_version}-stable.tar.xz" \
    && curl --proto '=https' --tlsv1.2 -fL \
         https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json \
         -o /tmp/releases.json \
    && sha="$(jq -r --arg archive "stable/linux/${archive}" \
         '.releases[] | select(.channel == "stable" and .archive == $archive) | .sha256' \
         /tmp/releases.json)" \
    && test -n "${sha}" \
    && curl --proto '=https' --tlsv1.2 -fL \
         "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${archive}" \
         -o /tmp/flutter.tar.xz \
    && echo "${sha}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz /tmp/releases.json \
    && git config --system --add safe.directory /opt/flutter \
    && flutter config --no-analytics --enable-linux-desktop \
    && flutter precache --linux \
    && mkdir -p /opt/pub-cache \
    && chmod -R a+rwX /opt/flutter /opt/pub-cache

COPY container-build.sh /usr/local/bin/ocideck-container-build
RUN chmod 0755 /usr/local/bin/ocideck-container-build

WORKDIR /src
ENTRYPOINT ["/usr/local/bin/ocideck-container-build"]
