/// A process-local monotonic time source.
///
/// Values are meaningful only when compared with values produced by the same
/// clock instance. They are never persisted directly; durable recordings store
/// offsets relative to the start of a solve.
abstract interface class MonotonicClock {
  Duration get now;
}

final class StopwatchMonotonicClock implements MonotonicClock {
  StopwatchMonotonicClock() {
    _stopwatch.start();
  }

  final Stopwatch _stopwatch = Stopwatch();

  @override
  Duration get now => _stopwatch.elapsed;
}
