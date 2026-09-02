# E0: analyzer-guided transparent dispatch

This is a deliberately throwaway, narrow experiment. It answers whether stock Dart
AOT can retain an automatically inserted callee-entry dispatch from ordinary Dart
source to a data-only interpreted implementation. It does **not** establish broad
Dart or Flutter compatibility.

The checked-in fixture contains no patch import, API, or annotation. `bin/e0.dart`
parses it with the analyzer and composes ordered offset edits into an ephemeral
overlay. Every supported `int Function(int, int)` top-level function receives a
dense-slot lookup. The argument path is constructed only after a non-null lookup.
A pre-existing tear-off therefore enters the same guarded callee as a direct call.

The overlay also emits `source-map.json`, a deterministic insertion-aware v1 map
between generated and original UTF-16 source offsets. It distinguishes copied text
from synthetic imports, guards, and initialization. This proves offset bookkeeping
only; mapping symbolized AOT or Flutter stack traces remains unproven.

Task 16 additionally proves an opt-in, ordinary `StatelessWidget.build` guard.
Build context stays on the host; interpreted code returns a bounded node
description which an immutable application-owned registry turns into real Flutter
widgets. The demonstrated surface is deliberately limited to Column, Text,
TextStyle.fontSize, and a disabled ElevatedButton. It is not arbitrary Flutter.

Run from this directory:

```sh
dart pub get
dart run bin/e0.dart overlay fixture/release_app.dart .dart_tool/e0
dart run bin/e0.dart compile-patch fixture/patch_app.dart .dart_tool/e0
dart compile exe fixture/release_app.dart -o .dart_tool/e0/baseline
dart compile exe .dart_tool/e0/app.dart -o .dart_tool/e0/instrumented
.dart_tool/e0/instrumented --e0-patch=.dart_tool/e0/patch.e0.json
dart run tool/benchmark.dart 5000000
```

The patch source is normal Dart. The experimental compiler supports only integer
literals, two arguments, `+`, `-`, `*`, `<`, `==`, `if` without `else`, and
`return`. Unsupported syntax fails closed.
