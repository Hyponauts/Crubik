import 'dart:isolate';

import 'cuber_solver_backend_contract.dart';
import 'cuber_solver_engine.dart';

CuberSolverBackend createCuberSolverBackend() => _NativeCuberSolverBackend();

final class _NativeCuberSolverBackend implements CuberSolverBackend {
  @override
  Future<List<String>> solve(
    String facelets, {
    required int maxDepth,
    required Duration timeout,
  }) {
    return Isolate.run(
      () => solveWithCuber(facelets, maxDepth: maxDepth, timeout: timeout),
      debugName: 'crubik-cube-solver',
    );
  }

  @override
  void restart() {}

  @override
  void dispose() {}
}
