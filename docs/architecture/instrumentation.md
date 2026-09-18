# Instrumentation architecture

Status: Phase 1A implementation baseline.

Instrumentation operates on an ephemeral source overlay. Developer-owned Dart
files are read, analyzed, and copied to a temporary output tree. Selected
declarations receive an entry guard and a release manifest record; the original
source is never rewritten in place.

The generated guard is callee-entry dispatch, so direct calls, virtual calls,
and existing tear-offs reach the same release slot. The empty-slot branch
executes the original AOT body. The patched branch boxes only the bounded
arguments required for the active program.

The current transformer is `E0SourceTransformer` and
`E0OverlayBuilder` in `experiments/instrumentation/lib/src/transformer.dart`.
The Phase 1 package seam separates source instrumentation from the runtime and
patch protocol while retaining the transformer as the implementation adapter
during this transition.

Phase 1B adds `cli/lib/src/discovery.dart` and
`cli/lib/src/instrumentation.dart`. They select files from the resolved project
graph, run the transformer without explicit experiment source units, retain
logical source records, and apply generated source only inside a temporary
release-build overlay. The checked-out source remains unchanged.

## Selection rules in Phase 1A

- application Dart is the default candidate set;
- explicitly selected local pure-Dart packages may participate;
- Dart SDK, Flutter SDK, native plugin boundaries, FFI, platform views, and
  generated/native bindings are skipped or diagnosed unless a later policy
  explicitly supports them;
- every skipped candidate is represented in diagnostics or the baseline, never
  silently omitted from a requested patch.

## Source mapping

The overlay records generated-to-original offset segments. Diagnostics resolve
through the logical package URI and original source offsets, never exposing an
absolute build-machine path. Synthetic guard text is identified separately so
runtime failures can report the guest function and source location.

## Upgrade risk

The transformer depends on analyzer AST shape and Flutter/Dart source/build
conventions. The supported Flutter/Dart range is therefore recorded with each
baseline and tested explicitly. A source-overlay break is a compatibility
failure, not a reason to silently broaden patch behavior.
