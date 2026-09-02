import 'dart:convert';

import 'package:alphax/alphax.dart';
import 'package:flutter/services.dart';

import 'waypoint_asset_paths.dart';
import 'waypoint_data_exception.dart';

abstract interface class WaypointDataSource {
  String get modeLabel;

  bool get isDemo;

  String get transportLabel;

  Future<Object?> readJson(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    AlphaXCancellationToken? cancellationToken,
  });

  Stream<Object?> streamJson(
    String path, {
    AlphaXCancellationToken? cancellationToken,
  });

  Future<void> close();
}

final class WaypointAlphaXDataSource implements WaypointDataSource {
  WaypointAlphaXDataSource({
    required this.client,
    required Uri baseUri,
    required this.modeLabel,
    this.isDemo = false,
  }) : baseUri = _withTrailingSlash(baseUri);

  final AlphaXClient client;
  final Uri baseUri;

  @override
  final String modeLabel;

  @override
  final bool isDemo;

  @override
  String get transportLabel => client.capabilities.transportName ?? 'Unknown';

  @override
  Future<Object?> readJson(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    AlphaXCancellationToken? cancellationToken,
  }) async {
    final response = await client.get(
      _uri(path, queryParameters),
      cancellationToken: cancellationToken,
      timeout: const AlphaXTimeouts(
        connect: Duration(seconds: 5),
        request: Duration(seconds: 8),
        read: Duration(seconds: 8),
      ),
    );
    if (!response.isSuccessful) {
      throw WaypointDataException(
        'Waypoint request failed',
        statusCode: response.statusCode,
      );
    }
    return response.readAsJson();
  }

  @override
  Stream<Object?> streamJson(
    String path, {
    AlphaXCancellationToken? cancellationToken,
  }) async* {
    final request = AlphaXRequest(
      method: HttpMethod.get,
      uri: _uri(path, const <String, String>{}),
      cancellationToken: cancellationToken,
      timeout: const AlphaXTimeouts(read: Duration(seconds: 10)),
    );
    var pending = '';
    await for (final event in client.sendStreaming(request)) {
      switch (event) {
        case AlphaXResponseStarted(:final statusCode):
          if (statusCode < 200 || statusCode >= 300) {
            throw WaypointDataException(
              'Waypoint activity stream failed',
              statusCode: statusCode,
            );
          }
        case AlphaXResponseChunk(:final bytes):
          pending += utf8.decode(bytes);
          final lines = pending.split('\n');
          pending = lines.removeLast();
          for (final line in lines) {
            if (line.trim().isNotEmpty) {
              yield jsonDecode(line);
            }
          }
        case AlphaXResponseCompleted():
          if (pending.trim().isNotEmpty) {
            yield jsonDecode(pending);
          }
      }
    }
  }

  @override
  Future<void> close() => client.close();

  Uri _uri(String path, Map<String, String> queryParameters) => baseUri
      .resolve(path)
      .replace(
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
      );

  static Uri _withTrailingSlash(Uri value) =>
      value.path.endsWith('/') ? value : value.replace(path: '${value.path}/');
}

final class WaypointUnavailableDataSource implements WaypointDataSource {
  const WaypointUnavailableDataSource(this.reason);

  final Object reason;

  @override
  String get modeLabel => 'Unavailable';

  @override
  bool get isDemo => false;

  @override
  String get transportLabel => 'Not configured';

  @override
  Future<Object?> readJson(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    AlphaXCancellationToken? cancellationToken,
  }) => Future<Object?>.error(reason);

  @override
  Stream<Object?> streamJson(
    String path, {
    AlphaXCancellationToken? cancellationToken,
  }) => Stream<Object?>.error(reason);

  @override
  Future<void> close() async {}
}

final class WaypointDemoTransport extends AlphaXTransport {
  WaypointDemoTransport({
    AssetBundle? assetBundle,
    this.latency = const Duration(milliseconds: 120),
  }) : assetBundle = assetBundle ?? rootBundle;

  final AssetBundle assetBundle;
  final Duration latency;
  bool _closed = false;

  @override
  AlphaXCapabilities get capabilities => const AlphaXCapabilities(
    transportName: 'Waypoint asset fixture',
    transportVersion: 'local-json-v1',
    http11: AlphaXSupport.supported,
    streamingDownload: AlphaXSupport.supported,
    protocolRequirement: AlphaXSupport.supported,
    negotiatedProtocolReporting: AlphaXSupport.supported,
  );

  @override
  Future<AlphaXResponse> send(AlphaXRequest request) async {
    _ensureOpen();
    request.cancellationToken?.throwIfCancelled();
    _enforceRequirement(request);
    await _delay(request.cancellationToken);
    final body = await _route(request);
    final bytes = utf8.encode(jsonEncode(body));
    return AlphaXResponse(
      statusCode: 200,
      headers: AlphaXHeaders.fromEntries(<MapEntry<String, String>>[
        const MapEntry<String, String>('content-type', 'application/json'),
        MapEntry<String, String>('content-length', '${bytes.length}'),
      ]),
      bodyBytes: bytes,
      protocol: AlphaXProtocol.http11,
      requestedProtocol: _requestedProtocol(request),
      requiredProtocol: request.protocolRequirement,
      metrics: AlphaXRequestMetrics(
        protocol: AlphaXProtocol.http11,
        totalDuration: latency,
        downloadedBytes: bytes.length,
      ),
    );
  }

  @override
  Stream<AlphaXEvent> sendStreaming(AlphaXRequest request) async* {
    _ensureOpen();
    request.cancellationToken?.throwIfCancelled();
    _enforceRequirement(request);
    final requestedProtocol = _requestedProtocol(request);
    final body = await _loadHome();
    final activities = _list(body['activities']);
    final headers = AlphaXHeaders.fromEntries(<MapEntry<String, String>>[
      const MapEntry<String, String>('content-type', 'application/x-ndjson'),
    ]);
    yield AlphaXResponseStarted(
      statusCode: 200,
      headers: headers,
      protocol: AlphaXProtocol.http11,
      requestedProtocol: requestedProtocol,
      requiredProtocol: request.protocolRequirement,
    );
    var bytesReceived = 0;
    for (final activity in activities) {
      request.cancellationToken?.throwIfCancelled();
      await _delay(request.cancellationToken);
      final bytes = utf8.encode('${jsonEncode(activity)}\n');
      bytesReceived += bytes.length;
      yield AlphaXResponseChunk(bytes);
    }
    yield AlphaXResponseCompleted(
      metrics: AlphaXRequestMetrics(
        protocol: AlphaXProtocol.http11,
        totalDuration: latency * activities.length,
        downloadedBytes: bytesReceived,
      ),
      bytesReceived: bytesReceived,
      requestedProtocol: requestedProtocol,
      requiredProtocol: request.protocolRequirement,
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  Future<Object?> _route(AlphaXRequest request) async {
    final path = request.uri.path;
    final home = await _loadHome();
    if (path == '/api/home') {
      return home;
    }
    if (path == '/api/search') {
      final query = request.uri.queryParameters['q']?.trim().toLowerCase();
      final destinations = _list(home['destinations'] ?? home['places'])
          .where((destination) {
            if (query == null || query.isEmpty) {
              return true;
            }
            final map = _map(destination);
            final haystack = <Object?>[
              map['name'],
              map['country'],
              map['category'],
              map['locationLabel'] ?? map['location'],
              map['description'] ?? map['summary'],
            ].join(' ').toLowerCase();
            return haystack.contains(query);
          })
          .toList(growable: false);
      return <String, Object?>{'destinations': destinations};
    }
    if (path == '/api/activity') {
      return <String, Object?>{'activities': home['activities']};
    }
    if (path.startsWith('/api/trips/')) {
      final id = path.split('/').last;
      return _list(home['trips']).firstWhere(
        (trip) => _map(trip)['id'] == id,
        orElse: () => throw WaypointDataException(
          'Waypoint trip not found',
          statusCode: 404,
        ),
      );
    }
    throw WaypointDataException('Waypoint demo route not found');
  }

  Future<Map<String, Object?>> _loadHome() async {
    final raw = await assetBundle.loadString(WaypointAssetPaths.homeJson);
    final home = _map(jsonDecode(raw));
    final tripsRaw = await assetBundle.loadString(WaypointAssetPaths.tripsJson);
    final supplementalTrips = _map(jsonDecode(tripsRaw));
    final homeTrips = _list(home['trips']);
    final knownTripIds = <Object?>{
      for (final trip in homeTrips) _map(trip)['id'],
    };
    final mergedTrips = <Object?>[...homeTrips];
    for (final trip in _list(supplementalTrips['trips'])) {
      final supplementalTrip = _map(trip);
      final tripId = supplementalTrip['id'];
      if (knownTripIds.add(tripId)) {
        mergedTrips.add(trip);
        continue;
      }
      for (final homeTrip in homeTrips) {
        final homeTripMap = _map(homeTrip);
        if (homeTripMap['id'] != tripId) {
          continue;
        }
        final homeDocuments = _list(
          homeTripMap['documents'] ?? const <Object?>[],
        );
        final supplementalDocuments = _list(
          supplementalTrip['documents'] ?? const <Object?>[],
        );
        final documentNames = <Object?>{
          for (final document in homeDocuments) _map(document)['name'],
        };
        final newDocuments = supplementalDocuments
            .where((document) => documentNames.add(_map(document)['name']))
            .toList(growable: false);
        if (newDocuments.isNotEmpty) {
          homeTripMap['documents'] = <Object?>[
            ...homeDocuments,
            ...newDocuments,
          ];
        }
        break;
      }
    }
    home['trips'] = mergedTrips;
    final discoverRaw = await assetBundle.loadString(
      WaypointAssetPaths.discoverJson,
    );
    final discover = _map(jsonDecode(discoverRaw));
    final homePlaces = _list(home['places'] ?? home['destinations']);
    final discoverPlaces = _list(discover['places']);
    home['places'] = <Object?>[...homePlaces, ...discoverPlaces];
    home['categories'] = discover['categories'] ?? const <Object?>[];
    home['collections'] = discover['collections'] ?? const <Object?>[];
    home['searchSuggestions'] =
        discover['searchSuggestions'] ?? const <Object?>[];
    home['discoverTitle'] = discover['title'];
    final actionsRaw = await assetBundle.loadString(
      WaypointAssetPaths.actionsJson,
    );
    final actions = _map(jsonDecode(actionsRaw));
    home['actions'] = actions['actions'];
    home['permissionActions'] = actions['permissions'];
    return home;
  }

  Future<void> _delay(AlphaXCancellationToken? token) async {
    token?.throwIfCancelled();
    if (latency == Duration.zero) {
      return;
    }
    await Future<void>.delayed(latency);
    token?.throwIfCancelled();
  }

  void _ensureOpen() {
    if (_closed) {
      throw const AlphaXClientClosedException(
        'Waypoint demo transport is closed',
      );
    }
  }

  void _enforceRequirement(AlphaXRequest request) {
    final requirement = request.protocolRequirement;
    if (requirement != null &&
        !requirement.isSatisfiedBy(AlphaXProtocol.http11)) {
      throw AlphaXProtocolRequirementException(
        requiredProtocol: requirement,
        actualProtocol: AlphaXProtocol.http11,
      );
    }
  }

  AlphaXProtocolPreference? _requestedProtocol(AlphaXRequest request) =>
      request.protocolPreference == AlphaXProtocolPreference.auto
      ? null
      : request.protocolPreference;

  List<Object?> _list(Object? value) {
    if (value is List<Object?>) {
      return value;
    }
    if (value is List) {
      return List<Object?>.from(value);
    }
    throw const FormatException('Waypoint fixture field was not a list');
  }

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const FormatException('Waypoint fixture was not an object');
  }
}
