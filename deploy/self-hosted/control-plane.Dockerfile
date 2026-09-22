# Public OSS control-plane image. Keep this recipe independent from the
# private Cloud deployment and build only checked-in public packages.

# Update these digests only through a reviewed dependency-refresh change.
FROM dart:3.13.3@sha256:7e57e61d97813dc57dd0801656ff4d5c5efafa47bae563a681571543ad30f199 AS build

WORKDIR /src

COPY packages/patch_format/pubspec.yaml packages/patch_format/pubspec.lock packages/patch_format/
COPY packages/patch_format/lib packages/patch_format/lib
COPY packages/control_plane/pubspec.yaml packages/control_plane/pubspec.lock packages/control_plane/
COPY packages/control_plane/bin packages/control_plane/bin
COPY packages/control_plane/lib packages/control_plane/lib

WORKDIR /src/packages/control_plane
RUN mkdir -p /out \
    && dart pub get --enforce-lockfile --no-example \
    && dart compile exe bin/control_plane.dart \
      --output /out/hyfens-control-plane \
    && dart compile exe bin/health_check.dart \
      --output /out/hyfens-health-check

FROM gcr.io/distroless/base-debian12:nonroot@sha256:7f0c72cd138b442ae0deeb69c08b1acf5525439ba251a49ad93c320a061567e5

COPY --from=build /out/hyfens-control-plane /usr/local/bin/hyfens-control-plane
COPY --from=build /out/hyfens-health-check /usr/local/bin/hyfens-health-check

EXPOSE 18081
ENV HYFENS_HOST=0.0.0.0 \
    HYFENS_PORT=18081

USER nonroot:nonroot
ENTRYPOINT ["/usr/local/bin/hyfens-control-plane"]
HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=6 \
  CMD ["/usr/local/bin/hyfens-health-check"]
