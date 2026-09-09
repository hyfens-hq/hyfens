import 'dart:async';
import 'dart:convert';

import 'artifact_retention.dart';
import 'cloud_plans.dart';
import 'domain.dart';
import 'encoding.dart';
import 'errors.dart';
import 'persistence.dart';

const String cloudUsageEventsCollection = 'cloud_usage_events';

/// Stable identifiers for the first two Cloud infrastructure meters.
const String artifactStorageMeter = 'artifact_storage';
const String artifactDeliveryMeter = 'artifact_delivery';
const String cloudUsageBytesUnit = 'bytes';

const String artifactStorageAddedOperation = 'add';
const String artifactStorageRemovedOperation = 'remove';
const String artifactDeliveryOperation = 'deliver';

const String artifactStorageSource = 'artifact_state';
const String artifactDeliveryOriginSource = 'control_plane_origin';
const String artifactDeliveryCdnSource = 'cdn';
const String artifactDeliveryObjectStoreSource = 'object_store';
const String artifactDeliveryEdgeSource = 'edge';

const Set<String> trustedArtifactDeliverySources = <String>{
  artifactDeliveryOriginSource,
  artifactDeliveryCdnSource,
  artifactDeliveryObjectStoreSource,
  artifactDeliveryEdgeSource,
};

/// Completeness of trusted delivery-byte evidence for the configured customer
/// delivery surface. This is measurement authority, not a pricing decision.
enum CloudDeliveryMeterAuthority { authoritative, partial, unavailable }

/// The current delivery coverage declaration. The repository has one
/// customer-facing origin path, but it does not yet have trusted evidence for
/// edge/client egress or direct object-store delivery. Keeping this explicit
/// prevents the origin counter from being mistaken for a complete commercial
/// bandwidth total.
const CloudDeliveryMeterCoverage currentCloudDeliveryMeterCoverage =
    CloudDeliveryMeterCoverage(
      authority: CloudDeliveryMeterAuthority.partial,
      coveredSources: <String>{artifactDeliveryOriginSource},
      uncoveredSources: <String>{
        artifactDeliveryCdnSource,
        artifactDeliveryObjectStoreSource,
        artifactDeliveryEdgeSource,
      },
      quotaEligible: false,
    );

final class CloudDeliveryMeterCoverage {
  const CloudDeliveryMeterCoverage({
    required this.authority,
    required this.coveredSources,
    required this.uncoveredSources,
    required this.quotaEligible,
  });

  final CloudDeliveryMeterAuthority authority;
  final Set<String> coveredSources;
  final Set<String> uncoveredSources;
  final bool quotaEligible;

  bool get authoritative =>
      authority == CloudDeliveryMeterAuthority.authoritative;

  Map<String, Object?> toJson() => <String, Object?>{
    'authority': authority.name,
    'quota_eligible': quotaEligible,
    'covered_sources': coveredSources.toList()..sort(),
    'uncovered_sources': uncoveredSources.toList()..sort(),
  };
}

/// Evidence accepted from a trusted delivery adapter. The artifact ID is
/// resolved back to its server-owned record before the organization is chosen;
/// callers cannot self-report an organization or tenant assignment.
final class TrustedArtifactDeliveryObservation {
  TrustedArtifactDeliveryObservation({
    required String artifactId,
    required String source,
    required String sourceId,
    required this.bytes,
    required DateTime occurredAt,
    String? artifactDigest,
  }) : artifactId = requireOpaqueId(artifactId, 'artifact ID'),
       source = requireNonEmpty(source, 'delivery source', maxLength: 128),
       sourceId = requireNonEmpty(
         sourceId,
         'delivery source ID',
         maxLength: 256,
       ),
       artifactDigest = artifactDigest?.isEmpty == true ? null : artifactDigest,
       occurredAt = occurredAt.toUtc() {
    if (!trustedArtifactDeliverySources.contains(source)) {
      throw const FormatException('Delivery source is not trusted');
    }
    if (bytes < 0) {
      throw const FormatException('Delivered bytes must not be negative');
    }
    if (this.artifactDigest != null) {
      requireSha256Digest(this.artifactDigest!);
    }
  }

  final String artifactId;
  final String source;
  final String sourceId;
  final int bytes;
  final DateTime occurredAt;
  final String? artifactDigest;
}

/// An immutable fact about Cloud infrastructure consumption.
///
/// The event is deliberately independent of a plan, quota, billing provider,
/// or payment period. Those concerns may interpret the same evidence later.
final class CloudUsageEvent {
  CloudUsageEvent({
    required String id,
    required String organizationId,
    required String meter,
    required String operation,
    required this.quantityBytes,
    required this.occurredAt,
    required this.recordedAt,
    required String source,
    required String sourceId,
    this.metadata = const <String, Object?>{},
  }) : id = requireOpaqueId(id, 'usage event ID'),
       organizationId = requireOpaqueId(organizationId, 'organization ID'),
       meter = requireNonEmpty(meter, 'usage meter', maxLength: 64),
       operation = requireNonEmpty(operation, 'usage operation', maxLength: 64),
       source = requireNonEmpty(source, 'usage source', maxLength: 128),
       sourceId = requireNonEmpty(sourceId, 'usage source ID', maxLength: 256) {
    if (quantityBytes < 0) {
      throw const FormatException('Usage quantity must not be negative');
    }
    if (metadata.keys.any((key) => key.isEmpty || key.length > 128)) {
      throw const FormatException('Usage metadata keys are invalid');
    }
  }

  final String id;
  final String organizationId;
  final String meter;
  final String operation;
  final int quantityBytes;
  final DateTime occurredAt;
  final DateTime recordedAt;
  final String source;
  final String sourceId;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'organizationId': organizationId,
    'meter': meter,
    'operation': operation,
    'quantityBytes': quantityBytes,
    'unit': cloudUsageBytesUnit,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'source': source,
    'sourceId': sourceId,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  /// Fields that identify the fact for durable idempotency comparison.
  /// Recording time is intentionally excluded because a retry may be observed
  /// by the process at a different instant.
  Map<String, Object?> identityJson() => <String, Object?>{
    'organizationId': organizationId,
    'meter': meter,
    'operation': operation,
    'quantityBytes': quantityBytes,
    'unit': cloudUsageBytesUnit,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'source': source,
    'sourceId': sourceId,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  static CloudUsageEvent fromJson(Map<String, Object?> value) {
    final unit = value['unit'];
    if (unit != null && unit != cloudUsageBytesUnit) {
      throw const FormatException('Unsupported Cloud usage unit');
    }
    final quantity = value['quantityBytes'];
    final occurredAt = value['occurredAt'];
    final recordedAt = value['recordedAt'];
    final rawMetadata = value['metadata'];
    if (quantity is! int || occurredAt is! String || recordedAt is! String) {
      throw const FormatException('Malformed Cloud usage event');
    }
    final metadata = <String, Object?>{};
    if (rawMetadata != null) {
      if (rawMetadata is! Map) {
        throw const FormatException('Malformed Cloud usage metadata');
      }
      for (final entry in rawMetadata.entries) {
        if (entry.key is! String) {
          throw const FormatException('Malformed Cloud usage metadata key');
        }
        metadata[entry.key as String] = entry.value;
      }
    }
    return CloudUsageEvent(
      id: value['id']! as String,
      organizationId: value['organizationId']! as String,
      meter: value['meter']! as String,
      operation: value['operation']! as String,
      quantityBytes: quantity,
      occurredAt: DateTime.parse(occurredAt).toUtc(),
      recordedAt: DateTime.parse(recordedAt).toUtc(),
      source: value['source']! as String,
      sourceId: value['sourceId']! as String,
      metadata: metadata,
    );
  }
}

final class CloudUsagePeriod {
  CloudUsagePeriod({required this.start, required this.end}) {
    if (!end.isAfter(start)) {
      throw ArgumentError.value(end, 'end', 'must be after start');
    }
  }

  final DateTime start;
  final DateTime end;

  String get type => 'utc_calendar_month';

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
  };
}

CloudUsagePeriod currentUtcCalendarMonth(DateTime now) {
  final normalized = now.toUtc();
  final start = DateTime.utc(normalized.year, normalized.month);
  final end = normalized.month == 12
      ? DateTime.utc(normalized.year + 1)
      : DateTime.utc(normalized.year, normalized.month + 1);
  return CloudUsagePeriod(start: start, end: end);
}

/// A projection of measured usage. Storage is an instantaneous logical gauge;
/// delivery is a counter for the explicit operational period.
final class CloudMeteredUsage {
  const CloudMeteredUsage({
    required this.artifactStorageBytesCurrent,
    required this.artifactDeliveryBytesPeriod,
    required this.period,
    required this.deliveryCoverage,
  });

  final int artifactStorageBytesCurrent;
  final int artifactDeliveryBytesPeriod;
  final CloudUsagePeriod period;
  final CloudDeliveryMeterCoverage deliveryCoverage;

  /// Compatibility projection retained for existing billing consumers.
  bool get artifactDeliveryAuthoritative => deliveryCoverage.authoritative;

  String get artifactDeliveryAuthority => deliveryCoverage.authority.name;

  bool get artifactDeliveryQuotaEligible => deliveryCoverage.quotaEligible;

  Map<String, Object?> toJson() => <String, Object?>{
    'artifact_storage_bytes_current': artifactStorageBytesCurrent,
    'artifact_delivery_bytes_period': artifactDeliveryBytesPeriod,
    'artifact_delivery_period': period.toJson(),
    'artifact_delivery_authoritative': artifactDeliveryAuthoritative,
    'artifact_delivery_authority': artifactDeliveryAuthority,
    'artifact_delivery_quota_eligible': artifactDeliveryQuotaEligible,
    'artifact_delivery_source': artifactDeliveryOriginSource,
    'artifact_delivery_covered_sources':
        deliveryCoverage.coveredSources.toList()..sort(),
    'artifact_delivery_uncovered_sources':
        deliveryCoverage.uncoveredSources.toList()..sort(),
  };
}

/// A read-only comparison between authoritative artifact state and the
/// append-only storage transition facts. No automatic repair is performed.
final class CloudStorageUsageReconciliation {
  const CloudStorageUsageReconciliation({
    required this.organizationId,
    required this.expectedStorageBytes,
    required this.accountedStorageBytes,
    required this.eventCount,
    required this.findings,
  });

  final String organizationId;
  final int expectedStorageBytes;
  final int accountedStorageBytes;
  final int eventCount;
  final List<String> findings;

  bool get balanced =>
      findings.isEmpty && expectedStorageBytes == accountedStorageBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'organization_id': organizationId,
    'expected_storage_bytes': expectedStorageBytes,
    'accounted_storage_bytes': accountedStorageBytes,
    'event_count': eventCount,
    'balanced': balanced,
    'findings': findings,
  };
}

/// Deep usage accounting behind a small interface.
///
/// This module intentionally owns evidence, not commercial policy. It has no
/// knowledge of plan limits, prices, overages, or payment providers.
final class CloudUsageMeteringService {
  CloudUsageMeteringService(
    this.store, {
    this.deploymentModel = DeploymentModel.selfHosted,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final ControlPlaneStore store;
  final DeploymentModel deploymentModel;
  final DateTime Function() _clock;
  Future<void> _writeTail = Future<void>.value();

  bool get isCloud => deploymentModel == DeploymentModel.cloud;

  Future<bool> recordArtifactStorageAdded({
    required ArtifactRecord artifact,
    required String sourceId,
    DateTime? occurredAt,
  }) => _recordArtifactStorageTransition(
    artifact: artifact,
    operation: artifactStorageAddedOperation,
    sourceId: sourceId,
    occurredAt: occurredAt,
  );

  /// Ensures that the current logical READY state has one net storage fact.
  ///
  /// The check makes a retried upload safe even if the artifact state write
  /// succeeded immediately before an accounting write was interrupted. It
  /// also avoids double-counting a later retry of an already-ready artifact.
  Future<bool> ensureArtifactStorageAdded({
    required ArtifactRecord artifact,
    required String sourceId,
    DateTime? occurredAt,
  }) async {
    if (!isCloud) return false;
    return _serializedWrite(() async {
      if (artifact.state != 'READY') {
        throw const FormatException(
          'Only a READY artifact can create a storage addition fact',
        );
      }
      var accounted = 0;
      for (final event in await _events(artifact.organizationId)) {
        if (event.meter != artifactStorageMeter ||
            event.metadata['artifact_id'] != artifact.id) {
          continue;
        }
        accounted += event.operation == artifactStorageAddedOperation
            ? event.quantityBytes
            : event.operation == artifactStorageRemovedOperation
            ? -event.quantityBytes
            : 0;
      }
      if (accounted == artifact.sizeBytes) return false;
      if (accounted != 0) {
        throw const ControlPlaneException(
          'USAGE_EVENT_CONFLICT',
          'Artifact storage facts do not describe one current logical state',
          statusCode: 409,
        );
      }
      return _recordUnlocked(
        meter: artifactStorageMeter,
        operation: artifactStorageAddedOperation,
        quantityBytes: artifact.sizeBytes,
        organizationId: artifact.organizationId,
        source: artifactStorageSource,
        sourceId: sourceId,
        occurredAt: (occurredAt ?? _clock()).toUtc(),
        metadata: <String, Object?>{
          'artifact_id': artifact.id,
          'artifact_digest': artifact.sha256,
        },
      );
    });
  }

  Future<bool> recordArtifactStorageRemoved({
    required ArtifactRecord artifact,
    required String sourceId,
    DateTime? occurredAt,
  }) => _recordArtifactStorageTransition(
    artifact: artifact,
    operation: artifactStorageRemovedOperation,
    sourceId: sourceId,
    occurredAt: occurredAt,
  );

  /// Ensures a non-ready artifact has a matching removal fact when an add was
  /// previously recorded. A never-ready artifact remains a no-op.
  Future<bool> ensureArtifactStorageRemoved({
    required ArtifactRecord artifact,
    required String sourceId,
    DateTime? occurredAt,
  }) async {
    if (!isCloud) return false;
    return _serializedWrite(() async {
      var accounted = 0;
      for (final event in await _events(artifact.organizationId)) {
        if (event.meter != artifactStorageMeter ||
            event.metadata['artifact_id'] != artifact.id) {
          continue;
        }
        accounted += event.operation == artifactStorageAddedOperation
            ? event.quantityBytes
            : event.operation == artifactStorageRemovedOperation
            ? -event.quantityBytes
            : 0;
      }
      if (accounted == 0) return false;
      if (accounted != artifact.sizeBytes) {
        throw const ControlPlaneException(
          'USAGE_EVENT_CONFLICT',
          'Artifact storage facts do not describe one removable logical state',
          statusCode: 409,
        );
      }
      return _recordUnlocked(
        meter: artifactStorageMeter,
        operation: artifactStorageRemovedOperation,
        quantityBytes: artifact.sizeBytes,
        organizationId: artifact.organizationId,
        source: artifactStorageSource,
        sourceId: sourceId,
        occurredAt: (occurredAt ?? _clock()).toUtc(),
        metadata: <String, Object?>{
          'artifact_id': artifact.id,
          'artifact_digest': artifact.sha256,
        },
      );
    });
  }

  /// Records bytes accepted by the current control-plane origin response.
  ///
  /// This does not claim to measure CDN, proxy, or direct object-store egress.
  /// A zero-byte response is not a delivery fact and is ignored.
  Future<bool> recordArtifactDelivery({
    required ArtifactRecord artifact,
    required int bytes,
    required String sourceId,
    DateTime? occurredAt,
  }) => recordTrustedArtifactDelivery(
    observation: TrustedArtifactDeliveryObservation(
      artifactId: artifact.id,
      artifactDigest: artifact.sha256,
      source: artifactDeliveryOriginSource,
      sourceId: sourceId,
      bytes: bytes,
      occurredAt: (occurredAt ?? _clock()).toUtc(),
    ),
  );

  /// Accepts one observation from a trusted delivery adapter and derives the
  /// organization from the authoritative artifact record. This is an internal
  /// integration seam, not a customer-facing usage-reporting endpoint.
  Future<bool> recordTrustedArtifactDelivery({
    required TrustedArtifactDeliveryObservation observation,
  }) async {
    if (!isCloud || observation.bytes == 0) return false;
    final raw = await store.readJson('artifacts', observation.artifactId);
    if (raw == null) {
      throw const ControlPlaneException(
        'DELIVERY_ARTIFACT_NOT_FOUND',
        'Delivery evidence references an unknown artifact',
        statusCode: 404,
      );
    }
    final artifact = ArtifactRecord.fromJson(raw);
    if (observation.artifactDigest != null &&
        observation.artifactDigest != artifact.sha256) {
      throw const ControlPlaneException(
        'DELIVERY_ARTIFACT_MISMATCH',
        'Delivery evidence does not match the server artifact identity',
        statusCode: 409,
      );
    }
    return _record(
      meter: artifactDeliveryMeter,
      operation: artifactDeliveryOperation,
      quantityBytes: observation.bytes,
      organizationId: artifact.organizationId,
      source: observation.source,
      sourceId: observation.sourceId,
      occurredAt: observation.occurredAt.toUtc(),
      metadata: <String, Object?>{
        'artifact_id': artifact.id,
        'artifact_digest': artifact.sha256,
      },
    );
  }

  Future<CloudMeteredUsage?> readUsage({
    required String organizationId,
    CloudUsagePeriod? period,
  }) async {
    if (!isCloud) return null;
    final selectedPeriod = period ?? currentUtcCalendarMonth(_clock());
    var storageBytes = 0;
    for (final raw in await store.listJson('artifacts')) {
      final artifact = ArtifactRecord.fromJson(raw);
      if (artifact.organizationId == organizationId &&
          artifact.state == artifactReadyState) {
        storageBytes += artifact.sizeBytes;
      }
    }

    var deliveryBytes = 0;
    for (final event in await _events(organizationId)) {
      if (event.meter != artifactDeliveryMeter ||
          event.operation != artifactDeliveryOperation ||
          !_inPeriod(event.occurredAt, selectedPeriod)) {
        continue;
      }
      deliveryBytes += event.quantityBytes;
    }
    return CloudMeteredUsage(
      artifactStorageBytesCurrent: storageBytes,
      artifactDeliveryBytesPeriod: deliveryBytes,
      period: selectedPeriod,
      deliveryCoverage: currentCloudDeliveryMeterCoverage,
    );
  }

  Future<CloudStorageUsageReconciliation> reconcileStorage({
    required String organizationId,
  }) async {
    if (!isCloud) {
      return CloudStorageUsageReconciliation(
        organizationId: organizationId,
        expectedStorageBytes: 0,
        accountedStorageBytes: 0,
        eventCount: 0,
        findings: const <String>['not_applicable_for_self_hosted'],
      );
    }
    final usage = await readUsage(organizationId: organizationId);
    final events = await _events(organizationId);
    var accounted = 0;
    for (final event in events) {
      if (event.meter != artifactStorageMeter) continue;
      accounted += event.operation == artifactStorageAddedOperation
          ? event.quantityBytes
          : event.operation == artifactStorageRemovedOperation
          ? -event.quantityBytes
          : 0;
    }
    final findings = <String>[];
    if (usage == null) {
      findings.add('usage_projection_unavailable');
    } else if (accounted != usage.artifactStorageBytesCurrent) {
      findings.add('storage_event_net_mismatch');
    }
    if (accounted < 0) findings.add('negative_storage_event_net');
    return CloudStorageUsageReconciliation(
      organizationId: organizationId,
      expectedStorageBytes: usage?.artifactStorageBytesCurrent ?? 0,
      accountedStorageBytes: accounted,
      eventCount: events
          .where((event) => event.meter == artifactStorageMeter)
          .length,
      findings: List.unmodifiable(findings),
    );
  }

  Future<bool> _recordArtifactStorageTransition({
    required ArtifactRecord artifact,
    required String operation,
    required String sourceId,
    DateTime? occurredAt,
  }) {
    if (!isCloud) return Future<bool>.value(false);
    if (artifact.state != 'READY' &&
        operation == artifactStorageAddedOperation) {
      throw const FormatException(
        'Only a READY artifact can create a storage addition fact',
      );
    }
    return _record(
      meter: artifactStorageMeter,
      operation: operation,
      quantityBytes: artifact.sizeBytes,
      organizationId: artifact.organizationId,
      source: artifactStorageSource,
      sourceId: sourceId,
      occurredAt: (occurredAt ?? _clock()).toUtc(),
      metadata: <String, Object?>{
        'artifact_id': artifact.id,
        'artifact_digest': artifact.sha256,
      },
    );
  }

  Future<bool> _record({
    required String organizationId,
    required String meter,
    required String operation,
    required int quantityBytes,
    required String source,
    required String sourceId,
    required DateTime occurredAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => _serializedWrite(
    () => _recordUnlocked(
      organizationId: organizationId,
      meter: meter,
      operation: operation,
      quantityBytes: quantityBytes,
      source: source,
      sourceId: sourceId,
      occurredAt: occurredAt,
      metadata: metadata,
    ),
  );

  Future<bool> _recordUnlocked({
    required String organizationId,
    required String meter,
    required String operation,
    required int quantityBytes,
    required String source,
    required String sourceId,
    required DateTime occurredAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final event = CloudUsageEvent(
      id: _eventId(
        organizationId: organizationId,
        meter: meter,
        operation: operation,
        source: source,
        sourceId: sourceId,
      ),
      organizationId: organizationId,
      meter: meter,
      operation: operation,
      quantityBytes: quantityBytes,
      occurredAt: occurredAt,
      recordedAt: _clock().toUtc(),
      source: source,
      sourceId: sourceId,
      metadata: metadata,
    );
    final existing = await store.readJson(cloudUsageEventsCollection, event.id);
    if (existing != null) return _sameFact(existing, event);
    try {
      await store.createJson(
        cloudUsageEventsCollection,
        event.id,
        event.toJson(),
      );
      return true;
    } on StorageConflict {
      final concurrent = await store.readJson(
        cloudUsageEventsCollection,
        event.id,
      );
      if (concurrent == null) rethrow;
      return _sameFact(concurrent, event);
    }
  }

  Future<List<CloudUsageEvent>> _events(String organizationId) async {
    final events = <CloudUsageEvent>[];
    for (final raw in await store.listJson(cloudUsageEventsCollection)) {
      final event = CloudUsageEvent.fromJson(raw);
      if (event.organizationId == organizationId) events.add(event);
    }
    return List.unmodifiable(events);
  }

  bool _sameFact(Map<String, Object?> raw, CloudUsageEvent expected) {
    final existing = CloudUsageEvent.fromJson(raw);
    if (canonicalJson(existing.identityJson()) ==
        canonicalJson(expected.identityJson())) {
      return false;
    }
    throw const ControlPlaneException(
      'USAGE_EVENT_CONFLICT',
      'A usage event id is already bound to different accounting facts',
      statusCode: 409,
    );
  }

  String _eventId({
    required String organizationId,
    required String meter,
    required String operation,
    required String source,
    required String sourceId,
  }) =>
      'cue_${sha256Hex(utf8.encode('$organizationId|$meter|$operation|$source|$sourceId')).substring(0, 32)}';

  bool _inPeriod(DateTime value, CloudUsagePeriod period) {
    final instant = value.toUtc();
    return !instant.isBefore(period.start) && instant.isBefore(period.end);
  }

  Future<T> _serializedWrite<T>(Future<T> Function() action) async {
    final previous = _writeTail;
    final gate = Completer<void>();
    _writeTail = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }
}
