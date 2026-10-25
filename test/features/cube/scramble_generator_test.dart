import 'dart:math';

import 'package:crubik/features/cube/data/solver/cuber_cube_solver.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/scramble_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the same default minimum-distance rule as TNoodle', () {
    expect(WcaScrambleGenerator.isAllowedTarget(CubeState.solved()), isFalse);
    expect(
      WcaScrambleGenerator.isAllowedTarget(
        CubeState.solved()..apply(CubeMove.parse('R')),
      ),
      isFalse,
    );
    expect(
      WcaScrambleGenerator.isAllowedTarget(
        CubeState.solved()..applyAll(CubeScramble.parse('R U').moves),
      ),
      isTrue,
    );
  });

  test(
    'generates a reachable random-state scramble through the solver',
    () async {
      final solver = CuberCubeSolver(timeout: const Duration(seconds: 20));
      addTearDown(solver.dispose);
      final generator = WcaScrambleGenerator(
        solver: solver,
        random: Random(42),
      );

      final scramble = await generator.generate();
      final target = CubeState.solved()..applyAll(scramble.moves);
      final solution = await solver.solve(target);
      target.applyAll(solution.moves);

      expect(scramble.moves.length, inInclusiveRange(2, 21));
      expect(target.isSolved, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
