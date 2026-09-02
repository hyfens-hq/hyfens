final class ControlPlaneException implements Exception {
  const ControlPlaneException(
    this.code,
    this.message, {
    this.statusCode = 400,
    this.details = const <String, Object?>{},
  });

  final String code;
  final String message;
  final int statusCode;
  final Map<String, Object?> details;

  Map<String, Object?> toJson(String requestId) => <String, Object?>{
    'error': <String, Object?>{
      'code': code,
      'message': message,
      if (details.isNotEmpty) 'details': details,
    },
    'request_id': requestId,
  };

  @override
  String toString() => 'ControlPlaneException($code): $message';
}

final class StorageConflict implements Exception {
  const StorageConflict(this.message);

  final String message;

  @override
  String toString() => 'StorageConflict: $message';
}

final class StoragePreconditionFailed implements Exception {
  const StoragePreconditionFailed(
    this.message, {
    required this.currentRevision,
  });

  final String message;
  final int currentRevision;

  @override
  String toString() =>
      'StoragePreconditionFailed(currentRevision: $currentRevision): $message';
}

final class StorageIdempotencyConflict implements Exception {
  const StorageIdempotencyConflict(this.message);

  final String message;

  @override
  String toString() => 'StorageIdempotencyConflict: $message';
}

final class StorageDigestMismatch implements Exception {
  const StorageDigestMismatch(this.expected, this.actual);

  final String expected;
  final String actual;

  @override
  String toString() =>
      'StorageDigestMismatch(expected: $expected, actual: $actual)';
}

final class StorageUnavailable implements Exception {
  const StorageUnavailable(this.message);

  final String message;

  @override
  String toString() => 'StorageUnavailable: $message';
}
