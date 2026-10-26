import 'dart:async';

class InsightsCancelled implements Exception {}

class InsightsException implements Exception {
  const InsightsException(this.message);
  final String message;
  @override
  String toString() => message;
}

class InsightsCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled;

  void check() {
    if (_cancelled) throw InsightsCancelled();
  }

  void Function() onCancel(void Function() callback) {
    if (_cancelled) {
      callback();
    } else {
      _listeners.add(callback);
    }
    return () => _listeners.remove(callback);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in _listeners.toList()) {
      callback();
    }
    _listeners.clear();
  }

  /// Cancels awaiting immediately; the operation must also release its I/O.
  Future<T> bind<T>(Future<T> operation) async {
    check();
    final stopped = Completer<T>();
    final unregister = onCancel(
      () => stopped.completeError(InsightsCancelled()),
    );
    try {
      return await Future.any([operation, stopped.future]);
    } finally {
      unregister();
    }
  }
}
