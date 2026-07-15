import 'dart:math';

import 'cube_model.dart';

final class ScrambleGenerator {
  ScrambleGenerator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  static const _faces = CubeFace.values;

  Scramble generate({int length = 20}) {
    assert(length > 0);
    final moves = <CubeMove>[];

    while (moves.length < length) {
      final face = _faces[_random.nextInt(_faces.length)];
      if (moves.isNotEmpty && moves.last.face == face) {
        continue;
      }
      if (moves.length > 1 &&
          moves.last.axis == faceAxis(face) &&
          moves[moves.length - 2].axis == faceAxis(face)) {
        continue;
      }

      moves.add(CubeMove(face, turns: _random.nextInt(3) + 1));
    }

    return Scramble(List.unmodifiable(moves));
  }

  static CubeAxis faceAxis(CubeFace face) => switch (face) {
    CubeFace.right || CubeFace.left => CubeAxis.x,
    CubeFace.up || CubeFace.down => CubeAxis.y,
    CubeFace.front || CubeFace.back => CubeAxis.z,
  };
}
