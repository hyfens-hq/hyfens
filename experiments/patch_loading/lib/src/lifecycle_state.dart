import 'dart:async';

/// Durable lifecycle states exposed by the E1 controller.
///
/// [failed] is an in-memory recovery barrier. It is never written as a
/// lifecycle record because a failed record cannot be trusted as an authority
/// for either executable code or the anti-replay high-water.
enum E1LifecycleState { base, candidate, current, failed }

/// Durable I/O points that tests may fault deterministically.
///
/// These hooks are deliberately controller-local. They do not represent a
/// production crash API or a second persistence protocol.
enum E1DurableBoundary {
  beforeArtifactWrite,
  afterArtifactFlush,
  beforeArtifactRename,
  afterArtifactRename,
  beforeStateCopyWrite,
  afterStateCopyFlush,
  beforeStateCopyRename,
  afterStateCopyRename,
  afterStateCopyReadback,
}

typedef E1DurableBoundaryHook = FutureOr<void> Function(
  E1DurableBoundary boundary,
  String name,
  int generation,
);

/// Shared lifecycle invariants kept separate from filesystem and runtime I/O.
final class E1LifecycleInvariant {
  const E1LifecycleInvariant._();

  /// A pending candidate receives one durable runtime-publish attempt.
  ///
  /// Startup never retries an unconfirmed candidate. It selects the verified
  /// last-known-good or base instead, which bounds a candidate boot loop to a
  /// single process attempt.
  static const int maxCandidateBootAttempts = 1;

  static void validateRecord({
    required E1LifecycleState state,
    required int generation,
    required int highWaterSequence,
    required String? highWaterDigest,
    required String? current,
    required String? lastKnownGood,
    required int candidateBootAttempts,
    required bool Function(String reference) isValidReference,
  }) {
    if (generation < 0) {
      throw const FormatException('state generation is invalid');
    }
    validateHighWater(sequence: highWaterSequence, digest: highWaterDigest);
    if ((current != null || lastKnownGood != null) && highWaterSequence == 0) {
      throw const FormatException(
        'patch references require a positive durable high-water',
      );
    }
    if (current != null && !isValidReference(current)) {
      throw const FormatException('current patch reference is invalid');
    }
    if (lastKnownGood != null && !isValidReference(lastKnownGood)) {
      throw const FormatException('last-known-good patch reference is invalid');
    }
    if (current != null && current == lastKnownGood) {
      throw const FormatException(
        'current and last-known-good must be distinct references',
      );
    }
    if (candidateBootAttempts < 0 ||
        candidateBootAttempts > maxCandidateBootAttempts) {
      throw const FormatException('candidate boot-attempt bound is invalid');
    }

    switch (state) {
      case E1LifecycleState.base:
        if (current != null ||
            lastKnownGood != null ||
            candidateBootAttempts != 0) {
          throw const FormatException('base lifecycle invariants violated');
        }
      case E1LifecycleState.candidate:
        if (current == null ||
            candidateBootAttempts != maxCandidateBootAttempts) {
          throw const FormatException(
            'candidate lifecycle invariants violated',
          );
        }
      case E1LifecycleState.current:
        if (current == null || candidateBootAttempts != 0) {
          throw const FormatException('current lifecycle invariants violated');
        }
      case E1LifecycleState.failed:
        throw const FormatException('failed is not a durable lifecycle state');
    }
  }

  static void validateHighWater({
    required int sequence,
    required String? digest,
  }) {
    if (sequence < 0 ||
        (sequence == 0) != (digest == null) ||
        (digest != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest))) {
      throw const FormatException('durable high-water is invalid');
    }
  }

  /// Returns whether [newer] can follow [older] without replay regression.
  ///
  /// Rollback and recovery may change the executable target while retaining
  /// the same high-water. They may never lower its sequence or replace the
  /// digest at an equal sequence.
  static bool isHighWaterMonotonic({
    required int olderSequence,
    required String? olderDigest,
    required int newerSequence,
    required String? newerDigest,
  }) {
    if (newerSequence < olderSequence) return false;
    if (newerSequence == olderSequence && newerDigest != olderDigest) {
      return false;
    }
    return true;
  }
}
