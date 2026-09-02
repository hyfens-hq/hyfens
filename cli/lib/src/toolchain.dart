import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:hyfens_compiler/compiler.dart';
import 'package:hyfens_patch_format/patch_format.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'canonical.dart';
import 'configuration.dart';
import 'diagnostics.dart';
import 'discovery.dart';
import 'graph.dart';
import 'instrumentation.dart';
import 'project.dart';
import 'signing.dart';
import 'source_fingerprints.dart';

// The CLI version is part of release identity and must match cli/pubspec.yaml
// and the version used by the release workflows.
const hyfensToolVersion = '0.1.0';
const _bridgeExtensionType = 9;
const _rollbackStateVersion = 1;
const _rollbackTargetBaseAot = 'base-aot';
const _rollbackStatePrimaryName = 'rollback-state-a.json';
const _rollbackStateBackupName = 'rollback-state-b.json';
const _statusScanLimit = 256;
final _patchFileName = RegExp(r'^(\d{6})\.patch$');

String _checkedReleaseId(String value) {
  if (!RegExp(r'^[A-Za-z0-9:_-]{1,256}$').hasMatch(value)) {
    throw ToolFailure.single(
      exitCode: ToolExitCode.compatibility,
      code: 'R5002',
      summary: 'Release ID is invalid',
      detail: value,
      action: 'Use the exact release ID produced by hyfens release.',
    );
  }
  return value;
}

final class ToolStore {
  const ToolStore(this.project);

  final FlutterProject project;

  Directory get root => project.toolDirectory;
  Directory get releases => Directory(p.join(root.path, 'releases'));
  Directory get patches => Directory(p.join(root.path, 'patches'));
  Directory get keys => Directory(p.join(root.path, 'keys'));
  Directory get buildStaging => Directory(p.join(root.path, '.builds'));

  Directory release(String releaseId) =>
      Directory(p.join(releases.path, _checkedReleaseId(releaseId)));

  File releaseMetadata(String releaseId) =>
      File(p.join(release(releaseId).path, 'metadata.json'));

  File releaseManifest(String releaseId) =>
      File(p.join(release(releaseId).path, 'manifest.json'));

  File patch(String releaseId, int sequence) => File(
    p.join(
      patchDirectory(releaseId).path,
      '${sequence.toString().padLeft(6, '0')}.patch',
    ),
  );

  Directory patchDirectory(String releaseId) =>
      Directory(p.join(patches.path, _checkedReleaseId(releaseId)));

  File sequenceFile(String releaseId) =>
      File(p.join(patchDirectory(releaseId).path, 'sequence.json'));

  File rollbackStatePrimary(String releaseId) =>
      File(p.join(patchDirectory(releaseId).path, _rollbackStatePrimaryName));

  File rollbackStateBackup(String releaseId) =>
      File(p.join(patchDirectory(releaseId).path, _rollbackStateBackupName));

  File rollbackControl(String releaseId) =>
      File(p.join(patchDirectory(releaseId).path, 'rollback-control.json'));

  /// Inventories only bounded local metadata names and counts. It does not
  /// parse release/source records, read patch bytes, inspect keys, or contact
  /// a running application.
  Future<ToolStoreInventory> inspectInventory() async {
    final rootType = FileSystemEntity.typeSync(root.path, followLinks: false);
    if (rootType == FileSystemEntityType.notFound) {
      return const ToolStoreInventory(
        status: 'NOT_INITIALIZED',
        rootPresent: false,
        requiredDirectoriesPresent: false,
        releaseDirectories: 0,
        releaseMetadataFiles: 0,
        patchDirectories: 0,
        patchArtifacts: 0,
        scanTruncated: false,
        scanError: false,
      );
    }
    if (rootType != FileSystemEntityType.directory) {
      return const ToolStoreInventory(
        status: 'INCOMPLETE',
        rootPresent: false,
        requiredDirectoriesPresent: false,
        releaseDirectories: 0,
        releaseMetadataFiles: 0,
        patchDirectories: 0,
        patchArtifacts: 0,
        scanTruncated: false,
        scanError: true,
      );
    }

    final requiredDirectories = <Directory>[releases, patches, keys];
    final requiredDirectoriesPresent = requiredDirectories.every(
      _isStatusDirectory,
    );
    final releaseScan = await _scanStatusReleases(releases);
    final patchScan = await _scanStatusPatches(patches);
    final scanTruncated = releaseScan.truncated || patchScan.truncated;
    final scanError = releaseScan.error || patchScan.error;
    final complete = requiredDirectoriesPresent && !scanError;
    return ToolStoreInventory(
      status: complete ? 'READY' : 'INCOMPLETE',
      rootPresent: true,
      requiredDirectoriesPresent: requiredDirectoriesPresent,
      releaseDirectories: releaseScan.directories,
      releaseMetadataFiles: releaseScan.matchingFiles,
      patchDirectories: patchScan.directories,
      patchArtifacts: patchScan.matchingFiles,
      scanTruncated: scanTruncated,
      scanError: scanError,
    );
  }

  File resolveConfiguredPath(String value, {bool allowExternal = false}) {
    final normalized = value.replaceAll(r'\', '/');
    final rootPath = p.normalize(project.root.absolute.path);
    final resolved = p.normalize(p.join(rootPath, normalized));
    final absoluteInput =
        p.isAbsolute(normalized) ||
        normalized.startsWith('//') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized);
    if (allowExternal && absoluteInput) return File(p.normalize(normalized));
    if (normalized.isEmpty ||
        absoluteInput ||
        (resolved != rootPath && !p.isWithin(rootPath, resolved))) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1205',
        summary: 'Tool path escapes the project',
        detail: value,
        action: 'Use a project-relative path in tool.yaml.',
      );
    }
    return File(p.join(project.root.path, normalized));
  }

  Future<void> ensure() async {
    await root.create(recursive: true);
    await releases.create(recursive: true);
    await patches.create(recursive: true);
    await keys.create(recursive: true);
  }

  Future<void> writeRelease(
    ReleaseRecord record, {
    List<File> artifacts = const <File>[],
  }) async {
    await ensure();
    final destination = release(record.releaseId);
    if (destination.existsSync()) {
      final existing = _readRelease(record.releaseId);
      if (!_releaseIsComplete(existing)) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1606',
          summary: 'Existing release baseline has no usable artifact',
          detail: record.releaseId,
          action: 'Create a new release baseline; the incomplete evidence was preserved.',
        );
      }
      if (_releaseComparable(existing) != _releaseComparable(record)) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.compatibility,
          code: 'R5003',
          summary: 'Release identity already has different metadata',
          detail: record.releaseId,
          action: 'Inspect the existing baseline; do not overwrite it.',
        );
      }
      return;
    }
    final staging = Directory(
      p.join(releases.path, '.tmp-${record.releaseId}-${pid}'),
    );
    if (staging.existsSync()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      await writeAtomicText(
        File(p.join(staging.path, 'metadata.json')),
        record.encode(),
      );
      await writeAtomicText(
        File(p.join(staging.path, 'manifest.json')),
        record.manifest.encode(),
      );
      await writeAtomicText(
        File(p.join(staging.path, 'package-graph.json')),
        canonicalJson(record.graph),
      );
      await writeAtomicText(
        File(p.join(staging.path, 'source-fingerprints.json')),
        canonicalJson(record.sourceFingerprints),
      );
      await writeAtomicText(
        File(p.join(staging.path, 'instrumentation.json')),
        canonicalJson(record.instrumentation),
      );
      await writeAtomicText(
        File(p.join(staging.path, 'build.json')),
        canonicalJson(record.build),
      );
      if (artifacts.isNotEmpty) {
        final artifactDirectory = Directory(p.join(staging.path, 'artifacts'));
        await artifactDirectory.create(recursive: true);
        for (final artifact in artifacts) {
          if (!artifact.existsSync()) {
            throw ToolFailure.single(
              exitCode: ToolExitCode.environment,
              code: 'T1604',
              summary: 'Release artifact disappeared before baseline commit',
              detail: artifact.path,
              action:
                  'Retry the release build; the baseline was not activated.',
            );
          }
          await artifact.copy(
            p.join(artifactDirectory.path, p.basename(artifact.path)),
          );
        }
      }
      await staging.rename(destination.path);
    } finally {
      if (staging.existsSync()) await staging.delete(recursive: true);
    }
  }

  ReleaseRecord readRelease(String releaseId) {
    final metadata = releaseMetadata(releaseId);
    if (!metadata.existsSync()) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'R5001',
        summary: 'Release baseline not found',
        detail: releaseId,
        action: 'Run hyfens release for the target platform first.',
      );
    }
    late final ReleaseRecord record;
    try {
      record = _readRelease(releaseId);
    } on Object catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'R5007',
        summary: 'Release baseline metadata is malformed',
        detail: '$error',
        action: 'Preserve the evidence and create a new release baseline.',
      );
    }
    if (!_releaseIsComplete(record)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1606',
        summary: 'Release baseline has no usable artifact',
        detail: releaseId,
        action: 'Create a new release baseline; the incomplete evidence was preserved.',
      );
    }
    return record;
  }

  List<ReleaseRecord> listReleases() {
    if (!releases.existsSync()) return const <ReleaseRecord>[];
    final records = <ReleaseRecord>[];
    for (final entry in releases.listSync(followLinks: false)) {
      if (entry is! Directory || p.basename(entry.path).startsWith('.'))
        continue;
      final metadata = File(p.join(entry.path, 'metadata.json'));
      if (!metadata.existsSync()) continue;
      try {
        final record = ReleaseRecord.decode(metadata.readAsStringSync());
        if (_releaseIsComplete(record)) records.add(record);
      } on Object {
        // Ignore malformed local evidence during automatic target inference;
        // an explicit target reports R5007 with the parse detail.
      }
    }
    records.sort((left, right) => left.releaseId.compareTo(right.releaseId));
    return records;
  }

  int nextSequence(String releaseId) {
    final directory = patchDirectory(releaseId);
    var highest = 0;
    if (directory.existsSync()) {
      for (final entry in directory.listSync(followLinks: false)) {
        final match = RegExp(r'^(\d+)\.patch$')
            .firstMatch(p.basename(entry.path));
        if (match != null) {
          final parsed = int.tryParse(match.group(1)!);
          if (parsed == null || parsed <= 0) {
            throw ToolFailure.single(
              exitCode: ToolExitCode.compatibility,
              code: 'R5008',
              summary: 'Patch sequence metadata is malformed',
              detail: entry.path,
              action: 'Preserve the patch directory and repair its sequence metadata deliberately.',
            );
          }
          highest = highest > parsed ? highest : parsed;
        }
      }
    }
    final storedSequence = _readSequenceLast(releaseId);
    if (storedSequence != null) {
      highest = highest > storedSequence ? highest : storedSequence;
    }
    final rollback = readRollbackState(releaseId);
    if (rollback != null) {
      highest = highest > rollback.highWaterSequence
          ? highest
          : rollback.highWaterSequence;
    }
    return highest + 1;
  }

  Future<void> commitSequence(String releaseId, int sequence) async {
    if (sequence <= 0) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'R5008',
        summary: 'Patch sequence metadata is malformed',
        detail: '$sequence',
        action: 'Use the next sequence produced by the tool; never reset sequence state.',
      );
    }
    final priorSequence = _readSequenceLast(releaseId) ?? 0;
    final rollback = readRollbackState(releaseId);
    final durableHighWater = priorSequence > (rollback?.highWaterSequence ?? 0)
        ? priorSequence
        : (rollback?.highWaterSequence ?? 0);
    if (sequence < durableHighWater) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: ToolDiagnosticCodes.rollbackHighWaterRegression,
        summary: 'Patch sequence would lower the durable high-water',
        detail: '$sequence < $durableHighWater for $releaseId',
        action: 'Preserve the existing sequence state and create a new patch with a higher sequence.',
      );
    }
    await writeAtomicText(
      sequenceFile(releaseId),
      canonicalJson(<String, Object>{'version': 1, 'last': sequence}) + '\n',
    );
  }

  /// Reads the durable developer-side rollback journal, if one exists.
  ///
  /// The two copies follow the same newest-consistent-copy rule as E1. A
  /// malformed or conflicting journal is never treated as a fresh sequence
  /// zero state because doing so would make old patches eligible again.
  RollbackState? readRollbackState(String releaseId) {
    final files = <File>[
      rollbackStatePrimary(releaseId),
      rollbackStateBackup(releaseId),
    ];
    final existing = files
        .where((file) => file.existsSync())
        .toList(growable: false);
    if (existing.isEmpty) return null;
    final valid = <RollbackState>[];
    for (final file in existing) {
      try {
        if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw const FormatException('rollback state is not a regular file');
        }
        valid.add(
          RollbackState.decode(
            file.readAsStringSync(),
            expectedReleaseId: releaseId,
          ),
        );
      } on Object {
        // A bad copy is only recoverable when the other copy is valid. If both
        // copies fail, the caller receives the stable fail-closed diagnostic.
      }
    }
    if (valid.isEmpty) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: ToolDiagnosticCodes.rollbackStateInvalid,
        summary: 'Rollback state is malformed or unavailable',
        detail: existing.map((file) => file.path).join(', '),
        action: 'Preserve both state copies and recover the release deliberately; do not delete them to reset replay protection.',
      );
    }
    if (valid.length == 2) {
      final left = valid[0];
      final right = valid[1];
      if ((left.generation - right.generation).abs() > 1 ||
          (left.generation == right.generation &&
              left.encode() != right.encode())) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.compatibility,
          code: ToolDiagnosticCodes.rollbackStateInvalid,
          summary: 'Rollback state copies disagree',
          detail: existing.map((file) => file.path).join(', '),
          action: 'Preserve the evidence and recover from a trusted release; do not reset high-water state.',
        );
      }
    }
    valid.sort((left, right) => right.generation.compareTo(left.generation));
    return valid.first;
  }

  /// Records an explicit reset to the installed AOT base without changing the
  /// durable sequence high-water or deleting any patch evidence.
  Future<RollbackState> commitBaseRollback(
    String releaseId, {
    required int highWaterSequence,
    required String? highWaterDigest,
  }) async {
    if (highWaterSequence < 0 ||
        (highWaterSequence == 0) != (highWaterDigest == null) ||
        (highWaterDigest != null &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(highWaterDigest))) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: ToolDiagnosticCodes.rollbackHighWaterUnavailable,
        summary: 'Durable patch high-water cannot be established',
        detail: releaseId,
        action: 'Preserve the patch directory and recover its sequence state before rolling back.',
      );
    }
    final prior = readRollbackState(releaseId);
    if (prior != null) {
      if (highWaterSequence < prior.highWaterSequence) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.compatibility,
          code: ToolDiagnosticCodes.rollbackHighWaterRegression,
          summary: 'Rollback would lower the durable high-water',
          detail:
              '$highWaterSequence < ${prior.highWaterSequence} for $releaseId',
          action: 'Keep the existing rollback journal and use a higher sequence for future patches.',
        );
      }
      if (highWaterSequence == prior.highWaterSequence &&
          highWaterDigest != prior.highWaterDigest) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.compatibility,
          code: ToolDiagnosticCodes.rollbackHighWaterRegression,
          summary: 'Rollback high-water digest changed at the same sequence',
          detail: releaseId,
          action: 'Preserve the existing journal and inspect the patch evidence for tampering.',
        );
      }
    }
    final next = RollbackState(
      releaseId: releaseId,
      generation: (prior?.generation ?? 0) + 1,
      target: _rollbackTargetBaseAot,
      highWaterSequence: highWaterSequence,
      highWaterDigest: highWaterDigest,
    );
    final directory = patchDirectory(releaseId);
    await directory.create(recursive: true);
    try {
      // Keep the older valid copy until the new generation has been written.
      await writeAtomicText(rollbackStateBackup(releaseId), next.encode());
      await writeAtomicText(rollbackStatePrimary(releaseId), next.encode());
    } on Object catch (error) {
      try {
        final recovered = readRollbackState(releaseId);
        if (recovered?.encode() == next.encode()) return recovered!;
      } on Object {
        // Fall through to the stable commit diagnostic below.
      }
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: ToolDiagnosticCodes.rollbackStateCommitFailed,
        summary: 'Rollback state could not be committed',
        detail: '$releaseId: $error',
        action: 'Preserve the release, patch evidence, and both state copies; retry only after the storage issue is resolved.',
      );
    }
    return next;
  }

  /// Returns the highest sequence that must remain replay-ineligible and its
  /// known artifact digest. Missing old artifacts are allowed after explicit
  /// cleanup only when the journal already retains the digest.
  RollbackHighWater readRollbackHighWater(String releaseId) {
    final rollback = readRollbackState(releaseId);
    final directory = patchDirectory(releaseId);
    var highestPatch = 0;
    if (directory.existsSync()) {
      for (final entry in directory.listSync(followLinks: false)) {
        final match = _patchFileName.firstMatch(p.basename(entry.path));
        if (match == null) continue;
        if (FileSystemEntity.typeSync(entry.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw ToolFailure.single(
            exitCode: ToolExitCode.compatibility,
            code: ToolDiagnosticCodes.rollbackHighWaterUnavailable,
            summary: 'Patch high-water contains a non-file artifact',
            detail: entry.path,
            action: 'Preserve the patch directory and repair it deliberately; do not follow links during rollback or cleanup.',
          );
        }
        final sequence = int.parse(match.group(1)!);
        highestPatch = highestPatch > sequence ? highestPatch : sequence;
      }
    }
    final sequence = _readSequenceLast(releaseId) ?? 0;
    if (rollback != null && sequence < rollback.highWaterSequence) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: ToolDiagnosticCodes.rollbackHighWaterRegression,
        summary: 'Patch sequence metadata is below the rollback high-water',
        detail: '$sequence < ${rollback.highWaterSequence} for $releaseId',
        action: 'Restore the sequence metadata from trusted evidence; never reset it to replay an old patch.',
      );
    }
    final highest = <int>[
      highestPatch,
      sequence,
      rollback?.highWaterSequence ?? 0,
    ].reduce((left, right) => left > right ? left : right);
    if (highest == 0) return const RollbackHighWater(sequence: 0);

    if (rollback != null && rollback.highWaterSequence == highest) {
      final digest = rollback.highWaterDigest;
      if (digest == null) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.compatibility,
          code: ToolDiagnosticCodes.rollbackHighWaterUnavailable,
          summary: 'Rollback high-water has no accepted artifact digest',
          detail: releaseId,
          action: 'Preserve the journal and patch evidence; do not infer a lower sequence.',
        );
      }
      final artifact = patch(releaseId, highest);
      if (artifact.existsSync() &&
          sha256Hex(artifact.readAsBytesSync()) != digest) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.compatibility,
          code: ToolDiagnosticCodes.rollbackHighWaterUnavailable,
          summary: 'Highest patch evidence does not match rollback state',
          detail: artifact.path,
          action: 'Preserve the evidence and investigate the digest mismatch before retrying.',
        );
      }
      return RollbackHighWater(sequence: highest, digest: digest);
    }

    final artifact = patch(releaseId, highest);
    if (!artifact.existsSync() ||
        FileSystemEntity.typeSync(artifact.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: ToolDiagnosticCodes.rollbackHighWaterUnavailable,
        summary: 'Highest patch sequence has no usable evidence',
        detail: '$releaseId sequence $highest',
        action: 'Preserve the sequence state and recover the missing patch evidence; do not reset high-water.',
      );
    }
    return RollbackHighWater(
      sequence: highest,
      digest: sha256Hex(artifact.readAsBytesSync()),
    );
  }

  int? _readSequenceLast(String releaseId) {
    final sequence = sequenceFile(releaseId);
    if (!sequence.existsSync()) return null;
    try {
      if (FileSystemEntity.typeSync(sequence.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('sequence metadata is not a regular file');
      }
      final raw = jsonDecode(sequence.readAsStringSync());
      final last = raw is Map<String, Object?> ? raw['last'] : null;
      if (last is! int || last <= 0) {
        throw const FormatException('last sequence must be positive');
      }
      return last;
    } on ToolFailure {
      rethrow;
    } on Object catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'R5008',
        summary: 'Patch sequence metadata is malformed',
        detail: '$error',
        action: 'Preserve the patch directory and repair its sequence metadata deliberately.',
      );
    }
  }

  ReleaseRecord _readRelease(String releaseId) =>
      ReleaseRecord.decode(releaseMetadata(releaseId).readAsStringSync());

  bool _releaseIsComplete(ReleaseRecord record) {
    if (!RegExp(r'^[A-Za-z0-9:_-]{1,256}$').hasMatch(record.releaseId)) {
      return false;
    }
    if (record.build['metadataOnly'] == true) return true;
    final artifact = record.build['artifact'];
    return artifact is String &&
        p.basename(artifact) == artifact &&
        File(p.join(release(record.releaseId).path, 'artifacts', artifact))
            .existsSync();
  }
}

final class ToolStoreInventory {
  const ToolStoreInventory({
    required this.status,
    required this.rootPresent,
    required this.requiredDirectoriesPresent,
    required this.releaseDirectories,
    required this.releaseMetadataFiles,
    required this.patchDirectories,
    required this.patchArtifacts,
    required this.scanTruncated,
    required this.scanError,
  });

  final String status;
  final bool rootPresent;
  final bool requiredDirectoriesPresent;
  final int releaseDirectories;
  final int releaseMetadataFiles;
  final int patchDirectories;
  final int patchArtifacts;
  final bool scanTruncated;
  final bool scanError;

  Map<String, Object> toJson() => <String, Object>{
    'status': status,
    'releaseDirectories': releaseDirectories,
    'releaseMetadataFiles': releaseMetadataFiles,
    'patchDirectories': patchDirectories,
    'patchArtifacts': patchArtifacts,
    'scanTruncated': scanTruncated,
  };
}

final class _StatusDirectoryScan {
  const _StatusDirectoryScan({
    required this.directories,
    required this.matchingFiles,
    required this.truncated,
    required this.error,
  });

  final int directories;
  final int matchingFiles;
  final bool truncated;
  final bool error;
}

bool _isStatusDirectory(Directory directory) =>
    FileSystemEntity.typeSync(directory.path, followLinks: false) ==
    FileSystemEntityType.directory;

Future<_StatusDirectoryScan> _scanStatusDirectory(
  Directory directory, {
  String? fileName,
  RegExp? filePattern,
}) async {
  if (!_isStatusDirectory(directory)) {
    return const _StatusDirectoryScan(
      directories: 0,
      matchingFiles: 0,
      truncated: false,
      error: false,
    );
  }
  var directories = 0;
  var matchingFiles = 0;
  var entries = 0;
  var truncated = false;
  try {
    await for (final entry in directory.list(followLinks: false)) {
      if (entries == _statusScanLimit) {
        truncated = true;
        break;
      }
      entries++;
      final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        directories++;
        continue;
      }
      if (type != FileSystemEntityType.file) continue;
      final name = p.basename(entry.path);
      if ((fileName == null || name == fileName) &&
          (filePattern == null || filePattern.hasMatch(name))) {
        matchingFiles++;
      }
    }
  } on Object {
    return _StatusDirectoryScan(
      directories: directories,
      matchingFiles: matchingFiles,
      truncated: truncated,
      error: true,
    );
  }
  return _StatusDirectoryScan(
    directories: directories,
    matchingFiles: matchingFiles,
    truncated: truncated,
    error: false,
  );
}

Future<_StatusDirectoryScan> _scanStatusPatches(Directory directory) async {
  if (!_isStatusDirectory(directory)) {
    return const _StatusDirectoryScan(
      directories: 0,
      matchingFiles: 0,
      truncated: false,
      error: false,
    );
  }
  var directories = 0;
  var matchingFiles = 0;
  var entries = 0;
  var truncated = false;
  var error = false;
  try {
    await for (final entry in directory.list(followLinks: false)) {
      if (entries == _statusScanLimit) {
        truncated = true;
        break;
      }
      entries++;
      if (FileSystemEntity.typeSync(entry.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      directories++;
      final scan = await _scanStatusDirectory(
        Directory(entry.path),
        filePattern: _patchFileName,
      );
      matchingFiles += scan.matchingFiles;
      truncated = truncated || scan.truncated;
      error = error || scan.error;
    }
  } on Object {
    error = true;
  }
  return _StatusDirectoryScan(
    directories: directories,
    matchingFiles: matchingFiles,
    truncated: truncated,
    error: error,
  );
}

Future<_StatusDirectoryScan> _scanStatusReleases(Directory directory) async {
  if (!_isStatusDirectory(directory)) {
    return const _StatusDirectoryScan(
      directories: 0,
      matchingFiles: 0,
      truncated: false,
      error: false,
    );
  }
  var directories = 0;
  var matchingFiles = 0;
  var entries = 0;
  var truncated = false;
  var error = false;
  try {
    await for (final entry in directory.list(followLinks: false)) {
      if (entries == _statusScanLimit) {
        truncated = true;
        break;
      }
      entries++;
      if (FileSystemEntity.typeSync(entry.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      directories++;
      final scan = await _scanStatusDirectory(
        Directory(entry.path),
        fileName: 'metadata.json',
      );
      matchingFiles += scan.matchingFiles;
      truncated = truncated || scan.truncated;
      error = error || scan.error;
    }
  } on Object {
    error = true;
  }
  return _StatusDirectoryScan(
    directories: directories,
    matchingFiles: matchingFiles,
    truncated: truncated,
    error: error,
  );
}

/// Developer-side journal for the explicit base rollback boundary.
///
/// This is not a Patch Format payload and does not authorize runtime code. It
/// records the local lifecycle decision while retaining the E1 invariant that
/// the accepted patch high-water is independent from the active target.
final class RollbackState {
  RollbackState({
    required this.releaseId,
    required this.generation,
    required this.target,
    required this.highWaterSequence,
    required this.highWaterDigest,
  }) {
    if (!RegExp(r'^[A-Za-z0-9:_-]{1,256}$').hasMatch(releaseId) ||
        generation < 0 ||
        target != _rollbackTargetBaseAot ||
        highWaterSequence < 0 ||
        (highWaterSequence == 0) != (highWaterDigest == null) ||
        (highWaterDigest != null &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(highWaterDigest!))) {
      throw ArgumentError('Invalid rollback state invariants');
    }
  }

  final String releaseId;
  final int generation;
  final String target;
  final int highWaterSequence;
  final String? highWaterDigest;

  Map<String, Object?> _body() => <String, Object?>{
    'generation': generation,
    'highWaterDigest': highWaterDigest,
    'highWaterSequence': highWaterSequence,
    'releaseId': releaseId,
    'stateVersion': _rollbackStateVersion,
    'target': target,
  };

  Map<String, Object?> toJson() {
    final body = _body();
    return <String, Object?>{...body, 'checksum': digestJson(body)};
  }

  String encode() => canonicalJson(toJson());

  static RollbackState decode(
    String source, {
    required String expectedReleaseId,
  }) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(_keys).isNotEmpty ||
        _keys.difference(decoded.keys.toSet()).isNotEmpty) {
      throw const FormatException('invalid rollback state fields');
    }
    if (canonicalJson(decoded) != source) {
      throw const FormatException('rollback state is not canonical');
    }
    final body = <String, Object?>{
      for (final key in decoded.keys)
        if (key != 'checksum') key: decoded[key],
    };
    if (decoded['checksum'] != digestJson(body)) {
      throw const FormatException('rollback state checksum mismatch');
    }
    if (decoded['stateVersion'] != _rollbackStateVersion ||
        decoded['releaseId'] != expectedReleaseId ||
        decoded['releaseId'] is! String ||
        decoded['generation'] is! int ||
        decoded['target'] is! String ||
        decoded['highWaterSequence'] is! int ||
        (decoded['highWaterDigest'] != null &&
            decoded['highWaterDigest'] is! String)) {
      throw const FormatException('invalid release-bound rollback state');
    }
    try {
      return RollbackState(
        releaseId: decoded['releaseId']! as String,
        generation: decoded['generation']! as int,
        target: decoded['target']! as String,
        highWaterSequence: decoded['highWaterSequence']! as int,
        highWaterDigest: decoded['highWaterDigest'] as String?,
      );
    } on ArgumentError {
      throw const FormatException('invalid rollback state invariants');
    }
  }

  static const _keys = <String>{
    'checksum',
    'generation',
    'highWaterDigest',
    'highWaterSequence',
    'releaseId',
    'stateVersion',
    'target',
  };
}

final class RollbackHighWater {
  const RollbackHighWater({required this.sequence, this.digest});

  final int sequence;
  final String? digest;
}

String _releaseComparable(ReleaseRecord record) {
  final decoded = jsonDecode(record.encode()) as Map<String, Object?>;
  final build = decoded['build'];
  if (build is Map<String, Object?>) {
    decoded['build'] = <String, Object?>{...build}..remove('elapsedMs');
  }
  return canonicalJson(decoded);
}

final class ReleaseRecord {
  ReleaseRecord({
    required this.applicationId,
    required this.releaseId,
    required this.target,
    required this.architecture,
    required this.buildMode,
    required this.buildFingerprint,
    required this.sourceFingerprint,
    required this.graphFingerprint,
    required this.toolVersion,
    required this.flutterVersion,
    required this.dartVersion,
    required this.manifest,
    required this.graph,
    required this.sourceFingerprints,
    required this.instrumentation,
    required this.build,
    required List<SourceRecord> sources,
    required List<FunctionRecord> functions,
    required List<ToolDiagnostic> diagnostics,
    required this.configFingerprint,
    required this.nativeFingerprints,
  }) : sources = List.unmodifiable(sources),
       functions = List.unmodifiable(functions),
       diagnostics = List.unmodifiable(diagnostics);

  final String applicationId;
  final String releaseId;
  final String target;
  final String architecture;
  final String buildMode;
  final String buildFingerprint;
  final String sourceFingerprint;
  final String graphFingerprint;
  final String toolVersion;
  final String flutterVersion;
  final String dartVersion;
  final ReleaseBaselineManifest manifest;
  final Map<String, Object?> graph;
  final Map<String, Object?> sourceFingerprints;
  final Map<String, Object?> instrumentation;
  final Map<String, Object?> build;
  final List<SourceRecord> sources;
  final List<FunctionRecord> functions;
  final List<ToolDiagnostic> diagnostics;
  final String configFingerprint;
  final Map<String, Object?> nativeFingerprints;

  String encode() => canonicalJson(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'applicationId': applicationId,
    'releaseId': releaseId,
    'target': target,
    'architecture': architecture,
    'buildMode': buildMode,
    'buildFingerprint': buildFingerprint,
    'sourceFingerprint': sourceFingerprint,
    'graphFingerprint': graphFingerprint,
    'toolVersion': toolVersion,
    'flutterVersion': flutterVersion,
    'dartVersion': dartVersion,
    'manifest': manifest.encode(),
    'graph': graph,
    'sourceFingerprints': sourceFingerprints,
    'instrumentation': instrumentation,
    'build': build,
    'sources': sources.map((item) => item.toJson()).toList(),
    'functions': functions.map((item) => item.toJson()).toList(),
    'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
    'configFingerprint': configFingerprint,
    'nativeFingerprints': nativeFingerprints,
  };

  static ReleaseRecord decode(String source) {
    final raw = jsonDecode(source);
    if (raw is! Map<String, Object?> || raw['version'] != 1) {
      throw const FormatException('Invalid release metadata');
    }
    final requiredStrings = <String>[
      'applicationId',
      'releaseId',
      'target',
      'architecture',
      'buildMode',
      'buildFingerprint',
      'sourceFingerprint',
      'graphFingerprint',
      'toolVersion',
      'flutterVersion',
      'dartVersion',
      'manifest',
      'configFingerprint',
    ];
    if (requiredStrings.any((key) => raw[key] is! String) ||
        raw['sources'] is! List<Object?> ||
        raw['functions'] is! List<Object?> ||
        raw['diagnostics'] is! List<Object?> ||
        raw['graph'] is! Map<String, Object?> ||
        raw['sourceFingerprints'] is! Map<String, Object?> ||
        raw['instrumentation'] is! Map<String, Object?> ||
        raw['build'] is! Map<String, Object?> ||
        raw['nativeFingerprints'] is! Map<String, Object?>) {
      throw const FormatException('Invalid release metadata fields');
    }
    final sources = (raw['sources']! as List<Object?>)
        .map(SourceRecord.fromJson)
        .toList(growable: false);
    final functions = (raw['functions']! as List<Object?>)
        .map(FunctionRecord.fromJson)
        .toList(growable: false);
    final diagnostics = (raw['diagnostics']! as List<Object?>)
        .map(_diagnosticFromJson)
        .toList(growable: false);
    final result = ReleaseRecord(
      applicationId: raw['applicationId']! as String,
      releaseId: raw['releaseId']! as String,
      target: raw['target']! as String,
      architecture: raw['architecture']! as String,
      buildMode: raw['buildMode']! as String,
      buildFingerprint: raw['buildFingerprint']! as String,
      sourceFingerprint: raw['sourceFingerprint']! as String,
      graphFingerprint: raw['graphFingerprint']! as String,
      toolVersion: raw['toolVersion']! as String,
      flutterVersion: raw['flutterVersion']! as String,
      dartVersion: raw['dartVersion']! as String,
      manifest: ReleaseBaselineManifest.decode(raw['manifest']! as String),
      graph: raw['graph']! as Map<String, Object?>,
      sourceFingerprints: raw['sourceFingerprints']! as Map<String, Object?>,
      instrumentation: raw['instrumentation']! as Map<String, Object?>,
      build: raw['build']! as Map<String, Object?>,
      sources: sources,
      functions: functions,
      diagnostics: diagnostics,
      configFingerprint: raw['configFingerprint']! as String,
      nativeFingerprints: raw['nativeFingerprints']! as Map<String, Object?>,
    );
    if (result.encode() != source) {
      throw const FormatException('Release metadata is not canonical');
    }
    return result;
  }
}

final class SourceRecord {
  SourceRecord({
    required this.relativePath,
    required this.libraryUri,
    required this.packageName,
    required this.kind,
    required this.selected,
    required this.entrypoint,
    required this.instrumented,
    required this.fingerprint,
    required this.semanticFingerprint,
    required Map<String, String> declarationFingerprints,
    required this.exclusions,
    required this.manifest,
    bool includeDeclarationFingerprints = true,
  }) : declarationFingerprints = Map.unmodifiable(declarationFingerprints),
       _includeDeclarationFingerprints = includeDeclarationFingerprints;

  final String relativePath;
  final String libraryUri;
  final String packageName;
  final String kind;
  final bool selected;
  final bool entrypoint;
  final bool instrumented;
  final String fingerprint;
  final String semanticFingerprint;
  final Map<String, String> declarationFingerprints;
  final List<String> exclusions;
  final String? manifest;
  final bool _includeDeclarationFingerprints;

  Map<String, Object?> toJson() => <String, Object?>{
    'relativePath': relativePath,
    'libraryUri': libraryUri,
    'packageName': packageName,
    'kind': kind,
    'selected': selected,
    'entrypoint': entrypoint,
    'instrumented': instrumented,
    'fingerprint': fingerprint,
    'semanticFingerprint': semanticFingerprint,
    if (_includeDeclarationFingerprints)
      'declarationFingerprints': declarationFingerprints,
    'exclusions': exclusions,
    'manifest': manifest,
  };

  static SourceRecord fromJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value['relativePath'] is! String ||
        value['libraryUri'] is! String ||
        value['packageName'] is! String ||
        value['kind'] is! String ||
        value['selected'] is! bool ||
        value['entrypoint'] is! bool ||
        value['instrumented'] is! bool ||
        value['fingerprint'] is! String ||
        value['semanticFingerprint'] is! String ||
        (value['declarationFingerprints'] != null &&
            value['declarationFingerprints'] is! Map<String, Object?>) ||
        (value['declarationFingerprints'] is Map<String, Object?> &&
            (value['declarationFingerprints']! as Map<String, Object?>).entries
                .any((entry) => entry.value is! String)) ||
        value['exclusions'] is! List<Object?> ||
        (value['exclusions']! as List<Object?>).any(
          (item) => item is! String,
        ) ||
        (value['manifest'] != null && value['manifest'] is! String)) {
      throw const FormatException('Invalid release source record');
    }
    return SourceRecord(
      relativePath: value['relativePath']! as String,
      libraryUri: value['libraryUri']! as String,
      packageName: value['packageName']! as String,
      kind: value['kind']! as String,
      selected: value['selected']! as bool,
      entrypoint: value['entrypoint']! as bool,
      instrumented: value['instrumented']! as bool,
      fingerprint: value['fingerprint']! as String,
      semanticFingerprint: value['semanticFingerprint']! as String,
      declarationFingerprints: <String, String>{
        for (final entry
            in ((value['declarationFingerprints'] as Map<String, Object?>?) ??
                    const <String, Object?>{})
                .entries)
          entry.key: entry.value! as String,
      },
      exclusions: (value['exclusions']! as List<Object?>).cast<String>(),
      manifest: value['manifest'] as String?,
      includeDeclarationFingerprints: value.containsKey(
        'declarationFingerprints',
      ),
    );
  }
}

final class FunctionRecord {
  const FunctionRecord({
    required this.id,
    required this.slot,
    required this.signatureDigest,
    required this.sourcePath,
    required this.libraryUri,
    required this.name,
    required this.className,
    required this.manifest,
  });

  final String id;
  final int slot;
  final String signatureDigest;
  final String sourcePath;
  final String libraryUri;
  final String name;
  final String? className;
  final Map<String, Object?> manifest;

  String get declarationKey {
    if (className == null) return 'function|$name';
    final identity = manifest['identity'];
    final memberKind =
        identity is Map<String, Object?> && identity['memberKind'] is String
        ? identity['memberKind']! as String
        : 'instanceMethod';
    return 'method|$className|$memberKind|$name';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'slot': slot,
    'signatureDigest': signatureDigest,
    'sourcePath': sourcePath,
    'libraryUri': libraryUri,
    'name': name,
    'className': className,
    'manifest': manifest,
  };

  static FunctionRecord fromJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value['id'] is! String ||
        value['slot'] is! int ||
        value['signatureDigest'] is! String ||
        value['sourcePath'] is! String ||
        value['libraryUri'] is! String ||
        value['name'] is! String ||
        (value['className'] != null && value['className'] is! String) ||
        value['manifest'] is! Map<String, Object?>) {
      throw const FormatException('Invalid release function record');
    }
    return FunctionRecord(
      id: value['id']! as String,
      slot: value['slot']! as int,
      signatureDigest: value['signatureDigest']! as String,
      sourcePath: value['sourcePath']! as String,
      libraryUri: value['libraryUri']! as String,
      name: value['name']! as String,
      className: value['className'] as String?,
      manifest: value['manifest']! as Map<String, Object?>,
    );
  }
}

final class ToolEnvironmentSnapshot {
  const ToolEnvironmentSnapshot({
    required this.flutterVersion,
    required this.dartVersion,
    required this.flutterStatus,
    required this.dartStatus,
    required this.androidStatus,
    required this.xcodeStatus,
    this.gitStatus = 'NOT TESTED',
    this.runtimeStatus = 'NOT TESTED',
  });

  final String flutterVersion;
  final String dartVersion;
  final String flutterStatus;
  final String dartStatus;
  final String androidStatus;
  final String xcodeStatus;
  final String gitStatus;
  final String runtimeStatus;

  Map<String, Object> toJson() => <String, Object>{
    'flutterVersion': flutterVersion,
    'dartVersion': dartVersion,
    'flutterStatus': flutterStatus,
    'dartStatus': dartStatus,
    'androidStatus': androidStatus,
    'xcodeStatus': xcodeStatus,
    'gitStatus': gitStatus,
    'runtimeStatus': runtimeStatus,
  };

  ToolEnvironmentSnapshot withRuntimeStatus(String value) =>
      ToolEnvironmentSnapshot(
        flutterVersion: flutterVersion,
        dartVersion: dartVersion,
        flutterStatus: flutterStatus,
        dartStatus: dartStatus,
        androidStatus: androidStatus,
        xcodeStatus: xcodeStatus,
        gitStatus: gitStatus,
        runtimeStatus: value,
      );
}

final class ToolStatus {
  ToolStatus({
    required this.result,
    required String projectPackage,
    required String applicationId,
    required this.configurationStatus,
    required this.store,
    required this.environment,
    required List<ToolDiagnostic> diagnostics,
  }) : projectPackage = _boundedStatusText(projectPackage),
       applicationId = _boundedStatusText(applicationId),
       diagnostics = List.unmodifiable(diagnostics);

  final String result;
  final String projectPackage;
  final String applicationId;
  final String configurationStatus;
  final ToolStoreInventory store;
  final ToolEnvironmentSnapshot environment;
  final List<ToolDiagnostic> diagnostics;

  String get applicationRuntimeStatus => 'NOT_CONNECTED';

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'result': result,
    'toolVersion': hyfensToolVersion,
    'project': <String, String>{
      'package': projectPackage,
      'applicationId': applicationId,
    },
    'configuration': <String, String>{'status': configurationStatus},
    'store': store.toJson(),
    'environment': environment.toJson(),
    'runtime': <String, String>{
      'scope': 'LOCAL_TOOL_ONLY',
      'status': applicationRuntimeStatus,
      'introspection': 'NOT_AVAILABLE',
    },
    'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
  };
}

final class ToolEnvironment {
  const ToolEnvironment();

  ToolEnvironmentSnapshot inspectVersionsSync() {
    final flutter = _versionSync('flutter', const ['--version']);
    final dart = _versionSync('dart', const ['--version']);
    final flutterVersion = extractFlutterVersion(flutter.$1);
    final dartVersion = extractDartVersion(dart.$1);
    return ToolEnvironmentSnapshot(
      flutterVersion: flutterVersion ?? 'unknown',
      dartVersion: dartVersion ?? 'unknown',
      flutterStatus: flutterToolchainStatus(flutter.$2, flutterVersion),
      dartStatus: dartToolchainStatus(dart.$2, dartVersion),
      androidStatus: 'NOT TESTED',
      xcodeStatus: 'NOT TESTED',
      gitStatus: 'NOT TESTED',
    );
  }

  Future<ToolEnvironmentSnapshot> inspect(FlutterProject project) async {
    final flutter = await _version('flutter', const ['--version']);
    final dart = await _version('dart', const ['--version']);
    final git = await _version('git', const ['--version']);
    final flutterVersion = extractFlutterVersion(flutter.$1);
    final dartVersion = extractDartVersion(dart.$1);
    final xcode =
        Platform.isMacOS &&
            (await _version('xcodebuild', const ['-version'])).$2
        ? 'NOT TESTED'
        : Platform.isMacOS
        ? 'NOT AVAILABLE'
        : 'NOT APPLICABLE';
    final android =
        Directory(
          Platform.environment['ANDROID_SDK_ROOT'] ??
              Platform.environment['ANDROID_HOME'] ??
              '',
        ).existsSync()
        ? 'NOT TESTED'
        : 'NOT AVAILABLE';
    return ToolEnvironmentSnapshot(
      flutterVersion: flutterVersion ?? 'unknown',
      dartVersion: dartVersion ?? 'unknown',
      flutterStatus: flutterToolchainStatus(flutter.$2, flutterVersion),
      dartStatus: dartToolchainStatus(dart.$2, dartVersion),
      androidStatus: android,
      xcodeStatus: xcode,
      gitStatus: git.$2 ? 'SUPPORTED' : 'NOT AVAILABLE',
    );
  }

  Future<(String, bool)> _version(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await Process.run(executable, arguments);
      final output = '${result.stdout}\n${result.stderr}';
      return (output, result.exitCode == 0);
    } on Object catch (error) {
      return (error.toString(), false);
    }
  }

  (String, bool) _versionSync(String executable, List<String> arguments) {
    try {
      final result = Process.runSync(executable, arguments);
      final output = '${result.stdout}\n${result.stderr}';
      return (output, result.exitCode == 0);
    } on Object catch (error) {
      return (error.toString(), false);
    }
  }
}

final class AnalysisItem {
  const AnalysisItem({
    required this.classification,
    required this.path,
    required this.detail,
    required this.functionIds,
    this.libraryUri,
    this.line,
    this.column,
    this.diagnostic,
  });

  final ChangeClassification classification;
  final String path;
  final String detail;
  final List<String> functionIds;
  final String? libraryUri;
  final int? line;
  final int? column;
  final ToolDiagnostic? diagnostic;

  Map<String, Object?> toJson() => <String, Object?>{
    'classification': classification.name,
    'path': path,
    'detail': detail,
    'functionIds': functionIds,
    'libraryUri': libraryUri,
    'line': line,
    'column': column,
    'diagnostic': diagnostic?.toJson(),
  };
}

final class _SourceLocation {
  const _SourceLocation({required this.line, required this.column});

  final int line;
  final int column;
}

enum ChangeClassification {
  patchable,
  unsupported,
  storeReleaseRequired,
  noEffect,
  unknown,
}

final class AnalysisResult {
  AnalysisResult({
    required this.release,
    required this.currentSourceFingerprint,
    required this.currentGraphFingerprint,
    required List<AnalysisItem> items,
    required this.plan,
    required List<ToolDiagnostic> diagnostics,
  }) : items = List.unmodifiable(items),
       diagnostics = List.unmodifiable(diagnostics);

  final ReleaseRecord release;
  final String currentSourceFingerprint;
  final String currentGraphFingerprint;
  final List<AnalysisItem> items;
  final InstrumentationPlan plan;
  final List<ToolDiagnostic> diagnostics;

  bool get canPatch =>
      items.any(
        (item) => item.classification == ChangeClassification.patchable,
      ) &&
      items.every(
        (item) =>
            item.classification == ChangeClassification.patchable ||
            item.classification == ChangeClassification.noEffect,
      ) &&
      diagnostics.every((item) => item.severity != DiagnosticSeverity.error);

  Map<String, Object?> toJson() => <String, Object?>{
    'releaseId': release.releaseId,
    'applicationId': release.applicationId,
    'target': release.target,
    'result': canPatch ? 'PATCHABLE' : 'PATCH_BLOCKED',
    'currentSourceFingerprint': currentSourceFingerprint,
    'currentGraphFingerprint': currentGraphFingerprint,
    'items': items.map((item) => item.toJson()).toList(),
    'diagnostics': diagnostics.map((item) => item.toJson()).toList(),
  };
}

final class HyfensToolchain {
  HyfensToolchain({
    ProjectDiscovery? discovery,
    ProjectGraphLoader? graphLoader,
    SourceDiscoverer? sourceDiscoverer,
    InstrumentationPlanner? instrumentationPlanner,
    ToolEnvironment? environment,
    KeyStore? keyStore,
  }) : _discovery = discovery ?? const ProjectDiscovery(),
       _graphLoader = graphLoader ?? const ProjectGraphLoader(),
       _sourceDiscoverer = sourceDiscoverer ?? const SourceDiscoverer(),
       _instrumentationPlanner =
           instrumentationPlanner ?? const InstrumentationPlanner(),
       _environment = environment ?? const ToolEnvironment(),
       _keyStore = keyStore ?? const KeyStore();

  final ProjectDiscovery _discovery;
  final ProjectGraphLoader _graphLoader;
  final SourceDiscoverer _sourceDiscoverer;
  final InstrumentationPlanner _instrumentationPlanner;
  final ToolEnvironment _environment;
  final KeyStore _keyStore;

  FlutterProject project({String? projectPath}) =>
      _discovery.discover(projectPath: projectPath);

  ToolConfig config(FlutterProject project) =>
      ToolConfig.load(project.configFile);

  Future<ToolEnvironmentSnapshot> doctor({String? projectPath}) async {
    final current = project(projectPath: projectPath);
    final snapshot = await _environment.inspect(current);
    final runtime = Isolate.resolvePackageUriSync(
      Uri.parse('package:instrumentation_e0/e0_runtime.dart'),
    );
    return snapshot.withRuntimeStatus(
      runtime == null ? 'NOT AVAILABLE' : 'SUPPORTED',
    );
  }

  /// Returns a bounded, local-only status projection.
  ///
  /// This command deliberately reports toolchain and artifact inventory, not
  /// application lifecycle state. The CLI has no authenticated app-runtime
  /// introspection seam, and adding one would cross this package's boundary.
  Future<ToolStatus> status({String? projectPath}) async {
    late final FlutterProject current;
    try {
      current = project(projectPath: projectPath);
    } on ToolFailure catch (failure) {
      throw _redactedStatusFailure(failure);
    }

    final environment = await doctor(projectPath: current.root.path);
    final inventory = await ToolStore(current).inspectInventory();
    var configurationStatus = 'NOT_INITIALIZED';
    final diagnostics = <ToolDiagnostic>[];
    if (!current.configFile.existsSync() ||
        FileSystemEntity.typeSync(
              current.configFile.path,
              followLinks: false,
            ) !=
            FileSystemEntityType.file) {
      if (inventory.status != 'NOT_INITIALIZED') {
        diagnostics.add(
          _statusDiagnostic(
            code: ToolDiagnosticCodes.statusNotInitialized,
            severity: DiagnosticSeverity.info,
            summary: 'Local tool configuration is not initialized',
            detail: 'The local status is limited until tool initialization is complete.',
            action: 'Run hyfens init before release or patch operations.',
          ),
        );
      }
    } else {
      try {
        config(current);
        configurationStatus = 'SUPPORTED';
      } on ToolFailure catch (failure) {
        final diagnostic = failure.diagnostics.first;
        diagnostics.add(
          _statusDiagnostic(
            code: _safeDiagnosticCode(diagnostic.code),
            severity: DiagnosticSeverity.warning,
            summary: 'Local tool configuration cannot be inspected',
            detail: 'Repair the configuration before relying on release or patch status.',
            action:
                'Run hyfens doctor for the detailed configuration diagnostic.',
          ),
        );
        configurationStatus = 'INVALID';
      } on Object {
        diagnostics.add(
          _statusDiagnostic(
            code: 'T9999',
            severity: DiagnosticSeverity.warning,
            summary: 'Local tool configuration cannot be inspected',
            detail: 'Repair the configuration before relying on release or patch status.',
            action:
                'Run hyfens doctor for the detailed configuration diagnostic.',
          ),
        );
        configurationStatus = 'INVALID';
      }
    }

    if (inventory.status == 'INCOMPLETE') {
      diagnostics.add(
        _statusDiagnostic(
          code: ToolDiagnosticCodes.statusStoreIncomplete,
          severity: DiagnosticSeverity.warning,
          summary: 'Local tool metadata store is incomplete',
          detail: 'The status inventory found missing or unreadable tool-owned directories.',
          action: 'Preserve existing evidence and inspect the local .tool store deliberately.',
        ),
      );
    }
    if (inventory.scanTruncated) {
      diagnostics.add(
        _statusDiagnostic(
          code: ToolDiagnosticCodes.statusInventoryTruncated,
          severity: DiagnosticSeverity.warning,
          summary: 'Local status inventory was bounded',
          detail: 'Some local entries were not counted after the safety limit was reached.',
          action: 'Use the existing exact release or patch inspection commands for one target.',
        ),
      );
    }

    final missingConfiguration = configurationStatus == 'NOT_INITIALIZED';
    final missingStore = inventory.status == 'NOT_INITIALIZED';
    final result =
        configurationStatus == 'INVALID' ||
            inventory.status == 'INCOMPLETE' ||
            inventory.scanTruncated
        ? 'WARNING'
        : missingConfiguration || missingStore
        ? 'NOT_INITIALIZED'
        : 'READY';
    if (missingConfiguration && missingStore && diagnostics.isEmpty) {
      diagnostics.add(
        _statusDiagnostic(
          code: ToolDiagnosticCodes.statusNotInitialized,
          severity: DiagnosticSeverity.info,
          summary: 'Local tool metadata is not initialized',
          detail: 'No tool configuration or local artifact store was found.',
          action: 'Run hyfens init to create the local developer metadata.',
        ),
      );
    }
    return ToolStatus(
      result: result,
      projectPackage: current.packageName,
      applicationId: current.applicationId,
      configurationStatus: configurationStatus,
      store: inventory,
      environment: environment,
      diagnostics: diagnostics,
    );
  }

  Future<InitResult> init({
    String? projectPath,
    bool dryRun = false,
    bool force = false,
  }) async {
    final current = project(projectPath: projectPath);
    final environment = await _environment.inspect(current);
    if (environment.flutterStatus != 'SUPPORTED' ||
        environment.dartStatus != 'SUPPORTED') {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1102',
        summary: 'A supported Flutter/Dart toolchain is required for init',
        detail:
            'Flutter ${environment.flutterVersion}, Dart ${environment.dartVersion}.',
        action:
            'Install/use the supported Flutter and Dart toolchain, then retry.',
      );
    }
    final store = ToolStore(current);
    final existingConfig = current.configFile.existsSync();
    if (existingConfig && !force && !dryRun) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.refused,
        code: 'T1210',
        summary: 'tool.yaml already exists',
        detail: current.configFile.path,
        action: 'Review it or pass --force to replace only the tool-owned configuration.',
      );
    }
    final configText = ToolConfig(applicationId: current.applicationId)
        .encode();
    final actions = <String>[
      '${existingConfig ? 'replace' : 'create'} ${current.relative(current.configFile)}',
      'create ${current.relative(store.root)}',
      'create ${current.relative(store.releases)}',
      'create ${current.relative(store.patches)}',
      'create ${current.relative(store.keys)}',
    ];
    if (!dryRun) {
      await store.ensure();
      await writeAtomicText(current.configFile, configText);
      await writeAtomicText(
        File(p.join(store.root.path, '.gitignore')),
        'keys/\nreleases/\npatches/\nbuilds/\n',
      );
    }
    return InitResult(
      project: current,
      dryRun: dryRun,
      actions: actions,
      environment: environment,
    );
  }

  /// Explicitly records a rollback to the trusted store-installed AOT base.
  ///
  /// The CLI does not clear or rewrite app-local E1 state. It records the
  /// developer decision beside the patch sequence so a later patch continues
  /// above the accepted high-water. Manual selection of an older patch is
  /// intentionally refused: E1 can only restore that behavior through its
  /// already-safe local fallback or a newly authenticated higher sequence.
  Future<RollbackResult> rollback({
    String? projectPath,
    String? releaseId,
    String target = 'base',
  }) async {
    if (target != 'base' && target != _rollbackTargetBaseAot) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.refused,
        code: ToolDiagnosticCodes.rollbackTargetUnsupported,
        summary: 'Rollback target is not safe at the Phase 1B CLI boundary',
        detail: target,
        action: 'Use --to base for the trusted store-installed AOT base; prior-patch restoration requires an already-safe E1 fallback or a new higher-sequence artifact.',
      );
    }
    final current = project(projectPath: projectPath);
    final store = ToolStore(current);
    final config = this.config(current);
    final release = _selectRelease(store, releaseId);
    final baseArtifact = _trustedStoreInstalledArtifact(store, release);
    final highWater = store.readRollbackHighWater(release.releaseId);
    final publicKey = _keyStore.readPublic(
      store.resolveConfiguredPath(config.publicKeyPath),
    );
    final privateKey = _keyStore.readPrivate(
      store.resolveConfiguredPath(config.privateKeyPath, allowExternal: true),
    );
    if (privateKey.keyId != publicKey.keyId) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.signing,
        code: 'S4007',
        summary: 'Rollback signer does not match the release trust key',
        detail: '${privateKey.keyId} != ${publicKey.keyId}',
        action: 'Use the private key paired with the public key embedded in this release.',
      );
    }
    final command = await RollbackControlCommand.sign(
      applicationId: release.applicationId,
      releaseId: release.releaseId,
      highWaterSequence: highWater.sequence,
      highWaterDigest: highWater.digest,
      keyId: privateKey.keyId,
      signer: privateKey.sign,
    );
    final state = await store.commitBaseRollback(
      release.releaseId,
      highWaterSequence: highWater.sequence,
      highWaterDigest: highWater.digest,
    );
    final commandFile = store.rollbackControl(release.releaseId);
    await writeAtomicText(commandFile, command.encode());
    return RollbackResult(
      project: current,
      release: release,
      baseArtifact: baseArtifact,
      state: state,
      commandFile: commandFile,
      keyId: command.keyId,
    );
  }

  /// Cleans only an exact, explicitly confirmed mutable target.
  ///
  /// `builds` removes one temporary release staging directory. `patches`
  /// removes only numbered patch files for one release after a base rollback;
  /// sequence metadata, rollback journals, release records, keys, source, and
  /// all other evidence remain in place. Broad scopes are rejected.
  Future<CleanupResult> cleanup({
    required String scope,
    String? releaseId,
    String? confirmation,
    String? projectPath,
  }) async {
    const protectedScopes = <String>{
      'all',
      'evidence',
      'keys',
      'releases',
      'source',
    };
    const supportedScopes = <String>{'builds', 'patches'};
    if (protectedScopes.contains(scope)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.refused,
        code: ToolDiagnosticCodes.cleanupScopeProtected,
        summary: 'Cleanup scope is protected',
        detail: scope,
        action: 'Keys, immutable releases, source, rollback journals, sequence state, and evidence require deliberate recovery and are never removed by a broad cleanup.',
      );
    }
    if (!supportedScopes.contains(scope)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: ToolDiagnosticCodes.cleanupScopeUnsupported,
        summary: 'Cleanup scope is unsupported',
        detail: scope,
        action: 'Use --scope builds or --scope patches.',
      );
    }
    if (releaseId == null ||
        releaseId.isEmpty ||
        !RegExp(r'^[A-Za-z0-9:_-]{1,256}$').hasMatch(releaseId)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: ToolDiagnosticCodes.cleanupTargetInvalid,
        summary: 'Cleanup requires one exact release target',
        detail: releaseId ?? '<missing>',
        action:
            'Pass the exact --release <release-id> produced by hyfens release.',
      );
    }
    if (confirmation != releaseId) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.refused,
        code: ToolDiagnosticCodes.cleanupConfirmationRequired,
        summary: 'Cleanup requires exact target confirmation',
        detail: 'Expected --confirm $releaseId',
        action: 'Review the target and repeat its exact release ID with --confirm; no files were changed.',
      );
    }
    final current = project(projectPath: projectPath);
    final store = ToolStore(current);
    // Resolve the exact release before touching any mutable directory. A
    // malformed or missing release is never treated as an empty cleanup.
    final release = store.readRelease(releaseId);
    return switch (scope) {
      'builds' => _cleanupBuildStaging(current, store, release),
      'patches' => await _cleanupPatchArtifacts(current, store, release),
      _ => throw StateError('validated cleanup scope was not handled'),
    };
  }

  CleanupResult _cleanupBuildStaging(
    FlutterProject current,
    ToolStore store,
    ReleaseRecord release,
  ) {
    final target = Directory(
      p.join(store.buildStaging.path, release.releaseId),
    );
    final type = FileSystemEntity.typeSync(target.path, followLinks: false);
    if (type == FileSystemEntityType.link ||
        (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.refused,
        code: ToolDiagnosticCodes.cleanupTargetInvalid,
        summary: 'Build cleanup target is not a private directory',
        detail: target.path,
        action: 'Preserve the target and inspect it manually; the tool does not follow links or delete files here.',
      );
    }
    if (type == FileSystemEntityType.directory) {
      if (_containsSymlink(target)) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.refused,
          code: ToolDiagnosticCodes.cleanupTargetInvalid,
          summary: 'Build cleanup target contains a symbolic link',
          detail: target.path,
          action: 'Preserve the staging directory and inspect links manually; cleanup never follows them.',
        );
      }
      try {
        target.deleteSync(recursive: true);
      } on Object catch (error) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: ToolDiagnosticCodes.cleanupFailed,
          summary: 'Build staging cleanup failed',
          detail: '$target: $error',
          action: 'Resolve the filesystem error; no release, key, source, or patch evidence was targeted.',
        );
      }
      return CleanupResult(
        scope: 'builds',
        release: release,
        removedPaths: <String>[relativePath(current.root, target)],
        retainedPaths: <String>[
          relativePath(current.root, store.release(release.releaseId)),
        ],
      );
    }
    return CleanupResult(
      scope: 'builds',
      release: release,
      removedPaths: const <String>[],
      retainedPaths: <String>[
        relativePath(current.root, store.release(release.releaseId)),
      ],
    );
  }

  Future<CleanupResult> _cleanupPatchArtifacts(
    FlutterProject current,
    ToolStore store,
    ReleaseRecord release,
  ) async {
    try {
      _trustedStoreInstalledArtifact(store, release);
    } on ToolFailure catch (error) {
      final code = error.diagnostics.single.code;
      if (code == ToolDiagnosticCodes.rollbackBaseUnavailable) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.refused,
          code: ToolDiagnosticCodes.cleanupRequiresBaseRollback,
          summary: 'Patch cleanup requires a trusted store-installed AOT base',
          detail: release.releaseId,
          action: 'Use a real store release with an immutable artifact before removing mutable patch files.',
        );
      }
      rethrow;
    }
    final rollback = store.readRollbackState(release.releaseId);
    if (rollback == null || rollback.target != _rollbackTargetBaseAot) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.refused,
        code: ToolDiagnosticCodes.cleanupRequiresBaseRollback,
        summary: 'Patch cleanup requires an explicit base rollback',
        detail: release.releaseId,
        action: 'Run hyfens rollback --release <release-id> --to base first; patch files and sequence state were preserved.',
      );
    }
    final highWater = store.readRollbackHighWater(release.releaseId);
    final directory = store.patchDirectory(release.releaseId);
    final type = FileSystemEntity.typeSync(directory.path, followLinks: false);
    if (type == FileSystemEntityType.link ||
        (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.refused,
        code: ToolDiagnosticCodes.cleanupTargetInvalid,
        summary: 'Patch cleanup target is not a private directory',
        detail: directory.path,
        action: 'Preserve the target and inspect it manually; the tool does not follow links.',
      );
    }
    final candidates = <File>[];
    final removed = <String>[];
    if (type == FileSystemEntityType.directory) {
      for (final entry in directory.listSync(followLinks: false)) {
        if (!_patchFileName.hasMatch(p.basename(entry.path))) continue;
        if (FileSystemEntity.typeSync(entry.path, followLinks: false) !=
            FileSystemEntityType.file) {
          throw ToolFailure.single(
            exitCode: ToolExitCode.refused,
            code: ToolDiagnosticCodes.cleanupTargetInvalid,
            summary: 'Patch cleanup encountered a non-file artifact',
            detail: entry.path,
            action: 'Preserve the patch evidence and remove the link or special file manually after review.',
          );
        }
        candidates.add(File(entry.path));
      }
      final control = store.rollbackControl(release.releaseId);
      if (control.existsSync() &&
          FileSystemEntity.typeSync(control.path, followLinks: false) ==
              FileSystemEntityType.file) {
        control.deleteSync();
        removed.add(relativePath(current.root, control));
      }
    }
    candidates.sort((left, right) => left.path.compareTo(right.path));
    try {
      for (final candidate in candidates) {
        candidate.deleteSync();
        removed.add(relativePath(current.root, candidate));
      }
    } on Object catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: ToolDiagnosticCodes.cleanupFailed,
        summary: 'Patch cleanup stopped before completion',
        detail: '$release.releaseId: $error',
        action: 'Preserve the remaining patch files and sequence state; resolve the filesystem error before retrying.',
      );
    }
    final retained = <String>[
      relativePath(current.root, store.release(release.releaseId)),
      relativePath(current.root, store.sequenceFile(release.releaseId)),
      relativePath(current.root, store.rollbackStatePrimary(release.releaseId)),
      relativePath(current.root, store.rollbackStateBackup(release.releaseId)),
    ];
    if (highWater.sequence > 0) {
      retained.add('high-water sequence ${highWater.sequence} retained');
    }
    return CleanupResult(
      scope: 'patches',
      release: release,
      removedPaths: removed,
      retainedPaths: retained,
    );
  }

  File _trustedStoreInstalledArtifact(ToolStore store, ReleaseRecord release) {
    final artifactName = release.build['artifact'];
    final artifact = artifactName is String
        ? File(
            p.join(
              store.release(release.releaseId).path,
              'artifacts',
              artifactName,
            ),
          )
        : null;
    if (release.build['metadataOnly'] == true ||
        release.build['status'] != 'SUCCESS' ||
        artifactName is! String ||
        p.basename(artifactName) != artifactName ||
        artifact == null ||
        FileSystemEntity.typeSync(artifact.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.refused,
        code: ToolDiagnosticCodes.rollbackBaseUnavailable,
        summary: 'Trusted store-installed AOT base is unavailable',
        detail: release.releaseId,
        action: 'Use a completed non-metadata store release with its immutable artifact retained.',
      );
    }
    return artifact;
  }

  Future<ReleaseRecord> release({
    required String target,
    String? projectPath,
    String architecture = 'arm64',
    String buildMode = 'release',
    bool metadataOnly = false,
  }) async {
    if (target != 'android' && target != 'ios') {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'T1006',
        summary: 'Unsupported release target',
        detail: target,
        action: 'Use android or ios.',
      );
    }
    final current = project(projectPath: projectPath);
    final config = this.config(current);
    final store = ToolStore(current);
    final configuredPublicKey = store.resolveConfiguredPath(
      config.publicKeyPath,
    );
    final trustedPublicKey = configuredPublicKey.existsSync()
        ? _keyStore.readPublic(configuredPublicKey)
        : null;
    if (!metadataOnly && trustedPublicKey == null) {
      _keyStore.readPublic(configuredPublicKey);
    }
    final graph = _graphLoader.load(current);
    final source = _sourceDiscoverer.discover(current, graph, config);
    final environment = await _environment.inspect(current);
    final targetName = '$target-$architecture-$buildMode';
    final graphFingerprint = graph.fingerprint;
    final native = _nativeSnapshot(current, graph);
    final configFingerprint = digestJson(<String, Object?>{
      'tool': config.encode(),
    });
    final dependencyFingerprint = digestJson(<String, Object?>{
      'graph': graphFingerprint,
      'flutter': environment.flutterVersion,
      'dart': environment.dartVersion,
      'config': configFingerprint,
      'native': digestJson(native),
      'toolVersion': hyfensToolVersion,
      'formatVersion': patchFormatV1,
      'signingKeyId': trustedPublicKey?.keyId ?? 'unconfigured',
      'updateUrl': config.updateUrl,
    });
    final applicationId =
        config.applicationId ?? current.applicationIdFor(target);
    final releaseId = releaseIdFor(
      applicationId: applicationId,
      sourceFingerprint: source.fingerprint,
      dependencyFingerprint: dependencyFingerprint,
      runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
      target: targetName,
    );
    final buildFingerprint = digestJson(<String, Object?>{
      'target': targetName,
      'applicationId': applicationId,
      'flutter': environment.flutterVersion,
      'dart': environment.dartVersion,
      'tool': hyfensToolVersion,
      'runtime': patchFormatRuntimeCompatibilityV1,
      'format': patchFormatV1,
      'graph': graphFingerprint,
      'signingKeyId': trustedPublicKey?.keyId ?? 'unconfigured',
    });
    final plan = _instrumentationPlanner.build(
      project: current,
      discovery: source,
      config: config,
      applicationId: applicationId,
      releaseId: releaseId,
      buildFingerprint: buildFingerprint,
      runtimeBootstrap: trustedPublicKey == null
          ? null
          : RuntimeBootstrapConfiguration(
              updateUrl: Uri.parse(config.updateUrl),
              keyId: trustedPublicKey.keyId,
              publicKey: trustedPublicKey.publicKey,
            ),
    );
    final manifest = _baselineManifest(
      project: current,
      source: source,
      plan: plan,
      releaseId: releaseId,
      buildFingerprint: buildFingerprint,
      applicationId: applicationId,
    );
    File? stagedArtifact;
    final buildResult = metadataOnly
        ? <String, Object?>{
            'metadataOnly': true,
            'status': 'NOT_RUN',
            'reason': 'Explicit --metadata-only',
          }
        : await _buildInstrumentedRelease(
            project: current,
            plan: plan,
            target: target,
            buildMode: buildMode,
            environment: environment,
            graph: graph,
            artifactStagingDirectory: Directory(
              p.join(current.toolDirectory.path, '.builds', releaseId),
            ),
          );
    final build = Map<String, Object?>.from(buildResult);
    final stagedArtifactPath = build.remove('artifactPath');
    if (stagedArtifactPath is String) stagedArtifact = File(stagedArtifactPath);
    final functions = _functionRecords(current, plan);
    final record = ReleaseRecord(
      applicationId: applicationId,
      releaseId: releaseId,
      target: target,
      architecture: architecture,
      buildMode: buildMode,
      buildFingerprint: buildFingerprint,
      sourceFingerprint: source.fingerprint,
      graphFingerprint: graphFingerprint,
      toolVersion: hyfensToolVersion,
      flutterVersion: environment.flutterVersion,
      dartVersion: environment.dartVersion,
      manifest: manifest,
      graph: graph.toJson(),
      sourceFingerprints: <String, Object?>{
        for (final unit in source.units)
          unit.relativeTo(current): <String, Object?>{
            'fingerprint': unit.fingerprint,
            'libraryUri': unit.libraryUri,
            'kind': unit.kind.name,
            'selected': unit.selected,
          },
      },
      instrumentation: plan.toJson(),
      build: build,
      sources: <SourceRecord>[
        for (final unit in source.units) _sourceRecord(current, unit, plan),
      ],
      functions: functions,
      diagnostics: plan.diagnostics,
      configFingerprint: configFingerprint,
      nativeFingerprints: native,
    );
    try {
      await store.writeRelease(
        record,
        artifacts: stagedArtifact == null
            ? const <File>[]
            : <File>[stagedArtifact],
      );
    } finally {
      final stagingRoot = stagedArtifact?.parent.parent;
      if (stagingRoot != null && stagingRoot.existsSync()) {
        await stagingRoot.delete(recursive: true);
      }
    }
    return record;
  }

  AnalysisResult analyze({String? projectPath, String? releaseId}) {
    final current = project(projectPath: projectPath);
    final config = this.config(current);
    final store = ToolStore(current);
    final release = _selectRelease(store, releaseId);
    final graph = _graphLoader.load(current);
    final source = _sourceDiscoverer.discover(current, graph, config);
    final plan = _instrumentationPlanner.build(
      project: current,
      discovery: source,
      config: config,
      applicationId: release.applicationId,
      releaseId: release.releaseId,
      buildFingerprint: release.buildFingerprint,
    );
    final baselineSources = <String, SourceRecord>{
      for (final item in release.sources) item.relativePath: item,
    };
    final currentSources = <String, SourceUnit>{
      for (final item in source.units) item.relativeTo(current): item,
    };
    final currentInstrumented = <String, InstrumentedUnit>{
      for (final item in plan.units) item.source.relativeTo(current): item,
    };
    final paths = <String>{...baselineSources.keys, ...currentSources.keys};
    final items = <AnalysisItem>[];
    final diagnostics = <ToolDiagnostic>[...plan.diagnostics];
    final environment = _environment.inspectVersionsSync();
    if (environment.flutterStatus != 'SUPPORTED' ||
        environment.dartStatus != 'SUPPORTED') {
      final diagnostic = ToolDiagnostic(
        code: 'T1102',
        severity: DiagnosticSeverity.error,
        summary: 'Current Flutter/Dart toolchain is unavailable',
        detail:
            'Flutter ${environment.flutterVersion}, Dart ${environment.dartVersion}.',
        action: 'Use the same supported Flutter/Dart toolchain used for the release.',
        storeReleaseRequired: true,
      );
      diagnostics.add(diagnostic);
      items.add(
        AnalysisItem(
          classification: ChangeClassification.storeReleaseRequired,
          path: '<toolchain>',
          detail: diagnostic.detail,
          functionIds: const <String>[],
          diagnostic: diagnostic,
        ),
      );
    } else if (environment.flutterVersion != release.flutterVersion ||
        environment.dartVersion != release.dartVersion) {
      final diagnostic = ToolDiagnostic(
        code: 'T1102',
        severity: DiagnosticSeverity.error,
        summary: 'Flutter/Dart toolchain differs from the release',
        detail:
            'Release Flutter ${release.flutterVersion}/Dart ${release.dartVersion}; current Flutter ${environment.flutterVersion}/Dart ${environment.dartVersion}.',
        action:
            'Use the exact compatible toolchain or create a new store release.',
        storeReleaseRequired: true,
      );
      diagnostics.add(diagnostic);
      items.add(
        AnalysisItem(
          classification: ChangeClassification.storeReleaseRequired,
          path: '<toolchain>',
          detail: diagnostic.detail,
          functionIds: const <String>[],
          diagnostic: diagnostic,
        ),
      );
    }
    if (release.toolVersion != hyfensToolVersion) {
      final diagnostic = ToolDiagnostic(
        code: 'R5006',
        severity: DiagnosticSeverity.error,
        summary: 'Toolchain version is incompatible with the release',
        detail:
            'Release tool ${release.toolVersion}; current tool $hyfensToolVersion.',
        action: 'Use the recorded tool version or create a new store release.',
        storeReleaseRequired: true,
      );
      diagnostics.add(diagnostic);
      items.add(
        AnalysisItem(
          classification: ChangeClassification.storeReleaseRequired,
          path: '<toolchain>',
          detail: diagnostic.detail,
          functionIds: const <String>[],
          diagnostic: diagnostic,
        ),
      );
    }
    for (final path in paths.toList()..sort()) {
      final before = baselineSources[path];
      final after = currentSources[path];
      if (before != null &&
          after != null &&
          before.fingerprint == after.fingerprint) {
        continue;
      }
      if (before != null &&
          after != null &&
          before.semanticFingerprint ==
              sha256Hex(
                utf8.encode(
                  stripDartCommentsAndWhitespace(after.file.readAsStringSync()),
                ),
              )) {
        continue;
      }
      if (after == null) {
        final diagnostic = ToolDiagnostic(
          code: 'P2005',
          severity: DiagnosticSeverity.error,
          summary: 'Tracked source file was removed',
          detail: path,
          action: 'Create a new store release for source removal.',
          storeReleaseRequired: true,
        );
        diagnostics.add(diagnostic);
        items.add(
          AnalysisItem(
            classification: ChangeClassification.storeReleaseRequired,
            path: path,
            detail: 'Source file removed',
            functionIds: const <String>[],
            diagnostic: diagnostic,
          ),
        );
        continue;
      }
      if (before == null) {
        final diagnostic = ToolDiagnostic(
          code: 'P2006',
          severity: DiagnosticSeverity.error,
          summary: 'New source unit is not in the release baseline',
          detail: path,
          action: 'Create a new store release before patching a new library.',
          storeReleaseRequired: true,
        );
        diagnostics.add(diagnostic);
        items.add(
          AnalysisItem(
            classification: ChangeClassification.storeReleaseRequired,
            path: path,
            detail: 'New source unit',
            functionIds: const <String>[],
            diagnostic: diagnostic,
          ),
        );
        continue;
      }
      if (!after.selected ||
          !after.kind.name.contains('Dart') &&
              after.kind != SourceKind.applicationDart &&
              after.kind != SourceKind.localPackage) {
        final nativeBoundary =
            after.kind == SourceKind.nativeBoundary ||
            after.kind == SourceKind.pluginDart;
        final diagnostic = ToolDiagnostic(
          code: nativeBoundary ? 'N3005' : 'P2002',
          severity: DiagnosticSeverity.error,
          summary: nativeBoundary
              ? 'Native boundary source changed'
              : 'Changed source unit is outside the patchable subset',
          detail: after.reason ?? after.kind.name,
          path: path,
          action: nativeBoundary
              ? 'Create a normal store release; native implementation changes are not OTA patch content.'
              : 'Perform a normal store release or change only supported source.',
          storeReleaseRequired: nativeBoundary,
        );
        diagnostics.add(diagnostic);
        items.add(
          AnalysisItem(
            classification: nativeBoundary
                ? ChangeClassification.storeReleaseRequired
                : ChangeClassification.unsupported,
            path: path,
            detail: diagnostic.detail,
            functionIds: const <String>[],
            diagnostic: diagnostic,
          ),
        );
        continue;
      }
      final transformed = currentInstrumented[path];
      if (transformed == null ||
          !transformed.instrumented ||
          transformed.manifest == null) {
        final diagnostic = ToolDiagnostic(
          code: 'P2003',
          severity: DiagnosticSeverity.error,
          summary: 'Changed source contains unsupported declarations',
          detail:
              transformed?.exclusions.join('; ') ?? 'No instrumented manifest',
          path: path,
          action: 'Perform a normal store release or remove the unsupported change.',
        );
        diagnostics.add(diagnostic);
        items.add(
          AnalysisItem(
            classification: ChangeClassification.unsupported,
            path: path,
            detail: diagnostic.detail,
            functionIds: const <String>[],
            diagnostic: diagnostic,
          ),
        );
        continue;
      }
      final beforeFunctions = release.functions
          .where((item) => item.sourcePath == path)
          .toList(growable: false);
      final afterFunctions = transformed.manifest!.functions;
      final beforeIds = beforeFunctions.map((item) => item.id).toSet();
      final afterIds = afterFunctions.map((item) => item.id).toSet();
      if (!beforeIds.containsAll(afterIds) ||
          !afterIds.containsAll(beforeIds)) {
        final diagnostic = ToolDiagnostic(
          code: 'P2004',
          severity: DiagnosticSeverity.error,
          summary: 'Changed function table is incompatible with the release',
          detail: 'Function additions or removals are not patchable.',
          path: path,
          action: 'Create a new store release for function table changes.',
          storeReleaseRequired: true,
        );
        diagnostics.add(diagnostic);
        items.add(
          AnalysisItem(
            classification: ChangeClassification.storeReleaseRequired,
            path: path,
            detail: diagnostic.detail,
            functionIds: const <String>[],
            diagnostic: diagnostic,
          ),
        );
        continue;
      }
      final incompatibleSignature = afterFunctions.any((function) {
        final baseline = beforeFunctions.firstWhere(
          (item) => item.id == function.id,
        );
        return baseline.signatureDigest !=
            _wireSignatureDigest(function.signatureDigest);
      });
      if (incompatibleSignature) {
        final diagnostic = ToolDiagnostic(
          code: 'P2007',
          severity: DiagnosticSeverity.error,
          summary: 'Changed function signature is incompatible',
          detail: 'Parameter ordering, names, defaults, receiver, or return type changed.',
          path: path,
          action: 'Create a new store release for signature changes.',
          storeReleaseRequired: true,
        );
        diagnostics.add(diagnostic);
        items.add(
          AnalysisItem(
            classification: ChangeClassification.storeReleaseRequired,
            path: path,
            detail: diagnostic.detail,
            functionIds: const <String>[],
            diagnostic: diagnostic,
          ),
        );
        continue;
      }

      final currentDeclarationFingerprints =
          SourceDeclarationFingerprints.collect(
            after.file.readAsStringSync(),
            path: path,
          );
      final changedDeclarationKeys = _changedDeclarationKeys(
        before.declarationFingerprints,
        currentDeclarationFingerprints,
      );
      final supportedDeclarationKeys = beforeFunctions
          .map((function) => function.declarationKey)
          .toSet();
      final unsupportedDeclarationChanges =
          changedDeclarationKeys
              .where((key) => !supportedDeclarationKeys.contains(key))
              .toList()
            ..sort();
      if (before.declarationFingerprints.isEmpty ||
          unsupportedDeclarationChanges.isNotEmpty) {
        final detail = before.declarationFingerprints.isEmpty
            ? 'The release has no declaration fingerprints for this source unit.'
            : 'Changed unsupported declarations: ${unsupportedDeclarationChanges.join(', ')}';
        final diagnostic = ToolDiagnostic(
          code: 'P2003',
          severity: DiagnosticSeverity.error,
          summary: 'Changed source contains unsupported declarations',
          detail: detail,
          path: path,
          action: 'Perform a normal store release or remove the unsupported change.',
        );
        diagnostics.add(diagnostic);
        items.add(
          AnalysisItem(
            classification: ChangeClassification.unsupported,
            path: path,
            detail: detail,
            functionIds: const <String>[],
            diagnostic: diagnostic,
          ),
        );
        continue;
      }

      final functionIds = beforeFunctions
          .where(
            (function) =>
                changedDeclarationKeys.contains(function.declarationKey),
          )
          .map((function) => function.id)
          .toList();
      if (functionIds.isEmpty) {
        final diagnostic = ToolDiagnostic(
          code: 'P2008',
          severity: DiagnosticSeverity.error,
          summary: 'Changed source has no patchable function body',
          detail: 'Imports, top-level metadata, or unsupported syntax may have changed.',
          path: path,
          action: 'Create a store release unless the change is reverted.',
        );
        diagnostics.add(diagnostic);
        items.add(
          AnalysisItem(
            classification: ChangeClassification.unknown,
            path: path,
            detail: diagnostic.detail,
            functionIds: const <String>[],
            diagnostic: diagnostic,
          ),
        );
      } else {
        final firstFunction = beforeFunctions.firstWhere(
          (function) => function.id == functionIds.first,
        );
        final location = _functionLocation(after.file, firstFunction.name);
        items.add(
          AnalysisItem(
            classification: ChangeClassification.patchable,
            path: path,
            detail: '${functionIds.length} function(s) selected',
            functionIds: functionIds,
            libraryUri: after.libraryUri,
            line: location?.line,
            column: location?.column,
          ),
        );
      }
    }
    if (graph.fingerprint != release.graphFingerprint) {
      final diagnostic = ToolDiagnostic(
        code: 'N3003',
        severity: DiagnosticSeverity.error,
        summary: 'Resolved package graph changed',
        detail: '${release.graphFingerprint} -> ${graph.fingerprint}',
        action: 'Create a new store release; dependency changes are not assumed patch-safe.',
        storeReleaseRequired: true,
      );
      diagnostics.add(diagnostic);
      items.add(
        AnalysisItem(
          classification: ChangeClassification.storeReleaseRequired,
          path: 'pubspec.lock',
          detail: diagnostic.detail,
          functionIds: const <String>[],
          diagnostic: diagnostic,
        ),
      );
    }
    final native = _nativeSnapshot(current, graph);
    if (canonicalJson(native) != canonicalJson(release.nativeFingerprints)) {
      final diagnostic = ToolDiagnostic(
        code: 'N3001',
        severity: DiagnosticSeverity.error,
        summary: 'Native or store-reviewed project input changed',
        detail:
            'Android/iOS/native build inputs differ from the release baseline.',
        action: 'Create a normal store release; OTA data patches cannot change native inputs.',
        storeReleaseRequired: true,
      );
      diagnostics.add(diagnostic);
      items.add(
        AnalysisItem(
          classification: ChangeClassification.storeReleaseRequired,
          path: '<native inputs>',
          detail: diagnostic.detail,
          functionIds: const <String>[],
          diagnostic: diagnostic,
        ),
      );
    }
    final currentConfigFingerprint = digestJson(<String, Object?>{
      'tool': config.encode(),
    });
    if (currentConfigFingerprint != release.configFingerprint) {
      final diagnostic = ToolDiagnostic(
        code: 'N3004',
        severity: DiagnosticSeverity.error,
        summary: 'Toolchain configuration changed',
        detail: 'tool.yaml differs from the release baseline.',
        action:
            'Create a new store release after changing instrumentation policy.',
        storeReleaseRequired: true,
      );
      diagnostics.add(diagnostic);
      items.add(
        AnalysisItem(
          classification: ChangeClassification.storeReleaseRequired,
          path: 'tool.yaml',
          detail: diagnostic.detail,
          functionIds: const <String>[],
          diagnostic: diagnostic,
        ),
      );
    }
    if (items.isEmpty && source.fingerprint == release.sourceFingerprint) {
      items.add(
        const AnalysisItem(
          classification: ChangeClassification.noEffect,
          path: '<working tree>',
          detail: 'No patchable source changes detected.',
          functionIds: <String>[],
        ),
      );
    }
    return AnalysisResult(
      release: release,
      currentSourceFingerprint: source.fingerprint,
      currentGraphFingerprint: graph.fingerprint,
      items: items,
      plan: plan,
      diagnostics: diagnostics,
    );
  }

  _SourceLocation? _functionLocation(File file, String name) {
    final source = file.readAsStringSync();
    final match = RegExp('\\b${RegExp.escape(name)}\\b').firstMatch(source);
    if (match == null) return null;
    final offset = match.start;
    final line = 1 + '\n'.allMatches(source.substring(0, offset)).length;
    final previousNewline = source.lastIndexOf('\n', offset - 1);
    return _SourceLocation(line: line, column: offset - previousNewline);
  }

  Future<PatchBuildResult> patch({
    String? projectPath,
    String? releaseId,
  }) async {
    final analysis = analyze(projectPath: projectPath, releaseId: releaseId);
    if (!analysis.canPatch) {
      final errors = analysis.diagnostics
          .where((item) => item.severity == DiagnosticSeverity.error)
          .toList(growable: false);
      if (errors.isEmpty) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.analysis,
          code: 'P2010',
          summary: 'No patchable changes were found',
          detail:
              'The working tree contains no changed supported function body.',
          action: 'Change supported Dart code or create a new store release.',
        );
      }
      throw ToolFailure(exitCode: ToolExitCode.analysis, diagnostics: errors);
    }
    final current = analysis.plan.project;
    final config = this.config(current);
    final store = ToolStore(current);
    final privateKey = _keyStore.readPrivate(
      store.resolveConfiguredPath(config.privateKeyPath, allowExternal: true),
    );
    final trustedPublicKey = _keyStore.readPublic(
      store.resolveConfiguredPath(config.publicKeyPath),
    );
    if (trustedPublicKey.keyId != privateKey.keyId) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.signing,
        code: 'S4007',
        summary: 'Configured private key does not match the trusted public key',
        detail: '${privateKey.keyId} / ${trustedPublicKey.keyId}',
        action: 'Use the key pair configured for this release baseline.',
      );
    }
    final sequence = store.nextSequence(analysis.release.releaseId);
    final changed = analysis.items
        .where((item) => item.classification == ChangeClassification.patchable)
        .expand((item) => item.functionIds)
        .toSet();
    if (changed.isEmpty) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.analysis,
        code: 'P2010',
        summary: 'No patchable changes were found',
        detail: 'The working tree contains no changed supported function body.',
        action: 'Change supported Dart code or create a new store release.',
      );
    }
    final baselineFunctions = <String, FunctionRecord>{
      for (final function in analysis.release.functions) function.id: function,
    };
    final expectedFunctions = <String, int>{
      for (final function in analysis.release.functions)
        function.id: function.slot,
    };
    final expectedSignatures = <String, E0FunctionSignature>{};
    final expectedReceivers = <String, E0ReceiverDescriptor>{};
    for (final function in analysis.release.functions) {
      final manifest = E0FunctionManifest.fromJson(function.manifest);
      expectedSignatures[function.id] = manifest.signature;
      expectedReceivers[function.id] = manifest.receiver;
    }
    final compiled = <String, List<int>>{};
    final patchFunctions = <PatchFunctionEntry>[];
    for (final planned in analysis.plan.functions) {
      if (!changed.contains(planned.manifest.id)) continue;
      final baseline = baselineFunctions[planned.manifest.id];
      if (baseline == null) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.compatibility,
          code: 'P2009',
          summary: 'Changed function is not in the release baseline',
          detail: planned.manifest.id,
        );
      }
      final bytes = HyfensCompiler().compile(
        PatchCompileRequest(
          source: planned.source.file.readAsStringSync(),
          manifest: planned.sourceManifest(analysis.plan),
          functionName: planned.manifest.name,
          className: planned.manifest.identity.ownerName,
          canonicalLibraryUri: planned.source.libraryUri,
          patchSequence: sequence,
        ),
      );
      final program = E0PatchContainer.decode(
        bytes,
        expectedAppId: analysis.release.applicationId,
        expectedReleaseId: analysis.release.releaseId,
        expectedBuildFingerprint: analysis.release.buildFingerprint,
        expectedFunctions: expectedFunctions,
        expectedSignatures: expectedSignatures,
        expectedReceivers: expectedReceivers,
      );
      if (program.capabilities.isNotEmpty ||
          program.widgetFactories.isNotEmpty) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.analysis,
          code: 'P2011',
          summary: 'Compiled patch requires an undeclared host contract',
          detail:
              '${program.capabilities.length} capabilities, ${program.widgetFactories.length} widget factories',
          action: 'Use only capabilities declared by the release contract or create a normal store release.',
        );
      }
      compiled[planned.manifest.id] = bytes;
      patchFunctions.add(
        PatchFunctionEntry(
          id: baseline.id,
          slot: baseline.slot,
          signatureDigest: baseline.signatureDigest,
        ),
      );
    }
    patchFunctions.sort((left, right) => left.id.compareTo(right.id));
    final bridge = <String, Object?>{
      'bridgeVersion': 1,
      'encoding': 'e0-patch-container-v9-bytes',
      'functions': <String, Object?>{
        for (final id in compiled.keys.toList()..sort())
          id: base64.encode(compiled[id]!),
      },
    };
    final draft = PatchArtifact(
      runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
      applicationId: analysis.release.applicationId,
      releaseId: analysis.release.releaseId,
      patchId: patchIdFor(
        releaseId: analysis.release.releaseId,
        sourceFingerprint: analysis.currentSourceFingerprint,
        sequence: sequence,
      ),
      sequence: sequence,
      functions: patchFunctions,
      capabilities: const <PatchCapabilityEntry>[],
      constants: const <PatchValue>[PatchValue.string('hyfens-e0-bridge-v1')],
      instructions: const <int>[0],
      signatureMetadata: PatchSignatureMetadata(
        algorithm: 'ed25519',
        keyId: privateKey.keyId,
      ),
      payloadDigest: const <int>[],
      signature: const <int>[],
      extensions: <PatchExtensionSection>[
        PatchExtensionSection(
          type: _bridgeExtensionType,
          flags: 0,
          payload: utf8.encode(canonicalJson(bridge)),
        ),
      ],
    );
    final artifact = await PatchFormatV1.sealAsync(draft, privateKey.sign);
    final bytes = PatchFormatV1.encode(artifact);
    final preflight = PatchFormatV1.decode(bytes);
    final preflightValid = await trustedPublicKey.verify(
      PatchFormatV1.signingBytes(preflight),
      preflight.signature,
    );
    if (!preflightValid) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.signing,
        code: 'S4007',
        summary: 'Configured private key does not match the trusted public key',
        detail: trustedPublicKey.keyId,
        action: 'Use the key pair configured for this release baseline.',
      );
    }
    final output = store.patch(analysis.release.releaseId, sequence);
    await writeAtomicBytes(output, bytes);
    final decoded = PatchFormatV1.decode(output.readAsBytesSync());
    final valid = await trustedPublicKey.verify(
      PatchFormatV1.signingBytes(decoded),
      decoded.signature,
    );
    if (!valid) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.signing,
        code: 'S4006',
        summary: 'Generated patch signature did not verify',
        detail: output.path,
      );
    }
    await store.commitSequence(analysis.release.releaseId, sequence);
    return PatchBuildResult(
      artifact: decoded,
      output: output,
      size: bytes.length,
    );
  }

  PatchInspection inspect(File file) {
    try {
      final artifact = PatchFormatV1.decode(file.readAsBytesSync());
      return PatchInspection(artifact: artifact, path: file.path);
    } on Object catch (error) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'R5004',
        summary: 'Patch artifact is malformed',
        detail: '$error',
        path: file.path,
      );
    }
  }

  Future<PatchInspection> verify({
    required File file,
    String? projectPath,
    String? releaseId,
  }) async {
    final inspection = inspect(file);
    final current = project(projectPath: projectPath);
    final config = this.config(current);
    final publicKey = _keyStore.readPublic(
      ToolStore(current).resolveConfiguredPath(config.publicKeyPath),
    );
    if (inspection.artifact.signatureMetadata.algorithm != 'ed25519') {
      throw ToolFailure.single(
        exitCode: ToolExitCode.signing,
        code: 'S4008',
        summary: 'Patch signature algorithm is unsupported',
        detail: inspection.artifact.signatureMetadata.algorithm,
        action: 'Generate the patch with the configured Ed25519 signer.',
      );
    }
    if (publicKey.keyId != inspection.artifact.signatureMetadata.keyId) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.signing,
        code: 'S4007',
        summary: 'Patch key is not the configured trusted key',
        detail: inspection.artifact.signatureMetadata.keyId,
      );
    }
    final valid = await publicKey.verify(
      PatchFormatV1.signingBytes(inspection.artifact),
      inspection.artifact.signature,
    );
    if (!valid) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.signing,
        code: 'S4008',
        summary: 'Patch signature is invalid',
        detail: file.path,
      );
    }
    if (releaseId != null) {
      final baseline = ToolStore(current).readRelease(releaseId);
      _verifyAgainstRelease(inspection.artifact, baseline);
    }
    return inspection;
  }

  Future<SigningKey> generateKeys({String? projectPath}) async {
    final current = project(projectPath: projectPath);
    final config = this.config(current);
    final store = ToolStore(current);
    await store.ensure();
    return _keyStore.generate(
      privateFile: store.resolveConfiguredPath(
        config.privateKeyPath,
        allowExternal: true,
      ),
      publicFile: store.resolveConfiguredPath(config.publicKeyPath),
    );
  }

  PublicSigningKey inspectPublicKey({String? projectPath}) {
    final current = project(projectPath: projectPath);
    final config = this.config(current);
    return _keyStore.readPublic(
      ToolStore(current).resolveConfiguredPath(config.publicKeyPath),
    );
  }

  ReleaseRecord _selectRelease(ToolStore store, String? releaseId) {
    if (releaseId != null) return store.readRelease(releaseId);
    final records = store.listReleases();
    if (records.length == 1) return records.single;
    if (records.isEmpty) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'R5001',
        summary: 'No release baseline is available',
        detail: store.releases.path,
        action: 'Run hyfens release android or hyfens release ios first.',
      );
    }
    throw ToolFailure.single(
      exitCode: ToolExitCode.compatibility,
      code: 'R5002',
      summary: 'Release target is ambiguous',
      detail: records.map((item) => item.releaseId).join(', '),
      action: 'Pass --release <release-id> explicitly.',
    );
  }

  ReleaseBaselineManifest _baselineManifest({
    required FlutterProject project,
    required SourceDiscoveryResult source,
    required InstrumentationPlan plan,
    required String releaseId,
    required String buildFingerprint,
    required String applicationId,
  }) {
    final functions = <PatchFunctionEntry>[];
    final byId = <String, PlannedFunction>{
      for (final function in plan.functions) function.manifest.id: function,
    };
    final ids = byId.keys.toList()..sort();
    for (var index = 0; index < ids.length; index++) {
      final function = byId[ids[index]]!.manifest;
      functions.add(
        PatchFunctionEntry(
          id: function.id,
          slot: index,
          signatureDigest: _wireSignatureDigest(function.signatureDigest),
        ),
      );
    }
    final sortedUnits = source.units.toList()
      ..sort((left, right) => left.libraryUri.compareTo(right.libraryUri));
    return ReleaseBaselineManifest(
      applicationId: applicationId,
      releaseId: releaseId,
      runtimeCompatibilityVersion: patchFormatRuntimeCompatibilityV1,
      patchFormatVersion: patchFormatV1,
      buildFingerprint: buildFingerprint,
      functions: functions,
      capabilities: const <PatchCapabilityEntry>[],
      packages: <String>{
        for (final unit in source.units) unit.packageName,
      }.toList()..sort(),
      sourceUnits: <ReleaseBaselineSourceUnit>[
        for (final unit in sortedUnits)
          ReleaseBaselineSourceUnit(
            packageName: unit.packageName,
            libraryUri: unit.libraryUri,
            sourceKind: unit.kind.name,
            instrumented: plan.units.any(
              (item) =>
                  item.source.libraryUri == unit.libraryUri &&
                  item.instrumented,
            ),
          ),
      ],
    );
  }

  List<FunctionRecord> _functionRecords(
    FlutterProject project,
    InstrumentationPlan plan,
  ) {
    final functions = plan.functions.toList()
      ..sort((left, right) => left.manifest.id.compareTo(right.manifest.id));
    return <FunctionRecord>[
      for (var index = 0; index < functions.length; index++)
        FunctionRecord(
          id: functions[index].manifest.id,
          slot: index,
          signatureDigest: _wireSignatureDigest(
            functions[index].manifest.signatureDigest,
          ),
          sourcePath: functions[index].source.relativeTo(project),
          libraryUri: functions[index].source.libraryUri,
          name: functions[index].manifest.name,
          className: functions[index].manifest.identity.ownerName,
          manifest: Map<String, Object?>.from(
            functions[index].manifest.toJson(),
          ),
        ),
    ];
  }

  SourceRecord _sourceRecord(
    FlutterProject project,
    SourceUnit source,
    InstrumentationPlan plan,
  ) {
    final unit = plan.units
        .where((item) => item.source.libraryUri == source.libraryUri)
        .firstOrNull;
    return SourceRecord(
      relativePath: source.relativeTo(project),
      libraryUri: source.libraryUri,
      packageName: source.packageName,
      kind: source.kind.name,
      selected: source.selected,
      entrypoint: source.entrypoint,
      instrumented: unit?.instrumented ?? false,
      fingerprint: source.fingerprint,
      semanticFingerprint: sha256Hex(
        utf8.encode(
          stripDartCommentsAndWhitespace(source.file.readAsStringSync()),
        ),
      ),
      declarationFingerprints: SourceDeclarationFingerprints.collect(
        source.file.readAsStringSync(),
        path: source.relativeTo(project),
      ),
      exclusions: unit?.exclusions ?? <String>[source.reason ?? 'not selected'],
      manifest: unit?.manifest?.encode(),
    );
  }

  Map<String, Object?> _nativeSnapshot(
    FlutterProject project,
    ProjectGraph graph,
  ) {
    final paths = <String>[];
    for (final directory in <String>[
      'android',
      'ios',
      'macos',
      'windows',
      'linux',
    ]) {
      final root = Directory(p.join(project.root.path, directory));
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = relativePath(project.root, entity);
        if (_nativeInput(relative) && !_volatileNativePath(relative)) {
          paths.add(relative);
        }
      }
    }
    final packageFiles = <String, File>{};
    for (final package in graph.packages) {
      if (!package.hasNativeImplementation || package.root == null) continue;
      for (final directory in <String>[
        'android',
        'ios',
        'macos',
        'windows',
        'linux',
      ]) {
        final root = Directory(p.join(package.root!.path, directory));
        if (!root.existsSync()) continue;
        for (final entity in root.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          final relative = relativePath(package.root!, entity);
          if (_nativeInput(relative) && !_volatileNativePath(relative)) {
            packageFiles['package:${package.name}/$relative'] = entity;
          }
        }
      }
    }
    paths.sort();
    final result = <String, Object?>{
      for (final path in paths)
        path: sha256Hex(
          File(p.join(project.root.path, path)).readAsBytesSync(),
        ),
    };
    result.addAll(<String, String>{
      for (final entry in packageFiles.entries)
        entry.key: sha256Hex(entry.value.readAsBytesSync()),
    });
    return result;
  }

  Future<Map<String, Object?>> _buildInstrumentedRelease({
    required FlutterProject project,
    required InstrumentationPlan plan,
    required String target,
    required String buildMode,
    required ToolEnvironmentSnapshot environment,
    required ProjectGraph graph,
    required Directory artifactStagingDirectory,
  }) async {
    if (environment.flutterStatus != 'SUPPORTED') {
      throw ToolFailure.single(
        exitCode: ToolExitCode.environment,
        code: 'T1101',
        summary: 'Flutter SDK is unavailable for release build',
        detail: environment.flutterStatus,
        action: 'Install/use a supported Flutter SDK or pass --metadata-only for metadata tests.',
      );
    }
    final workspace = await Directory.systemTemp.createTemp('hyfens-build-');
    final started = DateTime.now();
    try {
      await _copyTree(
        project.root,
        workspace,
        skip: <String>{'.git', '.tool', 'build', '.dart_tool'},
      );
      await _copyTree(
        Directory(p.join(project.root.path, '.dart_tool')),
        Directory(p.join(workspace.path, '.dart_tool')),
        // Keep package configuration, but never carry Flutter's prior build
        // graph/native-asset outputs into the isolated overlay. Those files
        // can retain plugins removed from the current resolved graph.
        skip: <String>{
          '.DS_Store',
          'e1_overlay',
          'e1_ios_overlay',
          'flutter_build',
        },
      );
      await _writeOverlayRuntimeDependencies(workspace);
      final overlayPackageRoots = <String, Directory>{};
      final selectedExternalPackages = plan.units
          .where(
            (unit) =>
                unit.instrumented && !isWithin(project.root, unit.source.file),
          )
          .map((unit) => unit.source.packageName)
          .toSet();
      for (final package in graph.packages) {
        if (!selectedExternalPackages.contains(package.name) ||
            package.root == null ||
            isWithin(project.root, package.root!)) {
          continue;
        }
        final destination = Directory(
          p.join(workspace.path, '.hyfens_packages', package.name),
        );
        await _copyTree(
          package.root!,
          destination,
          skip: <String>{'.git', '.dart_tool', 'build', '.gradle', '.DS_Store'},
        );
        overlayPackageRoots[package.name] = destination;
      }
      final packageConfig = project.packageConfigFile;
      if (packageConfig == null) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1602',
          summary: 'Dart package configuration is missing',
          detail: '.dart_tool/package_config.json',
          action: 'Run flutter pub get, then retry hyfens release.',
        );
      }
      await _writeOverlayPackageConfig(
        project,
        workspace,
        packageConfig,
        packageRootOverrides: overlayPackageRoots,
      );
      await _writeOverlayPackageGraph(workspace);
      await _writeOverlayPluginDependencies(
        workspace: workspace,
        flutterVersion: environment.flutterVersion,
      );
      await _writeOverlayAndroidPluginRegistrant(workspace);
      for (final unit in plan.units) {
        if (!unit.instrumented || unit.transformedSource == null) continue;
        final Directory destinationRoot;
        final String destinationRelativePath;
        if (isWithin(project.root, unit.source.file)) {
          destinationRoot = workspace;
          destinationRelativePath = relativePath(
            project.root,
            unit.source.file,
          );
        } else {
          final overlay = overlayPackageRoots[unit.source.packageName];
          final package = graph.packages
              .where((item) => item.name == unit.source.packageName)
              .firstOrNull;
          if (overlay == null || package?.root == null) {
            throw ToolFailure.single(
              exitCode: ToolExitCode.environment,
              code: 'T1607',
              summary:
                  'Selected external package cannot be instrumented safely',
              detail: unit.source.libraryUri,
              action: 'Use a supported local package path or exclude the package from instrumentation, then create a new release.',
            );
          }
          destinationRoot = overlay;
          destinationRelativePath = relativePath(
            package!.root!,
            unit.source.file,
          );
        }
        final destination = File(
          p.join(destinationRoot.path, destinationRelativePath),
        );
        await writeAtomicText(destination, unit.transformedSource!);
      }
      final command = <String>[
        'build',
        target == 'android' ? 'apk' : 'ipa',
        if (buildMode == 'release') '--release',
        // Phase 1B validates installation on registered physical devices.
        // A local development export uses the existing Apple Development
        // identity/profile and does not require a distribution certificate or
        // App Store credentials. The Flutter build is still Release mode.
        if (target == 'ios') '--export-method=development',
        '--no-pub',
      ];
      final runtimeDefines = _runtimeBuildDefines();
      command.addAll(runtimeDefines.arguments);
      final recordedCommand = <String>[
        'flutter',
        ...<String>[
          'build',
          target == 'android' ? 'apk' : 'ipa',
          if (buildMode == 'release') '--release',
          if (target == 'ios') '--export-method=development',
          '--no-pub',
        ],
        ...runtimeDefines.recordedArguments,
      ];
      final result = await Process.run(
        'flutter',
        command,
        workingDirectory: workspace.path,
      );
      if (result.exitCode != 0) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1603',
          summary: 'Instrumented Flutter release build failed',
          detail: '${result.stdout}\n${result.stderr}',
          action: 'Review the normal Flutter build output; original source was not modified.',
        );
      }
      final output = target == 'android'
          ? _firstFile(
              Directory(
                p.join(
                  workspace.path,
                  'build',
                  'app',
                  'outputs',
                  'flutter-apk',
                ),
              ),
              '.apk',
            )
          : _firstFile(
              Directory(p.join(workspace.path, 'build', 'ios', 'ipa')),
              '.ipa',
            );
      if (output == null) {
        final buildOutput = '${result.stdout}\n${result.stderr}'.trim();
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1606',
          summary: 'Flutter completed without a release artifact',
          detail:
              'Expected a ${target == 'android' ? '.apk' : '.ipa'} under the Flutter build output directory.\n${_boundedDiagnosticText(buildOutput)}',
          action: 'Resolve signing/export settings and retry; no release baseline was committed.',
        );
      }
      final destination = File(
        p.join(artifactStagingDirectory.path, p.basename(output.path)),
      );
      await destination.parent.create(recursive: true);
      await output.copy(destination.path);
      return <String, Object?>{
        'metadataOnly': false,
        'status': 'SUCCESS',
        'command': recordedCommand,
        'elapsedMs': DateTime.now().difference(started).inMilliseconds,
        'artifact': p.basename(output.path),
        'artifactPath': destination.path,
      };
    } finally {
      if (workspace.existsSync()) {
        await workspace.delete(recursive: true);
      }
    }
  }

  _RuntimeBuildDefines _runtimeBuildDefines() {
    const names = <String>[
      'HYFENS_CONTROL_PLANE_URL',
      'HYFENS_DELIVERY_CREDENTIAL',
      'HYFENS_APPLICATION_ID',
      'HYFENS_ENVIRONMENT_ID',
      'HYFENS_PLATFORM_ID',
    ];
    final arguments = <String>[];
    final recordedArguments = <String>[];
    for (final name in names) {
      final value = Platform.environment[name];
      if (value == null || value.isEmpty) continue;
      if (value.contains(RegExp(r'[\r\n]')) || value.length > 4096) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1610',
          summary: 'Runtime delivery build define is invalid',
          detail: name,
          action: 'Use a bounded single-line value for the runtime delivery configuration.',
        );
      }
      arguments.add('--dart-define=$name=$value');
      final recordedValue = name == 'HYFENS_DELIVERY_CREDENTIAL'
          ? '<redacted>'
          : value;
      recordedArguments.add('--dart-define=$name=$recordedValue');
    }
    return _RuntimeBuildDefines(
      arguments: arguments,
      recordedArguments: recordedArguments,
    );
  }

  Future<void> _writeOverlayPackageConfig(
    FlutterProject project,
    Directory workspace,
    File original, {
    Map<String, Directory> packageRootOverrides = const <String, Directory>{},
  }) async {
    final raw = decodeJsonObject(original);
    final packages = raw['packages'];
    if (packages is! List<Object?>) {
      throw const FormatException(
        'package_config.json packages must be a list',
      );
    }
    final canonicalWorkspace = Directory(workspace.resolveSymbolicLinksSync());
    final rewritten = <Object?>[];
    var hasInstrumentationRuntime = false;
    for (final item in packages) {
      if (item is! Map<String, Object?> || item['rootUri'] is! String) {
        throw const FormatException('Invalid package_config entry');
      }
      final declaredRootUri = Uri.parse(item['rootUri']! as String);
      final rootUri = declaredRootUri.isAbsolute
          ? declaredRootUri
          : original.parent.uri.resolveUri(declaredRootUri);
      final packageName = item['name']! as String;
      if (packageName == 'instrumentation_e0') {
        hasInstrumentationRuntime = true;
      }
      final override = packageRootOverrides[packageName];
      if (override != null) {
        rewritten.add(<String, Object?>{
          ...item,
          'rootUri': Directory(override.resolveSymbolicLinksSync()).absolute.uri
              .toString(),
        });
        continue;
      }
      if (rootUri.scheme == 'file') {
        final originalRoot = Directory.fromUri(rootUri);
        if (isWithin(project.root, originalRoot)) {
          final relative = relativePath(project.root, originalRoot);
          final replacement = Directory(
            p.join(canonicalWorkspace.path, relative),
          );
          rewritten.add(<String, Object?>{
            ...item,
            'rootUri': replacement.absolute.uri.toString(),
          });
          continue;
        }
      }
      rewritten.add(<String, Object?>{...item, 'rootUri': rootUri.toString()});
    }
    if (!hasInstrumentationRuntime) {
      final runtimeFile = Isolate.resolvePackageUriSync(
        Uri.parse('package:instrumentation_e0/e0_runtime.dart'),
      );
      if (runtimeFile == null || runtimeFile.scheme != 'file') {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1605',
          summary: 'Patch runtime package is unavailable to the tool',
          detail: 'package:instrumentation_e0/e0_runtime.dart',
          action: 'Install the tool with its runtime package and retry.',
        );
      }
      final runtimeRoot = Directory.fromUri(runtimeFile).parent.parent;
      rewritten.add(<String, Object?>{
        'name': 'instrumentation_e0',
        'rootUri': Directory(runtimeRoot.resolveSymbolicLinksSync())
            .absolute
            .uri
            .toString(),
        'packageUri': 'lib/',
        'languageVersion': '3.13',
      });
    }
    _appendToolRuntimePackages(rewritten);
    final output = <String, Object?>{...raw, 'packages': rewritten};
    await writeAtomicText(
      File(p.join(workspace.path, '.dart_tool', 'package_config.json')),
      canonicalJson(output),
    );
  }

  /// Rebuilds Flutter's ephemeral plugin graph after adding the runtime
  /// package to the temporary package configuration.
  ///
  /// The generated bootstrap uses `path_provider` for private application
  /// support storage. Merely adding its Dart package to package_config.json
  /// is insufficient: Flutter's native registrant is generated from
  /// `.flutter-plugins-dependencies`. This overlay-only file lets the normal
  /// Flutter build discover the resolved Android/iOS implementations without
  /// changing the developer's pubspec, lockfile, or native project.
  Future<void> _writeOverlayPluginDependencies({
    required Directory workspace,
    required String flutterVersion,
  }) async {
    final packageConfigFile = File(
      p.join(workspace.path, '.dart_tool', 'package_config.json'),
    );
    final packageConfig = decodeJsonObject(packageConfigFile);
    final rawPackages = packageConfig['packages'];
    if (rawPackages is! List<Object?>) {
      throw const FormatException(
        'overlay package_config.json packages must be a list',
      );
    }

    final packageDetails = <String, _OverlayPluginPackage>{};
    for (final raw in rawPackages) {
      if (raw is! Map<String, Object?> ||
          raw['name'] is! String ||
          raw['rootUri'] is! String) {
        throw const FormatException('Invalid overlay package_config entry');
      }
      final rootUri = Uri.parse(raw['rootUri']! as String);
      if (rootUri.scheme != 'file') continue;
      final root = Directory.fromUri(rootUri);
      final pubspec = File(p.join(root.path, 'pubspec.yaml'));
      if (!pubspec.existsSync()) continue;
      final decoded = loadYaml(pubspec.readAsStringSync());
      if (decoded is! YamlMap) continue;
      final flutter = decoded['flutter'];
      final plugin = flutter is YamlMap ? flutter['plugin'] : null;
      if (plugin is! YamlMap || plugin['platforms'] is! YamlMap) continue;
      final platforms = <String, Map<String, Object?>>{};
      final rawPlatforms = plugin['platforms']! as YamlMap;
      for (final entry in rawPlatforms.entries) {
        if (entry.key is! String || entry.value is! YamlMap) continue;
        platforms[entry.key! as String] = _yamlMapToObject(
          entry.value! as YamlMap,
        );
      }
      if (platforms.isEmpty) continue;
      final dependencies = decoded['dependencies'];
      final dependencyNames = dependencies is YamlMap
          ? dependencies.keys.whereType<String>().toSet()
          : <String>{};
      packageDetails[raw['name']! as String] = _OverlayPluginPackage(
        name: raw['name']! as String,
        root: root,
        platforms: platforms,
        dependencyNames: dependencyNames,
      );
    }

    final existingFile = File(
      p.join(workspace.path, '.flutter-plugins-dependencies'),
    );
    final existing = existingFile.existsSync()
        ? decodeJsonObject(existingFile)
        : <String, Object?>{};
    final existingPlugins = <String, List<Object?>>{};
    final rawExistingPlugins = existing['plugins'];
    if (rawExistingPlugins is Map<String, Object?>) {
      for (final entry in rawExistingPlugins.entries) {
        if (entry.value is List<Object?>) {
          existingPlugins[entry.key] = List<Object?>.from(
            entry.value! as List<Object?>,
          );
        }
      }
    }

    final pluginNames = packageDetails.keys.toSet();
    final platforms = <String>{...existingPlugins.keys};
    platforms.addAll(const <String>[
      'android',
      'ios',
      'linux',
      'macos',
      'web',
      'windows',
    ]);
    for (final platform in platforms) {
      final entriesByName = <String, Object?>{
        for (final item in existingPlugins[platform] ?? const <Object?>[])
          if (item is Map<String, Object?> && item['name'] is String)
            item['name']! as String: item,
      };
      for (final package in packageDetails.values) {
        final configuration = package.platforms[platform];
        if (configuration == null ||
            configuration['default_package'] is String) {
          continue;
        }
        entriesByName.putIfAbsent(
          package.name,
          () => <String, Object?>{
            'name': package.name,
            'path': '${package.root.absolute.path}${p.separator}',
            'native_build':
                configuration['pluginClass'] is String ||
                configuration['ffiPlugin'] == true ||
                configuration['native_build'] == true,
            'dependencies': <String>[
              ...package.dependencyNames.where(pluginNames.contains),
            ]..sort(),
            'dev_dependency': false,
          },
        );
      }
      existingPlugins[platform] = entriesByName.values.toList()
        ..sort((left, right) {
          final leftName = (left as Map<String, Object?>)['name']! as String;
          final rightName = (right as Map<String, Object?>)['name']! as String;
          return leftName.compareTo(rightName);
        });
    }

    final dependencyGraphByName = <String, Object?>{
      for (final item
          in (existing['dependencyGraph'] is List<Object?>
              ? existing['dependencyGraph']! as List<Object?>
              : const <Object?>[]))
        if (item is Map<String, Object?> && item['name'] is String)
          item['name']! as String: item,
    };
    for (final package in packageDetails.values) {
      dependencyGraphByName[package.name] = <String, Object?>{
        'name': package.name,
        'dependencies': <String>[
          ...package.dependencyNames.where(pluginNames.contains),
        ]..sort(),
      };
    }

    final output = <String, Object?>{
      'info': existing['info'] ?? 'This is a generated file; do not edit or check into version control.',
      'plugins': <String, Object?>{
        for (final platform in platforms)
          platform: existingPlugins[platform] ?? const <Object?>[],
      },
      'dependencyGraph': dependencyGraphByName.values.toList()
        ..sort((left, right) {
          final leftName = (left as Map<String, Object?>)['name']! as String;
          final rightName = (right as Map<String, Object?>)['name']! as String;
          return leftName.compareTo(rightName);
        }),
      'date_created': existing['date_created'] ?? '1970-01-01 00:00:00.000Z',
      'version': existing['version'] ?? flutterVersion,
      'swift_package_manager_enabled':
          existing['swift_package_manager_enabled'] ??
          <String, bool>{'ios': true, 'macos': false},
    };
    final hasPlugin = (output['plugins']! as Map<String, Object?>).values.any(
      (value) => value is List<Object?> && value.isNotEmpty,
    );
    if (!hasPlugin && !existingFile.existsSync()) return;
    await writeAtomicText(existingFile, canonicalJson(output));
  }

  /// Recreates Flutter's Android registrant inside the temporary overlay.
  ///
  /// A `--no-pub` build does not refresh the generated registrant in the
  /// checkout. The copied project can therefore contain an empty or stale
  /// registrant even though the overlay package graph contains native
  /// plugins. Generate the same narrow new-embedding shape Flutter uses from
  /// the resolved plugin manifests, excluding plugins marked as dev-only in
  /// Flutter's generated metadata; the source tree remains untouched.
  Future<void> _writeOverlayAndroidPluginRegistrant(Directory workspace) async {
    final packageConfigFile = File(
      p.join(workspace.path, '.dart_tool', 'package_config.json'),
    );
    final packageConfig = decodeJsonObject(packageConfigFile);
    final rawPackages = packageConfig['packages'];
    if (rawPackages is! List<Object?>) {
      throw const FormatException(
        'overlay package_config.json packages must be a list',
      );
    }

    final devDependencyPlugins = _overlayDevDependencyPluginNames(workspace);
    final plugins = <_OverlayAndroidPlugin>[];
    for (final raw in rawPackages) {
      if (raw is! Map<String, Object?> ||
          raw['name'] is! String ||
          raw['rootUri'] is! String) {
        throw const FormatException('Invalid overlay package_config entry');
      }
      final packageName = raw['name']! as String;
      if (devDependencyPlugins.contains(packageName)) continue;
      final rootUri = Uri.parse(raw['rootUri']! as String);
      if (rootUri.scheme != 'file') continue;
      final root = Directory.fromUri(rootUri);
      final pubspec = File(p.join(root.path, 'pubspec.yaml'));
      if (!pubspec.existsSync()) continue;
      final decoded = loadYaml(pubspec.readAsStringSync());
      if (decoded is! YamlMap) continue;
      final flutter = decoded['flutter'];
      final plugin = flutter is YamlMap ? flutter['plugin'] : null;
      if (plugin is! YamlMap || plugin['platforms'] is! YamlMap) continue;
      final platforms = plugin['platforms']! as YamlMap;
      final android = platforms['android'];
      if (android is! YamlMap) continue;
      final javaPackage = android['package'];
      final pluginClass = android['pluginClass'];
      if (javaPackage is! String || pluginClass is! String) continue;
      if (!_isJavaQualifiedIdentifier(javaPackage) ||
          !_isJavaIdentifier(pluginClass)) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.environment,
          code: 'T1608',
          summary:
              'Android plugin manifest contains an invalid registrant name',
          detail: '${raw['name']}: $javaPackage.$pluginClass',
          action:
              'Correct the plugin manifest or create a normal store release.',
        );
      }
      plugins.add(
        _OverlayAndroidPlugin(
          name: packageName,
          javaPackage: javaPackage,
          pluginClass: pluginClass,
        ),
      );
    }
    plugins.sort((left, right) {
      final byPackage = left.javaPackage.compareTo(right.javaPackage);
      if (byPackage != 0) return byPackage;
      return left.pluginClass.compareTo(right.pluginClass);
    });

    final androidRoot = Directory(p.join(workspace.path, 'android'));
    final candidates = androidRoot.existsSync()
        ? androidRoot
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .where(
                (file) =>
                    p.basename(file.path) == 'GeneratedPluginRegistrant.java',
              )
              .toList()
        : <File>[];
    candidates.sort((left, right) => left.path.compareTo(right.path));
    final registry = candidates.isNotEmpty
        ? candidates.first
        : File(
            p.join(
              workspace.path,
              'android',
              'app',
              'src',
              'main',
              'java',
              'io',
              'flutter',
              'plugins',
              'GeneratedPluginRegistrant.java',
            ),
          );

    final output = StringBuffer('''package io.flutter.plugins;

import androidx.annotation.Keep;
import androidx.annotation.NonNull;
import io.flutter.Log;
import io.flutter.embedding.engine.FlutterEngine;

/**
 * Generated inside the Hyfens release overlay; the checkout is unchanged.
 */
@Keep
public final class GeneratedPluginRegistrant {
  private static final String TAG = "GeneratedPluginRegistrant";

  public static void registerWith(@NonNull FlutterEngine flutterEngine) {
''');
    for (final plugin in plugins) {
      final qualified = '${plugin.javaPackage}.${plugin.pluginClass}';
      output
        ..writeln('    try {')
        ..writeln('      flutterEngine.getPlugins().add(new $qualified());')
        ..writeln('    } catch (Exception e) {')
        ..writeln(
          '      Log.e(TAG, "Error registering plugin ${plugin.name}", e);',
        )
        ..writeln('    }');
    }
    output.writeln('  }');
    output.writeln('}');
    await writeAtomicText(registry, output.toString());
  }

  /// Returns plugin names that Flutter classifies as development-only.
  ///
  /// Keep those entries in `.flutter-plugins-dependencies` so Flutter's normal
  /// test tooling can still discover them. They must be absent only from the
  /// production Android registrant generated for this release overlay.
  Set<String> _overlayDevDependencyPluginNames(Directory workspace) {
    final metadata = File(
      p.join(workspace.path, '.flutter-plugins-dependencies'),
    );
    if (!metadata.existsSync()) return const <String>{};
    final decoded = decodeJsonObject(metadata);
    final rawPlugins = decoded['plugins'];
    if (rawPlugins is! Map<String, Object?>) return const <String>{};
    final names = <String>{};
    for (final platformPlugins in rawPlugins.values) {
      if (platformPlugins is! List<Object?>) continue;
      for (final rawPlugin in platformPlugins) {
        if (rawPlugin is Map<String, Object?> &&
            rawPlugin['name'] is String &&
            rawPlugin['dev_dependency'] == true) {
          names.add(rawPlugin['name']! as String);
        }
      }
    }
    return names;
  }

  /// Makes the generated runtime package a dependency of the temporary
  /// application manifest. Flutter's Dart plugin registrant is resolved from
  /// the application's transitive pubspec graph, not from package_config.json
  /// alone. This overlay-only declaration lets Flutter discover the runtime's
  /// path_provider implementation without editing the checkout or lockfile.
  Future<void> _writeOverlayRuntimeDependencies(Directory workspace) async {
    final pubspec = File(p.join(workspace.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return;
    final source = pubspec.readAsStringSync();
    if (RegExp(
      r'^\s+hyfens_flutter_integration\s*:',
      multiLine: true,
    ).hasMatch(source)) {
      return;
    }
    final dependencies = RegExp(
      r'^dependencies:\s*$',
      multiLine: true,
    ).firstMatch(source);
    final updated = dependencies == null
        ? '$source\ndependencies:\n  hyfens_flutter_integration: any\n'
        : source.replaceRange(
            dependencies.end,
            dependencies.end,
            '\n  hyfens_flutter_integration: any',
          );
    await writeAtomicText(pubspec, updated);
  }

  void _appendToolRuntimePackages(List<Object?> rewritten) {
    final existing = <String>{
      for (final item in rewritten)
        if (item is Map<String, Object?> && item['name'] is String)
          item['name']! as String,
    };
    final toolPackageFile = _toolPackageConfigFile();
    if (toolPackageFile == null || !toolPackageFile.existsSync()) return;
    final raw = decodeJsonObject(toolPackageFile);
    final packages = raw['packages'];
    if (packages is! List<Object?>) return;
    // The generated bootstrap and E0 runtime are compiled from the tool's
    // checked-out package graph. Add only packages absent from the project;
    // an application's resolved version remains authoritative when present.
    // Unimported tool packages do not affect the application binary.
    for (final item in packages) {
      if (item is! Map<String, Object?> || item['name'] is! String) continue;
      final name = item['name']! as String;
      if (existing.add(name)) {
        final entry = <String, Object?>{...item};
        final declaredRoot = entry['rootUri'];
        if (declaredRoot is String) {
          final uri = Uri.parse(declaredRoot);
          final resolved = uri.isAbsolute
              ? uri
              : toolPackageFile.parent.uri.resolveUri(uri);
          entry['rootUri'] = resolved.toString();
        }
        rewritten.add(entry);
      }
    }
  }

  /// Rebuilds the temporary package graph after adding the runtime package.
  ///
  /// Flutter's plugin discovery follows `.dart_tool/package_graph.json`, not
  /// only `package_config.json`. Copying the project's graph would omit the
  /// overlay runtime and make Flutter regenerate an empty native registrant.
  Future<void> _writeOverlayPackageGraph(Directory workspace) async {
    final packageConfigFile = File(
      p.join(workspace.path, '.dart_tool', 'package_config.json'),
    );
    final packageConfig = decodeJsonObject(packageConfigFile);
    final rawPackages = packageConfig['packages'];
    if (rawPackages is! List<Object?>) {
      throw const FormatException(
        'overlay package_config.json packages must be a list',
      );
    }

    final packageNames = <String>{};
    final packageRoots = <String, Directory>{};
    for (final raw in rawPackages) {
      if (raw is! Map<String, Object?> ||
          raw['name'] is! String ||
          raw['rootUri'] is! String) {
        throw const FormatException('Invalid overlay package_config entry');
      }
      final name = raw['name']! as String;
      final rootUri = Uri.parse(raw['rootUri']! as String);
      if (rootUri.scheme != 'file') continue;
      packageNames.add(name);
      packageRoots[name] = Directory.fromUri(rootUri);
    }

    final graphFile = File(
      p.join(workspace.path, '.dart_tool', 'package_graph.json'),
    );
    final existing = graphFile.existsSync()
        ? decodeJsonObject(graphFile)
        : <String, Object?>{};
    final roots = existing['roots'] is List<Object?>
        ? List<Object?>.from(existing['roots']! as List<Object?>)
        : <Object?>[];

    final graphPackages = <Object?>[];
    for (final name in packageNames.toList()..sort()) {
      final root = packageRoots[name];
      final pubspec = root == null
          ? null
          : File(p.join(root.path, 'pubspec.yaml'));
      final decoded = pubspec != null && pubspec.existsSync()
          ? loadYaml(pubspec.readAsStringSync())
          : null;
      final dependencies = <String>[];
      final devDependencies = <String>[];
      if (decoded is YamlMap) {
        final rawDependencies = decoded['dependencies'];
        if (rawDependencies is YamlMap) {
          dependencies.addAll(
            rawDependencies.keys.whereType<String>().where(
              packageNames.contains,
            ),
          );
        }
        final rawDevDependencies = decoded['dev_dependencies'];
        if (rawDevDependencies is YamlMap) {
          devDependencies.addAll(
            rawDevDependencies.keys.whereType<String>().where(
              packageNames.contains,
            ),
          );
        }
      }
      dependencies.sort();
      devDependencies.sort();
      graphPackages.add(<String, Object?>{
        'name': name,
        'dependencies': dependencies,
        'devDependencies': devDependencies,
      });
    }

    final output = <String, Object?>{
      'configVersion': 1,
      'roots': roots,
      'packages': graphPackages,
    };
    await writeAtomicText(graphFile, canonicalJson(output));
  }

  File? _toolPackageConfigFile() {
    final resolved = Isolate.resolvePackageUriSync(
      Uri.parse('package:hyfens_tool/tool.dart'),
    );
    if (resolved == null || resolved.scheme != 'file') return null;
    final libFile = File.fromUri(resolved);
    final packageRoot = libFile.parent.parent;
    return File(p.join(packageRoot.path, '.dart_tool', 'package_config.json'));
  }

  void _verifyAgainstRelease(PatchArtifact artifact, ReleaseRecord release) {
    if (artifact.applicationId != release.applicationId ||
        artifact.releaseId != release.releaseId ||
        artifact.runtimeCompatibilityVersion !=
            release.manifest.runtimeCompatibilityVersion) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'R5002',
        summary: 'Patch does not target the selected release',
        detail: '${artifact.releaseId} / ${artifact.applicationId}',
      );
    }
    final expected = <String, PatchFunctionEntry>{
      for (final function in release.manifest.functions) function.id: function,
    };
    for (final function in artifact.functions) {
      final baseline = expected[function.id];
      if (baseline == null ||
          baseline.slot != function.slot ||
          baseline.signatureDigest != function.signatureDigest) {
        throw ToolFailure.single(
          exitCode: ToolExitCode.compatibility,
          code: 'R5005',
          summary: 'Patch function table is incompatible with the release',
          detail: function.id,
        );
      }
    }
  }
}

String _boundedStatusText(String value) {
  const limit = 128;
  final sanitized = value.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '?');
  if (sanitized.length <= limit) return sanitized;
  return '${sanitized.substring(0, limit)}...';
}

String _safeDiagnosticCode(String value) =>
    RegExp(r'^[A-Z]\d{4}$').hasMatch(value) ? value : 'T9999';

ToolDiagnostic _statusDiagnostic({
  required String code,
  required DiagnosticSeverity severity,
  required String summary,
  required String detail,
  String? action,
}) => ToolDiagnostic(
  code: _safeDiagnosticCode(code),
  severity: severity,
  summary: summary,
  detail: detail,
  action: action,
);

ToolFailure _redactedStatusFailure(ToolFailure failure) {
  final diagnostic = failure.diagnostics.first;
  return ToolFailure.single(
    exitCode: failure.exitCode,
    code: _safeDiagnosticCode(diagnostic.code),
    summary: 'Unable to discover a Flutter project for local status',
    detail: 'Status requires a discoverable Flutter project; no filesystem path was included.',
    action: 'Run hyfens doctor for the project diagnostic.',
  );
}

final class RollbackResult {
  const RollbackResult({
    required this.project,
    required this.release,
    required this.baseArtifact,
    required this.state,
    required this.commandFile,
    required this.keyId,
  });

  final FlutterProject project;
  final ReleaseRecord release;
  final File baseArtifact;
  final RollbackState state;
  final File commandFile;
  final String keyId;

  Map<String, Object?> toJson() => <String, Object?>{
    'result': 'ROLLED_BACK',
    'target': state.target,
    'releaseId': release.releaseId,
    'baseArtifact': relativePath(project.root, baseArtifact),
    'highWaterSequence': state.highWaterSequence,
    'highWaterDigest': state.highWaterDigest,
    'state': relativePath(
      project.root,
      ToolStore(project).rollbackStatePrimary(release.releaseId),
    ),
    'control': relativePath(project.root, commandFile),
    'keyId': keyId,
  };
}

final class _OverlayPluginPackage {
  const _OverlayPluginPackage({
    required this.name,
    required this.root,
    required this.platforms,
    required this.dependencyNames,
  });

  final String name;
  final Directory root;
  final Map<String, Map<String, Object?>> platforms;
  final Set<String> dependencyNames;
}

final class _OverlayAndroidPlugin {
  const _OverlayAndroidPlugin({
    required this.name,
    required this.javaPackage,
    required this.pluginClass,
  });

  final String name;
  final String javaPackage;
  final String pluginClass;
}

bool _isJavaIdentifier(String value) =>
    RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(value);

bool _isJavaQualifiedIdentifier(String value) =>
    value.split('.').every(_isJavaIdentifier);

Map<String, Object?> _yamlMapToObject(YamlMap value) => <String, Object?>{
  for (final entry in value.entries)
    if (entry.key is String)
      entry.key! as String: _yamlValueToObject(entry.value),
};

Object? _yamlValueToObject(Object? value) {
  if (value is YamlMap) return _yamlMapToObject(value);
  if (value is YamlList) return value.map(_yamlValueToObject).toList();
  return value;
}

final class CleanupResult {
  CleanupResult({
    required this.scope,
    required this.release,
    required List<String> removedPaths,
    required List<String> retainedPaths,
  }) : removedPaths = List.unmodifiable(removedPaths),
       retainedPaths = List.unmodifiable(retainedPaths);

  final String scope;
  final ReleaseRecord release;
  final List<String> removedPaths;
  final List<String> retainedPaths;

  Map<String, Object?> toJson() => <String, Object?>{
    'result': 'CLEANED',
    'scope': scope,
    'releaseId': release.releaseId,
    'removed': removedPaths,
    'retained': retainedPaths,
  };
}

final class InitResult {
  const InitResult({
    required this.project,
    required this.dryRun,
    required this.actions,
    required this.environment,
  });

  final FlutterProject project;
  final bool dryRun;
  final List<String> actions;
  final ToolEnvironmentSnapshot environment;
}

final class PatchBuildResult {
  const PatchBuildResult({
    required this.artifact,
    required this.output,
    required this.size,
  });

  final PatchArtifact artifact;
  final File output;
  final int size;
}

final class PatchInspection {
  const PatchInspection({required this.artifact, required this.path});

  final PatchArtifact artifact;
  final String path;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'formatVersion': patchFormatV1,
    'runtimeCompatibilityVersion': artifact.runtimeCompatibilityVersion,
    'applicationId': artifact.applicationId,
    'releaseId': artifact.releaseId,
    'patchId': artifact.patchId,
    'sequence': artifact.sequence,
    'functionCount': artifact.functions.length,
    'functions': artifact.functions.map((item) => item.toJson()).toList(),
    'capabilities': artifact.capabilities.map((item) => item.toJson()).toList(),
    'artifactBytes': PatchFormatV1.encode(artifact).length,
    'payloadDigest': base64.encode(artifact.payloadDigest),
    'signatureAlgorithm': artifact.signatureMetadata.algorithm,
    'keyId': artifact.signatureMetadata.keyId,
    'extensionTypes': artifact.extensions.map((item) => item.type).toList(),
  };
}

bool _nativeInput(String relative) {
  final lower = relative.toLowerCase();
  final basename = p.basename(lower);
  return lower.endsWith('androidmanifest.xml') ||
      lower.endsWith('podfile.lock') ||
      basename == 'podfile' ||
      lower.endsWith('.plist') ||
      lower.endsWith('.pbxproj') ||
      lower.endsWith('.entitlements') ||
      lower.endsWith('.xcconfig') ||
      lower.endsWith('.gradle') ||
      lower.endsWith('.gradle.kts') ||
      lower.endsWith('gradle.properties') ||
      lower.endsWith('settings.gradle') ||
      lower.endsWith('settings.gradle.kts') ||
      lower.endsWith('.podfile') ||
      lower.endsWith('.podspec') ||
      lower.endsWith('.kt') ||
      lower.endsWith('.swift') ||
      lower.endsWith('.java') ||
      lower.endsWith('.mm') ||
      lower.endsWith('.m') ||
      lower.endsWith('.h') ||
      lower.endsWith('.cpp') ||
      lower.endsWith('.c');
}

bool _volatileNativePath(String relative) {
  final segments = relative
      .replaceAll(r'\', '/')
      .split('/')
      .map((segment) => segment.toLowerCase())
      .toList(growable: false);
  const volatileDirectories = <String>{
    '.cxx',
    '.dart_tool',
    '.gradle',
    '.symlinks',
    'build',
    'deriveddata',
    'ephemeral',
    'pods',
    'xcuserdata',
  };
  if (segments.any(volatileDirectories.contains)) return true;
  final file = segments.last;
  return file == '.ds_store' ||
      file == 'local.properties' ||
      file == 'generated.xcconfig' ||
      file == 'flutter_export_environment.sh' ||
      file.contains('generatedpluginregistrant');
}

String _wireSignatureDigest(String value) =>
    value.startsWith('sha256:') ? value : 'sha256:$value';

Set<String> _changedDeclarationKeys(
  Map<String, String> before,
  Map<String, String> after,
) {
  final keys = <String>{...before.keys, ...after.keys};
  return <String>{
    for (final key in keys)
      if (before[key] != after[key]) key,
  };
}

Future<void> _copyTree(
  Directory source,
  Directory destination, {
  required Set<String> skip,
}) async {
  await destination.create(recursive: true);
  final entries = source.listSync(followLinks: false)
    ..sort((left, right) => left.path.compareTo(right.path));
  for (final entry in entries) {
    final name = p.basename(entry.path);
    if (skip.contains(name)) continue;
    final target = p.join(destination.path, name);
    switch (FileSystemEntity.typeSync(entry.path, followLinks: false)) {
      case FileSystemEntityType.directory:
        await _copyTree(Directory(entry.path), Directory(target), skip: skip);
      case FileSystemEntityType.file:
        await File(entry.path).copy(target);
      case FileSystemEntityType.link:
      case FileSystemEntityType.notFound:
        break;
    }
  }
}

final class _RuntimeBuildDefines {
  const _RuntimeBuildDefines({
    required this.arguments,
    required this.recordedArguments,
  });

  final List<String> arguments;
  final List<String> recordedArguments;
}

File? _firstFile(Directory directory, String suffix) {
  if (!directory.existsSync()) return null;
  final files =
      directory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith(suffix))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  return files.firstOrNull;
}

String _boundedDiagnosticText(String value) {
  const limit = 8192;
  if (value.length <= limit) return value;
  return '...${value.substring(value.length - limit)}';
}

bool _containsSymlink(Directory root) {
  final pending = <Directory>[root];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    for (final entry in directory.listSync(followLinks: false)) {
      final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
      if (type == FileSystemEntityType.link) return true;
      if (type == FileSystemEntityType.directory) {
        pending.add(Directory(entry.path));
      }
    }
  }
  return false;
}

ToolDiagnostic _diagnosticFromJson(Object? value) {
  if (value is! Map<String, Object?> ||
      value['code'] is! String ||
      value['severity'] is! String ||
      value['summary'] is! String ||
      value['detail'] is! String) {
    throw const FormatException('Invalid diagnostic metadata');
  }
  return ToolDiagnostic(
    code: value['code']! as String,
    severity: DiagnosticSeverity.values.firstWhere(
      (item) => item.name == value['severity'],
      orElse: () => DiagnosticSeverity.error,
    ),
    summary: value['summary']! as String,
    detail: value['detail']! as String,
    path: value['path'] as String?,
    line: value['line'] as int?,
    column: value['column'] as int?,
    action: value['action'] as String?,
    storeReleaseRequired: value['storeReleaseRequired'] as bool? ?? false,
  );
}

extension on PlannedFunction {
  E0ReleaseManifest sourceManifest(InstrumentationPlan plan) => plan.units
      .firstWhere((item) => item.source.libraryUri == source.libraryUri)
      .manifest!;
}

extension on Iterable<InstrumentedUnit> {
  InstrumentedUnit? get firstOrNull => isEmpty ? null : first;
}

extension on Iterable<File> {
  File? get firstOrNull => isEmpty ? null : first;
}
