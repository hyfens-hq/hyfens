import 'dart:convert';
import 'dart:io';

import 'package:hyfens_patch_format/patch_format.dart';
import 'package:patch_loading_e1/patch_loading_e1.dart';
import 'package:path/path.dart' as p;

import 'canonical.dart';
import 'configuration.dart';
import 'diagnostics.dart';
import 'project.dart';
import 'signing.dart';
import 'toolchain.dart';

/// Development-only artifact server. It intentionally has no authentication,
/// persistence, or deployment semantics and should be bound to loopback by
/// default.
final class PatchDevelopmentServer {
  PatchDevelopmentServer({required FlutterProject project, String? releaseId})
    : _project = project,
      _store = ToolStore(project),
      releaseId = releaseId;

  final FlutterProject _project;
  final ToolStore _store;
  final String? releaseId;

  Future<void> serve({
    String host = '127.0.0.1',
    int port = 18080,
    bool allowLan = false,
  }) async {
    final server = await bind(host: host, port: port, allowLan: allowLan);
    try {
      await for (final request in server) {
        await _handle(request);
      }
    } finally {
      await server.close(force: true);
    }
  }

  Future<HttpServer> bind({
    String host = '127.0.0.1',
    int port = 18080,
    bool allowLan = false,
  }) {
    final loopback =
        host == '127.0.0.1' || host == 'localhost' || host == '::1';
    if (!loopback && !allowLan) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.refused,
        code: 'T1701',
        summary: 'Development server host is not loopback',
        detail: host,
        action: 'Use loopback or pass --allow-lan after reviewing the local network boundary.',
      );
    }
    if (port < 0 || port > 65535) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'T1702',
        summary: 'Development server port is invalid',
        detail: '$port',
        action: 'Use a TCP port between 0 and 65535.',
      );
    }
    return HttpServer.bind(host, port, shared: false);
  }

  Future<void> handleRequest(HttpRequest request) => _handle(request);

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method != 'GET') {
        await _json(
          request.response,
          HttpStatus.methodNotAllowed,
          <String, Object?>{'result': 'METHOD_NOT_ALLOWED'},
        );
        return;
      }
      if (request.uri.path == '/health') {
        await _json(request.response, HttpStatus.ok, <String, Object?>{
          'service': 'hyfens-local-patch-server',
          'result': 'READY',
        });
        return;
      }
      if (request.uri.path == '/v1/check') {
        await _check(request);
        return;
      }
      if (request.uri.path == '/v1/patch') {
        await _patch(request);
        return;
      }
      if (request.uri.path == '/v1/control') {
        await _control(request);
        return;
      }
      await _json(request.response, HttpStatus.notFound, <String, Object?>{
        'result': 'NOT_FOUND',
      });
    } on ToolFailure catch (failure) {
      await _json(request.response, HttpStatus.badRequest, <String, Object?>{
        'result': 'ERROR',
        'diagnostics': failure.diagnostics
            .map((diagnostic) => diagnostic.toJson())
            .toList(growable: false),
      });
    } on Object catch (error) {
      await _json(
        request.response,
        HttpStatus.internalServerError,
        <String, Object?>{'result': 'ERROR', 'detail': '$error'},
      );
    }
  }

  Future<void> _check(HttpRequest request) async {
    final target = _targetRelease(request.uri);
    final artifact = await _latestPatch(target);
    if (artifact == null) {
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'result': 'NO_UPDATE',
        'releaseId': target,
      });
      return;
    }
    final currentSequence = int.tryParse(
      request.uri.queryParameters['sequence'] ?? '0',
    );
    if (currentSequence == null || currentSequence < 0) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'T1703',
        summary: 'Patch sequence query is invalid',
        detail: request.uri.queryParameters['sequence'] ?? '',
        action: 'Send a non-negative current sequence.',
      );
    }
    if (artifact.sequence <= currentSequence) {
      await _json(request.response, HttpStatus.ok, <String, Object?>{
        'result': 'NO_UPDATE',
        'releaseId': target,
        'sequence': artifact.sequence,
      });
      return;
    }
    await _json(request.response, HttpStatus.ok, <String, Object?>{
      'result': 'PATCH_AVAILABLE',
      'releaseId': target,
      'sequence': artifact.sequence,
      'patchId': artifact.patchId,
      'runtimeVersion': artifact.runtimeCompatibilityVersion,
      'formatVersion': patchFormatV1,
    });
  }

  Future<void> _patch(HttpRequest request) async {
    final target = _targetRelease(request.uri);
    final latest = await _latestPatch(target);
    if (latest == null) {
      await _json(request.response, HttpStatus.notFound, <String, Object?>{
        'result': 'NO_UPDATE',
        'releaseId': target,
      });
      return;
    }
    final currentSequence = int.tryParse(
      request.uri.queryParameters['sequence'] ?? '0',
    );
    if (currentSequence == null || currentSequence < 0) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'T1703',
        summary: 'Patch sequence query is invalid',
        detail: request.uri.queryParameters['sequence'] ?? '',
        action: 'Send a non-negative current sequence.',
      );
    }
    if (latest.sequence <= currentSequence) {
      await _json(request.response, HttpStatus.notFound, <String, Object?>{
        'result': 'NO_UPDATE',
        'releaseId': target,
      });
      return;
    }
    final response = request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('application', 'octet-stream')
      ..headers.contentLength = latest.bytes.length
      ..headers.set('x-hyfens-release', target)
      ..headers.set('x-hyfens-sequence', '${latest.sequence}')
      ..headers.set('x-hyfens-patch-id', latest.patchId);
    response.add(latest.bytes);
    await response.close();
  }

  Future<void> _control(HttpRequest request) async {
    final target = _targetRelease(request.uri);
    final file = _store.rollbackControl(target);
    if (!file.existsSync() ||
        FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
      request.response
        ..statusCode = HttpStatus.noContent
        ..contentLength = 0;
      await request.response.close();
      return;
    }
    try {
      final bytes = file.readAsBytesSync();
      final command = RollbackControlCommand.decode(bytes);
      final release = _store.readRelease(target);
      final config = ToolConfig.load(_project.configFile);
      final publicKey = const KeyStore().readPublic(
        _store.resolveConfiguredPath(config.publicKeyPath),
      );
      if (command.applicationId != release.applicationId ||
          command.releaseId != target ||
          command.keyId != publicKey.keyId ||
          !await command.verify(publicKey.publicKey)) {
        throw const FormatException('rollback control is not trusted');
      }
      final response = request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..headers.contentLength = bytes.length
        ..headers.set('x-hyfens-release', target)
        ..headers.set('x-hyfens-control', 'rollback-base');
      response.add(bytes);
      await response.close();
    } on Object {
      // A malformed or untrusted local control file is never delivered. The
      // detailed offline path remains `tool verify`/filesystem inspection.
      request.response
        ..statusCode = HttpStatus.noContent
        ..contentLength = 0;
      await request.response.close();
    }
  }

  String _targetRelease(Uri uri) {
    final requested = uri.queryParameters['release'];
    final target = requested ?? releaseId;
    if (target == null || target.isEmpty) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.usage,
        code: 'T1704',
        summary: 'Release ID is required by the development server',
        detail: uri.toString(),
        action: 'Pass ?release=<exact-release-id> or start the server for one release.',
      );
    }
    if (!RegExp(r'^[A-Za-z0-9:_-]{1,256}$').hasMatch(target)) {
      throw ToolFailure.single(
        exitCode: ToolExitCode.compatibility,
        code: 'R5002',
        summary: 'Release ID is invalid',
        detail: target,
        action: 'Use the exact release ID produced by hyfens release.',
      );
    }
    return target;
  }

  Future<_ServedPatch?> _latestPatch(String target) async {
    final directory = _store.patchDirectory(target);
    if (!directory.existsSync()) return null;
    final config = ToolConfig.load(_project.configFile);
    final publicKey = const KeyStore().readPublic(
      _store.resolveConfiguredPath(config.publicKeyPath),
    );
    final release = _store.readRelease(target);
    final candidates =
        directory
            .listSync(followLinks: false)
            .whereType<File>()
            .where(
              (file) =>
                  RegExp(r'^\d{6}\.patch$').hasMatch(p.basename(file.path)),
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final file in candidates.reversed) {
      try {
        final bytes = file.readAsBytesSync();
        final artifact = PatchFormatV1.decode(bytes);
        if (artifact.releaseId != target ||
            artifact.applicationId != release.applicationId ||
            artifact.signatureMetadata.keyId != publicKey.keyId ||
            !await publicKey.verify(
              PatchFormatV1.signingBytes(artifact),
              artifact.signature,
            )) {
          continue;
        }
        return _ServedPatch(
          bytes: bytes,
          sequence: artifact.sequence,
          patchId: artifact.patchId,
          runtimeCompatibilityVersion: artifact.runtimeCompatibilityVersion,
        );
      } on Object {
        // Ignore a corrupt local candidate; tool verify remains the detailed
        // operator path and the server must never deliver malformed bytes.
      }
    }
    return null;
  }

  Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    final bytes = utf8.encode(canonicalJson(body));
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.contentLength = bytes.length;
    response.add(bytes);
    await response.close();
  }
}

final class _ServedPatch {
  const _ServedPatch({
    required this.bytes,
    required this.sequence,
    required this.patchId,
    required this.runtimeCompatibilityVersion,
  });

  final List<int> bytes;
  final int sequence;
  final String patchId;
  final int runtimeCompatibilityVersion;
}
