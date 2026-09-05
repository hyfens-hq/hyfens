import 'dart:io';

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
    String? flavor,
    String? entrypointPath,
    Map<String, HyfensTargetBinding>? targetSelections,
    bool dryRun = false,
    bool force = false,
  }) async {
    final plannedProject = toolchain.project(projectPath: projectPath);
    final bindingFile = plannedProject.hyfensConfigFile;
    final existingBinding =
        HyfensProjectBinding.load(bindingFile) ??
        (plannedProject.workspaceHyfensConfigFile.path == bindingFile.path
            ? null
            : HyfensProjectBinding.load(
                plannedProject.workspaceHyfensConfigFile,
              ));
    if (existingBinding?.projectPath != null &&
        existingBinding!.projectPath != plannedProject.relativeProjectPath &&
        !force) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'H1209',
        summary: 'Persisted Flutter project selection is stale',
        detail:
            '${existingBinding.projectPath} != ${plannedProject.relativeProjectPath}',
        path: bindingFile.path,
        action: 'Run hyfens init --force after confirming the selected application.',
      );
    }
    final targets = <String>[
      if (Directory('${plannedProject.root.path}/android').existsSync())
        'android',
      if (Directory('${plannedProject.root.path}/ios').existsSync()) 'ios',
    ];
    final resolvedSelections = <String, HyfensTargetBinding>{};
    for (final target in targets) {
      final requested = targetSelections?[target];
      final persisted = existingBinding?.selectionFor(target);
      final selected = toolchain.resolveTarget(
        target: target,
        projectPath: plannedProject.root.path,
        flavor: requested?.flavor ?? flavor ?? persisted?.flavor,
        entrypointPath:
            requested?.entrypointPath ??
            entrypointPath ??
            persisted?.entrypointPath,
      );
      resolvedSelections[target] = HyfensTargetBinding(
        target: target,
        flavor: selected.flavor,
        entrypointPath: selected.entrypointPath,
      );
    }

    final identities = <String>{
      for (final selection in resolvedSelections.values)
        plannedProject.applicationIdFor(
          selection.target,
          flavor: selection.flavor,
        ),
      if (resolvedSelections.isEmpty) plannedProject.applicationId,
    };
    // Different native platform identities cannot share one runtime binding.
    // Their exact identities remain pinned in tool.yaml's per-target maps.
    final runtimeApplicationId = identities.length == 1
        ? identities.single
        : null;
    if (existingBinding?.runtimeApplicationId != null &&
        existingBinding!.runtimeApplicationId != runtimeApplicationId &&
        !force) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'H1205',
        summary:
            'Selected native application identity does not match hyfens.yaml',
        detail: 'The selected target identities differ from the existing runtime binding.',
        path: bindingFile.path,
        action: 'Review the exact application and run hyfens init --force. Existing releases must not be retargeted.',
      );
    }

    final result = await toolchain.init(
      projectPath: projectPath,
      applicationId: runtimeApplicationId,
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
    final sharedSelection = _sharedTargetSelection(resolvedSelections);
    final binding = HyfensProjectBinding(
      profile: activeProfile.name,
      organizationId: activeProfile.organizationId,
      applicationId: activeProfile.applicationId,
      environmentId: activeProfile.environmentId,
      runtimeApplicationId: runtimeApplicationId,
      projectPath: result.project.relativeProjectPath,
      flavor: sharedSelection?.flavor ?? flavor,
      entrypointPath: sharedSelection?.entrypointPath ?? entrypointPath,
      targetSelections: sharedSelection == null
          ? resolvedSelections
          : const <String, HyfensTargetBinding>{},
    );
    final actions = <String>[...result.actions];
    final selectionChanged =
        existingBinding == null ||
        existingBinding.projectPath != binding.projectPath ||
        existingBinding.runtimeApplicationId != binding.runtimeApplicationId ||
        existingBinding.flavor != binding.flavor ||
        existingBinding.entrypointPath != binding.entrypointPath ||
        !_sameTargetSelections(
          existingBinding.targetSelections,
          binding.targetSelections,
        );
    if (selectionChanged || force) {
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

HyfensTargetBinding? _sharedTargetSelection(
  Map<String, HyfensTargetBinding> selections,
) {
  if (selections.isEmpty) return null;
  final first = selections.values.first;
  return selections.values.every(
        (selection) =>
            selection.flavor == first.flavor &&
            selection.entrypointPath == first.entrypointPath,
      )
      ? first
      : null;
}

bool _sameTargetSelections(
  Map<String, HyfensTargetBinding> left,
  Map<String, HyfensTargetBinding> right,
) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    final other = right[entry.key];
    if (other == null ||
        other.flavor != entry.value.flavor ||
        other.entrypointPath != entry.value.entrypointPath) {
      return false;
    }
  }
  return true;
}
