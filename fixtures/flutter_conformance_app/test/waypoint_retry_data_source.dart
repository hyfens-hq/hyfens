import 'package:alphax/alphax.dart';
import 'package:conformance/waypoint/data/waypoint_data_source.dart';

import 'waypoint_test_support.dart';

final class WaypointFailOnceDataSource implements WaypointDataSource {
  WaypointFailOnceDataSource({Object? failure})
    : _failure = failure ?? StateError('Test home load failure'),
      _successSource = WaypointTestDataSource();

  final Object _failure;
  final WaypointTestDataSource _successSource;
  int homeLoadAttempts = 0;
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
    if (path == '/api/home') {
      homeLoadAttempts++;
      if (!_hasFailed) {
        _hasFailed = true;
        throw _failure;
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
