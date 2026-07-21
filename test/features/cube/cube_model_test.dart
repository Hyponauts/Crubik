import 'dart:math';

import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/scramble_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      final scramble = Scramble.parse("R U R' U' F2 D L2 B'");
      final state = CubeState.solved()
        ..applyAll(scramble.moves)
        ..applyAll(scramble.inverse.moves);

      expect(state.isSolved, isTrue);
    });

    test('round-trips a live cube state through Kociemba facelets', () {
      final original = CubeState.solved()
        ..applyAll(Scramble.parse("R U F' L2 D B").moves);

      final restored = CubeState.fromFacelets(original.facelets);

      expect(restored.facelets, original.facelets);
      expect(restored.isSolved, isFalse);
    });
  });

  group('ScrambleGenerator', () {
    test('creates a 20 move practice scramble without duplicate faces', () {
      final scramble = ScrambleGenerator(random: Random(7)).generate();

      expect(scramble.moves, hasLength(20));
      for (var index = 1; index < scramble.moves.length; index++) {
        expect(
          scramble.moves[index].face,
          isNot(scramble.moves[index - 1].face),
        );
      }
    });

    test('does not produce three consecutive moves on one axis', () {
      final scramble = ScrambleGenerator(
        random: Random(19),
      ).generate(length: 200);

      for (var index = 2; index < scramble.moves.length; index++) {
        final axes = scramble.moves
            .sublist(index - 2, index + 1)
            .map((move) => move.axis)
            .toSet();
        expect(axes.length, greaterThan(1));
      }
    });
  });
}
