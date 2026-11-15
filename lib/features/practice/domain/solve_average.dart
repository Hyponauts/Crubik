import 'solve_record.dart';
import 'solve_method.dart';

enum SolveAverageKind {
  ao5(5, 1),
  ao12(12, 1),
  ao100(100, 5);

  const SolveAverageKind(this.windowSize, this.trimCount);

  final int windowSize;
  final int trimCount;

  String get label => name.toUpperCase();
}

enum SolveAverageStatus { completed, dnf, unavailable }

/// One rolling average, anchored to the newest solve in its window.
final class SolveAverageRecord {
  const SolveAverageRecord({
    required this.kind,
    required this.endSolveId,
    required this.sessionId,
    required this.createdAt,
    required this.status,
    this.elapsed,
  });

  final SolveAverageKind kind;
  final String endSolveId;
  final String sessionId;
  final DateTime createdAt;
  final SolveAverageStatus status;
  final Duration? elapsed;

  String get id => '${kind.name}:$endSolveId';
}

/// Calculates WCA-style trimming without changing or copying solve evidence.
final class SolveAverageWindow {
  SolveAverageWindow._(
    this.record,
    List<SolveRecord> solves,
    List<SolveRecord> includedSolves,
    List<SolveRecord> excludedBest,
    List<SolveRecord> excludedWorst,
  ) : solves = List.unmodifiable(solves),
      includedSolves = List.unmodifiable(includedSolves),
      excludedBest = List.unmodifiable(excludedBest),
      excludedWorst = List.unmodifiable(excludedWorst);

  final SolveAverageRecord record;
  final List<SolveRecord> solves;
  final List<SolveRecord> includedSolves;
  final List<SolveRecord> excludedBest;
  final List<SolveRecord> excludedWorst;

  static SolveAverageWindow? calculate(
    SolveAverageKind kind,
    List<SolveRecord> newestFirst,
  ) {
    if (newestFirst.length < kind.windowSize) return null;
    final window = newestFirst.take(kind.windowSize).toList();
    final ranked = _rank(window, kind.trimCount);
    final excludedBest = ranked.best;
    final excludedWorst = ranked.worst;
    final included = ranked.included;
    final anchor = window.first;
    final dnfCount = window
        .where((solve) => solve.outcome != SolveOutcome.completed)
        .length;
    final status = dnfCount > kind.trimCount
        ? SolveAverageStatus.dnf
        : window.any(
            (solve) =>
                solve.outcome == SolveOutcome.completed &&
                !solve.isTimingReliable,
          )
        ? SolveAverageStatus.unavailable
        : SolveAverageStatus.completed;

    Duration? elapsed;
    if (status == SolveAverageStatus.completed) {
      final totalCentiseconds = included.fold<int>(
        0,
        (sum, solve) => sum + solve.elapsed.inMilliseconds ~/ 10,
      );
      final roundedCentiseconds =
          (totalCentiseconds + included.length ~/ 2) ~/ included.length;
      elapsed = Duration(milliseconds: roundedCentiseconds * 10);
    }
    return SolveAverageWindow._(
      SolveAverageRecord(
        kind: kind,
        endSolveId: anchor.id,
        sessionId: anchor.sessionId,
        createdAt: anchor.createdAt,
        status: status,
        elapsed: elapsed,
      ),
      window,
      status == SolveAverageStatus.completed ? included : const [],
      excludedBest,
      excludedWorst,
    );
  }

  /// Uses the Ao100 trim for a full window, or the nearest whole 5% per side
  /// while fewer than 100 solves are available. This comparison is not saved
  /// as an official Ao100 result until the window is complete.
  static List<SolveRecord> comparisonSolves(List<SolveRecord> newestFirst) {
    final window = newestFirst.take(SolveAverageKind.ao100.windowSize).toList();
    if (window.isEmpty) return const [];
    final trimCount = (window.length * 0.05).round().clamp(
      0,
      (window.length - 1) ~/ 2,
    );
    return List.unmodifiable(_rank(window, trimCount).included);
  }
}

({List<SolveRecord> best, List<SolveRecord> worst, List<SolveRecord> included})
_rank(List<SolveRecord> window, int trimCount) {
  final sorted = [...window]..sort(_compareResults);
  return (
    best: sorted.take(trimCount).toList(),
    worst: sorted.reversed.take(trimCount).toList(),
    included: sorted.sublist(trimCount, window.length - trimCount),
  );
}

final class SolveAverageStage {
  const SolveAverageStage({
    required this.kind,
    required this.recognitionTime,
    required this.executionTime,
    required this.stepTime,
    required this.turns,
    required this.turnsPerSecond,
    required this.regrips,
    required this.sampleCount,
  });

  final SolveStageKind kind;
  final Duration? recognitionTime;
  final Duration? executionTime;
  final Duration? stepTime;
  final double turns;
  final double? turnsPerSecond;
  final double? regrips;
  final int sampleCount;
}

final class SolveAverageDetails {
  SolveAverageDetails({
    required this.eligibleSolveCount,
    required List<SolveAverageStage> stages,
    required this.metrics,
  }) : stages = List.unmodifiable(stages);

  final int eligibleSolveCount;
  final List<SolveAverageStage> stages;
  final SolveAverageMetrics metrics;
}

final class SolveAverageMetrics {
  const SolveAverageMetrics({
    required this.inspectionTime,
    required this.recognitionTime,
    required this.executionTime,
    required this.turns,
    required this.turnsPerSecond,
    required this.skippedStages,
    required this.regrips,
  });

  final Duration? inspectionTime;
  final Duration? recognitionTime;
  final Duration? executionTime;
  final double? turns;
  final double? turnsPerSecond;
  final double? skippedStages;
  final double? regrips;
}

int _compareResults(SolveRecord first, SolveRecord second) {
  final firstRank = first.outcome == SolveOutcome.completed
      ? first.isTimingReliable
            ? 0
            : 1
      : 2;
  final secondRank = second.outcome == SolveOutcome.completed
      ? second.isTimingReliable
            ? 0
            : 1
      : 2;
  if (firstRank != secondRank) return firstRank.compareTo(secondRank);
  if (firstRank != 0) return first.createdAt.compareTo(second.createdAt);
  final timeOrder = (first.elapsed.inMilliseconds ~/ 10).compareTo(
    second.elapsed.inMilliseconds ~/ 10,
  );
  return timeOrder != 0
      ? timeOrder
      : first.createdAt.compareTo(second.createdAt);
}
