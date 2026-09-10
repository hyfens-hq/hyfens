# Third-party notices

This inventory covers external packages, fonts, native artifacts, container
bases, and other material directly used or redistributed by the current CLI,
control-plane, dashboard, and Flutter fixtures. It groups related package
families and does not reproduce the complete transitive dependency graph.
Resolved package versions below come from the checked-in lockfiles; image tags
and digests come from the Dockerfiles and Compose files.

Upstream license text controls. This file is an inventory and does not add
terms to any dependency or change the root [Apache License 2.0](LICENSE).
Where a release distributes a binary, app, or image, the applicable upstream
copyright and license texts must travel with that release; a live URL alone is
not a substitute for required notices.

## Root NOTICE decision

No separate root `NOTICE` file is included for this initial publication. The
project has no additional project-level NOTICE text to carry, and the
redistribution notices that apply to the checked-in source and dashboard
assets are recorded here and in [`docs/ASSET_PROVENANCE.md`](docs/ASSET_PROVENANCE.md).
Future binary or image releases must retain any notices emitted by their
resolved dependency and base-image closure.

## Classification

- `PERMISSIVE_COMPATIBLE`: the identified upstream license is Apache-2.0, MIT,
  BSD-style, or another permissive license screened as compatible with the
  root Apache-2.0 license, subject to preserving its notices.
- `NOTICE_REQUIRED`: the material is shipped, embedded, or loaded at runtime
  and its copyright/license notice must be carried with the relevant
  distribution.
- `REVIEW_REQUIRED`: the exact native/image closure, floating image contents,
  or additional terms require a per-artifact audit before release.
- `INCOMPATIBLE`: the current material cannot be redistributed as-is on the
  evidence and upstream terms currently available; replacement or permission
  is required.

## Direct/runtime Dart and Flutter dependencies

The rows below cover direct dependencies used by the CLI, instrumentation,
patch-loading, control-plane, Flutter integration, and conformance fixtures.
Endorsed platform implementations are grouped with their parent package
instead of listing every transitive package.

| Classification | Dependency family and resolved version(s) | License evidence | Used by |
| --- | --- | --- | --- |
| `PERMISSIVE_COMPATIBLE` | `analyzer` 8.4.1, `args` 2.7.0, `crypto` 3.0.7, `package_config` 2.2.0, `path` 1.9.1 | BSD 3-Clause: [analyzer](https://pub.dev/packages/analyzer/versions/8.4.1/license), [args](https://pub.dev/packages/args/versions/2.7.0/license), [crypto](https://pub.dev/packages/crypto/versions/3.0.7/license), [package_config](https://pub.dev/packages/package_config/versions/2.2.0/license), [path](https://pub.dev/packages/path/versions/1.9.1/license) | CLI, instrumentation, control plane, and Flutter integration |
| `PERMISSIVE_COMPATIBLE` | `yaml` 3.1.3 | MIT: [package license](https://pub.dev/packages/yaml/versions/3.1.3/license) | CLI configuration and project discovery |
| `PERMISSIVE_COMPATIBLE` | `cryptography` 2.9.0 | Apache-2.0: [upstream LICENSE](https://github.com/dint-dev/cryptography/blob/cryptography-v2.9.0/LICENSE) | CLI signing, control plane, patch loading, and the root experiment |
| `PERMISSIVE_COMPATIBLE` | `postgres` 3.5.12 | BSD-style package license with source/binary notice: [package license](https://pub.dev/packages/postgres/versions/3.5.12/license), [upstream project](https://github.com/isoos/postgresql-dart) | Control-plane persistence and CLI/runtime support |
| `PERMISSIVE_COMPATIBLE` | `alphax` and `alphax_native` 1.0.0-rc.3 | Apache-2.0 package texts: [alphax](https://pub.dev/packages/alphax/versions/1.0.0-rc.3/license), [alphax_native](https://pub.dev/packages/alphax_native/versions/1.0.0-rc.3/license); [source](https://github.com/auvana-ventures/alphax) | Flutter conformance app |
| `PERMISSIVE_COMPATIBLE` | `bloc` 9.2.1, `flutter_bloc` 9.1.1, `flutter_riverpod`/`riverpod` 3.4.2 | MIT: [bloc](https://pub.dev/packages/bloc/versions/9.2.1/license), [flutter_bloc](https://pub.dev/packages/flutter_bloc/versions/9.1.1/license), [flutter_riverpod](https://pub.dev/packages/flutter_riverpod/versions/3.4.2/license), [riverpod](https://pub.dev/packages/riverpod/versions/3.4.2/license) | Flutter conformance app and interoperability tests |
| `PERMISSIVE_COMPATIBLE` | `flutter_svg` 2.3.0, `permission_handler` 13.0.1, `cupertino_icons` 1.0.9 | MIT: [flutter_svg](https://pub.dev/packages/flutter_svg/versions/2.3.0/license), [permission_handler](https://pub.dev/packages/permission_handler/versions/13.0.1/license), [cupertino_icons](https://pub.dev/packages/cupertino_icons/versions/1.0.9/license) | Flutter conformance and toolchain fixtures |
| `PERMISSIVE_COMPATIBLE` | `go_router` 17.5.0, `path_provider` 2.1.6, and their locked/overridden platform implementations | BSD 3-Clause: [go_router](https://pub.dev/packages/go_router/versions/17.5.0/license), [path_provider](https://pub.dev/packages/path_provider/versions/2.1.6/license) | Flutter conformance and Flutter integration; the CLI/integration override pins `path_provider_android` 2.2.23, while the conformance lock resolves 2.3.1 |
| `PERMISSIVE_COMPATIBLE` | `video_player` 2.14.0 and its endorsed platform implementations | BSD 3-Clause: [package license](https://pub.dev/packages/video_player/versions/2.14.0/license) | Flutter conformance app |
| `PERMISSIVE_COMPATIBLE` | Dart SDK and Flutter SDK used by the CLI, containers, and Flutter fixtures | BSD-style: [Dart SDK license](https://github.com/dart-lang/sdk/blob/main/LICENSE), [Flutter license](https://github.com/flutter/flutter/blob/master/LICENSE) | Build/runtime toolchains; no separate SDK tree is copied into the CLI archive |
| `PERMISSIVE_COMPATIBLE` | Flutter Material Icons enabled by `uses-material-design: true` | Apache-2.0: [Material Design Icons license](https://github.com/google/material-design-icons/blob/master/LICENSE) | Flutter toolchain and conformance fixtures |

### Selected test-only source overlay

`collection` 1.19.1 is used only by the pure-Dart instrumentation test to
copy one resolved source unit into an ephemeral overlay. It is not a product
runtime dependency. Its BSD 3-Clause license is recorded here for that source
redistribution: [collection package license](https://pub.dev/packages/collection/versions/1.19.1/license).
Other test/lint-only packages are intentionally omitted.

### Native dependency requiring review

`alphax_native` declares
`com.google.android.gms:play-services-cronet:18.0.1` in its Android Gradle
dependencies. The [official Maven POM](https://dl.google.com/dl/android/maven2/com/google/android/gms/play-services-cronet/18.0.1/play-services-cronet-18.0.1.pom)
identifies the Android SDK License and pulls additional Google Play Services
and Chromium Cronet artifacts. The package's Apache-2.0 license does not by
itself close that native runtime closure.

| Classification | Material | Required follow-up |
| --- | --- | --- |
| `REVIEW_REQUIRED` | Google Play Services Cronet 18.0.1 and its resolved AAR/POM closure | Generate the Android artifact's OSS notices from the resolved Gradle graph and verify the Google/Chromium terms before distributing a mobile build. See [Google's Android OSS guidance](https://developers.google.com/android/guides/opensource). |

## Fonts and bundled application material

| Classification | Material | License/provenance evidence |
| --- | --- | --- |
| `NOTICE_REQUIRED` | Dashboard runtime fonts: IBM Plex Sans, IBM Plex Mono, and Bricolage Grotesque | SIL OFL 1.1 upstream licenses: [IBM Plex](https://github.com/IBM/plex/blob/master/LICENSE.txt), [Bricolage Grotesque](https://github.com/ateliertriay/bricolage/blob/main/OFL.txt). `dashboard/tokens.css` loads these families from Google Fonts; no font binaries are bundled by the dashboard. |
| `NOTICE_REQUIRED` | Flutter conformance `InterVariable.ttf` | SIL OFL 1.1: [local license copy](fixtures/flutter_conformance_app/assets/fonts/Inter-OFL.txt), sourced at the pinned Inter commit recorded in [asset attributions](fixtures/flutter_conformance_app/assets/ATTRIBUTIONS.md). The app source includes the font binary; an app distribution must expose the OFL notice. |

The dashboard has no package-manager manifest, bundled JavaScript framework, or
third-party JavaScript/CSS library. Its Python server uses the standard
library. The Hyfens brand mark, Waypoint SVG illustrations, deterministic JSON
fixtures, and generated route-preview video have no third-party license claim
in this file: `ATTRIBUTIONS.md` records the illustrations as locally authored
and the video as locally generated. Attribution is provenance, not a license
grant.

### Dashboard icons

| Classification | Material | Evidence and disposition |
| --- | --- | --- |
| `NOTICE_REQUIRED` | 22 vendored Lucide 1.27.0 SVG snapshots under `dashboard/icons/` | ISC license with the Feather-derived MIT notice. The exact commit, source mapping, license text, and attribution requirements are recorded in [asset provenance](docs/ASSET_PROVENANCE.md). The SVGs are part of the dashboard source and image; no unverified template icon files remain in the dashboard or fixtures. |

## Container bases and bundled image material

These images are deployment dependencies, not Dart package transitive
notices. The exact OS-package closure is not checked into this repository, so
image release must retain an SBOM/license report for the resolved digest.

| Classification | Image/surface | Evidence and disposition |
| --- | --- | --- |
| `NOTICE_REQUIRED` | NGINX 1.27 Alpine base in `dashboard/Dockerfile` and the proxy examples | NGINX is 2-clause BSD ([license](https://nginx.org/LICENSE)); the official image is [NGINX on Docker Hub](https://hub.docker.com/_/nginx). The dashboard image does not bundle a separate application framework or package manager. An image release should retain the resolved base-image notices. |
| `NOTICE_REQUIRED` | Dart SDK base in `deploy/p2/Dockerfile` | [Official Dart image](https://github.com/dart-lang/dart-docker) and [Dart SDK license](https://github.com/dart-lang/sdk/blob/main/LICENSE). The base image is build infrastructure; the published Hyfens control-plane image contains the compiled service and its source package notices, not the Pub cache. Pin/update the base deliberately for each image release. |
| `NOTICE_REQUIRED` | PostgreSQL 17 Alpine Compose dependency | PostgreSQL's permissive [official license](https://www.postgresql.org/about/licence/) and [image source](https://github.com/docker-library/postgres) apply to the separately pulled operator dependency. It is not copied into a Hyfens image; operators retain the image's own notices. |
| `NOTICE_REQUIRED` | MinIO and `mc` Compose dependencies | [MinIO](https://github.com/minio/minio/blob/master/LICENSE) and [mc](https://github.com/minio/mc/blob/master/LICENSE) are AGPL-3.0. These are separately pulled object-store services, not bundled into either Hyfens GHCR image or Apache-licensed source package. Operators must comply with the upstream AGPL terms for those services and may substitute another S3-compatible store. |
GitHub Action/tool images are CI infrastructure, not product runtime
redistribution surfaces. The public Compose package pulls PostgreSQL and
MinIO separately; those operator dependencies are covered above and are not
copied into either Hyfens image.

Both published Hyfens images copy the root `LICENSE` and this notice inventory
into their filesystem. The Lucide license text required for the dashboard
assets is reproduced above and is therefore available with the dashboard
image's notice inventory.

## CLI archive and release workflows

`scripts/cli-release/build.dart` builds the CLI from `cli/pubspec.lock`,
packages the compiled executable and first-party canonical bundle, and copies
the root `LICENSE` and this file into every platform archive. It does not copy
the Pub cache or third-party source trees. `.github/workflows/release-cli.yml`
uses GitHub Actions only to build and publish those archives; the Actions are
not redistributed by Hyfens. The archive inventory must remain limited to the
canonical `hyfens` binary, the intentional deprecated `tool` shim, license and
notice files, and the runtime support files required by the build output.

The CLI archive wiring is therefore `NOTICE_REQUIRED` and is present. The
native Flutter app closure and resolved container layers remain release-time
notice/SBOM responsibilities; they are not copied into the CLI archive. No
private keys, profiles, `.env` files, test credentials, or temporary build
material belong in an archive.
