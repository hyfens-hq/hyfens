/// Local process exclusion for startup, administrator, and periodic
/// reconciliation invocations.
///
/// This is deliberately a reject-while-active gate rather than a queue. A
/// caller that cannot enter must retry through its own bounded policy; no
/// unbounded work is accumulated in memory.
final class ReconciliationExecutionBusy implements Exception {
  const ReconciliationExecutionBusy();

  @override
  String toString() => 'ReconciliationExecutionBusy';
}

final class ReconciliationExecutionGate {
  bool _active = false;

  bool get isActive => _active;

  Future<T> run<T>(Future<T> Function() action) async {
    if (_active) throw const ReconciliationExecutionBusy();
    _active = true;
    try {
      return await action();
    } finally {
      _active = false;
    }
  }
}
