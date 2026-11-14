import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/practice/application/solve_statistics.dart';
import 'package:crubik/features/practice/domain/solve_analysis.dart';
import 'package:crubik/features/practice/domain/solve_method.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'average TPS is the mean of per-solve TPS, not pooled turns per time',
    () {
      final earlier = _solve('earlier', seconds: 2, turns: 2);
      final later = _solve('later', seconds: 4, turns: 8);

      final metrics = SolveStatistics.averageMetrics(
        includedSolves: [earlier, later],
        sameMethodSolves: [earlier, later],
        analysesById: const {},
      );

      expect(metrics.turns, 5);
      expect(metrics.turnsPerSecond, 1.5);
    },
  );

  test('stage means exclude missing durations instead of inventing zero', () {
    final complete = _analysis(
      recognition: const Duration(seconds: 1),
      execution: const Duration(seconds: 2),
      regrips: 2,
    );
    final partial = _analysis(
      recognition: null,
      execution: const Duration(seconds: 4),
      regrips: null,
    );
    final unavailable = _analysis(
      recognition: null,
      execution: null,
      regrips: null,
    );

    final stages = SolveStatistics.averageStages(
      [complete, partial, unavailable],
      order: [SolveStageKind.cross],
    );

    expect(stages.single.sampleCount, 3);
    expect(stages.single.recognitionTime, const Duration(seconds: 1));
    expect(stages.single.executionTime, const Duration(seconds: 3));
    expect(stages.single.stepTime, const Duration(seconds: 3));
    expect(stages.single.regrips, 2);
    expect(stages.single.turns, 1);
  });

  test('Ao metrics exclude solves without regrip data', () {
    final withRegrips = _solve('with', seconds: 3, turns: 3);
    final withoutRegrips = _solve('without', seconds: 3, turns: 3);
    final analyses = {
      withRegrips.id: _analysis(
        recognition: const Duration(seconds: 1),
        execution: const Duration(seconds: 2),
        regrips: 4,
      ),
      withoutRegrips.id: _analysis(
        recognition: const Duration(seconds: 1),
        execution: const Duration(seconds: 2),
        regrips: null,
      ),
    };

    final metrics = SolveStatistics.averageMetrics(
      includedSolves: [withRegrips, withoutRegrips],
      sameMethodSolves: [withRegrips, withoutRegrips],
      analysesById: analyses,
    );
    expect(metrics.regrips, 4);

    final unavailable = SolveStatistics.averageMetrics(
      includedSolves: [withoutRegrips],
      sameMethodSolves: [withoutRegrips],
      analysesById: analyses,
    );
    expect(unavailable.regrips, isNull);
  });
}

SolveRecord _solve(String id, {required int seconds, required int turns}) =>
    SolveRecord(
      id: id,
      scramble: 'R',
      elapsed: Duration(seconds: seconds),
      moveCount: turns,
      createdAt: DateTime.utc(2026),
    );

SolveAnalysis _analysis({
  required Duration? recognition,
  required Duration? execution,
  required int? regrips,
}) => SolveAnalysis(
  analyzerVersion: currentSolveAnalyzerVersion,
  method: SolveMethodConfig.preset(SolveMethodPreset.cfop),
  protocolFamily: 'test',
  createdAt: DateTime.utc(2026),
  isComplete: true,
  stages: [
    SolveStageAnalysis(
      kind: SolveStageKind.cross,
      recognitionTime: recognition,
      executionTime: execution,
      totalTime: recognition == null || execution == null
          ? null
          : recognition + execution,
      moves: [CubeMove.parse('R')],
      regripCount: regrips,
      skipped: false,
    ),
  ],
);
