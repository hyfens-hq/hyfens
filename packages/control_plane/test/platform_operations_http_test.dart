import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late ControlPlaneService service;
  late ControlPlaneHttpServer adapter;
  late HttpServer server;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hyfens-platform-ops-');
    store = FileControlPlaneStore(directory);
    final auth = HumanAuthService(
      store: store,
      config: HumanAuthConfig(
        issuer: 'platform-ops-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 9),
        platformAdminEmails: const <String>[demoOwnerEmail],
      ),
    );
    service = ControlPlaneService(
      store: store,
      humanAuth: auth,
      deploymentModel: DeploymentModel.cloud,
    );
    await service.initialize();
    await DemoAccountSeeder(
      store: store,
      auth: auth,
      billingService: service.billing,
    ).seed(password: 'demo-password');
    adapter = ControlPlaneHttpServer(service);
    server = await adapter.bind();
  });

  tearDown(() async {
    await adapter.close(force: true);
    await store.close();
    await directory.delete(recursive: true);
  });

  test('seeds admin@hyfens.com and audits reasoned owner changes', () async {
    final client = HttpClient();
    try {
      final login = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
        audience: platformAuthorizationAudience,
      );
      final token = login.body['access_token']! as String;
      final listed = await _get(
        client,
        server.port,
        '/v1/platform/operations/owners?profile=$demoOwnerProfileName',
        token: token,
      );
      expect(listed.statusCode, 200, reason: jsonEncode(listed.body));
      final owners = listed.body['owners']! as List<Object?>;
      expect(owners, hasLength(platformOperationsOwnerRoles.length));
      expect(
        owners.every(
          (value) =>
              (value! as Map<String, Object?>)['ownerEmail'] ==
              defaultPlatformOperationsOwnerEmail,
        ),
        isTrue,
      );

      final missingReason = await _postJson(
        client,
        server.port,
        '/v1/platform/operations/owners',
        token: token,
        idempotencyKey: 'ops-add-missing-reason',
        body: <String, Object?>{
          'role': 'email_delivery',
          'owner_email': 'ops@example.com',
          'reason': ' ',
        },
      );
      expect(missingReason.statusCode, 422);
      expect(missingReason.body['error'], isNotNull);

      final updated = await _patchJson(
        client,
        server.port,
        '/v1/platform/operations/owners/email_delivery',
        token: token,
        idempotencyKey: 'ops-update-email-delivery-1',
        body: <String, Object?>{
          'owner_email': 'oncall@hyfens.com',
          'reason': 'Assign the first monitored launch mailbox',
        },
      );
      expect(updated.statusCode, 200, reason: jsonEncode(updated.body));
      expect(
        (updated.body['owner']! as Map<String, Object?>)['ownerEmail'],
        'oncall@hyfens.com',
      );

      final repeated = await _patchJson(
        client,
        server.port,
        '/v1/platform/operations/owners/email_delivery',
        token: token,
        idempotencyKey: 'ops-update-email-delivery-1',
        body: <String, Object?>{
          'owner_email': 'oncall@hyfens.com',
          'reason': 'Assign the first monitored launch mailbox',
        },
      );
      expect(repeated.statusCode, 200);
      expect(repeated.body['owner'], updated.body['owner']);

      final removed = await _deleteJson(
        client,
        server.port,
        '/v1/platform/operations/owners/email_delivery',
        token: token,
        idempotencyKey: 'ops-remove-email-delivery-1',
        body: <String, Object?>{'reason': 'Retire the temporary mailbox'},
      );
      expect(removed.statusCode, 200, reason: jsonEncode(removed.body));
      expect(
        (removed.body['owner']! as Map<String, Object?>)['status'],
        'removed',
      );

      final readded = await _postJson(
        client,
        server.port,
        '/v1/platform/operations/owners',
        token: token,
        idempotencyKey: 'ops-add-email-delivery-2',
        body: <String, Object?>{
          'role': 'email_delivery',
          'owner_email': 'admin@hyfens.com',
          'reason': 'Restore the launch mailbox after the temporary assignment',
        },
      );
      expect(readded.statusCode, 201, reason: jsonEncode(readded.body));
      expect(
        (readded.body['owner']! as Map<String, Object?>)['status'],
        'active',
      );

      final audit = await store.listJson('audit');
      final changes = audit
          .where(
            (value) =>
                value['resourceType'] == 'platform_operations_owner' &&
                (value['metadata']! as Map<String, Object?>)['role'] ==
                    'email_delivery',
          )
          .toList(growable: false);
      expect(changes, hasLength(4));
      expect(
        changes.any(
          (value) =>
              value['action'] == 'platform.operations_owner.updated' &&
              (value['metadata']! as Map<String, Object?>)['reason'] ==
                  'Assign the first monitored launch mailbox',
        ),
        isTrue,
      );
      expect(
        changes.any(
          (value) =>
              value['action'] == 'platform.operations_owner.removed' &&
              (value['metadata']! as Map<String, Object?>)['reason'] ==
                  'Retire the temporary mailbox',
        ),
        isTrue,
      );

      final auditProjection = await _get(
        client,
        server.port,
        '/v1/platform/audit?profile=$demoOwnerProfileName',
        token: token,
      );
      expect(auditProjection.statusCode, 200);
      final events = auditProjection.body['events']! as List<Object?>;
      expect(
        events.any((value) {
          if (value is! Map<String, Object?> ||
              value['action'] != 'platform.operations_owner.updated') {
            return false;
          }
          final metadata = value['metadata'];
          return metadata is Map<String, Object?> &&
              metadata['reason'] == 'Assign the first monitored launch mailbox';
        }),
        isTrue,
      );
    } finally {
      client.close(force: true);
    }
  });

  test('customer sessions cannot read or mutate platform ownership', () async {
    final client = HttpClient();
    try {
      final login = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
      );
      final token = login.body['access_token']! as String;
      final read = await _get(
        client,
        server.port,
        '/v1/platform/operations/owners',
        token: token,
      );
      expect(read.statusCode, 403);

      final write = await _patchJson(
        client,
        server.port,
        '/v1/platform/operations/owners/email_delivery',
        token: token,
        idempotencyKey: 'ops-customer-write',
        body: <String, Object?>{
          'owner_email': 'attacker@example.com',
          'reason': 'should not be authorized',
        },
      );
      expect(write.statusCode, 403);
    } finally {
      client.close(force: true);
    }
  });
}

Future<_Response> _login(
  HttpClient client,
  int port,
  String email,
  String password, {
  String audience = customerAuthorizationAudience,
}) async {
  final request = await client.postUrl(
    Uri.parse('http://127.0.0.1:$port/auth/login'),
  );
  final body = utf8.encode(
    jsonEncode(<String, Object?>{
      'email': email,
      'password': password,
      'audience': audience,
    }),
  );
  request
    ..headers.contentType = ContentType.json
    ..contentLength = body.length;
  request.add(body);
  return _decodeResponse(await request.close());
}

Future<_Response> _get(
  HttpClient client,
  int port,
  String path, {
  String? token,
}) async {
  final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
  if (token != null) request.headers.set('Authorization', 'Bearer $token');
  return _decodeResponse(await request.close());
}

Future<_Response> _postJson(
  HttpClient client,
  int port,
  String path, {
  required Map<String, Object?> body,
  required String token,
  required String idempotencyKey,
}) => _writeJson(
  client,
  port,
  path,
  method: 'POST',
  body: body,
  token: token,
  idempotencyKey: idempotencyKey,
);

Future<_Response> _patchJson(
  HttpClient client,
  int port,
  String path, {
  required Map<String, Object?> body,
  required String token,
  required String idempotencyKey,
}) => _writeJson(
  client,
  port,
  path,
  method: 'PATCH',
  body: body,
  token: token,
  idempotencyKey: idempotencyKey,
);

Future<_Response> _deleteJson(
  HttpClient client,
  int port,
  String path, {
  required Map<String, Object?> body,
  required String token,
  required String idempotencyKey,
}) => _writeJson(
  client,
  port,
  path,
  method: 'DELETE',
  body: body,
  token: token,
  idempotencyKey: idempotencyKey,
);

Future<_Response> _writeJson(
  HttpClient client,
  int port,
  String path, {
  required String method,
  required Map<String, Object?> body,
  required String token,
  required String idempotencyKey,
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  final encoded = utf8.encode(jsonEncode(body));
  request
    ..headers.contentType = ContentType.json
    ..headers.set('Authorization', 'Bearer $token')
    ..headers.set('Idempotency-Key', idempotencyKey)
    ..contentLength = encoded.length;
  request.add(encoded);
  return _decodeResponse(await request.close());
}

Future<_Response> _decodeResponse(HttpClientResponse response) async {
  final text = await response.transform(utf8.decoder).join();
  final decoded = text.isEmpty ? <String, Object?>{} : jsonDecode(text);
  return _Response(
    response.statusCode,
    decoded is Map
        ? <String, Object?>{
            for (final entry in decoded.entries) '${entry.key}': entry.value,
          }
        : <String, Object?>{},
  );
}

final class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}
