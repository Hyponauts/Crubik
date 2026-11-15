import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/practice/domain/countable_solve.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pairs same-direction quarter turns without cancelling reversals', () {
    final raw = [
      'B',
      'B',
      "R'",
      "R'",
      'U2',
      'L',
      "L'",
      'F',
      'F',
      'F',
      'F',
    ].map(CubeMove.parse).toList();

    final countable = CountableSolve.fromMoves(raw);

    expect(countable.toString(), "B2 R2 U2 L L' F2 F2");
    expect(countable.rawMoveSpans, [
      (first: 0, last: 1),
      (first: 2, last: 3),
      (first: 4, last: 4),
      (first: 5, last: 5),
      (first: 6, last: 6),
      (first: 7, last: 8),
      (first: 9, last: 10),
    ]);
    expect(
      (CubeState.solved()..applyAll(countable.moves)).facelets,
      (CubeState.solved()..applyAll(raw)).facelets,
    );
  });

  test('pairs both directions on every face', () {
    for (final face in ['U', 'R', 'F', 'D', 'L', 'B']) {
      expect(
        CountableSolve.fromMoves([
          CubeMove.parse(face),
          CubeMove.parse(face),
          CubeMove.parse("$face'"),
          CubeMove.parse("$face'"),
        ]).toString(),
        '${face}2 ${face}2',
      );
    }
  });
}
