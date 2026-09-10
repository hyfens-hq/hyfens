import 'dart:async';
import 'dart:io';

import 'package:hyfens_control_plane/control_plane.dart';

Future<void> main(List<String> arguments) async {
  final options = _options(arguments);
  final values = <String, String>{...Platform.environment};
  final optionEnvironment = <String, String>{
    'root': 'HYFENS_FILE_ROOT',
    'host': 'HYFENS_HOST',
    'port': 'HYFENS_PORT',
    'database-url': 'HYFENS_DATABASE_URL',
    'artifact-endpoint': 'HYFENS_ARTIFACT_ENDPOINT',
    'artifact-bucket': 'HYFENS_ARTIFACT_BUCKET',
    'artifact-authorization': 'HYFENS_ARTIFACT_AUTHORIZATION',
    'artifact-access-key': 'HYFENS_ARTIFACT_ACCESS_KEY',
    'artifact-secret-key': 'HYFENS_ARTIFACT_SECRET_KEY',
    'artifact-region': 'HYFENS_ARTIFACT_REGION',
  };
  for (final entry in optionEnvironment.entries) {
    final value = options[entry.key];
    if (value != null) values[entry.value] = value;
  }
  final previewKey = options['preview-notification'];
  if (previewKey != null) {
    final rendered = NotificationPreview.render(key: previewKey);
    stdout.writeln(rendered.html);
    stdout.writeln('\n--- PLAIN TEXT ---\n');
    stdout.writeln(rendered.text);
    return;
  }
  final config = ControlPlaneConfig.fromEnvironment(values);
  final taskRoleCredentials = config.artifactUseTaskRole
      ? EcsTaskRoleCredentialsProvider.fromEnvironment(environment: values)
      : null;
  final artifactStore = config.artifactEndpoint == null
      ? null
      : S3CompatibleArtifactStore(
          endpoint: config.artifactEndpoint!,
          bucket: config.artifactBucket,
          authorization: config.artifactAuthorization,
          accessKey: config.artifactAccessKey,
          secretKey: config.artifactSecretKey,
          credentialsProvider: taskRoleCredentials,
          keyPrefix: config.artifactKeyPrefix,
          region: config.artifactRegion,
        );
  final legacyEmailDelivery = KeplarsHumanMessageDelivery.fromEnvironment(
    values,
  );
  final store = config.databaseUrl == null
      ? FileControlPlaneStore(config.fileRoot)
      : PostgresControlPlaneStore(
          config.databaseUrl!,
          artifacts: artifactStore,
        );
  final notifications = NotificationService.fromEnvironment(
    store: store,
    values: values,
  );
  final queuedEmailDelivery = notifications?.canQueueSensitiveMessages == true
      ? notifications!.authMessageDelivery()
      : null;
  final HumanAuthMessageDelivery? authEmailDelivery =
      queuedEmailDelivery ?? legacyEmailDelivery;
  final HumanDeletionMessageDelivery? deletionEmailDelivery =
      queuedEmailDelivery ?? legacyEmailDelivery;
  final auth = config.auth == null
      ? null
      : HumanAuthService(
          store: store,
          config: config.auth!,
          messageDelivery: authEmailDelivery,
          deletionMessageDelivery: deletionEmailDelivery,
        );
  final configuredService = ControlPlaneService(
    store: store,
    humanAuth: auth,
    deploymentModel: config.deploymentModel,
    razorpayBilling: config.razorpayBilling,
    billingProvider: config.billingProvider,
    notifications: notifications,
    deletionPolicy: config.deletionPolicy,
  );
  await configuredService.initialize();
  if (options.containsKey('process-deletions')) {
    if (options.containsKey('bootstrap') ||
        options.containsKey('bootstrap-admin') ||
        options.containsKey('bootstrap-owner') ||
        options.containsKey('seed-demo')) {
      throw ArgumentError(
        '--process-deletions cannot be combined with a bootstrap mode',
      );
    }
    final deletion = configuredService.deletion;
    if (deletion == null) {
      throw StateError(
        '--process-deletions requires human authentication and deletion '
        'configuration',
      );
    }
    try {
      final processed = await deletion.processPendingDeletions(
        now: _deletionWorkerNow(options, values),
      );
      final counts = <String, int>{};
      for (final request in processed) {
        final status = request['status'];
        if (status is String) {
          counts[status] = (counts[status] ?? 0) + 1;
        }
      }
      stdout.write('deletion_worker_processed=${processed.length}');
      final entries = counts.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      for (final entry in entries) {
        stdout.write(' ${entry.key}=${entry.value}');
      }
      stdout.writeln();
    } finally {
      await store.close();
      taskRoleCredentials?.close();
    }
    return;
  }
  if (options.containsKey('process-notifications')) {
    if (options.containsKey('bootstrap') ||
        options.containsKey('bootstrap-admin') ||
        options.containsKey('bootstrap-owner') ||
        options.containsKey('seed-demo') ||
        options.containsKey('process-deletions')) {
      throw ArgumentError(
        '--process-notifications cannot be combined with another worker or bootstrap mode',
      );
    }
    final configuredNotifications = configuredService.notifications;
    if (configuredNotifications == null) {
      throw StateError(
        '--process-notifications requires a configured notification provider',
      );
    }
    try {
      final processed = await configuredNotifications.dispatchPending();
      stdout.writeln('notification_worker_processed=$processed');
    } finally {
      await store.close();
      taskRoleCredentials?.close();
    }
    return;
  }
  if (options.containsKey('seed-demo')) {
    if (options.containsKey('bootstrap') ||
        options.containsKey('bootstrap-admin') ||
        options.containsKey('bootstrap-owner')) {
      throw ArgumentError(
        '--seed-demo cannot be combined with another bootstrap mode',
      );
    }
    if (!options.containsKey('password-stdin')) {
      throw ArgumentError('--seed-demo requires --password-stdin');
    }
    final configuredAuth = configuredService.humanAuth;
    if (configuredAuth == null) {
      throw ArgumentError(
        '--seed-demo requires human authentication to be configured',
      );
    }
    final password = stdin.readLineSync();
    if (password == null) {
      throw ArgumentError(
        '--password-stdin requires one password line on stdin',
      );
    }
    final result = await DemoAccountSeeder(
      store: store,
      auth: configuredAuth,
      billingService: configuredService.billing,
    ).seed(password: password);
    stdout.writeln('seed=local-demo');
    stdout.writeln('organization_id=${result.organization.id}');
    stdout.writeln('application_id=${result.application.id}');
    stdout.writeln('environment_id=${result.environment.id}');
    stdout.writeln('human_owner_id=${result.owner.id}');
    stdout.writeln('human_owner_email=${result.owner.email}');
    stdout.writeln('human_owner_profile=$demoOwnerProfileName');
    await store.close();
    taskRoleCredentials?.close();
    return;
  }
  if (options.containsKey('bootstrap-admin')) {
    if (options.containsKey('bootstrap') ||
        options.containsKey('bootstrap-owner')) {
      throw ArgumentError(
        '--bootstrap-admin cannot be combined with another bootstrap mode',
      );
    }
    if (!options.containsKey('password-stdin')) {
      throw ArgumentError('--bootstrap-admin requires --password-stdin');
    }
    final password = stdin.readLineSync();
    if (password == null) {
      throw ArgumentError(
        '--password-stdin requires one password line on stdin',
      );
    }
    final admin = await configuredService.bootstrapAdmin(
      organizationId: _requiredOption(options, 'organization-id'),
      applicationId: _requiredOption(options, 'application-id'),
      environmentId: _requiredOption(options, 'environment-id'),
      email: _requiredOption(options, 'email'),
      password: password,
      profileName: options['profile'] ?? 'content-admin',
    );
    stdout.writeln('human_admin_id=${admin.id}');
    stdout.writeln('human_admin_email=${admin.email}');
    stdout.writeln(
      'human_admin_profile=${options['profile'] ?? 'content-admin'}',
    );
    await store.close();
    taskRoleCredentials?.close();
    return;
  }
  if (options.containsKey('bootstrap-owner')) {
    if (options.containsKey('bootstrap')) {
      throw ArgumentError(
        '--bootstrap-owner cannot be combined with --bootstrap',
      );
    }
    if (!options.containsKey('password-stdin')) {
      throw ArgumentError('--bootstrap-owner requires --password-stdin');
    }
    final password = stdin.readLineSync();
    if (password == null) {
      throw ArgumentError(
        '--password-stdin requires one password line on stdin',
      );
    }
    final owner = await configuredService.bootstrapOwner(
      organizationId: _requiredOption(options, 'organization-id'),
      applicationId: _requiredOption(options, 'application-id'),
      environmentId: _requiredOption(options, 'environment-id'),
      email: _requiredOption(options, 'email'),
      password: password,
      profileName: options['profile'] ?? 'demo',
    );
    stdout.writeln('human_owner_id=${owner.id}');
    stdout.writeln('human_owner_email=${owner.email}');
    stdout.writeln('human_owner_profile=${options['profile'] ?? 'demo'}');
    await store.close();
    taskRoleCredentials?.close();
    return;
  }
  if (options.containsKey('bootstrap')) {
    final result = await configuredService.bootstrap(
      organizationName: options['organization'] ?? 'Local organization',
      runtimeApplicationId: options['application'] ?? 'local.hyfens.app',
      platformId: options['platform'] ?? 'local-platform',
      environmentName: options['environment'] ?? 'development',
    );
    stdout.writeln('organization_id=${result.organization.id}');
    stdout.writeln('application_id=${result.application.id}');
    stdout.writeln('environment_id=${result.environment.id}');
    stdout.writeln('control_token=${result.controlCredential.token}');
    stdout.writeln('delivery_token=${result.deliveryCredential.token}');
    if (options.containsKey('bootstrap-only')) {
      await store.close();
      taskRoleCredentials?.close();
      return;
    }
  }
  final server = ControlPlaneHttpServer(
    configuredService,
    discovery: config.discovery,
    enterpriseInquiryNotifier: config.auth?.platformAdminEmails.isEmpty != false
        ? null
        : notifications != null
        ? (inquiry) => notifications
              .enqueueEnterpriseInquiry(
                recipients: config.auth!.platformAdminEmails,
                inquiry: inquiry,
              )
              .then((_) {})
        : legacyEmailDelivery == null
        ? null
        : (inquiry) => legacyEmailDelivery.sendEnterpriseInquiryNotification(
            recipients: config.auth!.platformAdminEmails,
            inquiry: inquiry,
          ),
    limits: ControlPlaneHttpLimits(
      maxJsonBodyBytes: config.maxJsonBodyBytes,
      maxArtifactBytes: config.maxArtifactBytes,
      maxRequestsPerMinute: config.rateLimitPerMinute,
    ),
    auditRetentionDays: config.auditRetentionDays,
    allowInsecureAuth: config.allowInsecureAuth,
    notificationProviderWebhookSecret: values['KEPLARS_WEBHOOK_SECRET'],
  );
  final bound = await server.bind(host: config.host, port: config.port);
  stdout.writeln(
    'hyfens control plane listening on ${bound.address.host}:${bound.port}',
  );
  final done = Completer<void>();
  for (final signal in <ProcessSignal>[
    ProcessSignal.sigint,
    ProcessSignal.sigterm,
  ]) {
    signal.watch().listen((_) {
      if (!done.isCompleted) done.complete();
    });
  }
  await done.future;
  await server.close(force: true);
  await store.close();
  taskRoleCredentials?.close();
}

DateTime? _deletionWorkerNow(
  Map<String, String> options,
  Map<String, String> values,
) {
  final raw = options['process-deletions-at'];
  if (raw == null) return null;
  if (values['HYFENS_DELETION_TEST_CLOCK'] != '1' ||
      values['RAZORPAY_MODE'] != 'test') {
    throw StateError(
      '--process-deletions-at is available only with '
      'HYFENS_DELETION_TEST_CLOCK=1 and RAZORPAY_MODE=test',
    );
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || !parsed.isUtc) {
    throw ArgumentError(
      '--process-deletions-at must be an ISO-8601 UTC timestamp ending in Z',
    );
  }
  return parsed;
}

Map<String, String> _options(List<String> arguments) {
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--bootstrap' || argument == '--bootstrap-only') {
      result['bootstrap'] = 'true';
      if (argument == '--bootstrap-only') result['bootstrap-only'] = 'true';
      continue;
    }
    if (argument == '--process-deletions' ||
        argument == '--process-notifications' ||
        argument == '--seed-demo' ||
        argument == '--bootstrap-admin' ||
        argument == '--bootstrap-owner' ||
        argument == '--password-stdin') {
      result[argument.substring(2)] = 'true';
      continue;
    }
    if (!argument.startsWith('--') || index + 1 >= arguments.length) {
      throw ArgumentError('Expected --name value or --bootstrap');
    }
    result[argument.substring(2)] = arguments[++index];
  }
  return result;
}

String _requiredOption(Map<String, String> options, String name) {
  final value = options[name];
  if (value == null || value.isEmpty) {
    throw ArgumentError('--$name is required');
  }
  return value;
}
