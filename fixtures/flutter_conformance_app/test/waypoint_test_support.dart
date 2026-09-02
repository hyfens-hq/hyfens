import 'dart:async';

import 'package:alphax/alphax.dart';
import 'package:conformance/waypoint/application/waypoint_providers.dart';
import 'package:conformance/waypoint/data/waypoint_data_source.dart';
import 'package:conformance/waypoint/data/waypoint_repository.dart';
import 'package:conformance/waypoint/platform/waypoint_permission.dart';
import 'package:conformance/waypoint/platform/waypoint_permission_result.dart';
import 'package:conformance/waypoint/platform/waypoint_permission_service.dart';
import 'package:conformance/waypoint/presentation/waypoint_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class WaypointTestDataSource implements WaypointDataSource {
  WaypointTestDataSource({Map<String, Object?>? home})
    : _home = home ?? waypointTestHomePayload();

  final Map<String, Object?> _home;
  final List<String> requestedPaths = <String>[];
  bool isClosed = false;

  @override
  String get modeLabel => 'Test memory';

  @override
  bool get isDemo => true;

  @override
  String get transportLabel => 'In-memory fixture';

  @override
  Future<Object?> readJson(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    AlphaXCancellationToken? cancellationToken,
  }) async {
    requestedPaths.add(path);
    cancellationToken?.throwIfCancelled();
    if (path == '/api/home') {
      return _home;
    }
    if (path == '/api/search') {
      return <String, Object?>{
        'destinations': _destinations
            .where((destination) {
              final query = queryParameters['q']?.trim().toLowerCase() ?? '';
              if (query.isEmpty) {
                return true;
              }
              final haystack = <String>[
                destination['name'] as String,
                destination['country'] as String,
                destination['category'] as String,
                destination['locationLabel'] as String,
                destination['summary'] as String,
              ].join(' ').toLowerCase();
              return haystack.contains(query);
            })
            .toList(growable: false),
      };
    }
    if (path.startsWith('/api/trips/')) {
      final id = path.split('/').last;
      return _trips.singleWhere((trip) => trip['id'] == id);
    }
    throw StateError('Unexpected Waypoint test route: $path');
  }

  @override
  Stream<Object?> streamJson(
    String path, {
    AlphaXCancellationToken? cancellationToken,
  }) async* {
    requestedPaths.add(path);
    cancellationToken?.throwIfCancelled();
    if (path != '/api/activity') {
      throw StateError('Unexpected Waypoint test stream: $path');
    }
    for (final activity in _activities) {
      cancellationToken?.throwIfCancelled();
      yield activity;
    }
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }

  List<Map<String, Object?>> get _destinations =>
      _asMaps(_home['destinations']);

  List<Map<String, Object?>> get _trips => _asMaps(_home['trips']);

  List<Map<String, Object?>> get _activities => _asMaps(_home['activities']);
}

final class WaypointActivityCancellationDataSource
    implements WaypointDataSource {
  WaypointActivityCancellationDataSource()
    : _delegate = WaypointTestDataSource();

  static const firstActivityTitle = 'Activity received before stop';
  static const lateActivityTitle = 'Late activity after stop';

  final WaypointTestDataSource _delegate;
  final Completer<void> started = Completer<void>();
  final Completer<void> _releaseGate = Completer<void>();
  bool cancellationObserved = false;

  @override
  String get modeLabel => _delegate.modeLabel;

  @override
  bool get isDemo => _delegate.isDemo;

  @override
  String get transportLabel => _delegate.transportLabel;

  @override
  Future<Object?> readJson(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    AlphaXCancellationToken? cancellationToken,
  }) => _delegate.readJson(
    path,
    queryParameters: queryParameters,
    cancellationToken: cancellationToken,
  );

  @override
  Stream<Object?> streamJson(
    String path, {
    AlphaXCancellationToken? cancellationToken,
  }) async* {
    if (path != '/api/activity') {
      yield* _delegate.streamJson(path, cancellationToken: cancellationToken);
      return;
    }

    try {
      cancellationToken?.throwIfCancelled();
      yield <String, Object?>{
        'id': 'activity-before-stop',
        'title': firstActivityTitle,
        'detail': 'This update arrived before the feed was stopped.',
        'timeLabel': 'Just now',
        'iconName': 'photo',
        'accentColor': '#B9DED2',
      };
      if (!started.isCompleted) {
        started.complete();
      }
      await _releaseGate.future;
      cancellationToken?.throwIfCancelled();
    } on AlphaXCancellationException {
      cancellationObserved = true;
      rethrow;
    }

    yield <String, Object?>{
      'id': 'activity-after-stop',
      'title': lateActivityTitle,
      'detail': 'This update must never appear after the feed was stopped.',
      'timeLabel': 'A moment later',
      'iconName': 'photo',
      'accentColor': '#E47755',
    };
  }

  void release() {
    if (!_releaseGate.isCompleted) {
      _releaseGate.complete();
    }
  }

  @override
  Future<void> close() => _delegate.close();
}

final class WaypointSearchFailOnceDataSource implements WaypointDataSource {
  WaypointSearchFailOnceDataSource()
    : _successSource = WaypointTestDataSource();

  final WaypointTestDataSource _successSource;
  int searchAttempts = 0;
  bool _hasFailed = false;

  @override
  String get modeLabel => _successSource.modeLabel;

  @override
  bool get isDemo => _successSource.isDemo;

  @override
  String get transportLabel => _successSource.transportLabel;

  @override
  Future<Object?> readJson(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    AlphaXCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    if (path == '/api/search') {
      searchAttempts++;
      if (!_hasFailed) {
        _hasFailed = true;
        throw StateError('Test search failure');
      }
    }
    return _successSource.readJson(
      path,
      queryParameters: queryParameters,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Stream<Object?> streamJson(
    String path, {
    AlphaXCancellationToken? cancellationToken,
  }) => _successSource.streamJson(path, cancellationToken: cancellationToken);

  @override
  Future<void> close() => _successSource.close();
}

final class WaypointSearchRaceDataSource implements WaypointDataSource {
  WaypointSearchRaceDataSource() : _delegate = WaypointTestDataSource();

  final WaypointTestDataSource _delegate;
  final Completer<void> _firstSearchGated = Completer<void>();
  final Completer<void> _releaseGate = Completer<void>();

  Future<void> get firstSearchGated => _firstSearchGated.future;

  @override
  String get modeLabel => _delegate.modeLabel;

  @override
  bool get isDemo => _delegate.isDemo;

  @override
  String get transportLabel => _delegate.transportLabel;

  @override
  Future<Object?> readJson(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    AlphaXCancellationToken? cancellationToken,
  }) async {
    final response = await _delegate.readJson(
      path,
      queryParameters: queryParameters,
      cancellationToken: cancellationToken,
    );
    final query = queryParameters['q']?.trim() ?? '';
    if (path == '/api/search' &&
        query.isNotEmpty &&
        !_firstSearchGated.isCompleted) {
      _firstSearchGated.complete();
      await _releaseGate.future;
    }
    return response;
  }

  @override
  Stream<Object?> streamJson(
    String path, {
    AlphaXCancellationToken? cancellationToken,
  }) => _delegate.streamJson(path, cancellationToken: cancellationToken);

  void releaseFirstSearch() {
    if (!_releaseGate.isCompleted) {
      _releaseGate.complete();
    }
  }

  @override
  Future<void> close() => _delegate.close();
}

final class WaypointActivityFailOnceDataSource implements WaypointDataSource {
  WaypointActivityFailOnceDataSource()
    : _successSource = WaypointTestDataSource();

  final WaypointTestDataSource _successSource;
  int activityAttempts = 0;
  bool _hasFailed = false;

  @override
  String get modeLabel => _successSource.modeLabel;

  @override
  bool get isDemo => _successSource.isDemo;

  @override
  String get transportLabel => _successSource.transportLabel;

  @override
  Future<Object?> readJson(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    AlphaXCancellationToken? cancellationToken,
  }) => _successSource.readJson(
    path,
    queryParameters: queryParameters,
    cancellationToken: cancellationToken,
  );

  @override
  Stream<Object?> streamJson(
    String path, {
    AlphaXCancellationToken? cancellationToken,
  }) {
    if (path == '/api/activity') {
      activityAttempts++;
      if (!_hasFailed) {
        _hasFailed = true;
        return Stream<Object?>.error(
          StateError('Test activity stream failure'),
        );
      }
    }
    return _successSource.streamJson(
      path,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<void> close() => _successSource.close();
}

final class WaypointTestPermissionService implements WaypointPermissionService {
  WaypointTestPermissionService({
    Map<WaypointPermission, WaypointPermissionStatus>? statuses,
  }) : statuses = <WaypointPermission, WaypointPermissionStatus>{...?statuses};

  final Map<WaypointPermission, WaypointPermissionStatus> statuses;
  final List<WaypointPermission> readPermissions = <WaypointPermission>[];
  final List<WaypointPermission> requested = <WaypointPermission>[];
  int openSettingsCalls = 0;

  @override
  Future<WaypointPermissionResult> read(WaypointPermission permission) async {
    readPermissions.add(permission);
    return _result(permission);
  }

  @override
  Future<WaypointPermissionResult> request(
    WaypointPermission permission,
  ) async {
    requested.add(permission);
    return _result(permission);
  }

  @override
  Future<bool> openAppSettings() async {
    openSettingsCalls++;
    return true;
  }

  WaypointPermissionResult _result(WaypointPermission permission) =>
      WaypointPermissionResult(
        permission: permission,
        status: statuses[permission] ?? WaypointPermissionStatus.denied,
      );
}

Future<void> pumpWaypointTestApp(
  WidgetTester tester, {
  WaypointDataSource? dataSource,
  WaypointTestPermissionService? permissionService,
}) async {
  final source = dataSource ?? WaypointTestDataSource();
  final permissions = permissionService ?? WaypointTestPermissionService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        waypointRepositoryProvider.overrideWithValue(
          WaypointRepository(source),
        ),
        waypointPermissionServiceProvider.overrideWithValue(permissions),
      ],
      child: const WaypointApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Map<String, Object?> waypointTestHomePayload() => <String, Object?>{
  'destinations': <Object?>[
    <String, Object?>{
      'id': 'kyoto',
      'name': 'Kyoto',
      'country': 'Japan',
      'summary': 'Quiet lanes, good tea, and a slower morning rhythm.',
      'category': 'Culture',
      'kind': 'culture',
      'locationLabel': 'Kyoto, Japan',
      'rating': 4.9,
      'durationLabel': '4 days',
      'imageAsset': 'assets/images/waypoint/kyoto.svg',
      'accentColor': '#D9D1EC',
      'tags': <Object?>['tea houses', 'temples'],
      'saved': false,
    },
    <String, Object?>{
      'id': 'lisbon',
      'name': 'Lisbon',
      'country': 'Portugal',
      'summary':
          'Sunlit streets, tiled facades, and a table worth lingering at.',
      'category': 'Food',
      'kind': 'food',
      'locationLabel': 'Lisbon, Portugal',
      'rating': 4.8,
      'durationLabel': '5 days',
      'imageAsset': 'assets/images/waypoint/lisbon.svg',
      'accentColor': '#E47755',
      'tags': <Object?>['markets', 'coast'],
      'saved': false,
    },
  ],
  'trips': <Object?>[
    <String, Object?>{
      'id': 'kyoto-trip',
      'title': 'A thoughtful Kyoto week',
      'destination': 'Kyoto',
      'dateRange': 'May 12–16, 2027',
      'durationLabel': '4 nights',
      'imageAsset': 'assets/images/waypoint/kyoto.svg',
      'progress': 0.65,
      'itinerary': <Object?>[
        <String, Object?>{
          'timeLabel': '09:00',
          'title': 'Morning tea in Gion',
          'detail': 'A quiet start before the lanes get busy.',
          'category': 'Food',
          'isComplete': true,
        },
      ],
      'checklist': <Object?>['Rail pass', 'Stay', 'Tea reservation'],
    },
  ],
  'activities': <Object?>[
    <String, Object?>{
      'id': 'saved-kyoto',
      'title': 'Kyoto saved to your shortlist',
      'detail': 'You can compare it with the rest of your ideas later.',
      'timeLabel': 'Just now',
      'iconName': 'bookmark',
      'accentColor': '#D9D1EC',
    },
  ],
  'offer': <String, Object?>{
    'id': 'spring-brief',
    'title': 'A little room to wander',
    'message':
        'Tell us the shape of your next escape and we will make a brief.',
    'actionLabel': 'Start a planning brief',
    'expiresAt': '2099-12-31T23:59:59.000Z',
    'accentColor': '#B9DED2',
  },
  'actions': <Object?>[
    <String, Object?>{
      'id': 'photo-check',
      'type': 'media',
      'title': 'Test a photo handoff',
      'subtitle': 'Keep camera and photo-library checks in settings.',
      'submitLabel': 'Test media',
    },
  ],
};

List<Map<String, Object?>> _asMaps(Object? value) => (value as List)
    .map((entry) => Map<String, Object?>.from(entry as Map))
    .toList(growable: false);
