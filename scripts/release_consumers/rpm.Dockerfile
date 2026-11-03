# Runtime dependencies must be resolved from the RPM, never preinstalled here.
FROM fedora:42@sha256:99e203b80b1c3d8f7e161ec10a68fd02b081ef83a3963553e513c82846b97814
ARG SOURCE_REVISION
LABEL org.opencontainers.image.revision=$SOURCE_REVISION
LABEL online.vigilis.ocideck.consumer="rpm"
RUN dnf install -y --setopt=install_weak_deps=False nodejs ca-certificates xorg-x11-server-Xvfb xorg-x11-xauth dejavu-sans-fonts \
    && mkdir -p /usr/share/ocideck-consumer \
    && rpm -qa --qf '%{NAME}=%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > /usr/share/ocideck-consumer/packages.txt \
    && dnf clean all
