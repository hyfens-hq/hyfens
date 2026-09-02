import 'dart:async';

import 'package:alphax/alphax.dart';
import 'package:conformance/waypoint/data/waypoint_data_source.dart';

import 'waypoint_test_support.dart';

final class WaypointLoadingDataSource implements WaypointDataSource {
  WaypointLoadingDataSource() : _delegate = WaypointTestDataSource();

  final WaypointTestDataSource _delegate;
  final Completer<void> _homeGate = Completer<void>();

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
    if (path == '/api/home') {
      await _homeGate.future;
    }
    return _delegate.readJson(
      path,
      queryParameters: queryParameters,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Stream<Object?> streamJson(
    String path, {
    AlphaXCancellationToken? cancellationToken,
  }) => _delegate.streamJson(path, cancellationToken: cancellationToken);

  void release() {
    if (!_homeGate.isCompleted) {
      _homeGate.complete();
    }
  }

  @override
  Future<void> close() => _delegate.close();
}
