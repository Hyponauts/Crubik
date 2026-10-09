import 'package:crubik/core/time/monotonic_clock.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';

final class PracticeTestClock implements SolveClock, MonotonicClock {
  PracticeTestClock({this.wallTime});

  final DateTime Function()? wallTime;
  final Stopwatch _stopwatch = Stopwatch()..start();
  Duration value = Duration.zero;

  @override
  Duration get now =>
      wallTime?.call().difference(DateTime.utc(2026)) ?? _stopwatch.elapsed;

  @override
  Duration get elapsed => value;

  @override
  void reset() => value = Duration.zero;

  @override
  void startAt(Duration hostTimestamp) {
    final initialElapsed = now - hostTimestamp;
    value = initialElapsed.isNegative ? Duration.zero : initialElapsed;
  }

  @override
  void stopAt(Duration hostTimestamp) {}
}
