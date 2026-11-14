import '../domain/solve_analysis.dart';
import '../domain/solve_average.dart';
import '../domain/solve_method.dart';
import '../domain/solve_record.dart';

/// Pure aggregation shared by Single comparisons and rolling-average views.
final class SolveStatistics {
  const SolveStatistics._();

  static List<SolveAverageStage> averageStages(
    Iterable<SolveAnalysis?> analyses, {
    Iterable<SolveStageKind>? order,
  }) {
    final totals = <SolveStageKind, _StageTotals>{};
    for (final analysis in analyses) {
      if (analysis == null || !analysis.isComplete || analysis.isOutdated) {
        continue;
      }
      for (final stage in analysis.stages) {
        if (stage.skipped) continue;
        totals.putIfAbsent(stage.kind, _StageTotals.new).add(stage);
      }
    }

    return [
      for (final kind in order ?? totals.keys)
        if (totals[kind] case final total?) total.average(kind),
    ];
  }

  static SolveAverageMetrics averageMetrics({
    required List<SolveRecord> includedSolves,
    required List<SolveRecord> sameMethodSolves,
    required Map<String, SolveAnalysis?> analysesById,
  }) {
    final completeAnalyses = [
      for (final solve in sameMethodSolves)
        if (analysesById[solve.id] case final analysis?
            when analysis.isComplete && !analysis.isOutdated)
          analysis,
    ];
    return SolveAverageMetrics(
      inspectionTime: _meanDuration(
        includedSolves.map((solve) => solve.inspectionElapsed),
      ),
      recognitionTime: _meanDuration(
        completeAnalyses.map((analysis) => analysis.totalRecognitionTime),
      ),
      executionTime: _meanDuration(
        completeAnalyses.map((analysis) => analysis.totalExecutionTime),
      ),
      turns: _mean(
        includedSolves.map(
          (solve) => solve.turnCountFor(analysesById[solve.id]).toDouble(),
        ),
      ),
      turnsPerSecond: _mean(
        includedSolves.map(
          (solve) => solve.turnsPerSecondFor(analysesById[solve.id]),
        ),
      ),
      skippedStages: _mean(
        completeAnalyses.map(
          (analysis) => analysis.skippedStageCount.toDouble(),
        ),
      ),
      regrips: _mean(completeAnalyses.map(_totalRegrips)),
    );
  }
}

final class _StageTotals {
  int recognitionMicroseconds = 0;
  int recognitionSamples = 0;
  int executionMicroseconds = 0;
  int executionSamples = 0;
  int stepMicroseconds = 0;
  int stepSamples = 0;
  int turns = 0;
  int regrips = 0;
  int regripSamples = 0;
  double tpsSum = 0;
  int tpsSamples = 0;
  int samples = 0;

  void add(SolveStageAnalysis stage) {
    if (stage.recognitionTime case final recognition?) {
      recognitionMicroseconds += recognition.inMicroseconds;
      recognitionSamples++;
    }
    if (stage.executionTime case final execution?) {
      executionMicroseconds += execution.inMicroseconds;
      executionSamples++;
    }
    if (stage.stepTime case final stepTime?) {
      stepMicroseconds += stepTime.inMicroseconds;
      stepSamples++;
    }
    turns += stage.moves.length;
    if (stage.regripCount case final value?) {
      regrips += value;
      regripSamples++;
    }
    if (stage.turnsPerSecond case final value?) {
      tpsSum += value;
      tpsSamples++;
    }
    samples++;
  }

  SolveAverageStage average(SolveStageKind kind) => SolveAverageStage(
    kind: kind,
    recognitionTime: recognitionSamples == 0
        ? null
        : Duration(microseconds: recognitionMicroseconds ~/ recognitionSamples),
    executionTime: executionSamples == 0
        ? null
        : Duration(microseconds: executionMicroseconds ~/ executionSamples),
    stepTime: stepSamples == 0
        ? null
        : Duration(microseconds: stepMicroseconds ~/ stepSamples),
    turns: turns / samples,
    turnsPerSecond: tpsSamples == 0 ? null : tpsSum / tpsSamples,
    regrips: regripSamples == 0 ? null : regrips / regripSamples,
    sampleCount: samples,
  );
}

Duration? _meanDuration(Iterable<Duration?> values) {
  var totalMicroseconds = 0;
  var count = 0;
  for (final value in values) {
    if (value == null) continue;
    totalMicroseconds += value.inMicroseconds;
    count++;
  }
  return count == 0 ? null : Duration(microseconds: totalMicroseconds ~/ count);
}

double? _mean(Iterable<double?> values) {
  var total = 0.0;
  var count = 0;
  for (final value in values) {
    if (value == null) continue;
    total += value;
    count++;
  }
  return count == 0 ? null : total / count;
}

double? _totalRegrips(SolveAnalysis analysis) {
  var total = 0;
  for (final stage in analysis.stages) {
    if (stage.regripCount case final count?) {
      total += count;
    } else {
      return null;
    }
  }
  return total.toDouble();
}
