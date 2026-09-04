import 'dart:io';

import 'package:path/path.dart' as p;

/// Package roots that a released CLI may need to overlay into a Flutter
/// application while building an instrumented release.
///
/// The source CLI resolves these packages from its Dart package graph. A
/// standalone release executable has no source checkout or package graph, so
/// the release archive carries the small runtime package bundle next to the
/// executable instead.
final class RuntimePackageBundle {
  RuntimePackageBundle._();

  static const repositoryPackagePaths = <String, String>{
    'hyfens_flutter_integration': 'packages/flutter_integration',
    'hyfens_patch_format': 'packages/patch_format',
    'hyfens_runtime': 'packages/runtime',
    'instrumentation_e0': 'experiments/instrumentation',
    'patch_loading_e1': 'experiments/patch_loading',
  };

  /// Hosted packages used by the generated Flutter runtime that may not be
  /// present in an otherwise ordinary Flutter application.
  static const hostedPackageNames = <String>[
    'collection',
    'crypto',
    'cryptography',
    'ffi',
    'meta',
    'typed_data',
  ];

  static const packageNames = <String>[
    'hyfens_flutter_integration',
    'hyfens_patch_format',
    'hyfens_runtime',
    'instrumentation_e0',
    'patch_loading_e1',
    ...hostedPackageNames,
  ];

  /// Returns valid package roots below a packaged runtime directory.
  static Map<String, Directory> packagesAt(Directory root) {
    final packages = <String, Directory>{};
    for (final name in packageNames) {
      final package = Directory(p.join(root.path, name));
      if (Directory(p.join(package.path, 'lib')).existsSync()) {
        packages[name] = package;
      }
    }
    return packages;
  }

  /// Finds the runtime bundle next to a release executable.
  ///
  /// The normal archive layout is `<root>/bin/hyfens` and
  /// `<root>/runtime/<package>`. Symlink resolution keeps Homebrew-style
  /// links working while the second candidate supports direct unpacked use.
  static Map<String, Directory> installedPackages() {
    final executable = File(Platform.resolvedExecutable);
    final roots = <Directory>[];
    try {
      final resolved = executable.resolveSymbolicLinksSync();
      roots.add(
        Directory(p.join(File(resolved).parent.parent.path, 'runtime')),
      );
    } on Object {
      // Fall back to the lexical executable path below.
    }
    roots.add(Directory(p.join(executable.parent.parent.path, 'runtime')));
    final seen = <String>{};
    for (final root in roots) {
      if (!seen.add(root.path)) continue;
      final packages = packagesAt(root);
      if (packages.containsKey('instrumentation_e0')) return packages;
    }
    return const <String, Directory>{};
  }
}
