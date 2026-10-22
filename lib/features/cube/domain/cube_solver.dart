import 'cube_model.dart';

/// Moves that transform a supplied cube state back to solved.
final class CubeSolution extends CubeAlgorithm {
  CubeSolution(super.moves);

  CubeScramble toScramble() =>
      CubeScramble(moves.reversed.map((move) => move.inverse));
}

abstract interface class CubeSolver {
  Future<CubeSolution> solve(CubeState state);

  void dispose();
}

final class CubeSolverException implements Exception {
  const CubeSolverException(this.message);

  final String message;

  @override
  String toString() => 'CubeSolverException: $message';
}
