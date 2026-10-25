import 'package:cuber/cuber.dart';

List<String> solveWithCuber(
  String facelets, {
  required int maxDepth,
  required Duration timeout,
}) {
  final cube = Cube.from(facelets);
  if (!cube.isOk) {
    throw const FormatException('The cube state is not physically reachable.');
  }
  final solution = cube.solve(maxDepth: maxDepth, timeout: timeout);
  if (solution == null) {
    throw StateError(
      'No solution was found within $maxDepth moves and '
      '${timeout.inSeconds} seconds.',
    );
  }
  return solution.algorithm.moves
      .map((move) => move.toString())
      .toList(growable: false);
}
