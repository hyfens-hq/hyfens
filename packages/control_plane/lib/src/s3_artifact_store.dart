import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'encoding.dart';
import 'errors.dart';
import 'persistence.dart';

/// Short-lived AWS credentials used to sign one S3 request.
///
/// The credentials are deliberately represented separately from the object
/// store.  A provider can refresh them without exposing a static access key
/// through application configuration or persisted control-plane state.
final class AwsSessionCredentials {
  const AwsSessionCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
    this.expiresAt,
  });

  final String accessKeyId;
  final String secretAccessKey;
  final String? sessionToken;
  final DateTime? expiresAt;

  void validate({DateTime? now}) {
    if (accessKeyId.isEmpty || secretAccessKey.isEmpty) {
      throw const FormatException('AWS credentials must not be empty');
    }
    final expiry = expiresAt;
    if (expiry != null && !expiry.isAfter((now ?? DateTime.now()).toUtc())) {
      throw const FormatException('AWS credentials are expired');
    }
  }
}

/// Credential source for an AWS-compatible request signer.
abstract interface class AwsCredentialsProvider {
  Future<AwsSessionCredentials> credentials();
}

/// Reads the ECS task-role credential endpoint exposed to a Fargate task.
///
/// The endpoint and optional authorization token are supplied by the ECS
/// agent.  The response is cached until shortly before its expiry, so normal
/// artifact traffic does not make a metadata request per object operation.
final class EcsTaskRoleCredentialsProvider implements AwsCredentialsProvider {
  EcsTaskRoleCredentialsProvider({
    required Uri endpoint,
    HttpClient? client,
    this.refreshSkew = const Duration(minutes: 1),
    this.authorizationToken,
  }) : _endpoint = endpoint,
       _client = client ?? HttpClient() {
    if (_endpoint.scheme != 'http' && _endpoint.scheme != 'https') {
      throw ArgumentError.value(endpoint, 'endpoint');
    }
    if (_endpoint.host.isEmpty) throw ArgumentError.value(endpoint, 'endpoint');
    if (refreshSkew < Duration.zero) {
      throw ArgumentError.value(refreshSkew, 'refreshSkew');
    }
  }

  factory EcsTaskRoleCredentialsProvider.fromEnvironment({
    Map<String, String>? environment,
    HttpClient? client,
  }) {
    final values = environment ?? Platform.environment;
    final relative = values['AWS_CONTAINER_CREDENTIALS_RELATIVE_URI'];
    final full = values['AWS_CONTAINER_CREDENTIALS_FULL_URI'];
    if ((relative == null || relative.isEmpty) &&
        (full == null || full.isEmpty)) {
      throw StateError(
        'ECS task-role credential endpoint environment is unavailable',
      );
    }
    final endpoint = relative != null && relative.isNotEmpty
        ? Uri.parse('http://169.254.170.2$relative')
        : Uri.parse(full!);
    final token = values['AWS_CONTAINER_AUTHORIZATION_TOKEN'];
    return EcsTaskRoleCredentialsProvider(
      endpoint: endpoint,
      client: client,
      authorizationToken: token,
    );
  }

  final Uri _endpoint;
  final Duration refreshSkew;
  final String? authorizationToken;
  HttpClient _client;
  AwsSessionCredentials? _cached;

  @override
  Future<AwsSessionCredentials> credentials() async {
    final cached = _cached;
    final now = DateTime.now().toUtc();
    if (cached != null) {
      final expiry = cached.expiresAt;
      if (expiry == null || expiry.isAfter(now.add(refreshSkew))) {
        return cached;
      }
    }
    final request = await _client.getUrl(_endpoint);
    if (authorizationToken != null && authorizationToken!.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, authorizationToken!);
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StorageUnavailable(
        'ECS task-role credential endpoint failed with HTTP '
        '${response.statusCode}',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ECS credentials response must be an object');
    }
    final accessKeyId = decoded['AccessKeyId'];
    final secretAccessKey = decoded['SecretAccessKey'];
    final sessionToken = decoded['Token'] ?? decoded['SessionToken'];
    if (accessKeyId is! String || secretAccessKey is! String) {
      throw const FormatException('ECS credentials response is incomplete');
    }
    final expiryValue = decoded['Expiration'];
    final expiresAt = expiryValue is String
        ? DateTime.tryParse(expiryValue)?.toUtc()
        : null;
    if (expiryValue != null && expiresAt == null) {
      throw const FormatException('ECS credentials expiration is invalid');
    }
    final result = AwsSessionCredentials(
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      sessionToken: sessionToken is String ? sessionToken : null,
      expiresAt: expiresAt,
    );
    result.validate(now: now);
    _cached = result;
    return result;
  }

  void close() {
    _client.close(force: true);
  }
}

/// Minimal provider-neutral S3-compatible object adapter.
///
/// Authentication can be delegated to the object endpoint or a reverse proxy
/// (for example, a pre-authenticated/private-network endpoint), or supplied
/// through standard AWS Signature V4 credentials. The adapter enforces
/// immutable digest-addressed objects and verifies bytes on both upload and
/// download.
final class S3CompatibleArtifactStore
    implements ArtifactStore, ArtifactStoreReadiness, ArtifactInventory {
  S3CompatibleArtifactStore({
    required Uri endpoint,
    required this.bucket,
    HttpClient? client,
    this.authorization,
    this.accessKey,
    this.secretKey,
    this.credentialsProvider,
    this.keyPrefix = '',
    this.region = 'us-east-1',
    this.service = 's3',
  }) : _endpoint = endpoint,
       _client = client ?? HttpClient() {
    if (credentialsProvider != null &&
        (accessKey != null || secretKey != null || authorization != null)) {
      throw ArgumentError(
        'Task-role credentials cannot be combined with static S3 auth',
      );
    }
    if ((accessKey == null) != (secretKey == null)) {
      throw ArgumentError('Both S3 accessKey and secretKey are required');
    }
    if (keyPrefix.startsWith('/') ||
        keyPrefix.endsWith('/') ||
        keyPrefix.contains('..') ||
        (keyPrefix.isNotEmpty &&
            !RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(keyPrefix))) {
      throw ArgumentError.value(keyPrefix, 'keyPrefix');
    }
  }

  final Uri _endpoint;
  final String bucket;
  final String? authorization;
  final String? accessKey;
  final String? secretKey;
  final AwsCredentialsProvider? credentialsProvider;
  final String keyPrefix;
  final String region;
  final String service;
  HttpClient _client;

  @override
  Future<void> putArtifact(String digest, List<int> bytes) async {
    final normalized = requireSha256Digest(digest);
    final actual = sha256Digest(bytes);
    if (actual != normalized) throw StorageDigestMismatch(normalized, actual);
    await _retry(() async {
      final request = await _client.putUrl(_objectUri(normalized));
      await _setHeaders(
        request,
        bytes.length,
        normalized,
        payload: bytes,
        immutable: true,
      );
      request.add(Uint8List.fromList(bytes));
      final response = await request.close();
      final status = response.statusCode;
      await response.drain<void>();
      if (status == HttpStatus.conflict ||
          status == HttpStatus.preconditionFailed) {
        final existing = await readArtifact(normalized);
        if (existing == null || !_sameBytes(existing, bytes)) {
          throw const StorageConflict('Content-addressed artifact was changed');
        }
        return;
      }
      if (status < 200 || status >= 300) {
        throw StorageUnavailable('Object upload failed with HTTP $status');
      }
    });
  }

  @override
  Future<void> checkReadiness() async {
    await _retry(() async {
      final digest = sha256Digest(const <int>[]);
      final request = await _client.headUrl(_bucketUri());
      await _setHeaders(request, 0, digest, payload: const <int>[]);
      final response = await request.close();
      final status = response.statusCode;
      await response.drain<void>();
      if (status < 200 || status >= 300) {
        throw StorageUnavailable(
          'Object bucket readiness failed with HTTP $status',
        );
      }
    });
  }

  @override
  Future<Set<String>> listArtifactKeys() async {
    final keys = <String>{};
    String? continuation;
    do {
      final query = <String, String>{
        'list-type': '2',
        if (keyPrefix.isNotEmpty) 'prefix': '$keyPrefix/',
      };
      if (continuation != null) query['continuation-token'] = continuation;
      final request = await _client.getUrl(
        _bucketUri().replace(queryParameters: query),
      );
      await _setHeaders(
        request,
        0,
        sha256Digest(const <int>[]),
        payload: const <int>[],
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StorageUnavailable(
          'Object inventory failed with HTTP ${response.statusCode}',
        );
      }
      for (final match in RegExp(
        r'<Key>(.*?)</Key>',
        dotAll: true,
      ).allMatches(body)) {
        final key = _decodeXml(match.group(1)!);
        final prefix = keyPrefix.isEmpty ? '' : '$keyPrefix/';
        if (!key.startsWith(prefix)) continue;
        keys.add(key.substring(prefix.length));
      }
      final truncated =
          RegExp(r'<IsTruncated>(true|false)</IsTruncated>')
              .firstMatch(body)
              ?.group(1) ==
          'true';
      continuation = truncated
          ? RegExp(r'<NextContinuationToken>(.*?)</NextContinuationToken>')
                .firstMatch(body)
                ?.group(1)
          : null;
      if (truncated && (continuation == null || continuation.isEmpty)) {
        throw const StorageConflict(
          'Object inventory was truncated without a continuation token',
        );
      }
    } while (continuation != null);
    return Set.unmodifiable(keys);
  }

  @override
  Future<List<int>?> readArtifact(String digest) async {
    final normalized = requireSha256Digest(digest);
    return _retry(() async {
      final request = await _client.getUrl(_objectUri(normalized));
      await _setHeaders(request, 0, normalized, payload: const <int>[]);
      final response = await request.close();
      if (response.statusCode == HttpStatus.notFound) {
        await response.drain<void>();
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw StorageUnavailable(
          'Object read failed with HTTP ${response.statusCode}',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      if (sha256Digest(bytes) != normalized) {
        throw const StorageConflict('Object failed its content digest check');
      }
      return bytes;
    });
  }

  Future<T> _retry<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on SocketException {
      _resetClient();
      try {
        return await operation();
      } on SocketException catch (error) {
        throw StorageUnavailable('Object endpoint is unavailable: $error');
      } on HttpException catch (error) {
        throw StorageUnavailable('Object endpoint is unavailable: $error');
      }
    } on HttpException {
      _resetClient();
      try {
        return await operation();
      } on SocketException catch (error) {
        throw StorageUnavailable('Object endpoint is unavailable: $error');
      } on HttpException catch (error) {
        throw StorageUnavailable('Object endpoint is unavailable: $error');
      }
    }
  }

  void _resetClient() {
    _client.close(force: true);
    _client = HttpClient();
  }

  Uri _objectUri(String digest) {
    final base = _endpoint.toString().endsWith('/')
        ? _endpoint
        : _endpoint.replace(path: '${_endpoint.path}/');
    return base.resolve(
      '${Uri.encodeComponent(bucket)}/'
      '${keyPrefix.isEmpty ? '' : '${Uri.encodeComponent(keyPrefix)}/'}'
      '${Uri.encodeComponent(digest.substring(7))}',
    );
  }

  Uri _bucketUri() {
    final base = _endpoint.toString().endsWith('/')
        ? _endpoint
        : _endpoint.replace(path: '${_endpoint.path}/');
    return base.resolve(Uri.encodeComponent(bucket));
  }

  String _decodeXml(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  Future<void> _setHeaders(
    HttpClientRequest request,
    int length,
    String digest, {
    required List<int> payload,
    bool immutable = false,
  }) async {
    final timestamp = DateTime.now().toUtc();
    final amzDate = _amzDate(timestamp);
    request.headers
      ..contentLength = length
      ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
      ..set('Digest', digest)
      ..set('x-amz-content-sha256', _hexSha256(payload))
      ..set('x-amz-date', amzDate);
    if (immutable) request.headers.set('If-None-Match', '*');
    if (credentialsProvider != null) {
      final credentials = await credentialsProvider!.credentials();
      _setAwsAuthorization(
        request,
        amzDate,
        payload,
        accessKeyId: credentials.accessKeyId,
        secretAccessKey: credentials.secretAccessKey,
        sessionToken: credentials.sessionToken,
      );
    } else if (accessKey != null || secretKey != null) {
      if (accessKey == null || secretKey == null) {
        throw ArgumentError('Both S3 accessKey and secretKey are required');
      }
      _setAwsAuthorization(
        request,
        amzDate,
        payload,
        accessKeyId: accessKey!,
        secretAccessKey: secretKey!,
      );
    } else if (authorization != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorization!);
    }
  }

  void _setAwsAuthorization(
    HttpClientRequest request,
    String amzDate,
    List<int> payload, {
    required String accessKeyId,
    required String secretAccessKey,
    String? sessionToken,
  }) {
    final uri = request.uri;
    final date = amzDate.substring(0, 8);
    final host = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    final headers = <String, String>{
      'content-type': 'application/octet-stream',
      'digest': request.headers.value('Digest')!,
      'host': host,
      'x-amz-content-sha256': _hexSha256(payload),
      'x-amz-date': amzDate,
    };
    if (sessionToken != null && sessionToken.isNotEmpty) {
      request.headers.set('x-amz-security-token', sessionToken);
      headers['x-amz-security-token'] = sessionToken;
    }
    if (request.headers.value('If-None-Match') != null) {
      headers['if-none-match'] = request.headers.value('If-None-Match')!;
    }
    final signedHeaders = headers.keys.toList()..sort();
    final canonicalHeaders = signedHeaders
        .map((name) => '$name:${_trimHeader(headers[name]!)}\n')
        .join();
    final canonicalRequest = <String>[
      request.method,
      _canonicalPath(uri),
      uri.hasQuery ? uri.query : '',
      canonicalHeaders,
      signedHeaders.join(';'),
      _hexSha256(payload),
    ].join('\n');
    final scope = '$date/$region/$service/aws4_request';
    final stringToSign = <String>[
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      _hexSha256(utf8Bytes(canonicalRequest)),
    ].join('\n');
    final dateKey = _hmac(utf8Bytes('AWS4$secretAccessKey'), utf8Bytes(date));
    final regionKey = _hmac(dateKey, utf8Bytes(region));
    final serviceKey = _hmac(regionKey, utf8Bytes(service));
    final signingKey = _hmac(serviceKey, utf8Bytes('aws4_request'));
    final signature = _hex(_hmac(signingKey, utf8Bytes(stringToSign)));
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'AWS4-HMAC-SHA256 Credential=$accessKeyId/$scope, '
      'SignedHeaders=${signedHeaders.join(';')}, Signature=$signature',
    );
  }

  String _canonicalPath(Uri uri) => uri.pathSegments
      .map(Uri.encodeComponent)
      .fold<String>('', (value, segment) => '$value/$segment');

  String _amzDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}${two(value.month)}'
        '${two(value.day)}T${two(value.hour)}${two(value.minute)}'
        '${two(value.second)}Z';
  }

  String _trimHeader(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  String _hexSha256(List<int> bytes) => sha256.convert(bytes).toString();

  List<int> _hmac(List<int> key, List<int> value) =>
      Hmac(sha256, key).convert(value).bytes;

  String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  List<int> utf8Bytes(String value) => utf8.encode(value);

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
