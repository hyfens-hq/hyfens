import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late FileControlPlaneStore store;
  late HumanAuthService auth;
  late ControlPlaneService service;
  late ControlPlaneHttpServer adapter;
  late HttpServer server;
  var now = DateTime.utc(2026, 9, 13, 12);

  setUp(() async {
    now = DateTime.utc(2026, 9, 13, 12);
    directory = await Directory.systemTemp.createTemp('hyfens-platform-staff-');
    store = FileControlPlaneStore(directory);
    auth = HumanAuthService(
      store: store,
      clock: () => now,
      config: HumanAuthConfig(
        issuer: 'platform-staff-test',
        audience: 'hyfens-control',
        signingKeySeed: List<int>.filled(32, 17),
        platformAdminEmails: const <String>[demoOwnerEmail],
      ),
    );
    service = ControlPlaneService(
      store: store,
      humanAuth: auth,
      clock: () => now,
      deploymentModel: DeploymentModel.cloud,
    );
    await service.initialize();
    await DemoAccountSeeder(
      store: store,
      auth: auth,
      billingService: service.billing,
      clock: () => now,
    ).seed(password: 'demo-password');
    adapter = ControlPlaneHttpServer(service);
    server = await adapter.bind();
  });

  tearDown(() async {
    await adapter.close(force: true);
    await store.close();
    await directory.delete(recursive: true);
  });

  test('staff invitation uses role-derived access, review, cool-off, and idempotency', () async {
    final client = HttpClient();
    try {
      final ownerLogin = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
        audience: platformAuthorizationAudience,
      );
      final ownerToken = ownerLogin.body['access_token']! as String;

      final invited = await _writeJson(
        client,
        server.port,
        '/v1/platform/staff/invitations?profile=$demoOwnerProfileName',
        method: 'POST',
        token: ownerToken,
        idempotencyKey: 'staff-invite-1',
        body: <String, Object?>{
          'email': 'support.staff@example.com',
          'role': 'support',
          'reason': 'Provide first-line Cloud support coverage',
        },
      );
      expect(invited.statusCode, 201, reason: jsonEncode(invited.body));
      final token = invited.body['token'];
      expect(token, isA<String>());
      final invitation = invited.body['invitation']! as Map<String, Object?>;
      final invitationId = invitation['id']! as String;
      final review = invited.body['review']! as Map<String, Object?>;
      final reviewId = review['id']! as String;
      expect(invitation['status'], 'pending_review');
      expect(review['status'], 'pending_review');
      expect(jsonEncode(invited.body), isNot(contains('tokenHash')));

      final repeated = await _writeJson(
        client,
        server.port,
        '/v1/platform/staff/invitations?profile=$demoOwnerProfileName',
        method: 'POST',
        token: ownerToken,
        idempotencyKey: 'staff-invite-1',
        body: <String, Object?>{
          'email': 'support.staff@example.com',
          'role': 'support',
          'reason': 'Provide first-line Cloud support coverage',
        },
      );
      expect(repeated.statusCode, 201);
      expect(repeated.body['token'], isNull);
      expect(
        (repeated.body['invitation']! as Map<String, Object?>)['id'],
        invitationId,
      );

      final reviewer = await auth.createManagedPlatformStaff(
        email: 'security.reviewer@example.com',
        password: 'reviewer-password',
        role: 'security',
      );
      final reviewerLogin = await _login(
        client,
        server.port,
        reviewer.email,
        'reviewer-password',
        audience: platformAuthorizationAudience,
      );
      final reviewerToken = reviewerLogin.body['access_token']! as String;

      final selfApproval = await _writeJson(
        client,
        server.port,
        '/v1/platform/staff/access-reviews/$reviewId/approve?profile=security',
        method: 'POST',
        token: ownerToken,
        idempotencyKey: 'staff-review-self-1',
        body: <String, Object?>{'reason': 'Owner cannot self-approve'},
      );
      expect(selfApproval.statusCode, 403);

      final approved = await _writeJson(
        client,
        server.port,
        '/v1/platform/staff/access-reviews/$reviewId/approve?profile=security',
        method: 'POST',
        token: reviewerToken,
        idempotencyKey: 'staff-review-approve-1',
        body: <String, Object?>{'reason': 'Independent review completed'},
      );
      expect(approved.statusCode, 200, reason: jsonEncode(approved.body));
      expect(
        (approved.body['review']! as Map<String, Object?>)['status'],
        'cooling_off',
      );

      final beforeCoolOff = await _get(
        client,
        server.port,
        '/v1/platform/staff/invitations?profile=$demoOwnerProfileName',
        token: ownerToken,
      );
      expect(beforeCoolOff.statusCode, 200);
      expect(
        ((beforeCoolOff.body['invitations']! as List<Object?>).single
            as Map<String, Object?>)['status'],
        'cooling_off',
      );

      now = now.add(const Duration(hours: 25));
      final accepted = await _writeJson(
        client,
        server.port,
        '/v1/platform/staff/invitations/accept',
        method: 'POST',
        token: null,
        idempotencyKey: null,
        body: <String, Object?>{'token': token, 'password': 'staff-password'},
      );
      expect(accepted.statusCode, 200, reason: jsonEncode(accepted.body));
      expect(accepted.body['status'], 'accepted');

      final staffLogin = await _login(
        client,
        server.port,
        'support.staff@example.com',
        'staff-password',
        audience: platformAuthorizationAudience,
      );
      expect(staffLogin.statusCode, 200, reason: jsonEncode(staffLogin.body));
      final profile =
          (staffLogin.body['profiles']! as List<Object?>).single
              as Map<String, Object?>;
      expect(profile['name'], 'support');
      expect(profile['platform'], isTrue);
      expect(
        (profile['platform_capabilities']! as List<Object?>).map(
          (value) => value as String,
        ),
        containsAll(<String>[
          platformOverviewCapability,
          platformOrganizationsReadCapability,
        ]),
      );
      expect(
        (profile['platform_capabilities']! as List<Object?>).map(
          (value) => value as String,
        ),
        isNot(contains(platformStaffManageCapability)),
      );

      final refreshedOwnerLogin = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
        audience: platformAuthorizationAudience,
      );
      final listed = await _get(
        client,
        server.port,
        '/v1/platform/staff/invitations?profile=$demoOwnerProfileName',
        token: refreshedOwnerLogin.body['access_token']! as String,
      );
      expect(listed.statusCode, 200);
      expect(
        ((listed.body['invitations']! as List<Object?>).single
            as Map<String, Object?>)['status'],
        'accepted',
      );

      final audit = await store.listJson('audit');
      expect(
        audit.any(
          (event) => event['action'] == 'platform.staff.invitation.requested',
        ),
        isTrue,
      );
      expect(
        audit.any(
          (event) => event['action'] == 'platform.staff.access_review.approved',
        ),
        isTrue,
      );
    } finally {
      client.close(force: true);
    }
  });

  test('staff role changes are reviewed and customer sessions cannot use staff routes', () async {
    final client = HttpClient();
    try {
      final ownerLogin = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
        audience: platformAuthorizationAudience,
      );
      final ownerToken = ownerLogin.body['access_token']! as String;
      final target = await auth.createManagedPlatformStaff(
        email: 'operations.staff@example.com',
        password: 'operations-password',
        role: 'support',
      );

      final requested = await _writeJson(
        client,
        server.port,
        '/v1/platform/staff/${target.id}?profile=$demoOwnerProfileName',
        method: 'PATCH',
        token: ownerToken,
        idempotencyKey: 'staff-change-1',
        body: <String, Object?>{
          'role': 'operations',
          'active': true,
          'reason': 'Operations coverage requires deployment visibility',
        },
      );
      expect(requested.statusCode, 202, reason: jsonEncode(requested.body));
      final review = requested.body['review']! as Map<String, Object?>;
      final reviewId = review['id']! as String;

      final customerLogin = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
      );
      final customerToken = customerLogin.body['access_token']! as String;
      final denied = await _get(
        client,
        server.port,
        '/v1/platform/staff/invitations',
        token: customerToken,
      );
      expect(denied.statusCode, 403);

      final reviewer = await auth.createManagedPlatformStaff(
        email: 'role.reviewer@example.com',
        password: 'role-reviewer-password',
        role: 'security',
      );
      final reviewerLogin = await _login(
        client,
        server.port,
        reviewer.email,
        'role-reviewer-password',
        audience: platformAuthorizationAudience,
      );
      final approved = await _writeJson(
        client,
        server.port,
        '/v1/platform/staff/access-reviews/$reviewId/approve?profile=security',
        method: 'POST',
        token: reviewerLogin.body['access_token']! as String,
        idempotencyKey: 'staff-role-approve-1',
        body: <String, Object?>{
          'reason': 'Reviewed against the operations role boundary',
        },
      );
      expect(approved.statusCode, 200);

      now = now.add(const Duration(hours: 25));
      final refreshedOwnerLogin = await _login(
        client,
        server.port,
        demoOwnerEmail,
        'demo-password',
        audience: platformAuthorizationAudience,
      );
      final reviews = await _get(
        client,
        server.port,
        '/v1/platform/staff/access-reviews?profile=$demoOwnerProfileName',
        token: refreshedOwnerLogin.body['access_token']! as String,
      );
      expect(reviews.statusCode, 200);
      expect(
        (reviews.body['reviews']! as List<Object?>).any(
          (value) =>
              value is Map<String, Object?> &&
              value['id'] == reviewId &&
              value['status'] == 'effective',
        ),
        isTrue,
      );

      final targetLogin = await _login(
        client,
        server.port,
        target.email,
        'operations-password',
        audience: platformAuthorizationAudience,
      );
      expect(targetLogin.statusCode, 200);
      final targetProfile =
          (targetLogin.body['profiles']! as List<Object?>).single
              as Map<String, Object?>;
      expect(targetProfile['name'], 'operations');
      expect(
        (targetProfile['platform_capabilities']! as List<Object?>).map(
          (value) => value as String,
        ),
        contains(platformOperationsManageCapability),
      );
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
  final encoded = utf8.encode(
    jsonEncode(<String, Object?>{
      'email': email,
      'password': password,
      'audience': audience,
    }),
  );
  request
    ..headers.contentType = ContentType.json
    ..contentLength = encoded.length;
  request.add(encoded);
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

Future<_Response> _writeJson(
  HttpClient client,
  int port,
  String path, {
  required String method,
  String? token,
  String? idempotencyKey,
  required Map<String, Object?> body,
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  final encoded = utf8.encode(jsonEncode(body));
  request
    ..headers.contentType = ContentType.json
    ..contentLength = encoded.length;
  if (token != null) request.headers.set('Authorization', 'Bearer $token');
  if (idempotencyKey != null) {
    request.headers.set('Idempotency-Key', idempotencyKey);
  }
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
