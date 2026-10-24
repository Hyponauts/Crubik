import 'dart:math';

import 'cube_model.dart';
import 'cube_solver.dart';

final class WcaScrambleGenerator {
  WcaScrambleGenerator({required CubeSolver solver, Random? random})
    : this._(solver, random ?? Random.secure());

  WcaScrambleGenerator._(this._solver, this._random);

  final CubeSolver _solver;
  final Random _random;

  Future<CubeScramble> generate() async {
    while (true) {
      final target = _randomReachableState();
      if (!isAllowedTarget(target)) continue;

      final solution = await _solver.solve(target);
      final scramble = solution.toScramble();
      final result = CubeState.solved()..applyAll(scramble.moves);
      if (result.facelets != target.facelets) {
        throw const CubeSolverException(
          'The solver returned a sequence for a different cube state.',
        );
      }
      return scramble;
    }
  }

  CubeState _randomReachableState() {
    final corners = _randomPermutation(8);
    final edges = _randomPermutation(12);
    final cornerPermutation = corners.values;
    final edgePermutation = edges.values;
    if (corners.parity != edges.parity) {
      final last = edgePermutation.length - 1;
      final previous = last - 1;
      final value = edgePermutation[previous];
      edgePermutation[previous] = edgePermutation[last];
      edgePermutation[last] = value;
    }

    final cornerOrientations = List<int>.generate(7, (_) => _random.nextInt(3));
    cornerOrientations.add(
      (3 - cornerOrientations.fold(0, (sum, value) => sum + value) % 3) % 3,
    );
    final edgeOrientations = List<int>.generate(11, (_) => _random.nextInt(2));
    edgeOrientations.add(
      (2 - edgeOrientations.fold(0, (sum, value) => sum + value) % 2) % 2,
    );

    return CubeState.fromCubieCoordinates(
      cornerPermutation: cornerPermutation,
      cornerOrientations: cornerOrientations,
      edgePermutation: edgePermutation,
      edgeOrientations: edgeOrientations,
    );
  }

  /// Matches TNoodle's default 3x3 minimum-distance rule: states solvable in
  /// zero or one move are rejected; states at distance two or more are valid.
  static bool isAllowedTarget(CubeState state) {
    if (state.isSolved) return false;
    for (final face in CubeFace.values) {
      for (var turns = 1; turns <= 3; turns++) {
        final neighbor = CubeState.solved()
          ..apply(CubeMove(face, turns: turns));
        if (state.facelets == neighbor.facelets) return false;
      }
    }
    return true;
  }

  ({List<int> values, int parity}) _randomPermutation(int length) {
    final values = List<int>.generate(length, (index) => index);
    var parity = 0;
    for (var index = length - 1; index > 0; index--) {
      final other = _random.nextInt(index + 1);
      if (other != index) {
        final value = values[index];
        values[index] = values[other];
        values[other] = value;
        parity ^= 1;
      }
    }
    return (values: values, parity: parity);
  }
}
