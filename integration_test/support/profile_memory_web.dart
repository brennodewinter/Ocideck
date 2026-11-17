import 'dart:async';
import 'dart:js_interop';
import 'package:integration_test/integration_test.dart';

@JS('performance.memory.usedJSHeapSize')
external double? get _usedJsHeap;
@JS('navigator.userAgent')
external String get _userAgent;

String get profilePlatform => 'web';
Map<String, Object> profileMemory(String phase) {
  double? used;
  try {
    used = _usedJsHeap;
  } catch (_) {
    // Not all browsers expose this Chromium-specific diagnostic.
  }
  return {
    'browser': _userAgent,
    'memory_metric':
        'performance.memory JS heap; excludes WASM and renderer memory',
    if (used != null) 'js_heap_${phase}_bytes': used.toInt(),
    if (used == null) 'memory_unavailable': 'performance.memory not exposed',
  };
}

@JS('requestAnimationFrame')
external int _requestFrame(JSFunction callback);
@JS('cancelAnimationFrame')
external void _cancelFrame(int id);

/// Browser presentation cadence, not native build/raster timings. In particular
/// a long JS task delays the next rAF even when the engine reports no frames.
Future<void> profileWatchPerformance(
  IntegrationTestWidgetsFlutterBinding binding,
  Future<void> Function() action, {
  required String reportKey,
}) async {
  final intervals = <double>[];
  final first = Completer<void>();
  double? previous;
  var handle = 0;
  late JSFunction callback;
  callback = ((double timestamp) {
    if (previous != null) intervals.add(timestamp - previous!);
    previous = timestamp;
    if (!first.isCompleted) first.complete();
    handle = _requestFrame(callback);
  }).toJS;
  handle = _requestFrame(callback);
  try {
    await first.future.timeout(const Duration(seconds: 10));
    await action().timeout(const Duration(minutes: 2));
    final presented = Completer<void>();
    _requestFrame(((double _) => presented.complete()).toJS);
    await presented.future.timeout(const Duration(seconds: 10));
  } finally {
    _cancelFrame(handle);
  }
  if (intervals.isEmpty) {
    throw StateError('Browser produced no presentation intervals');
  }
  intervals.sort();
  binding.reportData ??= {};
  binding.reportData![reportKey] = {
    'metric':
        'requestAnimationFrame presentation intervals; not native raster/build timings',
    'samples_ms': intervals,
    'median_ms': intervals[intervals.length ~/ 2],
    'p95_ms': intervals[((intervals.length - 1) * .95).ceil()],
    'max_ms': intervals.last,
    'over_20_ms': intervals.where((value) => value > 20).length,
  };
}
