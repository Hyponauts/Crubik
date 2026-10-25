import 'dart:math';

import 'package:crubik/core/time/monotonic_clock.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';

PracticeController createTestPracticeController({
  TestScrambleGenerator? scrambleGenerator,
  SolveHistoryRepository? repository,
  SolveClock? clock,
  MonotonicClock? monotonicClock,
  DateTime Function()? now,
  Duration preInspectionDelay = PracticeController.defaultPreInspectionDelay,
  Duration inspectionDuration = PracticeController.defaultInspectionDuration,
}) {
  final generator = scrambleGenerator ?? TestScrambleGenerator();
  return PracticeController(
    nextScramble: generator.generate,
    repository: repository,
    clock: clock,
    monotonicClock: monotonicClock,
    now: now,
    preInspectionDelay: preInspectionDelay,
    inspectionDuration: inspectionDuration,
  );
}

/// Fast deterministic move-list generator used only by interaction tests.
///
/// Production always uses random reachable states and a cube solver.
final class TestScrambleGenerator {
  TestScrambleGenerator({Random? random}) : _random = random ?? Random(1);

  final Random _random;

  CubeScramble generate({int length = 20}) {
    final moves = <CubeMove>[];
    while (moves.length < length) {
      final face = CubeFace.values[_random.nextInt(CubeFace.values.length)];
      if (moves.isNotEmpty && moves.last.face == face) continue;
      final axis = CubeMove(face).axis;
      if (moves.length > 1 &&
          moves.last.axis == axis &&
          moves[moves.length - 2].axis == axis) {
        continue;
      }
      moves.add(CubeMove(face, turns: _random.nextInt(3) + 1));
    }
    return CubeScramble(moves);
  }
}
