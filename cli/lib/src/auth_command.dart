import 'dart:io';

import 'package:args/command_runner.dart';

import 'auth_client.dart';
import 'auth_storage.dart';
import 'cli_runner.dart';
import 'diagnostics.dart';
import 'profile.dart';

typedef AuthPrompt = Future<String> Function(
  String message, {
  required bool secret,
});

Future<String> defaultAuthPrompt(String message, {required bool secret}) async {
  stdout.write(message);
  if (!secret || !stdin.hasTerminal) {
    return stdin.readLineSync() ?? '';
  }
  final previousEchoMode = stdin.echoMode;
  try {
    stdin.echoMode = false;
    return stdin.readLineSync() ?? '';
  } finally {
    stdin.echoMode = previousEchoMode;
    stdout.writeln();
  }
}

final class AuthCommand extends Command<void> {
  AuthCommand(this.runner) {
    addSubcommand(AuthLoginCommand(runner));
    addSubcommand(AuthStatusCommand(runner));
    addSubcommand(AuthLogoutCommand(runner));
  }

  final HyfensCommandRunner runner;

  @override
  String get name => 'auth';

  @override
  String get description => 'Manage the local human CLI session.';

  @override
  Future<void> run() async {}
}

/// Public canonical login command. The legacy `auth login` command below is
/// retained for scripts that still use the original password-session surface.
final class LoginCommand extends _AuthCommand {
  LoginCommand(super.runner) {
    argParser
      ..addOption(
        'host',
        help:
            'Control-plane API base. Defaults to managed Cloud (${managedCloudApiBase}).',
      )
      ..addOption('profile', help: 'Named profile to create or activate.')
      ..addFlag(
        'device',
        help: 'Use the advertised short-lived device authorization flow.',
      )
      ..addOption(
        'email',
        help:
            'Compatibility password-login email; otherwise use browser login.',
      )
      ..addOption('ca-cert', help: 'PEM CA certificate or HYFENS_TLS_CA_CERT.');
  }

  @override
  String get name => 'login';

  @override
  String get description =>
      'Sign in to managed Cloud or an explicit self-hosted control plane.';

  @override
  Future<void> run() async {
    if (argResults!['device'] == true && argResults!['email'] != null) {
      throw UsageException(
        'hyfens login --device cannot be combined with --email',
        usage,
      );
    }
    final profileName = argResults!['profile'] as String?;
    if (profileName != null &&
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(profileName)) {
      throw UsageException('Invalid --profile name.', usage);
    }
    final configuredHost = optionOrEnvironment(
      'host',
      'HYFENS_CONTROL_PLANE_URL',
    );
    final namedProfile = configuredHost == null && profileName != null
        ? await runner.authClient.storage.readNamedProfile(profileName)
        : null;
    final hostValue =
        configuredHost ??
        namedProfile?.endpoint.toString() ??
        managedCloudApiBase;
    final target = endpoint(hostValue, operation: 'login');
    final caCertPath = optionOrEnvironment('ca-cert', 'HYFENS_TLS_CA_CERT');
    late final AuthLoginResult result;
    if (argResults!['device'] == true) {
      result = await runner.authClient.loginDevice(
        endpoint: target,
        profileName: profileName,
        caCertPath: caCertPath,
        onPrompt: (prompt) {
          final destination = jsonMode ? runner.err : runner.out;
          destination.writeln('Open ${prompt.verificationUri}');
          destination.writeln('Enter code: ${prompt.userCode}');
        },
      );
    } else {
      final email = optionOrEnvironment('email', 'HYFENS_AUTH_EMAIL');
      if (email != null) {
        result = await runner.authClient.login(
          endpoint: target,
          email: email,
          password: await prompt('Password: ', secret: true),
          profileName: profileName,
          caCertPath: caCertPath,
        );
      } else {
        result = await runner.authClient.loginBrowser(
          endpoint: target,
          profileName: profileName,
          caCertPath: caCertPath,
        );
      }
    }
    if (jsonMode) {
      runner.writeJson(<String, Object?>{
        'result': 'LOGGED_IN',
        'profile': result.profile.toJson(),
      });
      return;
    }
    runner.write('Logged in');
    writeProfile(result.profile);
  }
}

final class LogoutCommand extends _AuthCommand {
  LogoutCommand(super.runner) {
    argParser
      ..addOption('host', help: 'Optional control-plane API base.')
      ..addOption('ca-cert', help: 'PEM CA certificate or HYFENS_TLS_CA_CERT.');
  }

  @override
  String get name => 'logout';

  @override
  String get description =>
      'Revoke the active session and remove its local secret.';

  @override
  Future<void> run() async {
    final hostValue = optionOrEnvironment('host', 'HYFENS_CONTROL_PLANE_URL');
    await runner.authClient.logout(
      endpoint: hostValue == null
          ? null
          : endpoint(hostValue, operation: 'logout'),
      caCertPath: optionOrEnvironment('ca-cert', 'HYFENS_TLS_CA_CERT'),
    );
    if (jsonMode) {
      runner.writeJson(<String, String>{'result': 'LOGGED_OUT'});
      return;
    }
    runner.write('Logged out');
  }
}

final class ProfileCommand extends Command<void> {
  ProfileCommand(this.runner) {
    addSubcommand(ProfileListCommand(runner));
    addSubcommand(ProfileShowCommand(runner));
    addSubcommand(ProfileUseCommand(runner));
    addSubcommand(ProfileRemoveCommand(runner));
    addSubcommand(ProfileCurrentCommand(runner));
  }

  final HyfensCommandRunner runner;

  @override
  String get name => 'profile';

  @override
  String get description =>
      'List and select non-secret control-plane profiles.';

  @override
  Future<void> run() async {}
}

abstract base class _ProfileCommand extends Command<void> {
  _ProfileCommand(this.runner) {
    argParser.addFlag('json', help: 'Emit machine-readable JSON.');
  }

  final HyfensCommandRunner runner;

  bool get jsonMode => runner.jsonMode || argResults?['json'] == true;

  AuthStorage get storage => runner.authClient.storage;

  Future<ProfileSet> catalogForDisplay() async {
    final catalog = await storage.readProfileCatalog();
    if (catalog.profiles.isNotEmpty) return catalog;
    final cloud = ControlPlaneProfile(
      name: managedCloudProfileName,
      endpoint: Uri.parse(managedCloudApiBase),
      managed: true,
    );
    return ProfileSet(
      activeProfile: cloud.name,
      profiles: <ControlPlaneProfile>[cloud],
    );
  }

  String requiredName() {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.length != 1 || rest.single.isEmpty) {
      throw UsageException('Expected exactly one profile name.', usage);
    }
    return rest.single;
  }

  void writeProfileJson(ControlPlaneProfile profile) =>
      runner.writeJson(profile.toJson());

  void writeProfileText(ControlPlaneProfile profile, {String? prefix}) {
    if (prefix != null) runner.write(prefix);
    runner.write('Name:         ${profile.name}');
    runner.write('Endpoint:     ${profile.endpoint}');
    runner.write('Managed:      ${profile.managed}');
    if (profile.organizationId != null) {
      runner.write('Organization: ${profile.organizationId}');
    }
    if (profile.applicationId != null) {
      runner.write('Application:  ${profile.applicationId}');
    }
    if (profile.environmentId != null) {
      runner.write('Environment:  ${profile.environmentId}');
    }
  }
}

final class ProfileListCommand extends _ProfileCommand {
  ProfileListCommand(super.runner);

  @override
  String get name => 'list';

  @override
  String get description => 'List available profiles.';

  @override
  Future<void> run() async {
    final catalog = await catalogForDisplay();
    if (jsonMode) {
      runner.writeJson(<String, Object?>{
        'active_profile': catalog.active.name,
        'profiles': catalog.profiles
            .map((profile) => profile.toJson())
            .toList(),
      });
      return;
    }
    runner.write('Profiles');
    for (final profile in catalog.profiles) {
      final marker = profile.name == catalog.active.name ? '*' : ' ';
      runner.write('$marker ${profile.name}  ${profile.endpoint}');
    }
  }
}

final class ProfileShowCommand extends _ProfileCommand {
  ProfileShowCommand(super.runner);

  @override
  String get name => 'show';

  @override
  String get description => 'Show one profile without credential material.';

  @override
  Future<void> run() async {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.length > 1)
      throw UsageException('Expected at most one profile name.', usage);
    final catalog = await catalogForDisplay();
    final profile = rest.isEmpty ? catalog.active : catalog.byName(rest.single);
    if (profile == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'A1025',
        summary: 'Profile does not exist',
        detail: rest.single,
        action: 'Run hyfens profile list to see available profiles.',
      );
    }
    if (jsonMode) {
      writeProfileJson(profile);
    } else {
      writeProfileText(profile);
    }
  }
}

final class ProfileCurrentCommand extends _ProfileCommand {
  ProfileCurrentCommand(super.runner);

  @override
  String get name => 'current';

  @override
  String get description => 'Show the active profile.';

  @override
  Future<void> run() async {
    final catalog = await catalogForDisplay();
    if (jsonMode) {
      writeProfileJson(catalog.active);
    } else {
      writeProfileText(catalog.active, prefix: 'Current profile');
    }
  }
}

final class ProfileUseCommand extends _ProfileCommand {
  ProfileUseCommand(super.runner);

  @override
  String get name => 'use';

  @override
  String get description => 'Make one profile active.';

  @override
  Future<void> run() async {
    final name = requiredName();
    final catalog = await storage.readProfileCatalog();
    if (catalog.profiles.isEmpty && name == managedCloudProfileName) {
      await storage.writeNamedProfile(
        ControlPlaneProfile(
          name: managedCloudProfileName,
          endpoint: Uri.parse(managedCloudApiBase),
          managed: true,
        ),
      );
    } else {
      await storage.useProfile(name);
    }
    if (jsonMode) {
      runner.writeJson(<String, Object?>{
        'result': 'PROFILE_SELECTED',
        'active_profile': name,
      });
    } else {
      runner.write('Active profile: $name');
    }
  }
}

final class ProfileRemoveCommand extends _ProfileCommand {
  ProfileRemoveCommand(super.runner);

  @override
  String get name => 'remove';

  @override
  String get description => 'Remove a named profile and its bound session.';

  @override
  Future<void> run() async {
    final name = requiredName();
    final catalog = await storage.readProfileCatalog();
    if (catalog.profiles.isEmpty && name == managedCloudProfileName) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'A1028',
        summary: 'The managed Cloud default is implicit',
        detail: 'There is no persisted profile named $name to remove.',
        action: 'Remove a persisted profile created with --profile.',
      );
    }
    await storage.removeNamedProfile(name);
    if (jsonMode) {
      runner.writeJson(<String, Object?>{
        'result': 'PROFILE_REMOVED',
        'profile': name,
      });
    } else {
      runner.write('Removed profile: $name');
    }
  }
}

abstract base class _AuthCommand extends Command<void> {
  _AuthCommand(this.runner) {
    argParser.addFlag('json', help: 'Emit machine-readable JSON.');
  }

  final HyfensCommandRunner runner;

  bool get jsonMode =>
      runner.jsonMode ||
      argResults?['json'] == true ||
      globalResults?['json'] == true;

  bool get nonInteractive => globalResults?['non-interactive'] == true;

  String? optionOrEnvironment(String option, String environment) {
    final optionValue = argResults?[option] as String?;
    if (optionValue != null && optionValue.isNotEmpty) return optionValue;
    final environmentValue = Platform.environment[environment];
    return environmentValue == null || environmentValue.isEmpty
        ? null
        : environmentValue;
  }

  Uri endpoint(String value, {String operation = 'login'}) {
    final parsed = Uri.tryParse(value);
    if (parsed == null) {
      throw UsageException(
        'auth endpoint must be an absolute HTTP or HTTPS URL',
        usage,
      );
    }
    // _authUri performs the same validation for requests; this early check
    // keeps command errors in the usage category before prompting.
    if ((parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty) {
      throw UsageException(
        'auth endpoint must be an absolute HTTP or HTTPS URL without embedded credentials',
        usage,
      );
    }
    return validateControlPlaneEndpoint(parsed, operation: operation);
  }

  Future<String> prompt(String message, {required bool secret}) async {
    if (nonInteractive) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'A1019',
        summary: 'Auth login requires interactive input',
        detail: 'A password was not supplied.',
        action: 'Run without --non-interactive and enter the password when prompted.',
      );
    }
    final value = await runner.authPrompt(message, secret: secret);
    if (value.isEmpty) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'A1008',
        summary: 'Login input is incomplete',
        detail: 'The prompted value was empty.',
        action: 'Retry with a non-empty value.',
      );
    }
    return value;
  }

  void writeProfile(Profile profile) {
    if (profile.email != null) runner.write('  Email:        ${profile.email}');
    if (profile.displayName != null) {
      runner.write('  Name:         ${profile.displayName}');
    }
    if (profile.userId != null)
      runner.write('  User ID:      ${profile.userId}');
    if (profile.organizationId != null) {
      runner.write('  Organization:  ${profile.organizationId}');
    }
    runner.write('  Endpoint:     ${profile.endpoint}');
  }
}

final class AuthLoginCommand extends _AuthCommand {
  AuthLoginCommand(super.runner) {
    argParser
      ..addOption(
        'endpoint',
        help: 'Control-plane URL or HYFENS_CONTROL_PLANE_URL.',
      )
      ..addOption(
        'email',
        help: 'Account email; otherwise prompt interactively.',
      )
      ..addOption('ca-cert', help: 'PEM CA certificate or HYFENS_TLS_CA_CERT.');
  }

  @override
  String get name => 'login';

  @override
  String get description => 'Create and store one human CLI session.';

  @override
  Future<void> run() async {
    final endpointValue = optionOrEnvironment(
      'endpoint',
      'HYFENS_CONTROL_PLANE_URL',
    );
    if (endpointValue == null) {
      throw UsageException(
        'auth login requires --endpoint or HYFENS_CONTROL_PLANE_URL',
        usage,
      );
    }
    endpoint(endpointValue);
    final requestEndpoint = Uri.parse(endpointValue);
    final email =
        optionOrEnvironment('email', 'HYFENS_AUTH_EMAIL') ??
        await prompt('Email: ', secret: false);
    final password = await prompt('Password: ', secret: true);
    final result = await runner.authClient.login(
      endpoint: requestEndpoint,
      email: email,
      password: password,
      caCertPath: optionOrEnvironment('ca-cert', 'HYFENS_TLS_CA_CERT'),
    );
    if (jsonMode) {
      runner.writeJson(<String, Object?>{
        'result': 'LOGGED_IN',
        'profile': result.profile.toJson(),
      });
      return;
    }
    runner.write('Logged in');
    writeProfile(result.profile);
  }
}

final class AuthStatusCommand extends _AuthCommand {
  AuthStatusCommand(super.runner);

  @override
  String get name => 'status';

  @override
  String get description => 'Show local human-session profile metadata.';

  @override
  Future<void> run() async {
    final profile = await runner.authClient.status();
    final loggedIn = profile != null;
    if (jsonMode) {
      runner.writeJson(<String, Object?>{
        'result': loggedIn ? 'LOGGED_IN' : 'NOT_LOGGED_IN',
        'profile': profile?.toJson(),
      });
      return;
    }
    if (!loggedIn) {
      runner.write('Not logged in');
      return;
    }
    runner.write('Logged in');
    writeProfile(profile);
  }
}

final class AuthLogoutCommand extends _AuthCommand {
  AuthLogoutCommand(super.runner) {
    argParser
      ..addOption(
        'endpoint',
        help: 'Optional control-plane URL or HYFENS_CONTROL_PLANE_URL.',
      )
      ..addOption('ca-cert', help: 'PEM CA certificate or HYFENS_TLS_CA_CERT.');
  }

  @override
  String get name => 'logout';

  @override
  String get description => 'Revoke the session and remove local auth data.';

  @override
  Future<void> run() async {
    final endpointValue = optionOrEnvironment(
      'endpoint',
      'HYFENS_CONTROL_PLANE_URL',
    );
    await runner.authClient.logout(
      endpoint: endpointValue == null ? null : endpoint(endpointValue),
      caCertPath: optionOrEnvironment('ca-cert', 'HYFENS_TLS_CA_CERT'),
    );
    if (jsonMode) {
      runner.writeJson(<String, String>{'result': 'LOGGED_OUT'});
      return;
    }
    runner.write('Logged out');
  }
}
