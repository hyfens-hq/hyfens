# Flutter project discovery

Hyfens discovers the Flutter application around the command before it creates
a release or patch. The same result is used by doctor, init, release, patch,
and analyze, so a patch cannot accidentally target a different app, flavor, or
Dart entrypoint than its release.

## Automatic discovery

From a normal Flutter application:

~~~bash
cd my_flutter_app
hyfens doctor
hyfens init
hyfens release android
~~~

Hyfens reads the project pubspec, valid executable Dart entrypoints, Android
Gradle configuration, and iOS schemes/configurations. It recognizes:

- a single app with lib/main.dart;
- conventional targets such as lib/main_dev.dart;
- nested targets such as lib/src/flavors/dev.dart;
- native flavors that all use lib/main.dart;
- custom Dart targets without native flavors;
- Melos and Dart Pub Workspaces;
- repositories with several Flutter applications;
- Flutter packages, plugins, and example applications.

An export-only file such as lib/main.dart is not considered an executable
entrypoint. An entrypoint must contain a valid top-level main function.

## Selection and overrides

Hyfens selects a single app automatically when the evidence is unambiguous.
When it finds several apps, or several flavors without a safe default, init
shows the choices and saves the selection in the app's hyfens.yaml. It never
chooses prod just because that flavor exists.

Use the explicit project selector for a workspace:

~~~bash
hyfens init --project apps/mobile
hyfens release android --project apps/mobile
~~~

Use flavor and entrypoint overrides for CI, a temporary alternate build, or
an intentionally different target:

~~~bash
hyfens release android --flavor dev
hyfens patch android --flavor dev
hyfens release android --entrypoint lib/src/flavors/dev.dart
~~~

The project, flavor, and entrypoint must all describe the same Flutter
application. An explicit entrypoint is checked for existence, project
containment, and a top-level main function.

If an existing hyfens.yaml selection no longer matches the repository, Hyfens
fails safely and points to hyfens init. It does not silently retarget another
application after a move.

## Melos and Pub Workspaces

Run from the workspace root or from the selected app directory:

~~~bash
cd my_workspace
hyfens init
~~~

For example:

~~~text
my_workspace/
  apps/
    customer/
    admin/
  packages/
    design_system/
    networking/
~~~

Runnable applications under the workspace are offered as candidates. Pure
Dart packages, Flutter packages, and plugins are filtered out. Example apps
are offered only when there is no clearer application candidate. The workspace
root and app directory resolve to the same logical selection after init.

Discovery is bounded and ignores source-control, dependency, generated, and
build directories. A symlinked starting path is canonicalized, while recursive
discovery does not follow symlinked directories; this prevents a workspace scan
from escaping its repository boundary. It does not recursively search
indefinitely through nested repositories.

## Flavors and platforms

Android Groovy and Kotlin Gradle files are inspected for product flavors,
application IDs, suffixes, and dimensions. iOS flavor xcconfig files and
shared schemes are inspected for bundle identifiers and Flutter targets.
Android and iOS selections are resolved independently because their native
configuration can differ.

A native flavor does not require a separate Dart file. Conversely, a custom
Dart target can be used without a native flavor. Filename conventions are
evidence, not proof; the file must still be an executable entrypoint.

If one target has several native flavors and no persisted or explicit choice,
doctor reports NEEDS_SELECTION. Run init interactively, or provide an explicit
flavor in CI.

## CI and non-interactive use

Persist the result of init before running release commands in CI:

~~~bash
hyfens --non-interactive init --project apps/mobile
hyfens --non-interactive release android --project apps/mobile
~~~

An ambiguous or stale configuration fails before a build with an actionable
diagnostic. Interactive selection is never attempted in a non-TTY or when
--non-interactive is supplied.

The current stable selection metadata includes a repository-relative project
path, flavor, and entrypoint. It does not include an absolute local path,
source files, credentials, signing material, or secret values.

## Toolchain managers and build flags

Hyfens recognizes common FVM and Puro project markers and reports a hint. Run
Hyfens from the shell that has selected the project's pinned Flutter SDK. The
current CLI does not invoke a version manager for you.

The current CLI does not provide a generic pass-through for arbitrary Flutter
build flags such as dart-define or dart-define-from-file. Do not put secret
values in hyfens.yaml. If a flavor depends on such flags, keep those values in
the project's approved build configuration and treat any unsupported command
line requirement as a documented product limitation.

## Stable diagnostics

Discovery uses these stable diagnostics:

| Code | Meaning |
| --- | --- |
| T1301 | No runnable Flutter application was found |
| T1302 | Multiple Flutter applications need a project selection |
| T1304 | Multiple flavors or entrypoints need a selection |
| T1305 | No valid executable Dart entrypoint was found |
| T1306 | The selected project-relative path is invalid or missing |
| T1307 | The flavor is not defined for the selected target |
| T1308 | The flavor name is invalid |
| H1209 | The persisted project selection is stale |
| H1210 | The persisted target selection is invalid |

Use doctor to inspect what Hyfens understood before changing configuration.

## Design references

The discovery UX follows the same useful shape as established Flutter
deployment tools: a short init, clear release and patch commands, explicit
flavor/target overrides, and fail-closed native-change boundaries. See
[Shorebird release](https://docs.shorebird.dev/code-push/release/) and
[Shorebird flavors](https://docs.shorebird.dev/guides/flavors/) for public
reference material. The public
[Ejenix repository](https://github.com/ejenix/opensource) was also checked for
onboarding and OSS/Cloud presentation; it provides no public evidence of a
comparable Flutter project-discovery or Melos-selection contract. Hyfens uses
the concise onboarding pattern as inspiration while keeping its own discovery
model and product contracts.
