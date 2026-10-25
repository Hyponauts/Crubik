import 'package:crubik/features/cube/data/solver/cuber_cube_solver.dart';
import 'package:crubik/features/cube/data/solver/cuber_solver_backend_contract.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/cube_solver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts a solution into the inverse scramble', () {
    final solution = CubeSolution([
      CubeMove.parse("R'"),
      CubeMove.parse('U2'),
      CubeMove.parse('F'),
    ]);

    final scramble = solution.toScramble();

    expect(solution, isA<CubeAlgorithm>());
    expect(solution.toString(), "R' U2 F");
    expect(scramble.toString(), "F' U2 R");
  });

  test('restarts once and retries the same state', () async {
    final backend = _RetryBackend();
    final solver = CuberCubeSolver(backend: backend);
    addTearDown(solver.dispose);
    final state = CubeState.solved()..apply(CubeMove.parse('R'));

    final solution = await solver.solve(state);

    expect(solution.moves, [CubeMove.parse("R'")]);
    expect(backend.facelets, [state.facelets, state.facelets]);
    expect(backend.restarts, 1);
  });

  test('reports failure after the retry is exhausted', () async {
    final backend = _RetryBackend(alwaysFail: true);
    final solver = CuberCubeSolver(backend: backend);
    addTearDown(solver.dispose);

    await expectLater(
      solver.solve(CubeState.solved()),
      throwsA(isA<CubeSolverException>()),
    );
    expect(backend.restarts, 1);
    expect(backend.calls, 2);
  });
}

final class _RetryBackend implements CuberSolverBackend {
  _RetryBackend({this.alwaysFail = false});

  final bool alwaysFail;
  final List<String> facelets = [];
  int calls = 0;
  int restarts = 0;

  @override
  Future<List<String>> solve(
    String state, {
    required int maxDepth,
    required Duration timeout,
  }) async {
    facelets.add(state);
    calls++;
    if (calls == 1 || alwaysFail) throw StateError('transient failure');
    return ["R'"];
  }

  @override
  void restart() => restarts++;

  @override
  void dispose() {}
}
