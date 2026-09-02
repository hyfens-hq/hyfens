import 'auth_storage.dart';
import 'configuration.dart';
import 'diagnostics.dart';
import 'toolchain.dart';

/// Shared project-initialization result for the CLI and MCP adapters.
final class ProjectInitialization {
  const ProjectInitialization({
    required this.result,
    required this.binding,
    required this.actions,
  });

  final InitResult result;
  final HyfensProjectBinding binding;
  final List<String> actions;
}

/// Initializes the local tool metadata and the safe project/profile binding.
///
/// The terminal CLI and MCP adapter both use this service so an agent cannot
/// silently skip the same identity check or write a different project
/// contract than a human invoking `hyfens init`.
final class ProjectInitializationService {
  const ProjectInitializationService({
    required this.toolchain,
    required this.authStorage,
    this.profileName,
  });

  final HyfensToolchain toolchain;
  final AuthStorage authStorage;
  final String? profileName;

  Future<ProjectInitialization> initialize({
    String? projectPath,
    bool dryRun = false,
    bool force = false,
  }) async {
    final plannedProject = toolchain.project(projectPath: projectPath);
    final bindingFile = plannedProject.hyfensConfigFile;
    final existingBinding = HyfensProjectBinding.load(bindingFile);
    if (existingBinding != null &&
        existingBinding.runtimeApplicationId != null &&
        existingBinding.runtimeApplicationId != plannedProject.applicationId &&
        !force) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'H1205',
        summary: 'Project application identity does not match hyfens.yaml',
        detail:
            '${plannedProject.applicationId} != ${existingBinding.runtimeApplicationId}',
        path: bindingFile.path,
        action: 'Review the existing binding and pass --force only after confirming the exact application identity.',
      );
    }

    final result = await toolchain.init(
      projectPath: projectPath,
      dryRun: dryRun,
      force: force,
    );
    final activeProfile = profileName == null
        ? await authStorage.readActiveProfile()
        : await authStorage.readNamedProfile(profileName!);
    if (activeProfile == null) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'A1025',
        summary: 'Profile does not exist',
        detail: 'The requested MCP profile is not in the local catalog.',
        action: 'Run hyfens_profile_list and select an available profile.',
      );
    }
    final binding = HyfensProjectBinding(
      profile: activeProfile.name,
      organizationId: activeProfile.organizationId,
      applicationId: activeProfile.applicationId,
      environmentId: activeProfile.environmentId,
      runtimeApplicationId: result.project.applicationId,
    );
    final actions = <String>[...result.actions];
    if (existingBinding == null || force) {
      actions.add(
        '${existingBinding == null ? 'create' : 'replace'} ${result.project.relative(bindingFile)}',
      );
      if (!result.dryRun) {
        await writeHyfensBinding(bindingFile, binding: binding);
      }
    } else {
      actions.add('preserve ${result.project.relative(bindingFile)}');
    }
    return ProjectInitialization(
      result: result,
      binding: binding,
      actions: List.unmodifiable(actions),
    );
  }
}
