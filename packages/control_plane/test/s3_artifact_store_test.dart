import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late HttpClient client;
  final objects = <String, List<int>>{};
  var credentialRequests = 0;
  String? lastAuthorization;
  String? lastSecurityToken;

  setUp(() async {
    client = HttpClient();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final key = request.uri.path;
      lastAuthorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      lastSecurityToken = request.headers.value('x-amz-security-token');
      if (key == '/creds' || key == '/malformed-creds') {
        credentialRequests++;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            key == '/creds'
                ? '{"AccessKeyId":"ASIA_TEST","SecretAccessKey":"secret",'
                      '"Token":"session-token","Expiration":"2099-01-01T00:00:00Z"}'
                : '{"AccessKeyId":"ASIA_TEST"}',
          );
        await request.response.close();
        return;
      }
      if (request.method == 'PUT') {
        final bytes = <int>[];
        await for (final chunk in request) {
          bytes.addAll(chunk);
        }
        if (objects.containsKey(key) &&
            request.headers.value('if-none-match') == '*') {
          request.response.statusCode = HttpStatus.preconditionFailed;
        } else {
          objects[key] = bytes;
          request.response.statusCode = HttpStatus.created;
        }
        await request.response.close();
        return;
      }
      if (request.method == 'GET') {
        final bytes = objects[key];
        if (bytes == null) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..contentLength = bytes.length;
          request.response.add(bytes);
        }
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
    });
  });

  tearDown(() async {
    objects.clear();
    credentialRequests = 0;
    lastAuthorization = null;
    lastSecurityToken = null;
    client.close(force: true);
    await server.close(force: true);
  });

  test('uploads immutable digest objects and verifies downloads', () async {
    final store = S3CompatibleArtifactStore(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
      bucket: 'hyfens-test',
      client: client,
      authorization: 'Bearer object-test',
    );
    final bytes = <int>[1, 2, 3, 4];
    final digest = sha256Digest(bytes);
    await store.putArtifact(digest, bytes);
    await store.putArtifact(digest, bytes);
    expect(await store.readArtifact(digest), bytes);
  });

  test('rejects corrupted object bytes', () async {
    final store = S3CompatibleArtifactStore(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
      bucket: 'hyfens-test',
      client: client,
    );
    final bytes = <int>[5, 6, 7];
    final digest = sha256Digest(bytes);
    objects['/hyfens-test/${digest.substring(7)}'] = <int>[8, 9];
    await expectLater(
      store.readArtifact(digest),
      throwsA(isA<StorageConflict>()),
    );
  });

  test(
    'keeps a configured object prefix outside logical digest keys',
    () async {
      final store = S3CompatibleArtifactStore(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        bucket: 'hyfens-test',
        client: client,
        authorization: 'Bearer object-test',
        keyPrefix: 'artifacts',
      );
      final bytes = <int>[7, 8, 9];
      final digest = sha256Digest(bytes);
      await store.putArtifact(digest, bytes);
      expect(objects['/hyfens-test/artifacts/${digest.substring(7)}'], bytes);
      expect(await store.readArtifact(digest), bytes);
    },
  );

  test(
    'uses cached ECS task-role credentials and signs session requests',
    () async {
      final provider = EcsTaskRoleCredentialsProvider(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/creds'),
        client: HttpClient(),
      );
      final store = S3CompatibleArtifactStore(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        bucket: 'hyfens-test',
        client: client,
        credentialsProvider: provider,
        region: 'ap-south-1',
      );
      final bytes = <int>[10, 11, 12];
      final digest = sha256Digest(bytes);
      await store.putArtifact(digest, bytes);
      expect(await store.readArtifact(digest), bytes);
      expect(credentialRequests, 1);
      expect(
        lastAuthorization,
        startsWith('AWS4-HMAC-SHA256 Credential=ASIA_TEST/'),
      );
      expect(lastSecurityToken, 'session-token');
      provider.close();
    },
  );

  test('rejects static and task-role authentication combined', () {
    expect(
      () => S3CompatibleArtifactStore(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/'),
        bucket: 'hyfens-test',
        authorization: 'Bearer static',
        credentialsProvider: EcsTaskRoleCredentialsProvider(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/creds'),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('rejects malformed task-role credential responses', () async {
    final provider = EcsTaskRoleCredentialsProvider(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/malformed-creds'),
    );
    await expectLater(provider.credentials(), throwsA(isA<FormatException>()));
    provider.close();
  });
}
