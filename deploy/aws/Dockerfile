# The builder manifest digest is pinned to Dart 3.13.0. It is not shipped in
# the runtime image.
FROM dart@sha256:8b6175f6c6b89aaf31ffdace4a22d17715c07f1cf3a772dadb10c658f779e23d AS build

WORKDIR /opt/hyfens/packages/control_plane
ENV HOME=/tmp
ENV DART_SUPPRESS_ANALYTICS=1
ENV HYFENS_FILE_ROOT=/tmp/.hyfens-control-plane

COPY packages/patch_format/pubspec.yaml /opt/hyfens/packages/patch_format/pubspec.yaml
COPY packages/patch_format/pubspec.lock /opt/hyfens/packages/patch_format/pubspec.lock
COPY packages/patch_format/lib /opt/hyfens/packages/patch_format/lib
COPY packages/control_plane/pubspec.yaml /opt/hyfens/packages/control_plane/pubspec.yaml
COPY packages/control_plane/pubspec.lock /opt/hyfens/packages/control_plane/pubspec.lock
COPY packages/control_plane/lib /opt/hyfens/packages/control_plane/lib
COPY packages/control_plane/bin /opt/hyfens/packages/control_plane/bin

RUN dart pub get --enforce-lockfile

RUN mkdir -p /out \
    && dart compile exe bin/control_plane.dart -o /out/control_plane \
    && dart compile exe bin/health_check.dart -o /out/health_check \
    && chmod 0555 /out/control_plane /out/health_check

# AOT compilation removes the Dart SDK, package manager, source tree, shell,
# compiler tooling, and build-time OS utilities from the runtime surface.
FROM gcr.io/distroless/base-debian13:nonroot@sha256:2d7d29b504e7166f6d0c7655a18ebf5def5b37b029f8c4f8667e434ba774844f AS runtime

WORKDIR /app
ENV HOME=/tmp
ENV HYFENS_FILE_ROOT=/tmp/.hyfens-control-plane

COPY --from=build /out/control_plane /app/control_plane
COPY --from=build /out/health_check /app/health_check

USER nonroot:nonroot
EXPOSE 18081
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["/app/health_check"]
ENTRYPOINT ["/app/control_plane"]
