import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:hyfens_runtime/runtime.dart';
import 'package:instrumentation_e0/e0_runtime.dart';

export 'controller_receipt.dart';
export 'lifecycle_state.dart';

import 'controller_receipt.dart';
import 'key_lifecycle.dart';
import 'lifecycle_state.dart';
import 'rollback_control.dart';
import 'signed_patch.dart';

enum E1PatchMode { base, patch }

final class E1PatchStatus {
  const E1PatchStatus({
    required this.phase,
    required this.mode,
    required this.detail,
    this.patchBytes,
    this.downloadMicros,
    this.verificationMicros,
    this.loadMicros,
  });
  final String phase;
  final E1PatchMode mode;
  final String detail;
  final int? patchBytes;
  final int? downloadMicros;
  final int? verificationMicros;
  final int? loadMicros;
  Map<String, Object?> toJson() => <String, Object?>{
    'phase': phase,
    'mode': mode.name,
    'detail': detail,
    'patchBytes': patchBytes,
    'downloadMicros': downloadMicros,
    'verificationMicros': verificationMicros,
    'loadMicros': loadMicros,
  };
}

/// The single durable lifecycle/trust view selected by the controller.
///
/// The view is a projection of one checksummed journal record. It is exposed
/// for host diagnostics and tests; callers cannot mutate either trust state or
/// replay metadata through it.
final class E1ControllerDurableState {
  const E1ControllerDurableState({
    required this.appId,
    required this.releaseId,
    required this.generation,
    required this.trustGeneration,
    required this.highWaterSequence,
    required this.highWaterDigest,
    required this.current,
    required this.health,
    required this.lastKnownGood,
    required this.candidateBootAttempts,
    required this.trustState,
    required this.replayLedger,
  });

  final String appId;
  final String releaseId;
  final int generation;
  final int trustGeneration;
  final int highWaterSequence;
  final String? highWaterDigest;
  final String? current;
  final String health;
  final String? lastKnownGood;
  final int candidateBootAttempts;
  final E1KeyLifecycleState trustState;
  final E1ArtifactReplayLedger replayLedger;
}

typedef E1LogSink = void Function(String message);

/// Immutable host authority selected by the compiled release.
///
/// Runtime resets remove installed guest code and configured authority. The E1
/// controller reapplies these exact host-owned objects after every reset;
/// downloaded patch bytes cannot add capabilities or widget constructors.
final class E1RuntimeConfiguration {
  const E1RuntimeConfiguration({this.capabilities, this.widgetFactories});

  final E0CapabilityAuthority? capabilities;
  final E0WidgetFactoryRegistry? widgetFactories;
}

/// Deterministic failure/barrier seams used only by filesystem/concurrency tests.
final class E1PatchControllerTestHooks {
  const E1PatchControllerTestHooks({
    this.afterInputCopy,
    this.beforeRuntimePublish,
    this.beforeStateCopyWrite,
    this.durableBoundary,
  });
  final Future<void> Function()? afterInputCopy;
  final Future<void> Function()? beforeRuntimePublish;
  final Future<void> Function(String copyName, int generation)?
  beforeStateCopyWrite;
  final E1DurableBoundaryHook? durableBoundary;
}

final class E1PatchController {
  E1PatchController({
    required this.storageDirectory,
    required this.appId,
    required this.releaseId,
    required this.buildFingerprint,
    required this.functions,
    required this.signatures,
    required this.receivers,
    required this.patchUri,
    required Map<String, E1TrustedPublicKey> trustedPublicKeys,
    E1KeyLifecycleState? initialTrustState,
    this.runtimeConfiguration = const E1RuntimeConfiguration(),
    E1LogSink? log,
    this.testHooks,
    DateTime Function()? clock,
  }) : trustedPublicKeys = Map.unmodifiable(trustedPublicKeys),
       _log = log ?? print,
       _clock = clock ?? (() => DateTime.now().toUtc()) {
    _initialTrustState =
        initialTrustState ??
        _legacyTrustBaseline(
          appId: appId,
          releaseId: releaseId,
          trustedPublicKeys: trustedPublicKeys,
        );
    _trustState = _initialTrustState;
    _durableState = _PersistentState.base(
      appId: appId,
      releaseId: releaseId,
      trustState: _initialTrustState,
    );
    if (_initialTrustState.applicationId != appId ||
        _initialTrustState.releaseId != releaseId ||
        _initialTrustState.commandSequence != 0) {
      throw ArgumentError(
        'Initial trust state must be a sequence-zero state bound to this release',
      );
    }
    for (final entry in this.trustedPublicKeys.entries) {
      final lifecycleKey = _initialTrustState[entry.key];
      if (lifecycleKey == null ||
          !_equalBytes(lifecycleKey.publicKeyBytes, entry.value.bytes)) {
        throw ArgumentError(
          'Initial trust state and trusted public keys disagree for ${entry.key}',
        );
      }
    }
    if (this.trustedPublicKeys.isEmpty ||
        this.trustedPublicKeys.entries.any(
          (entry) => entry.key != entry.value.keyId,
        )) {
      throw ArgumentError('Trusted keys must be non-empty and keyed by keyId');
    }
  }

  static const _statePrimary = 'state-v3-a.json';
  static const _stateBackup = 'state-v3-b.json';
  static const int maxInstallReceiptOutbox = 128;
  static E1PatchController? _runtimeOwner;
  final Directory storageDirectory;
  final String appId;
  final String releaseId;
  final String buildFingerprint;
  final Map<String, int> functions;
  final Map<String, String> signatures;
  final Map<String, String> receivers;
  final Uri patchUri;
  final Map<String, E1TrustedPublicKey> trustedPublicKeys;
  final E1RuntimeConfiguration runtimeConfiguration;
  final E1LogSink _log;
  final E1PatchControllerTestHooks? testHooks;
  final DateTime Function() _clock;
  late final E1KeyLifecycleState _initialTrustState;
  late E1KeyLifecycleState _trustState;
  late _PersistentState _durableState;
  final _statusEvents = StreamController<E1PatchStatus>.broadcast(sync: true);
  Future<void> _operationTail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closing = false;
  bool _recoveryNeeded = false;
  bool _runtimeLeaseHeld = false;
  E1LifecycleState _lifecycleState = E1LifecycleState.base;
  E1PatchStatus _status = const E1PatchStatus(
    phase: 'created',
    mode: E1PatchMode.base,
    detail: 'not initialized',
  );

  E1PatchStatus get status => _status;
  Stream<E1PatchStatus> get statuses => _statusEvents.stream;
  bool get recoveryNeeded => _recoveryNeeded;
  E1KeyLifecycleState get trustState => _trustState;
  int get trustGeneration => _trustState.commandSequence;
  E1ControllerDurableState get durableState => _durableState.toPublicView();
  List<E1InstallReceiptContext> get pendingInstallReceipts =>
      List<E1InstallReceiptContext>.unmodifiable(
        _durableState.installReceiptOutbox,
      );
  E1LifecycleState get lifecycleState =>
      _recoveryNeeded ? E1LifecycleState.failed : _lifecycleState;

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    if (_closing) {
      return Future<T>.error(StateError('E1 patch controller is closed'));
    }
    final scheduled = _operationTail.then<T>((_) => operation());
    _operationTail = scheduled.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return scheduled;
  }

  Future<void> initialize() => _enqueue(_initialize);

  Future<void> _initialize() async {
    if (_recoveryNeeded) return;
    _acquireRuntimeLease();
    final watch = Stopwatch()..start();
    await storageDirectory.create(recursive: true);
    _resetRuntime();
    final loaded = await _loadState();
    if (loaded.recoveryNeeded) {
      _recoveryNeeded = true;
      _lifecycleState = E1LifecycleState.failed;
      _emit(
        E1PatchStatus(
          phase: 'recoveryNeeded',
          mode: E1PatchMode.base,
          detail: loaded.detail,
          loadMicros: watch.elapsedMicroseconds,
        ),
      );
      return;
    }
    var state = loaded.state!;
    _recoveryNeeded = false;
    _adoptState(state);
    if (state.legacy) {
      try {
        state = await _upgradeLegacyState(state);
        await _repairStateCopies(state);
      } on Object catch (error) {
        _recoveryNeeded = true;
        _lifecycleState = E1LifecycleState.failed;
        _emit(
          E1PatchStatus(
            phase: 'recoveryNeeded',
            mode: E1PatchMode.base,
            detail:
                'legacy durable state upgrade failed; activation is locked: $error',
            loadMicros: watch.elapsedMicroseconds,
          ),
        );
        return;
      }
      _adoptState(state);
    } else if (loaded.needsRepair) {
      state = state.copyWith(formatVersion: _PersistentState.currentVersion);
      try {
        await _repairStateCopies(state);
      } on Object catch (error) {
        _recoveryNeeded = true;
        _lifecycleState = E1LifecycleState.failed;
        _emit(
          E1PatchStatus(
            phase: 'recoveryNeeded',
            mode: E1PatchMode.base,
            detail: 'durable state repair failed; activation is locked: $error',
            loadMicros: watch.elapsedMicroseconds,
          ),
        );
        return;
      }
      _adoptState(state);
    }

    if (state.health == _PatchHealth.pending) {
      final pendingReceipt = state.pendingInstallReceipt;
      if (pendingReceipt != null && !_receiptDeadlineIsFuture(pendingReceipt)) {
        _log(
          'E1_PATCH expired pending install receipt; '
          'unconfirmed candidate will not be booted',
        );
      }
      final fallback = state.lastKnownGood == null
          ? null
          : await _readAndValidate(state.lastKnownGood!, state);
      try {
        if (fallback != null && _installStoredAfterReset(fallback)) {
          state = await _commitState(
            state.copyWith(
              current: state.lastKnownGood,
              health: _PatchHealth.healthy,
              clearLastKnownGood: true,
              candidateBootAttempts: 0,
              replayLedger: state.replayLedger.selectActiveArtifact(
                _digestFromPatchReference(state.lastKnownGood!),
              ),
              clearPendingInstallReceipt: true,
            ),
          );
          _adoptState(state);
          _emit(
            E1PatchStatus(
              phase: 'fallback',
              mode: E1PatchMode.patch,
              detail: 'unconfirmed candidate rolled back to last-known-good',
              patchBytes: fallback.artifactBytes.length,
              loadMicros: watch.elapsedMicroseconds,
            ),
          );
        } else {
          _resetRuntime();
          state = await _commitState(
            state.copyWith(
              clearCurrent: true,
              health: _PatchHealth.base,
              clearLastKnownGood: true,
              candidateBootAttempts: 0,
              replayLedger: state.replayLedger.rollbackToBase(),
              clearPendingInstallReceipt: true,
            ),
          );
          _adoptState(state);
          _emit(
            E1PatchStatus(
              phase: 'fallback',
              mode: E1PatchMode.base,
              detail: 'unconfirmed candidate rolled back to base; high-water retained',
              loadMicros: watch.elapsedMicroseconds,
            ),
          );
        }
      } on Object catch (error) {
        await _failClosedPendingInitialization(state, error);
      }
      return;
    }
    if (state.current == null) {
      _adoptState(state);
      _emit(
        E1PatchStatus(
          phase: 'healthy',
          mode: E1PatchMode.base,
          detail: 'base AOT active',
          loadMicros: watch.elapsedMicroseconds,
        ),
      );
      return;
    }
    final current = await _readAndValidate(state.current!, state);
    if (current != null && _installStored(current)) {
      _adoptState(state);
      _emit(
        E1PatchStatus(
          phase: 'healthy',
          mode: E1PatchMode.patch,
          detail: 'current healthy signed patch active',
          patchBytes: current.artifactBytes.length,
          loadMicros: watch.elapsedMicroseconds,
        ),
      );
      return;
    }
    await _recoverState(state, 'invalid current recovered');
  }

  Future<bool> downloadAndActivate({Uri? uri}) => _enqueue(() async {
    final watch = Stopwatch()..start();
    try {
      final bytes = await _download(uri ?? patchUri);
      watch.stop();
      return await _activateBytes(
        Uint8List.fromList(bytes),
        downloadMicros: watch.elapsedMicroseconds,
      );
    } on Object catch (error) {
      _reject(
        'download failed: $error',
        downloadMicros: watch.elapsedMicroseconds,
      );
      return false;
    }
  });

  Future<bool> activateBytes(
    List<int> envelopeBytes, {
    int? downloadMicros,
    E1InstallReceiptContext? receiptContext,
  }) {
    // Copy synchronously, before the first await or queue delay.
    final immutableInput = Uint8List.fromList(envelopeBytes);
    return _enqueue(
      () => _activateBytes(
        immutableInput,
        downloadMicros: downloadMicros,
        receiptContext: receiptContext,
      ),
    );
  }

  /// Removes one receipt after the owning server has acknowledged it.
  ///
  /// The controller performs no transport or acknowledgement itself. An
  /// unknown ID is a durable no-op and returns false.
  Future<bool> ackInstallReceipt(String receiptId) => _enqueue(() async {
    if (_recoveryNeeded) {
      return _recoveryLocked(
        'receipt acknowledgement locked: controller recovery is required',
      );
    }
    final loaded = await _loadState();
    if (loaded.recoveryNeeded) {
      _recoveryNeeded = true;
      _lifecycleState = E1LifecycleState.failed;
      _reject('receipt acknowledgement locked: ${loaded.detail}');
      return false;
    }
    var state = loaded.state!;
    if (loaded.needsRepair) {
      state = state.copyWith(formatVersion: _PersistentState.currentVersion);
      try {
        await _repairStateCopies(state);
      } on Object catch (error) {
        _recoveryNeeded = true;
        _lifecycleState = E1LifecycleState.failed;
        _reject(
          'receipt acknowledgement locked: durable state repair failed: $error',
        );
        return false;
      }
    }
    _adoptState(state);
    final index = state.installReceiptOutbox.indexWhere(
      (receipt) => receipt.receiptId == receiptId,
    );
    if (index < 0) return false;
    final nextOutbox = List<E1InstallReceiptContext>.of(
      state.installReceiptOutbox,
    )..removeAt(index);
    final committed = await _commitState(
      state.copyWith(installReceiptOutbox: nextOutbox),
    );
    _adoptState(committed);
    return true;
  });

  Future<bool> _activateBytes(
    Uint8List envelopeBytes, {
    int? downloadMicros,
    E1InstallReceiptContext? receiptContext,
  }) async {
    if (_recoveryNeeded) {
      return _recoveryLocked(
        'activation locked: controller recovery is required',
      );
    }
    await testHooks?.afterInputCopy?.call();
    final loaded = await _loadState();
    if (loaded.recoveryNeeded) {
      _recoveryNeeded = true;
      _lifecycleState = E1LifecycleState.failed;
      _reject('activation locked: ${loaded.detail}');
      return false;
    }
    var state = loaded.state!;
    _adoptState(state);
    if (loaded.needsRepair) {
      state = state.copyWith(formatVersion: _PersistentState.currentVersion);
      try {
        await _repairStateCopies(state);
      } on Object catch (error) {
        _recoveryNeeded = true;
        _lifecycleState = E1LifecycleState.failed;
        _reject('activation locked: durable state repair failed: $error');
        return false;
      }
      _adoptState(state);
    }
    final verifyWatch = Stopwatch()..start();
    late _VerifiedRuntimePatch verified;
    try {
      verified = _looksLikePatchFormat(envelopeBytes)
          ? await _verifyPatchFormat(envelopeBytes, state.trustState)
          : await _verifyLegacyEnvelope(envelopeBytes, state.trustState);
    } on Object catch (error) {
      verifyWatch.stop();
      _reject(
        'invalid signed patch rejected: $error',
        patchBytes: envelopeBytes.length,
        downloadMicros: downloadMicros,
        verificationMicros: verifyWatch.elapsedMicroseconds,
      );
      return false;
    }
    verifyWatch.stop();
    return _activateVerified(
      verified,
      state: state,
      downloadMicros: downloadMicros,
      verificationMicros: verifyWatch.elapsedMicroseconds,
      receiptContext: receiptContext,
    );
  }

  Future<bool> _activateVerified(
    _VerifiedRuntimePatch verified, {
    required _PersistentState state,
    int? downloadMicros,
    required int verificationMicros,
    E1InstallReceiptContext? receiptContext,
  }) async {
    final oldState = state;
    _adoptState(oldState);
    if (oldState.health == _PatchHealth.pending) {
      _reject(
        'activation rejected: current candidate still awaits markHealthy',
      );
      return false;
    }
    final stableEnvelope = Uint8List.fromList(verified.artifactBytes);
    final digest = sha256.convert(stableEnvelope).toString();
    E1InstallReceiptContext? boundReceiptContext;
    try {
      boundReceiptContext = _bindReceiptContext(
        receiptContext,
        digest: digest,
        verified: verified,
      );
    } on Object catch (error) {
      _reject('install receipt context rejected: $error');
      return false;
    }
    if (boundReceiptContext != null &&
        !_receiptDeadlineIsFuture(boundReceiptContext)) {
      _reject('install receipt activation deadline expired');
      return false;
    }
    final patchName = verified.patchFormat
        ? 'patch-$digest.v1.patch'
        : 'patch-$digest.e1.signed.json';
    final artifact = E1VerifiedArtifactIdentity(
      keyId: verified.keyId,
      sequence: verified.sequence,
      digest: digest,
    );
    final admission = oldState.replayLedger.admitNewArtifact(
      lifecycle: oldState.trustState,
      artifact: artifact,
    );
    if (admission.status == E1ArtifactAdmissionStatus.idempotent) {
      if (oldState.current != patchName) {
        _reject('signed patch replay rejected: equal sequence is not current');
        return false;
      }
      try {
        await _stageArtifact(patchName, stableEnvelope);
      } on Object catch (error) {
        _reject('idempotent artifact repair failed: $error');
        return false;
      }
      _emit(
        E1PatchStatus(
          phase: 'activated',
          mode: E1PatchMode.patch,
          detail: 'healthy signed patch already active; idempotent artifact verified',
          patchBytes: stableEnvelope.length,
          verificationMicros: verificationMicros,
          loadMicros: 0,
        ),
      );
      return true;
    }
    if (!admission.accepted) {
      _reject('signed patch rejected: ${admission.status.name}');
      return false;
    }
    if (boundReceiptContext != null) {
      if (oldState.installReceiptOutbox.length >=
          E1PatchController.maxInstallReceiptOutbox) {
        _reject('install receipt outbox is full; candidate was not published');
        return false;
      }
      if (_receiptIdIsQueued(oldState, boundReceiptContext.receiptId)) {
        _reject('install receipt ID is already queued');
        return false;
      }
    }

    var pending = oldState;
    try {
      await _stageArtifact(patchName, stableEnvelope);
      pending = await _commitState(
        oldState.copyWith(
          highWaterSequence: verified.sequence,
          highWaterDigest: digest,
          current: patchName,
          health: _PatchHealth.pending,
          lastKnownGood: oldState.current,
          candidateBootAttempts: E1LifecycleInvariant.maxCandidateBootAttempts,
          replayLedger: admission.ledger,
          pendingInstallReceipt: boundReceiptContext,
          clearPendingInstallReceipt: boundReceiptContext == null,
        ),
      );
      _adoptState(pending);
      await testHooks?.beforeRuntimePublish?.call();
      final loadWatch = Stopwatch()..start();
      if (!_installVerified(verified)) {
        throw StateError(
          E0PatchRuntime.lastRejection ?? 'runtime install failed',
        );
      }
      loadWatch.stop();
      _emit(
        E1PatchStatus(
          phase: 'pendingHealth',
          mode: E1PatchMode.patch,
          detail: 'authenticated candidate published; markHealthy required',
          patchBytes: stableEnvelope.length,
          downloadMicros: downloadMicros,
          verificationMicros: verificationMicros,
          loadMicros: loadWatch.elapsedMicroseconds,
        ),
      );
      return true;
    } on Object catch (error) {
      final newest = await _loadState();
      if (!newest.recoveryNeeded) pending = newest.state!;
      await _commitState(oldState.copyWith(generation: pending.generation));
      _adoptState(oldState);
      _reject('activation failed; prior state retained: $error');
      return false;
    }
  }

  Future<bool> markHealthy() => _enqueue(() async {
    if (_recoveryNeeded) {
      return _recoveryLocked(
        'health confirmation locked: controller recovery is required',
      );
    }
    final loaded = await _loadState();
    if (loaded.recoveryNeeded) {
      _lifecycleState = E1LifecycleState.failed;
      _reject('health confirmation locked: ${loaded.detail}');
      return false;
    }
    final state = loaded.state!;
    _adoptState(state);
    if (state.health != _PatchHealth.pending || state.current == null) {
      _reject('health confirmation rejected: no pending candidate');
      return false;
    }
    final pendingReceipt = state.pendingInstallReceipt;
    if (pendingReceipt != null && !_receiptDeadlineIsFuture(pendingReceipt)) {
      await _recoverState(
        state,
        'pending install receipt activation deadline expired',
      );
      return false;
    }
    final nextOutbox = List<E1InstallReceiptContext>.of(
      state.installReceiptOutbox,
    );
    if (pendingReceipt != null) nextOutbox.add(pendingReceipt);
    final committed = await _commitState(
      state.copyWith(
        health: _PatchHealth.healthy,
        candidateBootAttempts: 0,
        clearPendingInstallReceipt: true,
        installReceiptOutbox: nextOutbox,
      ),
    );
    _adoptState(committed);
    _emit(
      const E1PatchStatus(
        phase: 'healthy',
        mode: E1PatchMode.patch,
        detail: 'current candidate confirmed healthy',
      ),
    );
    return true;
  });

  Future<bool> recoverFromRuntimeException([Object? error]) =>
      _enqueue(() async {
        if (_recoveryNeeded) {
          return _recoveryLocked(
            'runtime recovery locked: controller recovery is required',
          );
        }
        final loaded = await _loadState();
        if (loaded.recoveryNeeded) {
          _resetRuntime();
          _lifecycleState = E1LifecycleState.failed;
          _reject('runtime recovery requires durable-state repair');
          return false;
        }
        return _recoverState(loaded.state!, 'runtime exception: $error');
      });

  Future<bool> _recoverState(_PersistentState state, String reason) async {
    _adoptState(state);
    final fallback = state.lastKnownGood == null
        ? null
        : await _readAndValidate(state.lastKnownGood!, state);
    var resetSucceeded = false;
    try {
      _resetRuntime();
      resetSucceeded = true;
      if (fallback == null) {
        final committed = await _commitState(
          state.copyWith(
            clearCurrent: true,
            health: _PatchHealth.base,
            clearLastKnownGood: true,
            candidateBootAttempts: 0,
            replayLedger: state.replayLedger.rollbackToBase(),
            clearPendingInstallReceipt: true,
          ),
        );
        _adoptState(committed);
        _emit(
          E1PatchStatus(
            phase: 'fallback',
            mode: E1PatchMode.base,
            detail: '$reason; base active and high-water retained',
          ),
        );
        return true;
      }
      if (!_installStored(fallback)) {
        throw StateError(
          E0PatchRuntime.lastRejection ?? 'last-known-good install failed',
        );
      }
      final committed = await _commitState(
        state.copyWith(
          current: state.lastKnownGood,
          health: _PatchHealth.healthy,
          clearLastKnownGood: true,
          candidateBootAttempts: 0,
          replayLedger: state.replayLedger.selectActiveArtifact(
            _digestFromPatchReference(state.lastKnownGood!),
          ),
          clearPendingInstallReceipt: true,
        ),
      );
      _adoptState(committed);
      _emit(
        E1PatchStatus(
          phase: 'fallback',
          mode: E1PatchMode.patch,
          detail: '$reason; last-known-good active and high-water retained',
        ),
      );
      return true;
    } on Object catch (error) {
      if (!resetSucceeded) {
        _reject('$reason; recovery could not reset runtime: $error');
        return false;
      }
      return _restorePriorAfterTransitionFailure(
        state,
        error,
        '$reason; recovery failed',
      );
    }
  }

  /// Applies a signed developer rollback command without lowering the
  /// authenticated patch high-water.
  ///
  /// The command is a lifecycle control message, not a Patch Format v1
  /// artifact. It must match the release-owned key, application/release
  /// identity, and the exact high-water currently stored by this controller.
  Future<bool> applyRollbackControl(
    List<int> commandBytes,
  ) => _enqueue(() async {
    if (_recoveryNeeded) {
      return _recoveryLocked(
        'signed base rollback locked: controller recovery is required',
      );
    }
    late final RollbackControlCommand command;
    try {
      command = RollbackControlCommand.decode(commandBytes);
      if (command.applicationId != appId || command.releaseId != releaseId) {
        throw const FormatException(
          'rollback control is bound to another release',
        );
      }
    } on Object catch (error) {
      _reject('signed base rollback rejected: $error');
      return false;
    }
    final loaded = await _loadState();
    if (loaded.recoveryNeeded) {
      _lifecycleState = E1LifecycleState.failed;
      _reject('signed base rollback unavailable: ${loaded.detail}');
      return false;
    }
    final state = loaded.state!;
    _adoptState(state);
    final rollbackKey = state.trustState[command.keyId];
    if (rollbackKey == null ||
        rollbackKey.state != E1ReleaseKeyState.active ||
        !rollbackKey.roles.contains(E1ReleaseKeyRole.rollback) ||
        !await command.verify(rollbackKey.publicKeyBytes)) {
      _reject('signed base rollback rejected: rollback key is not authorized');
      return false;
    }
    if (state.highWaterSequence != command.highWaterSequence ||
        state.highWaterDigest != command.highWaterDigest) {
      _reject(
        'signed base rollback rejected: high-water does not match durable state',
      );
      return false;
    }
    return _rollbackLoadedState(state, 'signed developer rollback to base AOT');
  });

  Future<bool> rollback() => _enqueue(() async {
    if (_recoveryNeeded) {
      return _recoveryLocked(
        'base rollback locked: controller recovery is required',
      );
    }
    final loaded = await _loadState();
    if (loaded.recoveryNeeded) {
      _lifecycleState = E1LifecycleState.failed;
      _reject('base rollback unavailable: ${loaded.detail}');
      return false;
    }
    final state = loaded.state!;
    _adoptState(state);
    return _rollbackLoadedState(state, 'manual rollback to base AOT');
  });

  Future<bool> _rollbackLoadedState(
    _PersistentState state,
    String detail,
  ) async {
    var resetSucceeded = false;
    try {
      // reset() checks active-continuation eligibility before mutating runtime
      // state. Publish base durably only after that check and reset succeed.
      _resetRuntime();
      resetSucceeded = true;
      final committed = await _commitState(
        state.copyWith(
          clearCurrent: true,
          health: _PatchHealth.base,
          clearLastKnownGood: true,
          candidateBootAttempts: 0,
          replayLedger: state.replayLedger.rollbackToBase(),
          clearPendingInstallReceipt: true,
        ),
      );
      _adoptState(committed);
      _emit(
        E1PatchStatus(
          phase: 'rolledBack',
          mode: E1PatchMode.base,
          detail: '$detail; high-water retained',
        ),
      );
      return true;
    } on Object catch (error) {
      if (resetSucceeded) {
        return _restorePriorAfterTransitionFailure(
          state,
          error,
          'base rollback failed',
        );
      }
      _reject('base rollback failed; prior state retained: $error');
      return false;
    }
  }

  /// Applies one authenticated key-lifecycle transition through the same
  /// journal as patch high-water and executable selection.
  ///
  /// A revoked key that currently authenticates the executable or retained
  /// fallback is removed from executable selection in this same durable
  /// transition. The high-water and remembered artifact identities remain.
  Future<bool> applyKeyLifecycleCommand(
    List<int> commandBytes,
  ) => _enqueue(() async {
    if (_recoveryNeeded) {
      return _recoveryLocked(
        'key lifecycle transition locked: controller recovery is required',
      );
    }
    final loaded = await _loadState();
    if (loaded.recoveryNeeded) {
      _lifecycleState = E1LifecycleState.failed;
      _recoveryNeeded = true;
      _reject('key lifecycle transition unavailable: ${loaded.detail}');
      return false;
    }
    var state = loaded.state!;
    _adoptState(state);
    if (loaded.needsRepair) {
      state = state.copyWith(formatVersion: _PersistentState.currentVersion);
      try {
        await _repairStateCopies(state);
      } on Object catch (error) {
        _recoveryNeeded = true;
        _lifecycleState = E1LifecycleState.failed;
        _reject('key lifecycle repair failed; activation is locked: $error');
        return false;
      }
      _adoptState(state);
    }

    late final E1KeyLifecycleCommand command;
    late final E1KeyLifecycleState nextTrust;
    try {
      command = E1KeyLifecycleCommand.decode(commandBytes);
      nextTrust = await state.trustState.apply(commandBytes);
    } on Object catch (error) {
      _reject('key lifecycle transition rejected: $error');
      return false;
    }

    var desired = state.copyWith(
      trustState: nextTrust,
      trustGeneration: nextTrust.commandSequence,
    );
    if (command.operation == E1KeyLifecycleOperation.revoke ||
        command.operation == E1KeyLifecycleOperation.recover) {
      desired = _removeRevokedExecutableSelection(
        desired,
        command.targetKeyId!,
      );
    }

    var resetSucceeded = false;
    try {
      if (desired.lifecycleState != state.lifecycleState ||
          desired.current != state.current) {
        _resetRuntime();
        resetSucceeded = true;
      }
      final committed = await _commitState(desired);
      if (desired.lifecycleState != state.lifecycleState ||
          desired.current != state.current) {
        // The durable record is already base/current-consistent. A
        // revoked current artifact is never republished after the trust
        // transition.
        if (committed.current != null) {
          final stored = await _readAndValidate(committed.current!, committed);
          if (stored == null || !_installStored(stored)) {
            throw StateError('committed executable selection failed');
          }
        }
      }
      _adoptState(committed);
      _emit(
        E1PatchStatus(
          phase: 'trustChanged',
          mode: committed.current == null
              ? E1PatchMode.base
              : E1PatchMode.patch,
          detail:
              'key lifecycle ${command.operation.name} committed atomically '
              'with high-water ${committed.highWaterSequence}',
        ),
      );
      return true;
    } on Object catch (error) {
      if (resetSucceeded || desired.current != state.current) {
        return _restorePriorAfterTransitionFailure(
          state,
          error,
          'key lifecycle transition failed',
        );
      }
      _reject('key lifecycle transition failed; prior state retained: $error');
      return false;
    }
  });

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _closing = true;
    final scheduled = _operationTail.then<void>((_) async {
      if (_runtimeLeaseHeld && identical(_runtimeOwner, this)) {
        // Do not leave an active program behind when the lease is released.
        // If reset fails, retain the lease and fail closed rather than
        // allowing a new controller to operate over unknown global state.
        E0PatchRuntime.reset();
        _runtimeLeaseHeld = false;
        _runtimeOwner = null;
      }
      await _statusEvents.close();
    });
    final result = scheduled.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        // A reset can fail while an interpreted continuation is still active.
        // Keep the lease and allow the owner to retry close after the
        // continuation settles; never expose the global runtime to a new
        // controller in an unknown state.
        _closeFuture = null;
        _closing = false;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _operationTail = scheduled.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _closeFuture = result;
    return result;
  }

  Future<List<int>> _download(Uri uri) async {
    if (uri.scheme != 'http' || !_isLocalDevelopmentHost(uri.host)) {
      throw const FormatException(
        'E1 only permits local-development HTTP endpoints',
      );
    }
    final requestUri = await _deliveryUri(uri);
    final client = HttpClient();
    try {
      final request = await client.getUrl(requestUri)
        ..followRedirects = false;
      final response = await request.close();
      if (response.isRedirect) {
        throw const FormatException('patch download redirects are disabled');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: requestUri);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > PatchFormatLimits.maxArtifactBytes) {
          throw const FormatException('download exceeds signed envelope limit');
        }
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<Uri> _deliveryUri(Uri uri) async {
    if (uri.path != '/v1/patch') return uri;
    final loaded = await _loadState();
    final sequence = loaded.state?.highWaterSequence ?? 0;
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'release': releaseId,
        'sequence': '$sequence',
      },
    );
  }

  static bool _isLocalDevelopmentHost(String host) {
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
      return true;
    }
    if (host.endsWith('.local')) return true;
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    if (address.type == InternetAddressType.IPv4) {
      final octets = host.split('.').map(int.parse).toList(growable: false);
      return octets[0] == 10 ||
          (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
          (octets[0] == 192 && octets[1] == 168) ||
          (octets[0] == 169 && octets[1] == 254);
    }
    final normalized = host.toLowerCase();
    return normalized.startsWith('fc') ||
        normalized.startsWith('fd') ||
        normalized.startsWith('fe80:');
  }

  E0PatchProgram _decode(List<int> bytes) => E0PatchContainer.decode(
    bytes,
    expectedAppId: appId,
    expectedReleaseId: releaseId,
    expectedBuildFingerprint: buildFingerprint,
    expectedFunctions: functions,
    expectedSignatures: _decodedSignatures,
    expectedReceivers: _decodedReceivers,
  );

  Future<_VerifiedRuntimePatch> _verifyLegacyEnvelope(
    Uint8List envelopeBytes,
    E1KeyLifecycleState trustState, {
    bool retained = false,
  }) async {
    final verified = await E1SignedPatchEnvelope.verify(
      envelopeBytes: envelopeBytes,
      trustedKeys: _trustedKeysFor(trustState, retained: retained),
    );
    final program = _decode(verified.patchBytes);
    return _VerifiedRuntimePatch(
      artifactBytes: Uint8List.fromList(verified.envelopeBytes),
      programBytes: <Uint8List>[Uint8List.fromList(verified.patchBytes)],
      sequence: program.patchSequence,
      patchFormat: false,
      keyId: verified.keyId,
    );
  }

  Future<_VerifiedRuntimePatch> _verifyPatchFormat(
    Uint8List artifactBytes,
    E1KeyLifecycleState trustState, {
    bool retained = false,
  }) async {
    final artifact = PatchFormatV1.decode(artifactBytes);
    if (artifact.applicationId != appId || artifact.releaseId != releaseId) {
      throw const FormatException('Patch Format artifact is not release-bound');
    }
    if (artifact.runtimeCompatibilityVersion !=
        patchFormatRuntimeCompatibilityV1) {
      throw const FormatException('Incompatible Patch Format runtime version');
    }
    if (artifact.signatureMetadata.algorithm != 'ed25519') {
      throw const FormatException(
        'Unsupported Patch Format signature algorithm',
      );
    }
    final trustedKey = _trustedKeysFor(
      trustState,
      retained: retained,
    )[artifact.signatureMetadata.keyId];
    if (trustedKey == null) {
      throw const FormatException('Patch Format signing key is not trusted');
    }
    final valid = await DartEd25519().verify(
      PatchFormatV1.signingBytes(artifact),
      signature: Signature(
        artifact.signature,
        publicKey: SimplePublicKey(trustedKey.bytes, type: KeyPairType.ed25519),
      ),
    );
    if (!valid) {
      throw const FormatException('Patch Format signature is invalid');
    }
    final bridge = PatchFormatV1E0Bridge.decode(artifact);
    final programBytes = <Uint8List>[];
    int? sequence;
    for (final function in artifact.functions) {
      final bytes = Uint8List.fromList(bridge[function.id]!);
      final program = _decode(bytes);
      if (program.patchSequence != artifact.sequence ||
          (sequence != null && sequence != program.patchSequence)) {
        throw const FormatException(
          'Patch Format sequence does not match E0 bridge sequence',
        );
      }
      sequence = program.patchSequence;
      programBytes.add(bytes);
    }
    if (sequence == null) {
      throw const FormatException('Patch Format artifact has no programs');
    }
    return _VerifiedRuntimePatch(
      artifactBytes: Uint8List.fromList(artifactBytes),
      programBytes: programBytes,
      sequence: sequence,
      patchFormat: true,
      keyId: artifact.signatureMetadata.keyId,
      patchId: artifact.patchId,
    );
  }

  Map<String, E1TrustedPublicKey> _trustedKeysFor(
    E1KeyLifecycleState trustState, {
    required bool retained,
  }) {
    final bytes = retained
        ? trustState.retainedArtifactTrust
        : trustState.activeArtifactTrust;
    return <String, E1TrustedPublicKey>{
      for (final entry in bytes.entries)
        entry.key: E1TrustedPublicKey(keyId: entry.key, bytes: entry.value),
    };
  }

  static bool _looksLikePatchFormat(List<int> bytes) =>
      bytes.length >= PatchFormatV1.magic.length &&
      _equalBytes(
        bytes.take(PatchFormatV1.magic.length).toList(),
        PatchFormatV1.magic,
      );

  bool _install(List<int> bytes) => E0PatchRuntime.installBytes(
    bytes,
    appId: appId,
    releaseId: releaseId,
    buildFingerprint: buildFingerprint,
    functions: functions,
    signatures: signatures,
    receivers: receivers,
  );
  bool _installVerified(_VerifiedRuntimePatch verified) => verified.patchFormat
      ? E0PatchRuntime.installBatchBytes(
          verified.programBytes,
          appId: appId,
          releaseId: releaseId,
          buildFingerprint: buildFingerprint,
          functions: functions,
          signatures: signatures,
          receivers: receivers,
        )
      : _install(verified.programBytes.single);

  bool _installStored(_StoredPatch stored) => stored.patchFormat
      ? E0PatchRuntime.installBatchBytes(
          stored.programBytes,
          appId: appId,
          releaseId: releaseId,
          buildFingerprint: buildFingerprint,
          functions: functions,
          signatures: signatures,
          receivers: receivers,
        )
      : _install(stored.programBytes.single);

  bool _installStoredAfterReset(_StoredPatch stored) {
    _resetRuntime();
    return _installStored(stored);
  }

  void _resetRuntime() {
    E0PatchRuntime.reset();
    if (runtimeConfiguration.capabilities case final capabilities?) {
      E0PatchRuntime.configureCapabilities(capabilities);
    }
    if (runtimeConfiguration.widgetFactories case final widgetFactories?) {
      E0PatchRuntime.configureWidgetFactories(widgetFactories);
    }
  }

  void _acquireRuntimeLease() {
    final owner = _runtimeOwner;
    if (owner != null && !identical(owner, this)) {
      throw StateError(
        'E1 runtime is already owned by another patch controller; '
        'multiple controllers cannot share the process-global runtime',
      );
    }
    _runtimeOwner = this;
    _runtimeLeaseHeld = true;
  }

  Map<String, E0FunctionSignature> get _decodedSignatures =>
      <String, E0FunctionSignature>{
        for (final entry in signatures.entries)
          entry.key: E0FunctionSignature.decode(entry.value),
      };
  Map<String, E0ReceiverDescriptor> get _decodedReceivers =>
      <String, E0ReceiverDescriptor>{
        for (final entry in receivers.entries)
          entry.key: E0ReceiverDescriptor.decode(entry.value),
      };

  Future<void> _stageArtifact(String name, Uint8List bytes) async {
    final target = File('${storageDirectory.path}/$name');
    if (await target.exists()) {
      try {
        if (_equalBytes(await target.readAsBytes(), bytes)) return;
      } on Object {
        // Repair below from the already verified immutable envelope.
      }
    }
    final temporary = File('${target.path}.tmp');
    try {
      await _durableBoundary(E1DurableBoundary.beforeArtifactWrite, name, 0);
      await temporary.writeAsBytes(bytes, flush: true);
      await _durableBoundary(E1DurableBoundary.afterArtifactFlush, name, 0);
      await _durableBoundary(E1DurableBoundary.beforeArtifactRename, name, 0);
      await temporary.rename(target.path);
      await _durableBoundary(E1DurableBoundary.afterArtifactRename, name, 0);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<_StoredPatch?> _readAndValidate(
    String name,
    _PersistentState state, {
    bool enforceLedger = true,
  }) async {
    if (!_validPatchName(name)) return null;
    try {
      final bytes = await File('${storageDirectory.path}/$name').readAsBytes();
      final expected = name.substring(
        'patch-'.length,
        name.length -
            (name.endsWith('.v1.patch')
                ? '.v1.patch'.length
                : '.e1.signed.json'.length),
      );
      if (sha256.convert(bytes).toString() != expected) {
        throw const FormatException(
          'stored envelope digest does not match name',
        );
      }
      final verified = _looksLikePatchFormat(bytes)
          ? await _verifyPatchFormat(
              Uint8List.fromList(bytes),
              state.trustState,
              retained: true,
            )
          : await _verifyLegacyEnvelope(
              Uint8List.fromList(bytes),
              state.trustState,
              retained: true,
            );
      final stored = _StoredPatch(
        artifactBytes: Uint8List.fromList(bytes),
        programBytes: verified.programBytes,
        patchFormat: verified.patchFormat,
        keyId: verified.keyId,
        sequence: verified.sequence,
        digest: expected,
      );
      if (enforceLedger) {
        final identity = E1VerifiedArtifactIdentity(
          keyId: stored.keyId,
          sequence: stored.sequence,
          digest: stored.digest,
        );
        final retained = state.replayLedger.verifyRetainedArtifact(
          lifecycle: state.trustState,
          artifact: identity,
        );
        if (!retained.accepted) {
          throw FormatException(
            'stored artifact is not an authorized retained identity: '
            '${retained.status.name}',
          );
        }
      }
      return stored;
    } on Object catch (error) {
      _log('E1_PATCH rejected stored signed patch: $error');
      return null;
    }
  }

  Future<void> _restoreRuntime(_PersistentState state) async {
    _resetRuntime();
    if (state.current == null) return;
    final stored = await _readAndValidate(state.current!, state);
    if (stored == null) {
      throw StateError('prior current patch is missing or invalid');
    }
    if (!_installStored(stored)) {
      throw StateError(
        E0PatchRuntime.lastRejection ?? 'prior current patch install failed',
      );
    }
  }

  Future<bool> _restorePriorAfterTransitionFailure(
    _PersistentState prior,
    Object transitionError,
    String detail,
  ) async {
    try {
      await _restoreExactState(prior);
      await _restoreRuntime(prior);
      _recoveryNeeded = false;
      _adoptState(prior);
      _reject('$detail; prior state retained: $transitionError');
      return false;
    } on Object catch (restoreError) {
      _recoveryNeeded = true;
      _lifecycleState = E1LifecycleState.failed;
      Object? resetError;
      try {
        _resetRuntime();
      } on Object catch (error) {
        resetError = error;
      }
      _emit(
        E1PatchStatus(
          phase: 'recoveryNeeded',
          mode: E1PatchMode.base,
          detail:
              '$detail; exact prior recovery failed and activation is locked: '
              '$transitionError; recovery: $restoreError'
              '${resetError == null ? '' : '; fail-closed reset: $resetError'}',
        ),
      );
      return false;
    }
  }

  Future<void> _failClosedPendingInitialization(
    _PersistentState prior,
    Object transitionError,
  ) async {
    Object? stateRestoreError;
    try {
      await _restoreExactState(prior);
    } on Object catch (error) {
      stateRestoreError = error;
    }
    Object? resetError;
    try {
      _resetRuntime();
    } on Object catch (error) {
      resetError = error;
    }
    _recoveryNeeded = true;
    _lifecycleState = E1LifecycleState.failed;
    _emit(
      E1PatchStatus(
        phase: 'recoveryNeeded',
        mode: E1PatchMode.base,
        detail:
            'pending startup fallback failed; unconfirmed candidate was not '
            'restored and activation is locked: $transitionError'
            '${stateRestoreError == null ? '' : '; durable recovery: $stateRestoreError'}'
            '${resetError == null ? '' : '; fail-closed reset: $resetError'}',
      ),
    );
  }

  Future<void> _restoreExactState(_PersistentState prior) async {
    await _repairStateCopies(prior);
    final restored = await _loadState();
    if (restored.recoveryNeeded ||
        restored.needsRepair ||
        restored.state!.encode() != prior.encode()) {
      throw StateError('exact prior durable state could not be restored');
    }
  }

  Future<_LoadedState> _loadState() async {
    final primary = await _readStateCopy(_statePrimary);
    final backup = await _readStateCopy(_stateBackup);
    final anyStateFile = primary.exists || backup.exists;
    final valid = <_StateCopy>[
      if (primary.state != null) primary,
      if (backup.state != null) backup,
    ];
    if (valid.isEmpty) {
      final artifacts = await _hasArtifacts();
      if (anyStateFile || artifacts) {
        return const _LoadedState.recovery(
          'durable state missing/corrupt with prior artifacts; recovery needed',
        );
      }
      return _LoadedState.ok(
        _PersistentState.base(
          appId: appId,
          releaseId: releaseId,
          trustState: _initialTrustState,
        ),
      );
    }
    if (valid.length == 2) {
      final ordered = List<_StateCopy>.of(valid)
        ..sort(
          (left, right) =>
              left.state!.generation.compareTo(right.state!.generation),
        );
      final older = ordered.first.state!;
      final newer = ordered.last.state!;
      if (newer.generation - older.generation > 1 ||
          (newer.generation == older.generation &&
              newer.encode() != older.encode()) ||
          !E1LifecycleInvariant.isHighWaterMonotonic(
            olderSequence: older.highWaterSequence,
            olderDigest: older.highWaterDigest,
            newerSequence: newer.highWaterSequence,
            newerDigest: newer.highWaterDigest,
          ) ||
          !_isTrustMonotonic(older.trustState, newer.trustState) ||
          !_isReplayMonotonic(older.replayLedger, newer.replayLedger)) {
        return const _LoadedState.recovery(
          'durable state copies have inconsistent predecessors or high-water; '
          'recovery needed',
        );
      }
    }
    valid.sort(
      (left, right) =>
          right.state!.generation.compareTo(left.state!.generation),
    );
    final chosen = valid.first.state!;
    final needsRepair =
        valid.length != 2 ||
        valid.any(
          (copy) => copy.legacy || copy.state!.encode() != chosen.encode(),
        );
    return _LoadedState.ok(chosen, needsRepair: needsRepair);
  }

  Future<_StateCopy> _readStateCopy(String name) async {
    final file = File('${storageDirectory.path}/$name');
    if (!await file.exists()) return const _StateCopy.missing();
    try {
      final source = await file.readAsString();
      final state = _PersistentState.decode(
        source,
        expectedAppId: appId,
        expectedReleaseId: releaseId,
        fallbackTrustState: _initialTrustState,
      );
      return _StateCopy(
        exists: true,
        state: state,
        legacy: state.formatVersion != _PersistentState.currentVersion,
      );
    } on Object catch (error) {
      _log('E1_PATCH invalid $name: $error');
      return const _StateCopy(exists: true, state: null);
    }
  }

  Future<bool> _hasArtifacts() async =>
      storageDirectory.existsSync() &&
      await storageDirectory.list().any(
        (entity) =>
            entity is File && _validPatchName(entity.uri.pathSegments.last),
      );

  Future<_PersistentState> _commitState(_PersistentState desired) async {
    final normalized = desired.formatVersion == _PersistentState.currentVersion
        ? desired
        : desired.copyWith(formatVersion: _PersistentState.currentVersion);
    normalized.validate();
    final committed = normalized.copyWith(
      generation: normalized.generation + 1,
    );
    committed.validate();
    try {
      await _writeStateCopy(_stateBackup, committed);
      await _writeStateCopy(_statePrimary, committed);
      return committed;
    } on Object {
      // A failure after the first rename can still leave a complete newest
      // generation. Treat that generation as committed; the next read heals
      // its peer. A failure before either rename is rethrown.
      final loaded = await _loadState();
      if (!loaded.recoveryNeeded &&
          loaded.state!.encode() == committed.encode()) {
        return committed;
      }
      rethrow;
    }
  }

  Future<void> _repairStateCopies(_PersistentState state) async {
    final normalized = state.formatVersion == _PersistentState.currentVersion
        ? state
        : state.copyWith(formatVersion: _PersistentState.currentVersion);
    await _writeStateCopy(_stateBackup, normalized);
    await _writeStateCopy(_statePrimary, normalized);
  }

  Future<void> _writeStateCopy(String name, _PersistentState state) async {
    await testHooks?.beforeStateCopyWrite?.call(name, state.generation);
    await _durableBoundary(
      E1DurableBoundary.beforeStateCopyWrite,
      name,
      state.generation,
    );
    final target = File('${storageDirectory.path}/$name');
    final temporary = File('${target.path}.tmp');
    final encoded = state.encode();
    try {
      await temporary.writeAsString(encoded, flush: true);
      await _durableBoundary(
        E1DurableBoundary.afterStateCopyFlush,
        name,
        state.generation,
      );
      await _durableBoundary(
        E1DurableBoundary.beforeStateCopyRename,
        name,
        state.generation,
      );
      await temporary.rename(target.path);
      await _durableBoundary(
        E1DurableBoundary.afterStateCopyRename,
        name,
        state.generation,
      );
      if (await target.readAsString() != encoded) {
        throw StateError('durable state copy readback mismatch');
      }
      await _durableBoundary(
        E1DurableBoundary.afterStateCopyReadback,
        name,
        state.generation,
      );
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _durableBoundary(
    E1DurableBoundary boundary,
    String name,
    int generation,
  ) async {
    await testHooks?.durableBoundary?.call(boundary, name, generation);
  }

  Future<_PersistentState> _upgradeLegacyState(_PersistentState state) async {
    final identities = <Object?>[];
    for (final reference in <String?>[state.current, state.lastKnownGood]) {
      if (reference == null) continue;
      final stored = await _readAndValidate(
        reference,
        state,
        enforceLedger: false,
      );
      if (stored == null) {
        throw StateError('legacy artifact $reference could not be reverified');
      }
      identities.add(
        E1VerifiedArtifactIdentity(
          keyId: stored.keyId,
          sequence: stored.sequence,
          digest: stored.digest,
        ).toJson(),
      );
    }
    final ledger = E1ArtifactReplayLedger.fromJson(<String, Object?>{
      'activeArtifactDigest': state.current == null
          ? null
          : _digestFromPatchReference(state.current!),
      'artifacts': identities,
      'highWaterDigest': state.highWaterDigest,
      'highWaterSequence': state.highWaterSequence,
      'releaseId': releaseId,
    }, expectedReleaseId: releaseId);
    return state.copyWith(
      replayLedger: ledger,
      formatVersion: _PersistentState.currentVersion,
      legacy: false,
    );
  }

  _PersistentState _removeRevokedExecutableSelection(
    _PersistentState state,
    String keyId,
  ) {
    final currentUsesKey = _referenceUsesKey(
      state.current,
      state.replayLedger,
      keyId,
    );
    final lkgUsesKey = _referenceUsesKey(
      state.lastKnownGood,
      state.replayLedger,
      keyId,
    );
    if (currentUsesKey) {
      return state.copyWith(
        clearCurrent: true,
        health: _PatchHealth.base,
        clearLastKnownGood: true,
        candidateBootAttempts: 0,
        replayLedger: state.replayLedger.rollbackToBase(),
        clearPendingInstallReceipt: true,
      );
    }
    if (lkgUsesKey) {
      return state.copyWith(clearLastKnownGood: true);
    }
    return state;
  }

  static bool _referenceUsesKey(
    String? reference,
    E1ArtifactReplayLedger ledger,
    String keyId,
  ) {
    if (reference == null) return false;
    final identity = ledger.artifacts[_digestFromPatchReference(reference)];
    return identity?.keyId == keyId;
  }

  static bool _isTrustMonotonic(
    E1KeyLifecycleState older,
    E1KeyLifecycleState newer,
  ) {
    if (newer.commandSequence < older.commandSequence) return false;
    if (newer.commandSequence == older.commandSequence &&
        newer.stateDigest != older.stateDigest) {
      return false;
    }
    for (final entry in older.keys.entries) {
      final next = newer.keys[entry.key];
      if (next == null ||
          !_equalBytes(next.publicKeyBytes, entry.value.publicKeyBytes) ||
          next.roles.length != entry.value.roles.length ||
          !next.roles.containsAll(entry.value.roles)) {
        return false;
      }
      final allowed = switch (entry.value.state) {
        E1ReleaseKeyState.active => true,
        E1ReleaseKeyState.retired =>
          next.state == E1ReleaseKeyState.retired ||
              next.state == E1ReleaseKeyState.revoked,
        E1ReleaseKeyState.revoked => next.state == E1ReleaseKeyState.revoked,
      };
      if (!allowed) return false;
    }
    return true;
  }

  static bool _isReplayMonotonic(
    E1ArtifactReplayLedger older,
    E1ArtifactReplayLedger newer,
  ) {
    if (!E1LifecycleInvariant.isHighWaterMonotonic(
      olderSequence: older.highWaterSequence,
      olderDigest: older.highWaterDigest,
      newerSequence: newer.highWaterSequence,
      newerDigest: newer.highWaterDigest,
    )) {
      return false;
    }
    for (final entry in older.artifacts.entries) {
      final next = newer.artifacts[entry.key];
      if (next == null || !next.sameAs(entry.value)) return false;
    }
    return true;
  }

  void _adoptState(_PersistentState state) {
    _lifecycleState = state.lifecycleState;
    _trustState = state.trustState;
    _durableState = state;
  }

  void _reject(
    String detail, {
    int? patchBytes,
    int? downloadMicros,
    int? verificationMicros,
  }) => _emit(
    E1PatchStatus(
      phase: 'rejected',
      mode: _status.mode,
      detail: detail,
      patchBytes: patchBytes,
      downloadMicros: downloadMicros,
      verificationMicros: verificationMicros,
    ),
  );
  bool _recoveryLocked(String detail) {
    _lifecycleState = E1LifecycleState.failed;
    _emit(
      E1PatchStatus(
        phase: 'recoveryNeeded',
        mode: E1PatchMode.base,
        detail: detail,
      ),
    );
    return false;
  }

  void _emit(E1PatchStatus value) {
    _status = value;
    _log('E1_STATUS ${jsonEncode(value.toJson())}');
    _statusEvents.add(value);
  }

  static bool _validPatchName(String name) =>
      RegExp(r'^patch-[0-9a-f]{64}(?:\.e1\.signed\.json|\.v1\.patch)$')
          .hasMatch(name);

  bool _receiptDeadlineIsFuture(E1InstallReceiptContext receipt) =>
      DateTime.parse(receipt.activationDeadline).isAfter(_clock().toUtc());

  E1InstallReceiptContext? _bindReceiptContext(
    E1InstallReceiptContext? context, {
    required String digest,
    required _VerifiedRuntimePatch verified,
  }) {
    if (context == null) return null;
    if (!verified.patchFormat || verified.patchId == null) {
      throw const FormatException(
        'install receipts require a signed Patch Format artifact identity',
      );
    }
    if (context.normalizedArtifactDigest != digest) {
      throw const FormatException(
        'install receipt artifact digest is not the verified artifact digest',
      );
    }
    if (context.releaseId != releaseId) {
      throw const FormatException(
        'install receipt release is not the controller release',
      );
    }
    if (context.runtimeApplicationId != appId) {
      throw const FormatException(
        'install receipt runtime application is not the controller app',
      );
    }
    if (context.patchId != verified.patchId) {
      throw const FormatException(
        'install receipt patch is not the verified artifact patch',
      );
    }
    return context;
  }

  static bool _receiptIdIsQueued(_PersistentState state, String receiptId) =>
      state.pendingInstallReceipt?.receiptId == receiptId ||
      state.installReceiptOutbox.any(
        (receipt) => receipt.receiptId == receiptId,
      );

  static String _digestFromPatchReference(String name) {
    if (!_validPatchName(name)) {
      throw const FormatException('invalid patch reference');
    }
    final suffix = name.endsWith('.v1.patch') ? '.v1.patch' : '.e1.signed.json';
    return name.substring('patch-'.length, name.length - suffix.length);
  }

  static E1KeyLifecycleState _legacyTrustBaseline({
    required String appId,
    required String releaseId,
    required Map<String, E1TrustedPublicKey> trustedPublicKeys,
  }) {
    final entries = trustedPublicKeys.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final authorityKeyId = entries.first.key;
    return E1KeyLifecycleState.staticBaseline(
      applicationId: appId,
      releaseId: releaseId,
      keys: <E1ReleaseKey>[
        for (final entry in entries)
          E1ReleaseKey(
            keyId: entry.key,
            publicKeyBytes: entry.value.bytes,
            roles: <E1ReleaseKeyRole>{
              E1ReleaseKeyRole.patch,
              E1ReleaseKeyRole.rollback,
              if (entry.key == authorityKeyId) E1ReleaseKeyRole.authority,
            },
          ),
      ],
    );
  }

  static bool _equalBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

final class _StoredPatch {
  const _StoredPatch({
    required this.artifactBytes,
    required this.programBytes,
    required this.patchFormat,
    required this.keyId,
    required this.sequence,
    required this.digest,
  });
  final Uint8List artifactBytes;
  final List<Uint8List> programBytes;
  final bool patchFormat;
  final String keyId;
  final int sequence;
  final String digest;
}

final class _VerifiedRuntimePatch {
  const _VerifiedRuntimePatch({
    required this.artifactBytes,
    required this.programBytes,
    required this.sequence,
    required this.patchFormat,
    required this.keyId,
    this.patchId,
  });
  final Uint8List artifactBytes;
  final List<Uint8List> programBytes;
  final int sequence;
  final bool patchFormat;
  final String keyId;
  final String? patchId;
}

enum _PatchHealth { base, pending, healthy }

final class _PersistentState {
  static const int currentVersion = 5;

  _PersistentState({
    required this.appId,
    required this.releaseId,
    required this.generation,
    required this.highWaterSequence,
    required this.highWaterDigest,
    required this.current,
    required this.health,
    required this.lastKnownGood,
    required this.candidateBootAttempts,
    required this.trustState,
    required this.trustGeneration,
    required this.replayLedger,
    this.pendingInstallReceipt,
    List<E1InstallReceiptContext> installReceiptOutbox =
        const <E1InstallReceiptContext>[],
    this.formatVersion = currentVersion,
    this.legacy = false,
  }) : installReceiptOutbox = List<E1InstallReceiptContext>.unmodifiable(
         installReceiptOutbox,
       );
  factory _PersistentState.base({
    required String appId,
    required String releaseId,
    required E1KeyLifecycleState trustState,
  }) => _PersistentState(
    appId: appId,
    releaseId: releaseId,
    generation: 0,
    highWaterSequence: 0,
    highWaterDigest: null,
    current: null,
    health: _PatchHealth.base,
    lastKnownGood: null,
    candidateBootAttempts: 0,
    trustState: trustState,
    trustGeneration: trustState.commandSequence,
    replayLedger: E1ArtifactReplayLedger.empty(releaseId: releaseId),
  );
  final String appId;
  final String releaseId;
  final int generation;
  final int highWaterSequence;
  final String? highWaterDigest;
  final String? current;
  final _PatchHealth health;
  final String? lastKnownGood;
  final int candidateBootAttempts;
  final E1KeyLifecycleState trustState;
  final int trustGeneration;
  final E1ArtifactReplayLedger replayLedger;
  final E1InstallReceiptContext? pendingInstallReceipt;
  final List<E1InstallReceiptContext> installReceiptOutbox;
  final int formatVersion;
  final bool legacy;

  E1LifecycleState get lifecycleState => switch (health) {
    _PatchHealth.base => E1LifecycleState.base,
    _PatchHealth.pending => E1LifecycleState.candidate,
    _PatchHealth.healthy => E1LifecycleState.current,
  };

  void validate() {
    E1LifecycleInvariant.validateRecord(
      state: lifecycleState,
      generation: generation,
      highWaterSequence: highWaterSequence,
      highWaterDigest: highWaterDigest,
      current: current,
      lastKnownGood: lastKnownGood,
      candidateBootAttempts: candidateBootAttempts,
      isValidReference: E1PatchController._validPatchName,
    );
    _validateIntegratedTrust();
    _validateReceipts();
  }

  void _validateIntegratedTrust() {
    if (trustState.applicationId != appId ||
        trustState.releaseId != releaseId ||
        trustGeneration != trustState.commandSequence ||
        trustGeneration < 0) {
      throw const FormatException(
        'durable trust generation or release mismatch',
      );
    }
    if (replayLedger.releaseId != releaseId ||
        replayLedger.highWaterSequence != highWaterSequence ||
        replayLedger.highWaterDigest != highWaterDigest) {
      throw const FormatException('trust ledger and patch high-water disagree');
    }
    if (legacy) return;
    final activeDigest = current == null
        ? null
        : E1PatchController._digestFromPatchReference(current!);
    if (replayLedger.activeArtifactDigest != activeDigest) {
      throw const FormatException('active artifact and replay ledger disagree');
    }
    if (lastKnownGood != null &&
        !replayLedger.artifacts.containsKey(
          E1PatchController._digestFromPatchReference(lastKnownGood!),
        )) {
      throw const FormatException('last-known-good is not remembered');
    }
  }

  void _validateReceipts() {
    if (formatVersion < 3 || formatVersion > currentVersion) {
      throw const FormatException('durable state version is invalid');
    }
    if (installReceiptOutbox.length >
        E1PatchController.maxInstallReceiptOutbox) {
      throw const FormatException('install receipt outbox is full');
    }
    final receiptIds = <String>{};
    for (final receipt in installReceiptOutbox) {
      _validateReceiptIdentity(receipt);
      if (!receiptIds.add(receipt.receiptId)) {
        throw const FormatException('duplicate install receipt ID');
      }
    }
    final pending = pendingInstallReceipt;
    if (pending == null) return;
    if (health != _PatchHealth.pending || current == null) {
      throw const FormatException(
        'pending install receipt requires a pending candidate',
      );
    }
    _validateReceiptIdentity(pending);
    if (!receiptIds.add(pending.receiptId)) {
      throw const FormatException('pending install receipt ID is duplicated');
    }
    if (pending.normalizedArtifactDigest !=
        E1PatchController._digestFromPatchReference(current!)) {
      throw const FormatException(
        'pending install receipt is not bound to current artifact',
      );
    }
  }

  void _validateReceiptIdentity(E1InstallReceiptContext receipt) {
    if (receipt.releaseId != releaseId ||
        receipt.runtimeApplicationId != appId) {
      throw const FormatException('install receipt is not release-bound');
    }
    final identity = replayLedger.artifacts[receipt.normalizedArtifactDigest];
    if (identity == null) {
      throw const FormatException('install receipt artifact is not remembered');
    }
  }

  E1ControllerDurableState toPublicView() => E1ControllerDurableState(
    appId: appId,
    releaseId: releaseId,
    generation: generation,
    trustGeneration: trustGeneration,
    highWaterSequence: highWaterSequence,
    highWaterDigest: highWaterDigest,
    current: current,
    health: health.name,
    lastKnownGood: lastKnownGood,
    candidateBootAttempts: candidateBootAttempts,
    trustState: trustState,
    replayLedger: replayLedger,
  );

  _PersistentState copyWith({
    int? generation,
    int? highWaterSequence,
    String? highWaterDigest,
    String? current,
    bool clearCurrent = false,
    _PatchHealth? health,
    String? lastKnownGood,
    bool clearLastKnownGood = false,
    int? candidateBootAttempts,
    E1KeyLifecycleState? trustState,
    int? trustGeneration,
    E1ArtifactReplayLedger? replayLedger,
    E1InstallReceiptContext? pendingInstallReceipt,
    bool clearPendingInstallReceipt = false,
    List<E1InstallReceiptContext>? installReceiptOutbox,
    int? formatVersion,
    bool? legacy,
  }) => _PersistentState(
    appId: appId,
    releaseId: releaseId,
    generation: generation ?? this.generation,
    highWaterSequence: highWaterSequence ?? this.highWaterSequence,
    highWaterDigest: highWaterDigest ?? this.highWaterDigest,
    current: clearCurrent ? null : (current ?? this.current),
    health: health ?? this.health,
    lastKnownGood: clearLastKnownGood
        ? null
        : (lastKnownGood ?? this.lastKnownGood),
    candidateBootAttempts: candidateBootAttempts ?? this.candidateBootAttempts,
    trustState: trustState ?? this.trustState,
    trustGeneration: trustGeneration ?? this.trustGeneration,
    replayLedger: replayLedger ?? this.replayLedger,
    pendingInstallReceipt: clearPendingInstallReceipt
        ? null
        : (pendingInstallReceipt ?? this.pendingInstallReceipt),
    installReceiptOutbox: installReceiptOutbox ?? this.installReceiptOutbox,
    formatVersion: formatVersion ?? this.formatVersion,
    legacy: legacy ?? this.legacy,
  );

  Map<String, Object?> _body() => <String, Object?>{
    'appId': appId,
    'artifactLedger': replayLedger.toJson(),
    'candidateBootAttempts': candidateBootAttempts,
    'current': current,
    'generation': generation,
    'health': health.name,
    'highWaterDigest': highWaterDigest,
    'highWaterSequence': highWaterSequence,
    'installReceiptOutbox': [
      for (final receipt in installReceiptOutbox) receipt.body,
    ],
    'lastKnownGood': lastKnownGood,
    'pendingInstallReceipt': pendingInstallReceipt?.body,
    'releaseId': releaseId,
    'stateVersion': currentVersion,
    'trust': jsonDecode(trustState.encode()),
    'trustGeneration': trustGeneration,
  };
  String encode() {
    final body = _body();
    final value = <String, Object?>{
      ...body,
      'checksum': sha256.convert(utf8.encode(jsonEncode(body))).toString(),
    };
    return jsonEncode(<String, Object?>{
      for (final key in value.keys.toList()..sort()) key: value[key],
    });
  }

  static _PersistentState decode(
    String source, {
    required String expectedAppId,
    required String expectedReleaseId,
    required E1KeyLifecycleState fallbackTrustState,
  }) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('invalid state fields');
    }
    final stateVersion = decoded['stateVersion'];
    final keys = stateVersion == currentVersion
        ? _v5Keys
        : stateVersion == 4
        ? _v4Keys
        : decoded.containsKey('candidateBootAttempts')
        ? _keys
        : _legacyKeys;
    if (decoded.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(decoded.keys.toSet()).isNotEmpty) {
      throw const FormatException('invalid state fields');
    }
    final canonical = jsonEncode(<String, Object?>{
      for (final key in decoded.keys.toList()..sort()) key: decoded[key],
    });
    if (canonical != source) {
      throw const FormatException('state is not canonical');
    }
    final body = <String, Object?>{
      for (final key in decoded.keys.where((key) => key != 'checksum'))
        key: decoded[key],
    };
    if (decoded['checksum'] !=
        sha256.convert(utf8.encode(jsonEncode(body))).toString()) {
      throw const FormatException('state checksum mismatch');
    }
    final healthName = decoded['health'];
    final health = _PatchHealth.values
        .where((item) => item.name == healthName)
        .firstOrNull;
    final rawCandidateBootAttempts = decoded['candidateBootAttempts'];
    final candidateBootAttempts = rawCandidateBootAttempts is int
        ? rawCandidateBootAttempts
        : health == _PatchHealth.pending
        ? E1LifecycleInvariant.maxCandidateBootAttempts
        : 0;
    final rawTrustGeneration = decoded['trustGeneration'];
    if (stateVersion != 3 &&
            stateVersion != 4 &&
            stateVersion != currentVersion ||
        decoded['appId'] != expectedAppId ||
        decoded['releaseId'] != expectedReleaseId ||
        decoded['generation'] is! int ||
        decoded['highWaterSequence'] is! int ||
        (decoded['highWaterDigest'] != null &&
            decoded['highWaterDigest'] is! String) ||
        (decoded['current'] != null && decoded['current'] is! String) ||
        (decoded['lastKnownGood'] != null &&
            decoded['lastKnownGood'] is! String) ||
        (rawCandidateBootAttempts != null &&
            rawCandidateBootAttempts is! int) ||
        (stateVersion != 3 && rawTrustGeneration is! int) ||
        health == null) {
      throw const FormatException('invalid release-bound state');
    }
    final trustState = stateVersion != 3
        ? E1KeyLifecycleState.decode(utf8.encode(jsonEncode(decoded['trust'])))
        : fallbackTrustState;
    final replayLedger = stateVersion != 3
        ? E1ArtifactReplayLedger.fromJson(
            decoded['artifactLedger'],
            expectedReleaseId: expectedReleaseId,
          )
        : E1ArtifactReplayLedger.fromJson(<String, Object?>{
            'activeArtifactDigest': null,
            'artifacts': const <Object?>[],
            'highWaterDigest': decoded['highWaterDigest'],
            'highWaterSequence': decoded['highWaterSequence'],
            'releaseId': expectedReleaseId,
          }, expectedReleaseId: expectedReleaseId);
    E1InstallReceiptContext? pendingInstallReceipt;
    final installReceiptOutbox = <E1InstallReceiptContext>[];
    if (stateVersion == currentVersion) {
      final rawPending = decoded['pendingInstallReceipt'];
      if (rawPending != null) {
        if (rawPending is! Map) {
          throw const FormatException('invalid pending install receipt');
        }
        pendingInstallReceipt = E1InstallReceiptContext(
          body: Map<String, Object?>.from(rawPending),
        );
      }
      final rawOutbox = decoded['installReceiptOutbox'];
      if (rawOutbox is! List) {
        throw const FormatException('invalid install receipt outbox');
      }
      for (final rawReceipt in rawOutbox) {
        if (rawReceipt is! Map) {
          throw const FormatException('invalid install receipt outbox entry');
        }
        installReceiptOutbox.add(
          E1InstallReceiptContext(body: Map<String, Object?>.from(rawReceipt)),
        );
      }
    }
    final state = _PersistentState(
      appId: decoded['appId']! as String,
      releaseId: decoded['releaseId']! as String,
      generation: decoded['generation']! as int,
      highWaterSequence: decoded['highWaterSequence']! as int,
      highWaterDigest: decoded['highWaterDigest'] as String?,
      current: decoded['current'] as String?,
      health: health,
      lastKnownGood: decoded['lastKnownGood'] as String?,
      candidateBootAttempts: candidateBootAttempts,
      trustState: trustState,
      trustGeneration: stateVersion != 3
          ? rawTrustGeneration! as int
          : trustState.commandSequence,
      replayLedger: replayLedger,
      pendingInstallReceipt: pendingInstallReceipt,
      installReceiptOutbox: installReceiptOutbox,
      formatVersion: stateVersion! as int,
      legacy: stateVersion == 3,
    );
    state.validate();
    if (stateVersion == currentVersion && state.encode() != source) {
      throw const FormatException('state nested encoding is not canonical');
    }
    return state;
  }

  static const _legacyKeys = <String>{
    'appId',
    'checksum',
    'current',
    'generation',
    'health',
    'highWaterDigest',
    'highWaterSequence',
    'lastKnownGood',
    'releaseId',
    'stateVersion',
  };
  static const _keys = <String>{..._legacyKeys, 'candidateBootAttempts'};
  static const _v4Keys = <String>{
    'appId',
    'artifactLedger',
    'candidateBootAttempts',
    'checksum',
    'current',
    'generation',
    'health',
    'highWaterDigest',
    'highWaterSequence',
    'lastKnownGood',
    'releaseId',
    'stateVersion',
    'trust',
    'trustGeneration',
  };
  static const _v5Keys = <String>{
    ..._v4Keys,
    'installReceiptOutbox',
    'pendingInstallReceipt',
  };
}

final class _StateCopy {
  const _StateCopy({
    required this.exists,
    required this.state,
    this.legacy = false,
  });
  const _StateCopy.missing() : exists = false, state = null, legacy = false;
  final bool exists;
  final _PersistentState? state;
  final bool legacy;
}

final class _LoadedState {
  const _LoadedState.ok(this.state, {this.needsRepair = false})
    : recoveryNeeded = false,
      detail = '';
  const _LoadedState.recovery(this.detail)
    : state = null,
      needsRepair = false,
      recoveryNeeded = true;
  final _PersistentState? state;
  final bool needsRepair;
  final bool recoveryNeeded;
  final String detail;
}
