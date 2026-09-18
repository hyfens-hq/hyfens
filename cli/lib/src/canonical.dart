import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

String canonicalJson(Object? value) {
  Object? normalize(Object? current) {
    if (current is Map<Object?, Object?>) {
      final map = <String, Object?>{};
      for (final entry in current.entries) {
        if (entry.key is! String) {
          throw FormatException('Canonical maps require string keys');
        }
        map[entry.key! as String] = entry.value;
      }
      final keys = map.keys.toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: normalize(map[key]),
      };
    }
    if (current is List<Object?>) {
      return current.map(normalize).toList(growable: false);
    }
    return current;
  }

  return jsonEncode(normalize(value));
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String digestJson(Object? value) =>
    sha256Hex(utf8.encode(canonicalJson(value)));

String relativePath(Directory root, FileSystemEntity entity) {
  final rootPath = p.normalize(root.absolute.path);
  final entityPath = p.normalize(entity.absolute.path);
  final result = p.relative(entityPath, from: rootPath).replaceAll(r'\', '/');
  if (result == '..' || result.startsWith('../')) {
    throw FormatException('Path escapes project root: $entityPath');
  }
  return result;
}

bool isWithin(Directory root, FileSystemEntity entity) {
  final rootPath = p.normalize(root.absolute.path);
  final entityPath = p.normalize(entity.absolute.path);
  return entityPath == rootPath || p.isWithin(rootPath, entityPath);
}

List<File> listDartFiles(Directory root, {int maxFiles = 50000}) {
  if (!root.existsSync()) return const <File>[];
  final files = <File>[];
  void visit(Directory directory) {
    if (files.length > maxFiles) {
      throw const FormatException('Source traversal exceeded file limit');
    }
    final entries = directory.listSync(followLinks: false)
      ..sort((left, right) => left.path.compareTo(right.path));
    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (name == '.dart_tool' || name == '.git' || name == 'build') continue;
      switch (FileSystemEntity.typeSync(entry.path, followLinks: false)) {
        case FileSystemEntityType.directory:
          visit(Directory(entry.path));
        case FileSystemEntityType.file:
          if (p.extension(entry.path) == '.dart') files.add(File(entry.path));
        case FileSystemEntityType.link:
        case FileSystemEntityType.notFound:
          // Symlinks and disappearing entries are not followed by the tool.
          break;
      }
    }
  }

  visit(root);
  files.sort((left, right) => left.path.compareTo(right.path));
  return List.unmodifiable(files);
}

Future<void> writeAtomicBytes(File destination, List<int> bytes) async {
  final parent = destination.absolute.parent;
  await parent.create(recursive: true);
  final temporary = File(
    '${destination.path}.tmp-${pid}-${DateTime.now().microsecondsSinceEpoch}',
  );
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(destination.path);
  } finally {
    if (temporary.existsSync()) await temporary.delete();
  }
}

Future<void> writeAtomicText(File destination, String text) =>
    writeAtomicBytes(destination, utf8.encode(text));

String? firstMatchingLine(String source, RegExp expression) {
  for (final line in const LineSplitter().convert(source)) {
    final match = expression.firstMatch(line);
    if (match != null) return match.group(1);
  }
  return null;
}
