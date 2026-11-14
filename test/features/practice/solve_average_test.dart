import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/practice/application/solve_history.dart';
import 'package:crubik/features/practice/domain/solve_analysis.dart';
import 'package:crubik/features/practice/domain/solve_average.dart';
import 'package:crubik/features/practice/domain/solve_method.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/practice_controller_factory.dart';

void main() {
  test('Ao5, Ao12 and Ao100 trim the requested counts', () {
    for (final (kind, expectedMilliseconds) in [
      (SolveAverageKind.ao5, 3000),
      (SolveAverageKind.ao12, 6500),
      (SolveAverageKind.ao100, 50500),
    ]) {
      final window = SolveAverageWindow.calculate(kind, [
        for (var index = kind.windowSize; index >= 1; index--) _solve(index),
      ])!;

      expect(window.record.status, SolveAverageStatus.completed);
      expect(window.record.elapsed!.inMilliseconds, expectedMilliseconds);
      expect(
        window.includedSolves.length,
        kind.windowSize - 2 * kind.trimCount,
      );
      expect(window.solves.length, kind.windowSize);
      expect(window.excludedBest.map((solve) => solve.id), [
        for (var index = 1; index <= kind.trimCount; index++) '$index',
      ]);
      expect(window.excludedWorst.map((solve) => solve.id), [
        for (
          var index = kind.windowSize;
          index > kind.windowSize - kind.trimCount;
          index--
        )
          '$index',
      ]);
    }
  });

  test('DNF and DNS count as worst results and overflow makes DNF', () {
    final base = [for (var index = 5; index >= 1; index--) _solve(index)];
    final oneDnf = [_solve(5, outcome: SolveOutcome.dnf), ...base.skip(1)];
    final twoDnf = [
      _solve(5, outcome: SolveOutcome.dnf),
      _solve(4, outcome: SolveOutcome.dns),
      ...base.skip(2),
    ];

    expect(
      SolveAverageWindow.calculate(
        SolveAverageKind.ao5,
        oneDnf,
      )!.record.elapsed,
      const Duration(seconds: 3),
    );
    expect(
      SolveAverageWindow.calculate(SolveAverageKind.ao5, twoDnf)!.record.status,
      SolveAverageStatus.dnf,
    );
    final twelve = [
      for (var index = 12; index >= 1; index--)
        _solve(
          index,
          outcome: index >= 11 ? SolveOutcome.dnf : SolveOutcome.completed,
        ),
    ];
    expect(
      SolveAverageWindow.calculate(
        SolveAverageKind.ao12,
        twelve,
      )!.record.status,
      SolveAverageStatus.dnf,
    );
    for (final dnfCount in [5, 6]) {
      final hundred = [
        for (var index = 100; index >= 1; index--)
          _solve(
            index,
            outcome: index > 100 - dnfCount
                ? SolveOutcome.dnf
                : SolveOutcome.completed,
          ),
      ];
      expect(
        SolveAverageWindow.calculate(
          SolveAverageKind.ao100,
          hundred,
        )!.record.status,
        dnfCount == 5 ? SolveAverageStatus.completed : SolveAverageStatus.dnf,
      );
    }
  });

  test('unreliable timing stays unavailable rather than becoming DNF', () {
    final solves = [
      _solve(5, reliable: false),
      for (var index = 4; index >= 1; index--) _solve(index),
    ];
    final window = SolveAverageWindow.calculate(SolveAverageKind.ao5, solves)!;
    expect(window.record.status, SolveAverageStatus.unavailable);
    expect(window.record.elapsed, isNull);
  });

  test(
    'history persists windows and updates only overlapping anchors',
    () async {
      final repository = MemorySolveHistoryRepository();
      final history = SolveHistory(repository: repository, now: DateTime.now);
      await history.initialize();
      for (var index = 1; index <= 101; index++) {
        history.add(_solve(index));
      }
      await history.flush();
      expect(
        history.averages.where((item) => item.kind == SolveAverageKind.ao5),
        hasLength(97),
      );
      expect(
        history.averages.where((item) => item.kind == SolveAverageKind.ao12),
        hasLength(90),
      );
      expect(
        history.averages.where((item) => item.kind == SolveAverageKind.ao100),
        hasLength(2),
      );
      final older = history.averages.firstWhere(
        (average) => average.id == 'ao5:10',
      );
      final affected = history.averages.firstWhere(
        (average) => average.id == 'ao5:21',
      );

      history.delete('20');
      await history.flush();
      expect(
        history.averages.where((item) => item.kind == SolveAverageKind.ao5),
        hasLength(96),
      );
      expect(
        history.averages.where((item) => item.kind == SolveAverageKind.ao12),
        hasLength(89),
      );
      expect(
        history.averages.where((item) => item.kind == SolveAverageKind.ao100),
        hasLength(1),
      );
      expect(
        history.averages.firstWhere((average) => average.id == older.id),
        same(older),
      );
      expect(
        history.averages
            .firstWhere((average) => average.id == affected.id)
            .elapsed,
        isNot(affected.elapsed),
      );

      final restored = SolveHistory(repository: repository, now: DateTime.now);
      await restored.initialize();
      expect(restored.averages.length, history.averages.length);
      expect(
        restored.averages.map((average) => average.id),
        history.averages.map((average) => average.id),
      );
    },
  );

  test(
    'Ao100 stage detail excludes trimmed solves and other methods',
    () async {
      final repository = MemorySolveHistoryRepository();
      for (var index = 1; index <= 100; index++) {
        final method = SolveMethodConfig.preset(
          index <= 80 ? SolveMethodPreset.twoLookCfop : SolveMethodPreset.cfop,
        );
        final solve = SolveRecord(
          id: '$index',
          scramble: 'R U',
          elapsed: Duration(seconds: index),
          moveCount: 2,
          createdAt: DateTime.utc(2026).add(Duration(seconds: index)),
          method: method,
        );
        await repository.add(solve);
        await repository.saveAnalysis(
          solve.id,
          SolveAnalysis(
            analyzerVersion: currentSolveAnalyzerVersion,
            method: method,
            protocolFamily: 'gan',
            createdAt: solve.createdAt,
            isComplete: true,
            stages: [
              SolveStageAnalysis(
                kind: SolveStageKind.cross,
                recognitionTime: Duration(seconds: index <= 80 ? 10 : 1),
                executionTime: const Duration(seconds: 1),
                totalTime: const Duration(seconds: 2),
                moves: [CubeMove.parse('R')],
                regripCount: 0,
                skipped: false,
              ),
            ],
          ),
        );
      }
      final practice = createTestPracticeController(repository: repository);
      addTearDown(practice.dispose);
      await practice.initialize();

      final average = practice.averagesFor(SolveAverageKind.ao100).single;
      expect(average.elapsed, const Duration(milliseconds: 50500));
      final details = await practice.detailsForAverage(average);

      expect(details?.eligibleSolveCount, 15);
      expect(details?.stages.single.sampleCount, 15);
      expect(
        details?.stages.single.recognitionTime,
        const Duration(seconds: 1),
      );
      expect(details?.stages.single.turnsPerSecond, 0.5);
    },
  );
}

SolveRecord _solve(
  int seconds, {
  SolveOutcome outcome = SolveOutcome.completed,
  bool reliable = true,
}) => SolveRecord(
  id: '$seconds',
  scramble: 'R U',
  elapsed: Duration(seconds: seconds),
  moveCount: 2,
  createdAt: DateTime.utc(2026).add(Duration(seconds: seconds)),
  outcome: outcome,
  isTimingReliable: reliable,
);
