import 'dart:convert';

import 'encoding.dart';

const String observationWriteScope = 'observation:write';
const String observationDeleteScope = 'observation:delete';
const int observationSchemaVersion = 1;

const int defaultObservationMaxEventBytes = 16 * 1024;
const int defaultObservationMaxMetadataKeys = 16;
const int defaultObservationMaxMetadataValueBytes = 256;
const int defaultObservationMaxMetadataBytes = 2048;
const int defaultObservationMaxEventsPerTokenWindow = 100;
const int defaultObservationMaxEventsPerInstallationWindow = 20;
const int defaultObservationMaxEventsPerTypeWindow = 50;
const Duration defaultObservationRateWindow = Duration(minutes: 1);
const Duration defaultObservationTokenLifetime = Duration(minutes: 10);
const Duration maxObservationTokenLifetime = Duration(minutes: 15);
const Duration defaultObservationFutureSkew = Duration(minutes: 5);
const Duration defaultObservationLateWindow = Duration(days: 7);
const Duration defaultObservationRetention = Duration(days: 30);

/// Versioned scalar keys only. Adding a key is a schema change; arbitrary
/// caller-controlled names are rejected to prevent an unbounded data channel.
const Set<String> observationSafeMetadataKeys = <String>{
  'attempt',
  'cache_hit',
  'duration_ms',
  'failure_class',
  'network_type',
  'reason',
  'retry_count',
  'source',
  'stage',
  'status',
};

enum ObservationEventType {
  lookup_attempt,
  candidate_offered,
  download_succeeded,
  download_failed,
  admission_verified,
  admission_rejected,
  activation_started,
  activation_succeeded,
  activation_failed,
  healthy_confirmed,
  runtime_fault,
  rollback,
  fallback_to_aot,
  restart_survived,
  store_release_required,
}

extension ObservationEventTypeWire on ObservationEventType {
  String get wireName => name;
}

ObservationEventType parseObservationEventType(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid observation event type');
  }
  for (final candidate in ObservationEventType.values) {
    if (candidate.name == value) return candidate;
  }
  throw const FormatException('Unsupported observation event type');
}

enum ObservationDisposition { accepted, late, quarantined }

extension ObservationDispositionWire on ObservationDisposition {
  String get wireName => name.toUpperCase();
}

ObservationDisposition parseObservationDisposition(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid observation disposition');
  }
  for (final candidate in ObservationDisposition.values) {
    if (candidate.name == value || candidate.wireName == value)
      return candidate;
  }
  throw const FormatException('Unsupported observation disposition');
}

final class ObservationPolicy {
  const ObservationPolicy({
    this.maxEventBytes = defaultObservationMaxEventBytes,
    this.maxMetadataKeys = defaultObservationMaxMetadataKeys,
    this.maxMetadataValueBytes = defaultObservationMaxMetadataValueBytes,
    this.maxMetadataBytes = defaultObservationMaxMetadataBytes,
    this.maxEventsPerTokenWindow = defaultObservationMaxEventsPerTokenWindow,
    this.maxEventsPerInstallationWindow =
        defaultObservationMaxEventsPerInstallationWindow,
    this.maxEventsPerTypeWindow = defaultObservationMaxEventsPerTypeWindow,
    this.rateWindow = defaultObservationRateWindow,
    this.tokenLifetime = defaultObservationTokenLifetime,
    this.futureSkew = defaultObservationFutureSkew,
    this.lateWindow = defaultObservationLateWindow,
    this.retention = defaultObservationRetention,
  });

  final int maxEventBytes;
  final int maxMetadataKeys;
  final int maxMetadataValueBytes;
  final int maxMetadataBytes;
  final int maxEventsPerTokenWindow;
  final int maxEventsPerInstallationWindow;
  final int maxEventsPerTypeWindow;
  final Duration rateWindow;
  final Duration tokenLifetime;
  final Duration futureSkew;
  final Duration lateWindow;
  final Duration retention;

  void validate() {
    if (maxEventBytes <= 0 ||
        maxMetadataKeys <= 0 ||
        maxMetadataValueBytes <= 0 ||
        maxMetadataBytes <= 0 ||
        maxEventsPerTokenWindow <= 0 ||
        maxEventsPerInstallationWindow <= 0 ||
        maxEventsPerTypeWindow <= 0 ||
        rateWindow <= Duration.zero ||
        tokenLifetime <= Duration.zero ||
        tokenLifetime > maxObservationTokenLifetime ||
        futureSkew < Duration.zero ||
        lateWindow <= Duration.zero ||
        retention <= Duration.zero ||
        lateWindow > retention) {
      throw const FormatException('Observation policy bounds are invalid');
    }
  }
}

/// The client event contains only patch-safety identity and bounded
/// diagnostics. Server receipt and disposition are stored separately.
final class ObservationEvent {
  ObservationEvent({
    required this.schemaVersion,
    required String eventId,
    required this.clientTimestamp,
    required String organizationId,
    required String applicationId,
    required String environmentId,
    required String platform,
    required String releaseId,
    required this.patchId,
    required this.sequence,
    required this.rolloutId,
    required this.rolloutRevision,
    required String installationBucket,
    required this.eventType,
    required String runtimeVersion,
    required this.patchFormatVersion,
    required this.diagnosticCode,
    Map<String, Object?> safeMetadata = const <String, Object?>{},
  }) : eventId = _observationId(eventId),
       organizationId = requireOpaqueId(organizationId, 'organization ID'),
       applicationId = requireOpaqueId(applicationId, 'application ID'),
       environmentId = requireOpaqueId(environmentId, 'environment ID'),
       platform = _platform(platform),
       releaseId = requireOpaqueId(releaseId, 'release ID'),
       installationBucket = _installationBucket(installationBucket),
       runtimeVersion = requireNonEmpty(
         runtimeVersion,
         'runtime version',
         maxLength: 64,
       ),
       safeMetadata = _safeMetadata(safeMetadata) {
    if (schemaVersion != observationSchemaVersion) {
      throw const FormatException('Unsupported observation schema version');
    }
    if (sequence != null && sequence! <= 0) {
      throw const FormatException('Observation sequence must be positive');
    }
    if (rolloutId == null && rolloutRevision != null ||
        rolloutId != null && rolloutRevision == null) {
      throw const FormatException(
        'Observation rollout ID and revision must be provided together',
      );
    }
    if (rolloutId != null) {
      _observationId(rolloutId!);
      if (rolloutRevision! <= 0) {
        throw const FormatException('Observation rollout revision is invalid');
      }
    }
    if (patchId != null) requireOpaqueId(patchId!, 'patch ID');
    if (diagnosticCode != null) _diagnosticCode(diagnosticCode!);
    if (patchFormatVersion <= 0) {
      throw const FormatException(
        'Observation Patch Format version is invalid',
      );
    }
  }

  final int schemaVersion;
  final String eventId;
  final DateTime clientTimestamp;
  final String organizationId;
  final String applicationId;
  final String environmentId;
  final String platform;
  final String releaseId;
  final String? patchId;
  final int? sequence;
  final String? rolloutId;
  final int? rolloutRevision;
  final String installationBucket;
  final ObservationEventType eventType;
  final String runtimeVersion;
  final int patchFormatVersion;
  final String? diagnosticCode;
  final Map<String, Object?> safeMetadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'eventId': eventId,
    'clientTimestamp': clientTimestamp.toUtc().toIso8601String(),
    'organizationId': organizationId,
    'applicationId': applicationId,
    'environmentId': environmentId,
    'platform': platform,
    'releaseId': releaseId,
    'patchId': patchId,
    'sequence': sequence,
    'rolloutId': rolloutId,
    'rolloutRevision': rolloutRevision,
    'installationBucket': installationBucket,
    'eventType': eventType.wireName,
    'runtimeVersion': runtimeVersion,
    'patchFormatVersion': patchFormatVersion,
    'diagnosticCode': diagnosticCode,
    'safeMetadata': safeMetadata,
  };

  static ObservationEvent fromJson(Object? value) {
    final map = _object(value, 'observation event');
    _exactKeys(map, const {
      'schemaVersion',
      'eventId',
      'clientTimestamp',
      'organizationId',
      'applicationId',
      'environmentId',
      'platform',
      'releaseId',
      'patchId',
      'sequence',
      'rolloutId',
      'rolloutRevision',
      'installationBucket',
      'eventType',
      'runtimeVersion',
      'patchFormatVersion',
      'diagnosticCode',
      'safeMetadata',
    }, 'observation event');
    final timestamp = map['clientTimestamp'];
    if (timestamp is! String) {
      throw const FormatException('Invalid observation client timestamp');
    }
    final safeMetadata = map['safeMetadata'];
    if (safeMetadata is! Map) {
      throw const FormatException('Invalid observation safe metadata');
    }
    return ObservationEvent(
      schemaVersion: _int(map['schemaVersion'], 'schema version'),
      eventId: _string(map['eventId'], 'event ID'),
      clientTimestamp: _timestamp(timestamp),
      organizationId: _string(map['organizationId'], 'organization ID'),
      applicationId: _string(map['applicationId'], 'application ID'),
      environmentId: _string(map['environmentId'], 'environment ID'),
      platform: _string(map['platform'], 'platform'),
      releaseId: _string(map['releaseId'], 'release ID'),
      patchId: _nullableString(map['patchId'], 'patch ID'),
      sequence: _nullableInt(map['sequence'], 'sequence'),
      rolloutId: _nullableString(map['rolloutId'], 'rollout ID'),
      rolloutRevision: _nullableInt(map['rolloutRevision'], 'rollout revision'),
      installationBucket: _string(
        map['installationBucket'],
        'installation bucket',
      ),
      eventType: parseObservationEventType(map['eventType']),
      runtimeVersion: _string(map['runtimeVersion'], 'runtime version'),
      patchFormatVersion: _int(
        map['patchFormatVersion'],
        'Patch Format version',
      ),
      diagnosticCode: _nullableString(map['diagnosticCode'], 'diagnostic code'),
      safeMetadata: Map<String, Object?>.from(
        safeMetadata.map<String, Object?>(
          (key, item) => MapEntry('$key', item),
        ),
      ),
    );
  }
}

final class ObservationRecord {
  ObservationRecord({
    required this.event,
    required this.receivedAt,
    required this.disposition,
  });

  final ObservationEvent event;
  final DateTime receivedAt;
  final ObservationDisposition disposition;

  Map<String, Object?> toJson() => <String, Object?>{
    'event': event.toJson(),
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'disposition': disposition.wireName,
  };

  static ObservationRecord fromJson(Object? value) {
    final map = _object(value, 'observation record');
    _exactKeys(map, const {'event', 'receivedAt', 'disposition'}, 'record');
    final receivedAt = map['receivedAt'];
    if (receivedAt is! String) {
      throw const FormatException('Invalid observation receipt timestamp');
    }
    return ObservationRecord(
      event: ObservationEvent.fromJson(map['event']),
      receivedAt: _timestamp(receivedAt),
      disposition: parseObservationDisposition(map['disposition']),
    );
  }
}

final class ObservationIngestResult {
  const ObservationIngestResult({
    required this.eventId,
    required this.receivedAt,
    required this.disposition,
    required this.duplicate,
  });

  final String eventId;
  final DateTime receivedAt;
  final ObservationDisposition disposition;
  final bool duplicate;

  Map<String, Object?> toJson() => <String, Object?>{
    'eventId': eventId,
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'disposition': disposition.wireName,
    'duplicate': duplicate,
  };
}

String observationStorageId({
  required String organizationId,
  required String applicationId,
  required String environmentId,
  required String eventId,
}) =>
    'obs_${sha256Hex(utf8.encode('$organizationId\u0000$applicationId\u0000$environmentId\u0000$eventId'))}';

String _observationId(String value) {
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.:-]{0,127}$').hasMatch(value)) {
    throw const FormatException('Invalid observation event ID');
  }
  return value;
}

String _platform(String value) {
  if (value != 'android' && value != 'ios') {
    throw const FormatException('Unsupported observation platform');
  }
  return value;
}

String _installationBucket(String value) {
  if (!RegExp(r'^(?:bucket:[0-9]{1,20}|cohort:[A-Za-z0-9_.:-]{1,64})$')
      .hasMatch(value)) {
    throw const FormatException(
      'Observation installationBucket must be a privacy-minimized bucket or cohort',
    );
  }
  return value;
}

String _diagnosticCode(String value) {
  if (!RegExp(r'^[A-Z][A-Z0-9_.:-]{0,63}$').hasMatch(value)) {
    throw const FormatException('Invalid observation diagnostic code');
  }
  return value;
}

Map<String, Object?> _safeMetadata(Map<String, Object?> value) {
  if (value.length > defaultObservationMaxMetadataKeys) {
    throw const FormatException('Observation safe metadata has too many keys');
  }
  final normalized = <String, Object?>{};
  for (final entry in value.entries) {
    if (!observationSafeMetadataKeys.contains(entry.key)) {
      throw const FormatException('Invalid observation safe metadata key');
    }
    final item = entry.value;
    if (item != null && item is! String && item is! bool && item is! num) {
      throw const FormatException(
        'Observation safe metadata must contain scalar values',
      );
    }
    if (item is double && !item.isFinite) {
      throw const FormatException(
        'Observation safe metadata cannot contain non-finite numbers',
      );
    }
    if (item is String && utf8.encode(item).length > 256) {
      throw const FormatException(
        'Observation safe metadata value is too large',
      );
    }
    normalized[entry.key] = item;
  }
  final encodedBytes = utf8.encode(canonicalJson(normalized));
  if (encodedBytes.length > defaultObservationMaxMetadataBytes) {
    throw const FormatException('Observation safe metadata is too large');
  }
  return Map.unmodifiable(normalized);
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map) throw FormatException('Invalid $name');
  return Map<String, Object?>.from(
    value.map<String, Object?>((key, item) => MapEntry('$key', item)),
  );
}

void _exactKeys(Map<String, Object?> value, Set<String> expected, String name) {
  if (!setEquals(value.keys.toSet(), expected)) {
    throw FormatException('Unexpected fields in $name');
  }
}

bool setEquals(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

String _string(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('Invalid observation $field');
  }
  return value;
}

int _int(Object? value, String field) {
  if (value is! int) throw FormatException('Invalid observation $field');
  return value;
}

String? _nullableString(Object? value, String field) {
  if (value == null) return null;
  return _string(value, field);
}

int? _nullableInt(Object? value, String field) {
  if (value == null) return null;
  return _int(value, field);
}

DateTime _timestamp(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null)
    throw const FormatException('Invalid observation timestamp');
  return parsed.toUtc();
}
