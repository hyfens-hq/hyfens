FROM dart:3.13.0@sha256:8b6175f6c6b89aaf31ffdace4a22d17715c07f1cf3a772dadb10c658f779e23d AS build

WORKDIR /opt/hyfens/packages/control_plane
ENV HOME=/tmp
ENV DART_SUPPRESS_ANALYTICS=1
COPY packages/patch_format /opt/hyfens/packages/patch_format
COPY packages/control_plane /opt/hyfens/packages/control_plane

RUN dart pub get --enforce-lockfile --no-example
RUN mkdir -p /opt/hyfens/bin \
    && dart compile exe bin/control_plane.dart -o /opt/hyfens/bin/control-plane

FROM dart:3.13.0@sha256:8b6175f6c6b89aaf31ffdace4a22d17715c07f1cf3a772dadb10c658f779e23d

WORKDIR /opt/hyfens
ENV DART_SUPPRESS_ANALYTICS=1
COPY --from=build /opt/hyfens/bin/control-plane /opt/hyfens/bin/control-plane

# Keep redistribution terms with the published image as well as in the
# source repository.
COPY LICENSE /opt/hyfens/LICENSE
COPY THIRD_PARTY_NOTICES.md /opt/hyfens/THIRD_PARTY_NOTICES.md

USER 65532:65532
EXPOSE 18081
ENTRYPOINT ["/opt/hyfens/bin/control-plane"]
