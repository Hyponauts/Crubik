import '../../domain/cube_model.dart';
import '../../domain/cube_solver.dart';
import 'cuber_solver_backend.dart';

final class CuberCubeSolver implements CubeSolver {
  CuberCubeSolver({
    CuberSolverBackend? backend,
    this.maxDepth = 21,
    this.timeout = const Duration(seconds: 60),
  }) : _backend = backend ?? createCuberSolverBackend();

  final CuberSolverBackend _backend;
  final int maxDepth;
  final Duration timeout;
  bool _disposed = false;

  @override
  Future<CubeSolution> solve(CubeState state) async {
    if (_disposed) {
      throw const CubeSolverException('The cube solver has been disposed.');
    }

    Object? firstFailure;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final moves = await _backend.solve(
          state.facelets,
          maxDepth: maxDepth,
          timeout: timeout,
        );
        return CubeSolution(moves.map(CubeMove.parse));
      } catch (error) {
        firstFailure ??= error;
        if (attempt == 0) _backend.restart();
      }
    }
    throw CubeSolverException(
      'Failed after one retry: ${firstFailure.toString()}',
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _backend.dispose();
  }
}
