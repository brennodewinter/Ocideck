FROM debian:12-slim

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
    && archive_version="${FLUTTER_VERSION%-stable}" \
    && case "${architecture}" in \
         amd64) archive="flutter_linux_${archive_version}-stable.tar.xz" ;; \
         arm64) archive="flutter_linux_arm64_${archive_version}-stable.tar.xz" ;; \
         *) echo "Niet-ondersteunde architectuur: ${architecture}" >&2; exit 1 ;; \
       esac \
    && curl --proto '=https' --tlsv1.2 -fL \
         "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${archive}" \
         -o /tmp/flutter.tar.xz \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --system --add safe.directory /opt/flutter \
    && flutter config --no-analytics --enable-linux-desktop \
    && flutter precache --linux \
    && mkdir -p /opt/pub-cache \
    && chmod -R a+rwX /opt/flutter /opt/pub-cache

COPY container-build.sh /usr/local/bin/ocideck-container-build
RUN chmod 0755 /usr/local/bin/ocideck-container-build

WORKDIR /src
ENTRYPOINT ["/usr/local/bin/ocideck-container-build"]
