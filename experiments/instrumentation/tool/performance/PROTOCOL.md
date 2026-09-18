# Task 22 host performance protocol

Predeclared: 2026-08-22, before running the Task 22 measurement harness.

## Scope and acceptance gates

The only acceptance gate is inherited from Task 08: for the synchronous hot-leaf
workload, instrumented/unpatched dispatch must add no more than 10 ns per call and
must take no more than 5x the stock-AOT time. Both limits must pass using the
median of process-isolated samples. Patched/interpreted, startup, RSS, artifact
size, lookup, activation, typed, control, instance, and async measurements are
reporting-only. No threshold will be invented after observing results.

No physical-device work is in scope. Results describe this host and Dart SDK only.

## Host AOT execution matrix

The primary hot-leaf fixture uses 10,000,000 calls per process and four variants:

1. stock AOT;
2. instrumented AOT with no installed patch;
3. instrumented AOT with an unrelated slot patched while the measured leaf is
   unpatched;
4. instrumented AOT with the measured leaf patched/interpreted.

Each variant receives two untimed process warm-ups followed by 15 timed,
process-isolated samples. Timed variant order is deterministically randomized by
sample round with seed `22082601`; raw order is retained. The checksum printed by
each executable must match the expected checksum for its semantic variant.
Elapsed time is measured inside the process around the call loop, excluding
process startup and patch file loading.

Representative typed, control-flow/collection, instance-method, and async
workloads use the same 2-warm-up/15-sample process protocol when practical.
Synchronous workload iteration counts are selected so a stock sample is long
enough to rise above timer granularity without making the full matrix excessive.
Async uses 10,000 sequential calls because Future scheduling dominates. Any
reduction is recorded in raw output and the report with the resource reason.

For each variant the report records all raw samples plus median, p95 (nearest-rank),
and median absolute deviation. Nanoseconds per invocation and ratios are derived
from the unrounded duration values. No outliers are discarded.

## Lookup, activation, artifacts, startup, and memory

Dense lookup hit and miss are measured in an AOT microbenchmark at 10,000,000
operations per process with the same sampling protocol. Direct-table, cached-flag,
or generation alternatives are measured only if a safe implementation is present;
measurement alone does not authorize adopting an optimization.

Activation timing separates read, Ed25519 signature verification, container
decode/compatibility verification, and install where the existing signed E1 path
allows the stages to be observed without changing production semantics. If only
end-to-end activation is reliably exposed, that limitation is reported. Activation
uses 15 process samples after two warm-ups.

Executable, patch-container, and signed-envelope sizes are exact byte counts.
Startup is external wall-clock time to a machine-readable ready marker. Peak RSS
uses the host's process resource accounting only if its units and child-process
scope can be established; otherwise it is omitted rather than mislabeled. Startup
and RSS use 15 samples after two warm-ups and are reporting-only.

## Noise and provenance controls

- Check for another Dart/Flutter/compiler process using the same output directory
  before compilation; Task 22 uses its own `.dart_tool/task22_performance` root.
- Compile all compared executables once before sampling and hash every source,
  executable, patch, and signed artifact with SHA-256.
- Record OS, architecture, Dart version, CPU model, logical CPU count, command,
  iteration count, sample order, exit status, output checksum, and UTC timestamps.
- Run samples serially, avoid concurrent builds, and do not perform validation
  builds during timing.
- Persist raw machine-readable JSON. The Markdown report is generated or copied
  from that immutable raw result; historical Task 08 figures are not rewritten.

## Selective instrumentation policy under test

- Application-owned libraries are selected by default.
- Local-path and hosted pure-Dart dependencies require explicit package opt-in.
- Generated sources are excluded by default even inside selected packages.
- Dart SDK and Flutter framework libraries are hard exclusions.
- A unit importing `dart:ffi` or Flutter APIs is a native/framework boundary and
  is rejected, not silently transformed.
- Explicit file exclusions take precedence over application default or package
  opt-in. The experiment remains source-unit explicit; it does not infer a
  transitive build graph.

The policy tests must cover application default inclusion, unselected dependency
exclusion, local and hosted opt-in, explicit exclude precedence, generated default
exclusion, and hard SDK/Flutter/FFI boundaries.

## Amendment 1 — provenance-hardened replacement run

Predeclared: 2026-08-22T02:57:23Z, after independent review of the first raw
results and before executing their replacements. This section is additive; it
does not alter the original gate, workloads, sample counts, statistics, seeds, or
selection policy above. The first raw-result SHA-256 values remain preserved in
Task 22 history.

The replacement run uses raw schema version 2 and adds these controls:

- Both benchmark scratch roots have an exclusive lock and reject a competing
  Dart/Flutter compiler or Task 22 worker before deleting or compiling in them.
- Every build and sampled process records its executable and argument vector,
  exit status, and UTC start/completion timestamps. Warm-ups remain untimed and
  are validated but are not retained as statistical samples.
- Provenance inventories hash the benchmark harnesses, workers, fixture inputs,
  package manifests/locks/configuration, and all Dart sources under the relevant
  instrumentation and patch-loading `lib/` trees. Generated overlays,
  manifests, executables, patches, and signed envelopes retain exact byte counts
  and SHA-256 hashes.
- Host workload and lookup outputs, plus every activation-stage output, must
  match independently derived expected checksums before a sample is accepted.
- Startup is described as external wall time to process completion. The
  executable emits one machine-readable line immediately before exit, but that
  line is not independently timestamped as a ready marker.
- Dense-lookup results remain optimizer-sensitive loop diagnostics. They are not
  represented as a proven non-elided standalone lookup cost; the unrelated-slot
  hot-leaf variant remains the end-to-end active-table miss evidence.
