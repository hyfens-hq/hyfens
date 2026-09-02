import 'dart:convert';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';
import 'package:test/test.dart';

void main() {
  test('configuration is explicit and does not invent secrets', () {
    final config = ControlPlaneConfig.fromEnvironment(<String, String>{});
    expect(config.host, '127.0.0.1');
    expect(config.port, 18081);
    expect(config.databaseUrl, isNull);
    expect(config.artifactAuthorization, isNull);
    expect(config.fileRoot, isA<Directory>());
    expect(config.auth, isNull);
  });

  test('human auth configuration is explicit and bounded', () {
    final config = ControlPlaneConfig.fromEnvironment(<String, String>{
      'HYFENS_AUTH_SIGNING_KEY': base64.encode(List<int>.filled(32, 3)),
      'HYFENS_AUTH_ISSUER': 'control.example',
      'HYFENS_AUTH_AUDIENCE': 'hyfens-control',
      'HYFENS_AUTH_ACCESS_TTL': '15m',
      'HYFENS_AUTH_SESSION_TTL': '30d',
    });
    expect(config.auth, isNotNull);
    expect(config.auth!.issuer, 'control.example');
    expect(config.auth!.audience, 'hyfens-control');
    expect(config.auth!.accessTtl, const Duration(minutes: 15));
    expect(config.auth!.sessionTtl, const Duration(days: 30));
    final composeStyle = ControlPlaneConfig.fromEnvironment(<String, String>{
      'HYFENS_AUTH_SIGNING_KEY': base64.encode(List<int>.filled(32, 3)),
      'HYFENS_AUTH_ISSUER': '',
      'HYFENS_AUTH_AUDIENCE': '',
      'HYFENS_AUTH_SIGNING_KEY_ID': '',
      'HYFENS_AUTH_VERIFY_KEYS': '',
      'HYFENS_AUTH_ACCESS_TTL': '',
      'HYFENS_AUTH_SESSION_TTL': '',
    });
    expect(composeStyle.auth!.issuer, 'hyfens-control-plane');
    expect(composeStyle.auth!.audience, 'hyfens-control');
    expect(composeStyle.auth!.accessTtl, const Duration(minutes: 15));
    expect(composeStyle.auth!.sessionTtl, const Duration(days: 30));
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_AUTH_AUDIENCE': 'hyfens-control',
      }),
      throwsArgumentError,
    );
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_AUTH_ACCESS_TTL': '15m',
      }),
      throwsArgumentError,
    );
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_AUTH_SIGNING_KEY_ID': 'rotated-key',
      }),
      throwsArgumentError,
    );
  });

  test('browser discovery configuration is explicit and origin-bound', () {
    final config = ControlPlaneConfig.fromEnvironment(<String, String>{
      'HYFENS_AUTH_SIGNING_KEY': base64.encode(List<int>.filled(32, 8)),
      'HYFENS_AUTH_AUTHORIZATION_ENDPOINT':
          'https://app.hyfens.com/cli/authorize',
      'HYFENS_AUTH_DEVICE_VERIFICATION_URI': 'https://app.hyfens.com/device',
      'HYFENS_WEB_ORIGINS': 'https://app.hyfens.com, http://localhost:8080',
    });
    expect(
      config.discovery.authorizationEndpoint,
      Uri.parse('https://app.hyfens.com/cli/authorize'),
    );
    expect(
      config.discovery.webOrigins,
      containsAll(<String>{'https://app.hyfens.com', 'http://localhost:8080'}),
    );
    final discovery = config.discovery.toJson(
      humanAuthConfigured: true,
      deviceVerificationUri: config.auth!.deviceVerificationUri,
    );
    expect(
      discovery['authorization_endpoint'],
      'https://app.hyfens.com/cli/authorize',
    );
    expect(discovery['authorization_api_endpoint'], '/auth/authorize');
    expect(
      discovery['device_verification_uri'],
      'https://app.hyfens.com/device',
    );
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_AUTH_SIGNING_KEY': base64.encode(List<int>.filled(32, 8)),
        'HYFENS_WEB_ORIGINS': 'https://app.hyfens.com/path',
      }),
      throwsArgumentError,
    );
  });

  test('public registration organization is explicit and fail-closed', () {
    final unconfigured = ControlPlaneConfig.fromEnvironment(<String, String>{});
    expect(unconfigured.publicRegistrationOrganizationId, isNull);
    expect(unconfigured.discovery.publicRegistrationOrganizationId, isNull);

    final configured = ControlPlaneConfig.fromEnvironment(<String, String>{
      'HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID': 'org_local',
    });
    expect(configured.publicRegistrationOrganizationId, 'org_local');
    expect(configured.discovery.publicRegistrationOrganizationId, 'org_local');

    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_PUBLIC_REGISTRATION_ORGANIZATION_ID': 'not-an-organization',
      }),
      throwsArgumentError,
    );
  });

  test('database and object configuration are injectable', () {
    final config = ControlPlaneConfig.fromEnvironment(<String, String>{
      'HYFENS_HOST': '0.0.0.0',
      'HYFENS_PORT': '19081',
      'HYFENS_DATABASE_URL': 'postgresql://example/db',
      'HYFENS_ARTIFACT_ENDPOINT': 'http://object-store:9000/',
      'HYFENS_ARTIFACT_ACCESS_KEY': 'access',
      'HYFENS_ARTIFACT_SECRET_KEY': 'secret',
      'HYFENS_ARTIFACT_BUCKET': 'bucket',
    });
    expect(config.usesPostgres, isTrue);
    expect(config.port, 19081);
    expect(config.artifactEndpoint, Uri.parse('http://object-store:9000/'));
    expect(config.artifactBucket, 'bucket');
  });

  test('database components build a URI without requiring a plaintext URL', () {
    final config = ControlPlaneConfig.fromEnvironment(<String, String>{
      'HYFENS_DATABASE_HOST': 'writer.example.internal',
      'HYFENS_DATABASE_USER': 'hyfens',
      'HYFENS_DATABASE_PASSWORD': 'secret with spaces',
      'HYFENS_DATABASE_NAME': 'control_plane',
    });
    expect(config.databaseUrl, contains('writer.example.internal'));
    expect(config.databaseUrl, contains('secret%20with%20spaces'));
    expect(config.usesPostgres, isTrue);
  });

  test('task-role object authentication is explicit and exclusive', () {
    final config = ControlPlaneConfig.fromEnvironment(<String, String>{
      'HYFENS_ARTIFACT_ENDPOINT': 'https://s3.ap-south-1.amazonaws.com/',
      'HYFENS_ARTIFACT_USE_TASK_ROLE': 'true',
    });
    expect(config.artifactUseTaskRole, isTrue);
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_ARTIFACT_USE_TASK_ROLE': 'true',
        'HYFENS_ARTIFACT_ACCESS_KEY': 'static',
        'HYFENS_ARTIFACT_SECRET_KEY': 'static',
      }),
      throwsArgumentError,
    );
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_ARTIFACT_USE_TASK_ROLE': 'true',
      }),
      throwsArgumentError,
    );
  });

  test('invalid limits and ports fail closed', () {
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_PORT': '0',
      }),
      throwsArgumentError,
    );
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_MAX_JSON_BYTES': '-1',
      }),
      throwsArgumentError,
    );
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_ARTIFACT_ACCESS_KEY': 'only-one',
      }),
      throwsArgumentError,
    );
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_ARTIFACT_ENDPOINT': 'ftp://object-store.example/',
      }),
      throwsArgumentError,
    );
  });
}
