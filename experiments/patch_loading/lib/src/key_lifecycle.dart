import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// The key states understood by the bounded release-owned lifecycle model.
///
/// [retired] keys may still authenticate artifacts that were already recorded
/// by the release before retirement. [revoked] keys cannot authenticate new or
/// retained artifacts. A state transition never adds a recovery key: recovery
/// anchors are installed with the release and remain outside downloaded
/// delegation.
enum E1ReleaseKeyState { active, retired, revoked }

/// Capabilities of a release-owned public key.
///
/// The [authority] role signs ordinary lifecycle changes. The [recovery] role
/// is intentionally separate and may only perform an atomic replacement of a
/// non-recovery key. A downloaded command can add patch, rollback, and
/// authority roles, but never the recovery role.
enum E1ReleaseKeyRole { patch, rollback, authority, recovery }

/// Signed transitions supported by this bounded model.
enum E1KeyLifecycleOperation { add, retire, revoke, recover }

/// Result of applying a post-verification artifact policy.
enum E1ArtifactAdmissionStatus {
  accepted,
  idempotent,
  retained,
  releaseMismatch,
  unknownKey,
  keyRevoked,
  keyRetiredForNewArtifact,
  keyRoleNotAllowed,
  stale,
  equivocation,
  replayAfterRollback,
  notRetained,
  artifactMismatch,
  ledgerFull,
}

/// Bounded limits for the release-owned controller journal.
abstract final class E1KeyLifecycleLimits {
  static const int maxKeys = 8;
  static const int maxLifecycleCommandBytes = 16 * 1024;
  static const int maxStateBytes = 32 * 1024;
  static const int maxRememberedArtifacts = 64;
}

/// A release-embedded Ed25519 public key and its lifecycle roles.
final class E1ReleaseKey {
  E1ReleaseKey({
    required this.keyId,
    required List<int> publicKeyBytes,
    required Set<E1ReleaseKeyRole> roles,
    this.state = E1ReleaseKeyState.active,
    this.changedAtCommandSequence,
  }) : publicKeyBytes = List<int>.unmodifiable(publicKeyBytes),
       roles = Set<E1ReleaseKeyRole>.unmodifiable(roles) {
    _validateKeyId(keyId);
    _validatePublicKey(publicKeyBytes);
    if (this.roles.isEmpty) {
      throw const FormatException('Release key roles must not be empty');
    }
    if (this.roles.contains(E1ReleaseKeyRole.recovery) &&
        this.roles.length != 1) {
      throw const FormatException(
        'Recovery keys must not share patch or lifecycle roles',
      );
    }
    final changed = changedAtCommandSequence;
    if (changed != null && changed < 1) {
      throw const FormatException('Key change sequence must be positive');
    }
    if (state == E1ReleaseKeyState.active && changed != null) {
      throw const FormatException(
        'An active key cannot carry a retirement or revocation sequence',
      );
    }
    if (state != E1ReleaseKeyState.active && changed == null) {
      throw const FormatException(
        'Retired and revoked keys require a change sequence',
      );
    }
    if (this.roles.contains(E1ReleaseKeyRole.recovery) &&
        state != E1ReleaseKeyState.active) {
      throw const FormatException(
        'Recovery anchors cannot be retired or revoked',
      );
    }
  }

  final String keyId;
  final List<int> publicKeyBytes;
  final Set<E1ReleaseKeyRole> roles;
  final E1ReleaseKeyState state;
  final int? changedAtCommandSequence;

  bool get acceptsNewArtifacts =>
      state == E1ReleaseKeyState.active &&
      roles.contains(E1ReleaseKeyRole.patch);

  bool get verifiesRetainedArtifacts =>
      state != E1ReleaseKeyState.revoked &&
      roles.contains(E1ReleaseKeyRole.patch);

  bool get signsLifecycleCommands =>
      state == E1ReleaseKeyState.active &&
      roles.contains(E1ReleaseKeyRole.authority);

  bool get isRecoveryAnchor => roles.contains(E1ReleaseKeyRole.recovery);

  E1ReleaseKey withState(E1ReleaseKeyState nextState, int commandSequence) =>
      E1ReleaseKey(
        keyId: keyId,
        publicKeyBytes: publicKeyBytes,
        roles: roles,
        state: nextState,
        changedAtCommandSequence: commandSequence,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'changedAtCommandSequence': changedAtCommandSequence,
    'keyId': keyId,
    'publicKey': base64.encode(publicKeyBytes),
    'roles': _roleNames(roles),
    'state': state.name,
  };

  static E1ReleaseKey fromJson(Map<String, Object?> value) {
    const fields = <String>{
      'changedAtCommandSequence',
      'keyId',
      'publicKey',
      'roles',
      'state',
    };
    if (value.keys.toSet().difference(fields).isNotEmpty ||
        fields.difference(value.keys.toSet()).isNotEmpty ||
        value['keyId'] is! String ||
        value['publicKey'] is! String ||
        value['roles'] is! List<Object?> ||
        value['state'] is! String ||
        (value['changedAtCommandSequence'] != null &&
            value['changedAtCommandSequence'] is! int)) {
      throw const FormatException('Invalid release key record');
    }
    final stateName = value['state']! as String;
    final state = _enumByName(
      E1ReleaseKeyState.values,
      stateName,
      'release key state',
    );
    final roleValues = value['roles']! as List<Object?>;
    final roles = <E1ReleaseKeyRole>{};
    for (final rawRole in roleValues) {
      if (rawRole is! String) {
        throw const FormatException('Invalid release key role');
      }
      roles.add(
        _enumByName(E1ReleaseKeyRole.values, rawRole, 'release key role'),
      );
    }
    final publicKey = _decodeCanonicalBase64(
      value['publicKey']! as String,
      'release public key',
    );
    return E1ReleaseKey(
      keyId: value['keyId']! as String,
      publicKeyBytes: publicKey,
      roles: roles,
      state: state,
      changedAtCommandSequence: value['changedAtCommandSequence'] as int?,
    );
  }
}

/// Immutable release-owned key state.
///
/// The initial key set is the trust anchor. Every later state is derived from
/// a canonical, Ed25519-signed command whose signer is already authorized by
/// the current state. New public-key bytes in a command are therefore data
/// until the command has passed this boundary; they never self-authorize.
final class E1KeyLifecycleState {
  E1KeyLifecycleState._({
    required this.applicationId,
    required this.releaseId,
    required this.commandSequence,
    required Map<String, E1ReleaseKey> keys,
    this._allowMissingRecoveryAnchor = false,
  }) : keys = Map.unmodifiable(keys) {
    _validateComponent(applicationId, 'application ID');
    _validateComponent(releaseId, 'release ID');
    if (commandSequence < 0 || commandSequence > 0x7fffffffffffffff) {
      throw const FormatException('Lifecycle command sequence is invalid');
    }
    _validateKeySet(
      this.keys,
      requireRecoveryAnchor: !_allowMissingRecoveryAnchor,
    );
  }

  static const int stateVersion = 1;
  static const int maxBytes = E1KeyLifecycleLimits.maxStateBytes;

  /// Creates the immutable release baseline. All initial records must be
  /// active; retired/revoked records can only be produced by a command.
  factory E1KeyLifecycleState.initial({
    required String applicationId,
    required String releaseId,
    required Iterable<E1ReleaseKey> keys,
  }) {
    final list = keys.toList(growable: false);
    if (list.any((key) => key.state != E1ReleaseKeyState.active)) {
      throw const FormatException('Initial release keys must be active');
    }
    return E1KeyLifecycleState._(
      applicationId: applicationId,
      releaseId: releaseId,
      commandSequence: 0,
      keys: _keyMap(list),
    );
  }

  /// Creates the compatibility baseline for a controller that only has the
  /// historical embedded patch-key map.
  ///
  /// This mode deliberately has no offline recovery anchor. It still uses the
  /// same signed add/retire/revoke state machine and the same durable journal;
  /// a release that needs compromise recovery must provide an explicit
  /// [initial] state containing a separate recovery key.
  factory E1KeyLifecycleState.staticBaseline({
    required String applicationId,
    required String releaseId,
    required Iterable<E1ReleaseKey> keys,
  }) {
    final list = keys.toList(growable: false);
    if (list.any((key) => key.state != E1ReleaseKeyState.active)) {
      throw const FormatException('Static baseline keys must be active');
    }
    return E1KeyLifecycleState._(
      applicationId: applicationId,
      releaseId: releaseId,
      commandSequence: 0,
      keys: _keyMap(list),
      allowMissingRecoveryAnchor: true,
    );
  }

  final String applicationId;
  final String releaseId;
  final int commandSequence;
  final Map<String, E1ReleaseKey> keys;
  final bool _allowMissingRecoveryAnchor;

  late final String stateDigest = _sha256(utf8.encode(_canonicalJson(_body())));

  String get canonicalJson => _canonicalJson(_body());

  E1ReleaseKey? operator [](String keyId) => keys[keyId];

  Map<String, List<int>> get activeArtifactTrust =>
      Map.unmodifiable(<String, List<int>>{
        for (final entry in keys.entries)
          if (entry.value.acceptsNewArtifacts)
            entry.key: List<int>.unmodifiable(entry.value.publicKeyBytes),
      });

  Map<String, List<int>> get retainedArtifactTrust =>
      Map.unmodifiable(<String, List<int>>{
        for (final entry in keys.entries)
          if (entry.value.verifiesRetainedArtifacts)
            entry.key: List<int>.unmodifiable(entry.value.publicKeyBytes),
      });

  /// Applies a canonical signed lifecycle command.
  ///
  /// This method changes only the immutable model. The caller still owns
  /// durable journaling and must commit the returned state before changing
  /// executable runtime state.
  Future<E1KeyLifecycleState> apply(List<int> commandBytes) async {
    final command = E1KeyLifecycleCommand.decode(commandBytes);
    if (command.applicationId != applicationId ||
        command.releaseId != releaseId) {
      throw const FormatException('Lifecycle command release binding mismatch');
    }
    if (command.commandSequence != commandSequence + 1) {
      throw const FormatException('Lifecycle command replay or gap');
    }
    if (command.previousStateDigest != stateDigest) {
      throw const FormatException('Lifecycle command previous state mismatch');
    }
    final signer = keys[command.signerKeyId];
    if (signer == null) {
      throw const FormatException('Lifecycle command signer is not trusted');
    }
    final signerAllowed = command.operation == E1KeyLifecycleOperation.recover
        ? signer.isRecoveryAnchor
        : signer.signsLifecycleCommands;
    if (!signerAllowed) {
      throw const FormatException(
        'Lifecycle command signer role is not allowed',
      );
    }
    if (!await command.verify(signer.publicKeyBytes)) {
      throw const FormatException('Lifecycle command signature is invalid');
    }
    return _applyVerified(command);
  }

  /// Serializes a checksummed state snapshot. The digest detects malformed or
  /// torn state but is not a MAC against a local attacker who can rewrite both
  /// state and checksum.
  List<int> encodeBytes() {
    final bytes = utf8.encode(
      _canonicalJson(<String, Object?>{..._body(), 'stateDigest': stateDigest}),
    );
    if (bytes.length > maxBytes) {
      throw const FormatException('Lifecycle state exceeds byte limit');
    }
    return bytes;
  }

  String encode() => utf8.decode(encodeBytes());

  factory E1KeyLifecycleState.decode(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Lifecycle state exceeds byte limit');
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object {
      throw const FormatException('Lifecycle state is not strict UTF-8 JSON');
    }
    const fields = <String>{
      'applicationId',
      'commandSequence',
      'keys',
      'releaseId',
      'stateDigest',
      'stateVersion',
    };
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(fields).isNotEmpty ||
        fields.difference(decoded.keys.toSet()).isNotEmpty ||
        decoded['stateVersion'] != stateVersion ||
        decoded['applicationId'] is! String ||
        decoded['releaseId'] is! String ||
        decoded['commandSequence'] is! int ||
        decoded['keys'] is! List<Object?> ||
        decoded['stateDigest'] is! String) {
      throw const FormatException('Invalid lifecycle state fields');
    }
    final state = E1KeyLifecycleState._(
      applicationId: decoded['applicationId']! as String,
      releaseId: decoded['releaseId']! as String,
      commandSequence: decoded['commandSequence']! as int,
      keys: _keysFromJson(decoded['keys']! as List<Object?>),
      allowMissingRecoveryAnchor: !(decoded['keys']! as List<Object?>).any(
        (value) =>
            value is Map<String, Object?> &&
            value['roles'] is List<Object?> &&
            (value['roles']! as List<Object?>).contains('recovery'),
      ),
    );
    if (decoded['stateDigest'] != state.stateDigest ||
        !_equalBytes(
          bytes,
          utf8.encode(
            _canonicalJson(<String, Object?>{
              ...state._body(),
              'stateDigest': state.stateDigest,
            }),
          ),
        )) {
      throw const FormatException(
        'Lifecycle state checksum or encoding mismatch',
      );
    }
    return state;
  }

  E1KeyLifecycleState _applyVerified(E1KeyLifecycleCommand command) {
    final next = <String, E1ReleaseKey>{...keys};
    switch (command.operation) {
      case E1KeyLifecycleOperation.add:
        final keyId = command.newKeyId!;
        if (next.length >= E1KeyLifecycleLimits.maxKeys ||
            next.containsKey(keyId)) {
          throw const FormatException(
            'Lifecycle key set is full or duplicated',
          );
        }
        final roles = command.newRoles!;
        if (roles.contains(E1ReleaseKeyRole.recovery)) {
          throw const FormatException(
            'Downloaded commands cannot add recovery keys',
          );
        }
        next[keyId] = E1ReleaseKey(
          keyId: keyId,
          publicKeyBytes: command.newPublicKey!,
          roles: roles,
        );
      case E1KeyLifecycleOperation.retire:
        final target = _target(next, command.targetKeyId!);
        _ensureActiveTarget(target);
        next[target.keyId] = target.withState(
          E1ReleaseKeyState.retired,
          command.commandSequence,
        );
      case E1KeyLifecycleOperation.revoke:
        final target = _target(next, command.targetKeyId!);
        _ensureRevocableTarget(target);
        next[target.keyId] = target.withState(
          E1ReleaseKeyState.revoked,
          command.commandSequence,
        );
      case E1KeyLifecycleOperation.recover:
        final target = _target(next, command.targetKeyId!);
        _ensureRevocableTarget(target);
        final replacementId = command.newKeyId!;
        if (next.containsKey(replacementId) ||
            replacementId == target.keyId ||
            next.length >= E1KeyLifecycleLimits.maxKeys) {
          throw const FormatException('Recovery replacement key is invalid');
        }
        final replacementRoles = command.newRoles!;
        if (replacementRoles.contains(E1ReleaseKeyRole.recovery) ||
            replacementRoles.length != target.roles.length ||
            !replacementRoles.containsAll(target.roles)) {
          throw const FormatException(
            'Recovery replacement must preserve non-recovery roles',
          );
        }
        next[target.keyId] = target.withState(
          E1ReleaseKeyState.revoked,
          command.commandSequence,
        );
        next[replacementId] = E1ReleaseKey(
          keyId: replacementId,
          publicKeyBytes: command.newPublicKey!,
          roles: replacementRoles,
        );
    }
    _validateKeySet(next, requireRecoveryAnchor: !_allowMissingRecoveryAnchor);
    return E1KeyLifecycleState._(
      applicationId: applicationId,
      releaseId: releaseId,
      commandSequence: command.commandSequence,
      keys: next,
      allowMissingRecoveryAnchor: _allowMissingRecoveryAnchor,
    );
  }

  Map<String, Object?> _body() => <String, Object?>{
    'applicationId': applicationId,
    'commandSequence': commandSequence,
    'keys': [
      for (final key
          in keys.values.toList()
            ..sort((left, right) => left.keyId.compareTo(right.keyId)))
        key.toJson(),
    ],
    'releaseId': releaseId,
    'stateVersion': stateVersion,
  };

  static E1ReleaseKey _target(Map<String, E1ReleaseKey> keys, String keyId) {
    final target = keys[keyId];
    if (target == null) {
      throw const FormatException('Lifecycle target key is not known');
    }
    return target;
  }

  static void _ensureActiveTarget(E1ReleaseKey target) {
    if (target.isRecoveryAnchor) {
      throw const FormatException('Recovery anchor is immutable');
    }
    if (target.state != E1ReleaseKeyState.active) {
      throw const FormatException('Lifecycle target is not active');
    }
  }

  static void _ensureRevocableTarget(E1ReleaseKey target) {
    if (target.isRecoveryAnchor) {
      throw const FormatException('Recovery anchor is immutable');
    }
    if (target.state == E1ReleaseKeyState.revoked) {
      throw const FormatException('Lifecycle target is already revoked');
    }
  }

  static Map<String, E1ReleaseKey> _keyMap(Iterable<E1ReleaseKey> values) {
    final result = <String, E1ReleaseKey>{};
    for (final key in values) {
      if (result.putIfAbsent(key.keyId, () => key) != key) {
        throw const FormatException('Duplicate release key ID');
      }
    }
    return result;
  }

  static Map<String, E1ReleaseKey> _keysFromJson(List<Object?> values) {
    final parsed = <E1ReleaseKey>[];
    for (final value in values) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('Invalid release key list entry');
      }
      parsed.add(E1ReleaseKey.fromJson(value));
    }
    return _keyMap(parsed);
  }

  static void _validateKeySet(
    Map<String, E1ReleaseKey> values, {
    required bool requireRecoveryAnchor,
  }) {
    if (values.isEmpty || values.length > E1KeyLifecycleLimits.maxKeys) {
      throw const FormatException('Release key set is outside its bound');
    }
    if (!values.values.any(
      (key) =>
          key.state == E1ReleaseKeyState.active &&
          key.roles.contains(E1ReleaseKeyRole.authority),
    )) {
      throw const FormatException('Release key set has no active authority');
    }
    if (requireRecoveryAnchor &&
        !values.values.any(
          (key) =>
              key.state == E1ReleaseKeyState.active && key.isRecoveryAnchor,
        )) {
      throw const FormatException('Release key set has no recovery anchor');
    }
    if (!values.values.any(
      (key) =>
          key.state == E1ReleaseKeyState.active &&
          key.roles.contains(E1ReleaseKeyRole.patch),
    )) {
      throw const FormatException('Release key set has no active patch key');
    }
  }
}

/// A canonical, signed key lifecycle command.
final class E1KeyLifecycleCommand {
  E1KeyLifecycleCommand._({
    required this.applicationId,
    required this.releaseId,
    required this.commandSequence,
    required this.previousStateDigest,
    required this.operation,
    required this.signerKeyId,
    required this.targetKeyId,
    required this.newKeyId,
    required List<int>? newPublicKey,
    required Set<E1ReleaseKeyRole>? newRoles,
    required List<int> signatureBytes,
  }) : newPublicKey = newPublicKey == null
           ? null
           : List<int>.unmodifiable(newPublicKey),
       newRoles = newRoles == null
           ? null
           : Set<E1ReleaseKeyRole>.unmodifiable(newRoles),
       signatureBytes = List<int>.unmodifiable(signatureBytes);

  static const int commandVersion = 1;
  static const String algorithm = 'Ed25519';
  static const int maxBytes = E1KeyLifecycleLimits.maxLifecycleCommandBytes;
  static final Uint8List _domain = Uint8List.fromList(
    utf8.encode('hyfens-key-lifecycle-v1\u0000'),
  );
  static final DartEd25519 _ed25519 = DartEd25519();

  final String applicationId;
  final String releaseId;
  final int commandSequence;
  final String previousStateDigest;
  final E1KeyLifecycleOperation operation;
  final String signerKeyId;
  final String? targetKeyId;
  final String? newKeyId;
  final List<int>? newPublicKey;
  final Set<E1ReleaseKeyRole>? newRoles;
  final List<int> signatureBytes;

  static Future<E1KeyLifecycleCommand> sign({
    required String applicationId,
    required String releaseId,
    required int commandSequence,
    required String previousStateDigest,
    required E1KeyLifecycleOperation operation,
    required String signerKeyId,
    String? targetKeyId,
    String? newKeyId,
    List<int>? newPublicKey,
    Set<E1ReleaseKeyRole>? newRoles,
    required Future<List<int>> Function(List<int> message) signer,
  }) async {
    _validateFields(
      applicationId: applicationId,
      releaseId: releaseId,
      commandSequence: commandSequence,
      previousStateDigest: previousStateDigest,
      operation: operation,
      signerKeyId: signerKeyId,
      targetKeyId: targetKeyId,
      newKeyId: newKeyId,
      newPublicKey: newPublicKey,
      newRoles: newRoles,
    );
    final signature = await signer(
      _message(
        _bodyFor(
          applicationId: applicationId,
          releaseId: releaseId,
          commandSequence: commandSequence,
          previousStateDigest: previousStateDigest,
          operation: operation,
          signerKeyId: signerKeyId,
          targetKeyId: targetKeyId,
          newKeyId: newKeyId,
          newPublicKey: newPublicKey,
          newRoles: newRoles,
        ),
      ),
    );
    if (signature.length != 64) {
      throw const FormatException(
        'Lifecycle command signature must be 64 bytes',
      );
    }
    return E1KeyLifecycleCommand._(
      applicationId: applicationId,
      releaseId: releaseId,
      commandSequence: commandSequence,
      previousStateDigest: previousStateDigest,
      operation: operation,
      signerKeyId: signerKeyId,
      targetKeyId: targetKeyId,
      newKeyId: newKeyId,
      newPublicKey: newPublicKey,
      newRoles: newRoles,
      signatureBytes: signature,
    );
  }

  factory E1KeyLifecycleCommand.decode(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Lifecycle command exceeds byte limit');
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object {
      throw const FormatException('Lifecycle command is not strict UTF-8 JSON');
    }
    const fields = <String>{
      'algorithm',
      'applicationId',
      'commandSequence',
      'commandVersion',
      'newKeyId',
      'newPublicKey',
      'newRoles',
      'operation',
      'previousStateDigest',
      'releaseId',
      'signature',
      'signerKeyId',
      'targetKeyId',
    };
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(fields).isNotEmpty ||
        fields.difference(decoded.keys.toSet()).isNotEmpty ||
        decoded['algorithm'] != algorithm ||
        decoded['commandVersion'] != commandVersion ||
        decoded['applicationId'] is! String ||
        decoded['releaseId'] is! String ||
        decoded['commandSequence'] is! int ||
        decoded['previousStateDigest'] is! String ||
        decoded['operation'] is! String ||
        decoded['signerKeyId'] is! String ||
        (decoded['targetKeyId'] != null && decoded['targetKeyId'] is! String) ||
        (decoded['newKeyId'] != null && decoded['newKeyId'] is! String) ||
        (decoded['newPublicKey'] != null &&
            decoded['newPublicKey'] is! String) ||
        (decoded['newRoles'] != null &&
            decoded['newRoles'] is! List<Object?>) ||
        decoded['signature'] is! String) {
      throw const FormatException('Invalid lifecycle command fields');
    }
    final operation = _enumByName(
      E1KeyLifecycleOperation.values,
      decoded['operation']! as String,
      'lifecycle operation',
    );
    List<int>? newPublicKey;
    if (decoded['newPublicKey'] != null) {
      newPublicKey = _decodeCanonicalBase64(
        decoded['newPublicKey']! as String,
        'new public key',
      );
    }
    Set<E1ReleaseKeyRole>? newRoles;
    if (decoded['newRoles'] != null) {
      final roles = <E1ReleaseKeyRole>{};
      for (final rawRole in decoded['newRoles']! as List<Object?>) {
        if (rawRole is! String) {
          throw const FormatException('Invalid lifecycle command role');
        }
        roles.add(
          _enumByName(E1ReleaseKeyRole.values, rawRole, 'lifecycle role'),
        );
      }
      newRoles = roles;
    }
    final signature = _decodeCanonicalBase64(
      decoded['signature']! as String,
      'lifecycle signature',
    );
    if (signature.length != 64) {
      throw const FormatException('Invalid lifecycle signature length');
    }
    final command = E1KeyLifecycleCommand._(
      applicationId: decoded['applicationId']! as String,
      releaseId: decoded['releaseId']! as String,
      commandSequence: decoded['commandSequence']! as int,
      previousStateDigest: decoded['previousStateDigest']! as String,
      operation: operation,
      signerKeyId: decoded['signerKeyId']! as String,
      targetKeyId: decoded['targetKeyId'] as String?,
      newKeyId: decoded['newKeyId'] as String?,
      newPublicKey: newPublicKey,
      newRoles: newRoles,
      signatureBytes: signature,
    );
    _validateFields(
      applicationId: command.applicationId,
      releaseId: command.releaseId,
      commandSequence: command.commandSequence,
      previousStateDigest: command.previousStateDigest,
      operation: command.operation,
      signerKeyId: command.signerKeyId,
      targetKeyId: command.targetKeyId,
      newKeyId: command.newKeyId,
      newPublicKey: command.newPublicKey,
      newRoles: command.newRoles,
    );
    final canonical = utf8.encode(
      _canonicalJson(<String, Object?>{
        ...command._body(),
        'signature': base64.encode(command.signatureBytes),
      }),
    );
    if (!_equalBytes(bytes, canonical)) {
      throw const FormatException('Lifecycle command is not canonical');
    }
    return command;
  }

  List<int> encodeBytes() => utf8.encode(encode());

  String encode() => _canonicalJson(<String, Object?>{
    ..._body(),
    'signature': base64.encode(signatureBytes),
  });

  Future<bool> verify(List<int> publicKeyBytes) async {
    if (publicKeyBytes.length != 32 || signatureBytes.length != 64) {
      return false;
    }
    try {
      return await _ed25519.verify(
        _message(_body()),
        signature: Signature(
          signatureBytes,
          publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }

  Map<String, Object?> _body() => _bodyFor(
    applicationId: applicationId,
    releaseId: releaseId,
    commandSequence: commandSequence,
    previousStateDigest: previousStateDigest,
    operation: operation,
    signerKeyId: signerKeyId,
    targetKeyId: targetKeyId,
    newKeyId: newKeyId,
    newPublicKey: newPublicKey,
    newRoles: newRoles,
  );

  static Map<String, Object?> _bodyFor({
    required String applicationId,
    required String releaseId,
    required int commandSequence,
    required String previousStateDigest,
    required E1KeyLifecycleOperation operation,
    required String signerKeyId,
    required String? targetKeyId,
    required String? newKeyId,
    required List<int>? newPublicKey,
    required Set<E1ReleaseKeyRole>? newRoles,
  }) => <String, Object?>{
    'algorithm': algorithm,
    'applicationId': applicationId,
    'commandSequence': commandSequence,
    'commandVersion': commandVersion,
    'newKeyId': newKeyId,
    'newPublicKey': newPublicKey == null ? null : base64.encode(newPublicKey),
    'newRoles': newRoles == null ? null : _roleNames(newRoles),
    'operation': operation.name,
    'previousStateDigest': previousStateDigest,
    'releaseId': releaseId,
    'signerKeyId': signerKeyId,
    'targetKeyId': targetKeyId,
  };

  static Uint8List _message(Map<String, Object?> body) => Uint8List.fromList(
    <int>[..._domain, ...utf8.encode(_canonicalJson(body))],
  );

  static void _validateFields({
    required String applicationId,
    required String releaseId,
    required int commandSequence,
    required String previousStateDigest,
    required E1KeyLifecycleOperation operation,
    required String signerKeyId,
    required String? targetKeyId,
    required String? newKeyId,
    required List<int>? newPublicKey,
    required Set<E1ReleaseKeyRole>? newRoles,
  }) {
    _validateComponent(applicationId, 'application ID');
    _validateComponent(releaseId, 'release ID');
    if (commandSequence < 1 || commandSequence > 0x7fffffffffffffff) {
      throw const FormatException('Lifecycle command sequence is invalid');
    }
    _validateSha256Digest(previousStateDigest, 'previous state digest');
    _validateKeyId(signerKeyId);
    if (targetKeyId != null) _validateKeyId(targetKeyId);
    if (newKeyId != null) _validateKeyId(newKeyId);
    if (newPublicKey != null) _validatePublicKey(newPublicKey);
    if (newRoles != null && newRoles.isEmpty) {
      throw const FormatException('Lifecycle command roles must not be empty');
    }
    if (newRoles != null && newRoles.contains(E1ReleaseKeyRole.recovery)) {
      throw const FormatException(
        'Lifecycle commands cannot delegate recovery',
      );
    }
    switch (operation) {
      case E1KeyLifecycleOperation.add:
        if (targetKeyId != null ||
            newKeyId == null ||
            newPublicKey == null ||
            newRoles == null) {
          throw const FormatException('Add command fields are invalid');
        }
      case E1KeyLifecycleOperation.retire:
      case E1KeyLifecycleOperation.revoke:
        if (targetKeyId == null ||
            newKeyId != null ||
            newPublicKey != null ||
            newRoles != null) {
          throw const FormatException('Key state command fields are invalid');
        }
      case E1KeyLifecycleOperation.recover:
        if (targetKeyId == null ||
            newKeyId == null ||
            newPublicKey == null ||
            newRoles == null) {
          throw const FormatException('Recovery command fields are invalid');
        }
    }
  }
}

/// Identity of an artifact after the existing signature, binding, and runtime
/// decoder checks have succeeded.
///
/// This class deliberately does not verify signatures. The coordinator must
/// construct it only after [E1SignedPatchEnvelope.verify] or the equivalent
/// Patch Format v1 verification and E0 compatibility checks have passed.
final class E1VerifiedArtifactIdentity {
  E1VerifiedArtifactIdentity({
    required this.keyId,
    required this.sequence,
    required this.digest,
  }) {
    _validateKeyId(keyId);
    if (sequence < 1 || sequence > 0x7fffffffffffffff) {
      throw const FormatException('Artifact sequence is invalid');
    }
    _validateSha256Digest(digest, 'artifact digest');
  }

  factory E1VerifiedArtifactIdentity.fromBytes({
    required String keyId,
    required int sequence,
    required List<int> envelopeBytes,
  }) => E1VerifiedArtifactIdentity(
    keyId: keyId,
    sequence: sequence,
    digest: _sha256(envelopeBytes),
  );

  final String keyId;
  final int sequence;
  final String digest;

  Map<String, Object?> toJson() => <String, Object?>{
    'digest': digest,
    'keyId': keyId,
    'sequence': sequence,
  };

  factory E1VerifiedArtifactIdentity.fromJson(Object? value) {
    const fields = <String>{'digest', 'keyId', 'sequence'};
    if (value is! Map<String, Object?> ||
        value.keys.toSet().difference(fields).isNotEmpty ||
        fields.difference(value.keys.toSet()).isNotEmpty ||
        value['digest'] is! String ||
        value['keyId'] is! String ||
        value['sequence'] is! int) {
      throw const FormatException('Invalid remembered artifact identity');
    }
    return E1VerifiedArtifactIdentity(
      keyId: value['keyId']! as String,
      sequence: value['sequence']! as int,
      digest: value['digest']! as String,
    );
  }

  bool sameAs(E1VerifiedArtifactIdentity other) =>
      keyId == other.keyId &&
      sequence == other.sequence &&
      digest == other.digest;
}

/// Bounded anti-replay ledger for already authenticated artifacts.
///
/// The E1 controller stores one instance of this ledger in the same
/// checksummed record as trust state, executable selection, and patch
/// high-water. It is policy data inside that journal, not a second persistence
/// or authority path.
final class E1ArtifactReplayLedger {
  E1ArtifactReplayLedger._({
    required this.releaseId,
    required this.highWaterSequence,
    required this.highWaterDigest,
    required this.activeArtifactDigest,
    required Map<String, E1VerifiedArtifactIdentity> artifacts,
  }) : artifacts = Map.unmodifiable(artifacts) {
    _validateComponent(releaseId, 'release ID');
    if (highWaterSequence < 0 ||
        highWaterSequence > 0x7fffffffffffffff ||
        (highWaterSequence == 0) != (highWaterDigest == null)) {
      throw const FormatException('Artifact high-water is invalid');
    }
    final storedHighWaterDigest = highWaterDigest;
    if (storedHighWaterDigest != null) {
      _validateSha256Digest(
        storedHighWaterDigest,
        'artifact high-water digest',
      );
    }
    final storedActiveArtifactDigest = activeArtifactDigest;
    if (storedActiveArtifactDigest != null) {
      _validateSha256Digest(
        storedActiveArtifactDigest,
        'active artifact digest',
      );
      if (!artifacts.containsKey(storedActiveArtifactDigest)) {
        throw const FormatException('Active artifact is not in the ledger');
      }
    }
    if (artifacts.length > E1KeyLifecycleLimits.maxRememberedArtifacts) {
      throw const FormatException('Artifact ledger exceeds its bound');
    }
    for (final entry in artifacts.entries) {
      if (entry.key != entry.value.digest) {
        throw const FormatException('Artifact ledger digest index mismatch');
      }
    }
  }

  factory E1ArtifactReplayLedger.empty({required String releaseId}) =>
      E1ArtifactReplayLedger._(
        releaseId: releaseId,
        highWaterSequence: 0,
        highWaterDigest: null,
        activeArtifactDigest: null,
        artifacts: const <String, E1VerifiedArtifactIdentity>{},
      );

  factory E1ArtifactReplayLedger.fromJson(
    Object? value, {
    required String expectedReleaseId,
  }) {
    const fields = <String>{
      'activeArtifactDigest',
      'artifacts',
      'highWaterDigest',
      'highWaterSequence',
      'releaseId',
    };
    if (value is! Map<String, Object?> ||
        value.keys.toSet().difference(fields).isNotEmpty ||
        fields.difference(value.keys.toSet()).isNotEmpty ||
        value['releaseId'] != expectedReleaseId ||
        value['artifacts'] is! List<Object?> ||
        value['highWaterSequence'] is! int ||
        (value['highWaterDigest'] != null &&
            value['highWaterDigest'] is! String) ||
        (value['activeArtifactDigest'] != null &&
            value['activeArtifactDigest'] is! String)) {
      throw const FormatException('Invalid remembered artifact ledger');
    }
    final artifacts = <String, E1VerifiedArtifactIdentity>{};
    for (final raw in value['artifacts']! as List<Object?>) {
      final artifact = E1VerifiedArtifactIdentity.fromJson(raw);
      if (artifacts.containsKey(artifact.digest)) {
        throw const FormatException('Duplicate remembered artifact digest');
      }
      artifacts[artifact.digest] = artifact;
    }
    return E1ArtifactReplayLedger._(
      releaseId: expectedReleaseId,
      highWaterSequence: value['highWaterSequence']! as int,
      highWaterDigest: value['highWaterDigest'] as String?,
      activeArtifactDigest: value['activeArtifactDigest'] as String?,
      artifacts: artifacts,
    );
  }

  final String releaseId;
  final int highWaterSequence;
  final String? highWaterDigest;
  final String? activeArtifactDigest;
  final Map<String, E1VerifiedArtifactIdentity> artifacts;

  String get canonicalJson => _canonicalJson(toJson());

  int get metadataBytes => utf8.encode(canonicalJson).length;

  Map<String, Object?> toJson() => <String, Object?>{
    'activeArtifactDigest': activeArtifactDigest,
    'artifacts': [
      for (final artifact
          in artifacts.values.toList()
            ..sort((left, right) => left.digest.compareTo(right.digest)))
        artifact.toJson(),
    ],
    'highWaterDigest': highWaterDigest,
    'highWaterSequence': highWaterSequence,
    'releaseId': releaseId,
  };

  E1ArtifactAdmission admitNewArtifact({
    required E1KeyLifecycleState lifecycle,
    required E1VerifiedArtifactIdentity artifact,
  }) {
    if (lifecycle.releaseId != releaseId) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.releaseMismatch,
        ledger: this,
      );
    }
    final key = lifecycle[artifact.keyId];
    if (key == null) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.unknownKey,
        ledger: this,
      );
    }
    if (key.state == E1ReleaseKeyState.revoked) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.keyRevoked,
        ledger: this,
      );
    }
    if (key.state == E1ReleaseKeyState.retired) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.keyRetiredForNewArtifact,
        ledger: this,
      );
    }
    if (!key.acceptsNewArtifacts) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.keyRoleNotAllowed,
        ledger: this,
      );
    }
    final existing = artifacts[artifact.digest];
    if (existing != null && !existing.sameAs(artifact)) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.artifactMismatch,
        ledger: this,
      );
    }
    if (artifact.sequence < highWaterSequence) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.stale,
        ledger: this,
      );
    }
    if (artifact.sequence == highWaterSequence) {
      if (artifact.digest != highWaterDigest) {
        return E1ArtifactAdmission._(
          status: E1ArtifactAdmissionStatus.equivocation,
          ledger: this,
        );
      }
      if (activeArtifactDigest == artifact.digest) {
        return E1ArtifactAdmission._(
          status: E1ArtifactAdmissionStatus.idempotent,
          ledger: this,
        );
      }
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.replayAfterRollback,
        ledger: this,
      );
    }
    if (existing != null) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.artifactMismatch,
        ledger: this,
      );
    }
    if (artifacts.length >= E1KeyLifecycleLimits.maxRememberedArtifacts) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.ledgerFull,
        ledger: this,
      );
    }
    final nextArtifacts = <String, E1VerifiedArtifactIdentity>{
      ...artifacts,
      artifact.digest: artifact,
    };
    return E1ArtifactAdmission._(
      status: E1ArtifactAdmissionStatus.accepted,
      ledger: E1ArtifactReplayLedger._(
        releaseId: releaseId,
        highWaterSequence: artifact.sequence,
        highWaterDigest: artifact.digest,
        activeArtifactDigest: artifact.digest,
        artifacts: nextArtifacts,
      ),
    );
  }

  /// Revalidates an exact artifact already recorded before key retirement.
  E1ArtifactAdmission verifyRetainedArtifact({
    required E1KeyLifecycleState lifecycle,
    required E1VerifiedArtifactIdentity artifact,
  }) {
    if (lifecycle.releaseId != releaseId) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.releaseMismatch,
        ledger: this,
      );
    }
    final stored = artifacts[artifact.digest];
    if (stored == null) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.notRetained,
        ledger: this,
      );
    }
    if (!stored.sameAs(artifact)) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.artifactMismatch,
        ledger: this,
      );
    }
    final key = lifecycle[artifact.keyId];
    if (key == null) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.unknownKey,
        ledger: this,
      );
    }
    if (key.state == E1ReleaseKeyState.revoked) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.keyRevoked,
        ledger: this,
      );
    }
    if (!key.verifiesRetainedArtifacts) {
      return E1ArtifactAdmission._(
        status: E1ArtifactAdmissionStatus.keyRoleNotAllowed,
        ledger: this,
      );
    }
    return E1ArtifactAdmission._(
      status: E1ArtifactAdmissionStatus.retained,
      ledger: this,
    );
  }

  /// Selects the installed base without lowering the patch high-water.
  E1ArtifactReplayLedger rollbackToBase() => E1ArtifactReplayLedger._(
    releaseId: releaseId,
    highWaterSequence: highWaterSequence,
    highWaterDigest: highWaterDigest,
    activeArtifactDigest: null,
    artifacts: artifacts,
  );

  /// Selects an exact remembered artifact as active without changing its
  /// sequence high-water. Recovery uses this when an older last-known-good
  /// artifact replaces a failed candidate.
  E1ArtifactReplayLedger selectActiveArtifact(String? digest) {
    if (digest != null && !artifacts.containsKey(digest)) {
      throw const FormatException('Active artifact is not remembered');
    }
    return E1ArtifactReplayLedger._(
      releaseId: releaseId,
      highWaterSequence: highWaterSequence,
      highWaterDigest: highWaterDigest,
      activeArtifactDigest: digest,
      artifacts: artifacts,
    );
  }
}

final class E1ArtifactAdmission {
  const E1ArtifactAdmission._({required this.status, required this.ledger});

  final E1ArtifactAdmissionStatus status;
  final E1ArtifactReplayLedger ledger;

  bool get accepted =>
      status == E1ArtifactAdmissionStatus.accepted ||
      status == E1ArtifactAdmissionStatus.idempotent ||
      status == E1ArtifactAdmissionStatus.retained;
}

String _sha256(List<int> bytes) => crypto.sha256.convert(bytes).toString();

void _validateComponent(String value, String label) {
  if (value.isEmpty || value.length > 256 || value == '.' || value == '..') {
    throw FormatException('Invalid $label');
  }
  if (value.contains('/') ||
      value.contains(r'\') ||
      value.codeUnits.any((unit) => unit == 0 || unit < 0x20)) {
    throw FormatException('Invalid $label');
  }
}

void _validateKeyId(String keyId) {
  if (!RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(keyId)) {
    throw const FormatException('Invalid release key ID');
  }
}

void _validatePublicKey(List<int> bytes) {
  if (bytes.length != 32) {
    throw const FormatException('Ed25519 public keys must contain 32 bytes');
  }
}

void _validateSha256Digest(String value, String label) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('Invalid $label');
  }
}

List<String> _roleNames(Set<E1ReleaseKeyRole> roles) =>
    roles.map((role) => role.name).toList()..sort();

T _enumByName<T extends Enum>(List<T> values, String name, String label) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('Invalid $label');
}

List<int> _decodeCanonicalBase64(String value, String label) {
  try {
    final decoded = base64.decode(value);
    if (base64.encode(decoded) != value) {
      throw FormatException('Non-canonical base64 in $label');
    }
    return decoded;
  } on FormatException {
    throw FormatException('Invalid base64 in $label');
  }
}

Object? _canonicalValue(Object? value) {
  if (value is List<Object?>) {
    return value.map(_canonicalValue).toList(growable: false);
  }
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalValue(value[key]),
    };
  }
  return value;
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalValue(value));

bool _equalBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
