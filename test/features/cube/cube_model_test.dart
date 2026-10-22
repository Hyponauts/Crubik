import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CubeAlgorithm', () {
    test('stores an immutable copy of its moves', () {
      final moves = [CubeMove.parse('R')];
      final scramble = CubeScramble(moves);

      moves.add(CubeMove.parse('U'));

      expect(scramble, isA<CubeAlgorithm>());
      expect(scramble.toString(), 'R');
      expect(
        () => scramble.moves.add(CubeMove.parse('F')),
        throwsUnsupportedError,
      );
    });
  });

  group('CubeState', () {
    test('starts solved with nine stickers on every face', () {
      final state = CubeState.solved();

      expect(state.isSolved, isTrue);
      for (final face in CubeFace.values) {
        expect(state.colorsFor(face), hasLength(9));
        expect(state.colorsFor(face).toSet(), hasLength(1));
      }
    });

    test('a move followed by its inverse restores the cube', () {
      for (final notation in ['U', 'R', 'F', 'D', 'L', 'B', 'R2']) {
        final move = CubeMove.parse(notation);
        final state = CubeState.solved()
          ..apply(move)
          ..apply(move.inverse);

        expect(state.isSolved, isTrue, reason: notation);
      }
    });

    test('four clockwise quarter turns restore the cube', () {
      for (final face in CubeFace.values) {
        final state = CubeState.solved();
        for (var index = 0; index < 4; index++) {
          state.apply(CubeMove(face));
        }
        expect(state.isSolved, isTrue, reason: face.name);
      }
    });

    test('front clockwise turn maps adjacent face colors correctly', () {
      final state = CubeState.solved()..apply(CubeMove.parse('F'));

      expect(
        state.colorsFor(CubeFace.up).sublist(6),
        everyElement(StickerColor.orange),
      );
      expect(
        [0, 3, 6].map(state.colorsFor(CubeFace.right).elementAt),
        everyElement(StickerColor.white),
      );
    });

    test('scramble followed by inverse restores the cube', () {
      final scramble = CubeScramble.parse("R U R' U' F2 D L2 B'");
      final state = CubeState.solved()
        ..applyAll(scramble.moves)
        ..applyAll(scramble.inverse.moves);

      expect(state.isSolved, isTrue);
    });

    test('round-trips a live cube state through Kociemba facelets', () {
      final original = CubeState.solved()
        ..applyAll(CubeScramble.parse("R U F' L2 D B").moves);

      final restored = CubeState.fromFacelets(original.facelets);

      expect(restored.facelets, original.facelets);
      expect(restored.isSolved, isFalse);
    });

    test('builds the solved cube from valid cubie coordinates', () {
      final state = CubeState.fromCubieCoordinates(
        cornerPermutation: List.generate(8, (index) => index),
        cornerOrientations: List.filled(8, 0),
        edgePermutation: List.generate(12, (index) => index),
        edgeOrientations: List.filled(12, 0),
      );

      expect(state.facelets, CubeState.solved().facelets);
    });

    test('accepts a reachable state with matching permutation parity', () {
      final state = CubeState.fromCubieCoordinates(
        cornerPermutation: [1, 0, 2, 3, 4, 5, 6, 7],
        cornerOrientations: [1, 2, 0, 0, 0, 0, 0, 0],
        edgePermutation: [1, 0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
        edgeOrientations: [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      );

      expect(state.isSolved, isFalse);
      expect(state.facelets.split('').toSet(), {'U', 'R', 'F', 'D', 'L', 'B'});
    });

    test('rejects duplicate cubies and unreachable coordinates', () {
      expect(
        () => CubeState.fromCubieCoordinates(
          cornerPermutation: [0, 0, 2, 3, 4, 5, 6, 7],
          cornerOrientations: List.filled(8, 0),
          edgePermutation: List.generate(12, (index) => index),
          edgeOrientations: List.filled(12, 0),
        ),
        throwsFormatException,
      );
      expect(
        () => CubeState.fromCubieCoordinates(
          cornerPermutation: List.generate(8, (index) => index),
          cornerOrientations: [1, 0, 0, 0, 0, 0, 0, 0],
          edgePermutation: List.generate(12, (index) => index),
          edgeOrientations: List.filled(12, 0),
        ),
        throwsFormatException,
      );
      expect(
        () => CubeState.fromCubieCoordinates(
          cornerPermutation: [1, 0, 2, 3, 4, 5, 6, 7],
          cornerOrientations: List.filled(8, 0),
          edgePermutation: List.generate(12, (index) => index),
          edgeOrientations: List.filled(12, 0),
        ),
        throwsFormatException,
      );
    });
  });
}
