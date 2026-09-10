FROM dart:stable

WORKDIR /opt/hyfens/packages/control_plane
ENV HOME=/tmp
ENV DART_SUPPRESS_ANALYTICS=1
COPY packages/patch_format /opt/hyfens/packages/patch_format
COPY packages/runtime /opt/hyfens/packages/runtime
COPY packages/control_plane /opt/hyfens/packages/control_plane
COPY experiments/instrumentation /opt/hyfens/experiments/instrumentation
COPY experiments/patch_loading /opt/hyfens/experiments/patch_loading

RUN dart pub get

# Keep redistribution terms with the published image as well as in the
# source repository.
COPY LICENSE /opt/hyfens/LICENSE
COPY THIRD_PARTY_NOTICES.md /opt/hyfens/THIRD_PARTY_NOTICES.md

USER 65532:65532
EXPOSE 18081
ENTRYPOINT ["dart", "run", "bin/control_plane.dart"]
