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
    expect(config.deploymentModel, DeploymentModel.selfHosted);
    expect(config.billingProvider, isNull);
  });

  test('empty optional billing environment remains disabled', () {
    final config = ControlPlaneConfig.fromEnvironment(<String, String>{
      'HYFENS_BILLING_PROVIDER_TOKEN_HASH': '',
      'HYFENS_RAZORPAY_STARTER_PLAN_ID': '',
      'HYFENS_RAZORPAY_TEAM_PLAN_ID': '',
      'HYFENS_RAZORPAY_WEBHOOK_SECRET': '',
      'HYFENS_RAZORPAY_CURRENCY': '',
      'HYFENS_RAZORPAY_STARTER_AMOUNT_MINOR': '',
      'HYFENS_RAZORPAY_TEAM_AMOUNT_MINOR': '',
    });
    expect(config.billingProvider, isNull);
    expect(config.razorpayBilling, isNull);
  });

  test('billing provider bridge uses a hashed deployment credential', () {
    const token = 'billing-bridge-test-token';
    final hash = CredentialService.tokenHash(token);
    final bridge = BillingProviderBridgeConfig.fromEnvironment(<String, String>{
      'HYFENS_BILLING_PROVIDER_TOKEN_HASH': hash,
    });
    expect(bridge, isNotNull);
    expect(bridge!.matches(token), isTrue);
    expect(bridge.matches('another-token'), isFalse);
    expect(bridge.principal.id, 'billing-provider');
    expect(bridge.principal.scopes, contains(billingProviderScope));
    expect(
      () => BillingProviderBridgeConfig.fromEnvironment(<String, String>{
        'HYFENS_BILLING_PROVIDER_TOKEN_HASH': 'not-a-sha256',
      }),
      throwsArgumentError,
    );
  });

  test('Cloud deployment mode is explicit and bounded', () {
    final config = ControlPlaneConfig.fromEnvironment(<String, String>{
      'HYFENS_DEPLOYMENT_MODEL': 'cloud',
    });
    expect(config.deploymentModel, DeploymentModel.cloud);
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_DEPLOYMENT_MODEL': 'self-hosted',
      }),
      throwsArgumentError,
    );
  });

  test('Razorpay checkout requires explicit currency configuration', () {
    expect(
      () => RazorpayBillingConfig.fromEnvironment(<String, String>{
        'HYFENS_RAZORPAY_STARTER_PLAN_ID': 'rzp_plan_starter',
        'HYFENS_RAZORPAY_TEAM_PLAN_ID': 'rzp_plan_team',
        'HYFENS_RAZORPAY_WEBHOOK_SECRET': 'secret',
      }),
      throwsArgumentError,
    );
    final config = RazorpayBillingConfig.fromEnvironment(<String, String>{
      'HYFENS_RAZORPAY_STARTER_PLAN_ID': 'rzp_plan_starter',
      'HYFENS_RAZORPAY_TEAM_PLAN_ID': 'rzp_plan_team',
      'HYFENS_RAZORPAY_WEBHOOK_SECRET': 'secret',
      'HYFENS_RAZORPAY_CURRENCY': 'USD',
      'HYFENS_RAZORPAY_STARTER_AMOUNT_MINOR': '4900',
      'HYFENS_RAZORPAY_TEAM_AMOUNT_MINOR': '19900',
    });
    expect(config, isNotNull);
    expect(config!.currency, 'USD');
    expect(config.starterAmountMinor, 4900);
    expect(config.teamAmountMinor, 19900);
    expect(
      () => RazorpayBillingConfig.fromEnvironment(<String, String>{
        'HYFENS_RAZORPAY_STARTER_PLAN_ID': 'rzp_plan_starter',
        'HYFENS_RAZORPAY_TEAM_PLAN_ID': 'rzp_plan_team',
        'HYFENS_RAZORPAY_WEBHOOK_SECRET': 'secret',
        'HYFENS_RAZORPAY_CURRENCY': 'INR',
        'HYFENS_RAZORPAY_STARTER_AMOUNT_MINOR': '4900',
        'HYFENS_RAZORPAY_TEAM_AMOUNT_MINOR': '19900',
      }),
      throwsArgumentError,
    );
    expect(
      () => RazorpayBillingConfig(
        starterPlanId: 'rzp_plan_starter',
        teamPlanId: 'rzp_plan_team',
        webhookSecret: 'secret',
        currency: 'INR',
        starterAmountMinor: 4900,
        teamAmountMinor: 19900,
      ),
      throwsArgumentError,
    );
  });

  test('runtime acceptance environments are explicit and bounded', () {
    final config = ControlPlaneConfig.fromEnvironment(<String, String>{
      'HYFENS_RUNTIME_ACCEPTANCE_ENVIRONMENTS': 'env_dev, env_test,env_dev',
    });
    expect(config.runtimeAcceptanceEnvironmentIds, <String>{
      'env_dev',
      'env_test',
    });
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_RUNTIME_ACCEPTANCE_ENVIRONMENTS': 'env_dev,,env_test',
      }),
      throwsArgumentError,
    );
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_RUNTIME_ACCEPTANCE_ENVIRONMENTS': 'ENV_DEV',
      }),
      throwsArgumentError,
    );
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

  test('managed Cloud signup requires explicit verification delivery', () {
    final token = List<String>.filled(32, 'a').join();
    final configured = ControlPlaneConfig.fromEnvironment(<String, String>{
      'HYFENS_CLOUD_SIGNUP_ENABLED': 'true',
      'HYFENS_CLOUD_SIGNUP_VERIFICATION_URL':
          'https://app.hyfens.com/verify-email',
      'HYFENS_CLOUD_SIGNUP_EMAIL_WEBHOOK_URL':
          'https://mail.example.test/hyfens',
      'HYFENS_CLOUD_SIGNUP_EMAIL_WEBHOOK_TOKEN': token,
      'HYFENS_CLOUD_SIGNUP_VERIFICATION_TTL_MINUTES': '45',
    });
    expect(configured.cloudOnboarding.enabled, isTrue);
    expect(
      configured.cloudOnboarding.verificationUrl,
      Uri.parse('https://app.hyfens.com/verify-email'),
    );
    expect(
      configured.cloudOnboarding.verificationTtl,
      const Duration(minutes: 45),
    );

    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_CLOUD_SIGNUP_ENABLED': 'true',
        'HYFENS_CLOUD_SIGNUP_VERIFICATION_URL':
            'https://app.hyfens.com/verify-email',
      }),
      throwsArgumentError,
    );
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_CLOUD_SIGNUP_ENABLED': 'true',
        'HYFENS_CLOUD_SIGNUP_VERIFICATION_URL':
            'https://app.hyfens.com/verify-email',
        'HYFENS_CLOUD_SIGNUP_EMAIL_WEBHOOK_URL':
            'https://mail.example.test/hyfens',
        'HYFENS_CLOUD_SIGNUP_EMAIL_WEBHOOK_TOKEN': 'too-short',
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

  test('artifact admission configuration is neutral and fail-closed', () {
    final unconfigured = ControlPlaneConfig.fromEnvironment(<String, String>{});
    expect(unconfigured.artifactAdmissionRequired, isFalse);
    expect(unconfigured.artifactAdmissionUrl, isNull);
    expect(unconfigured.artifactAdmissionServiceToken, isNull);

    final token = List<String>.filled(32, 'a').join();
    final configured = ControlPlaneConfig.fromEnvironment(<String, String>{
      'HYFENS_ARTIFACT_ADMISSION_URL':
          'http://127.0.0.1:18192/internal/runtime/artifact-admission',
      'HYFENS_ARTIFACT_ADMISSION_SERVICE_TOKEN': token,
      'HYFENS_ARTIFACT_ADMISSION_REQUIRED': 'true',
    });
    expect(
      configured.artifactAdmissionUrl,
      Uri.parse('http://127.0.0.1:18192/internal/runtime/artifact-admission'),
    );
    expect(configured.artifactAdmissionServiceToken, token);
    expect(configured.artifactAdmissionRequired, isTrue);

    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_ARTIFACT_ADMISSION_REQUIRED': 'true',
      }),
      throwsArgumentError,
    );
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_ARTIFACT_ADMISSION_URL':
            'http://admission.example/internal/runtime/artifact-admission',
        'HYFENS_ARTIFACT_ADMISSION_SERVICE_TOKEN': token,
      }),
      throwsArgumentError,
    );
    expect(
      () => ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_ARTIFACT_ADMISSION_URL':
            'https://admission.example/internal/runtime/artifact-admission?x=1',
        'HYFENS_ARTIFACT_ADMISSION_SERVICE_TOKEN': token,
      }),
      throwsArgumentError,
    );
    const invalidToken = 'short-secret';
    try {
      ControlPlaneConfig.fromEnvironment(<String, String>{
        'HYFENS_ARTIFACT_ADMISSION_URL':
            'https://admission.example/internal/runtime/artifact-admission',
        'HYFENS_ARTIFACT_ADMISSION_SERVICE_TOKEN': invalidToken,
      });
      fail('expected invalid artifact admission token');
    } on ArgumentError catch (error) {
      expect(error.toString(), isNot(contains(invalidToken)));
    }
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
