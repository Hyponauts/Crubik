enum CubeFace { up, right, front, down, left, back }

enum StickerColor { white, red, green, yellow, orange, blue }

enum CubeAxis { x, y, z }

final class CubeMove {
  const CubeMove(this.face, {this.turns = 1})
    : assert(turns == 1 || turns == 2 || turns == 3);

  final CubeFace face;

  /// Clockwise quarter turns as viewed directly at the face.
  /// Three quarter turns is the inverse move.
  final int turns;

  factory CubeMove.parse(String value) {
    final match = RegExp(r"^([URFDLB])([2']?)$").firstMatch(value.trim());
    if (match == null) {
      throw FormatException('Invalid cube move: $value');
    }

    final face = switch (match.group(1)) {
      'U' => CubeFace.up,
      'R' => CubeFace.right,
      'F' => CubeFace.front,
      'D' => CubeFace.down,
      'L' => CubeFace.left,
      'B' => CubeFace.back,
      _ => throw FormatException('Invalid cube face: $value'),
    };

    final turns = switch (match.group(2)) {
      '2' => 2,
      "'" => 3,
      _ => 1,
    };
    return CubeMove(face, turns: turns);
  }

  CubeMove get inverse => CubeMove(face, turns: turns == 2 ? 2 : 4 - turns);

  CubeAxis get axis => switch (face) {
    CubeFace.right || CubeFace.left => CubeAxis.x,
    CubeFace.up || CubeFace.down => CubeAxis.y,
    CubeFace.front || CubeFace.back => CubeAxis.z,
  };

  String get notation {
    final letter = switch (face) {
      CubeFace.up => 'U',
      CubeFace.right => 'R',
      CubeFace.front => 'F',
      CubeFace.down => 'D',
      CubeFace.left => 'L',
      CubeFace.back => 'B',
    };
    final suffix = switch (turns) {
      2 => '2',
      3 => "'",
      _ => '',
    };
    return '$letter$suffix';
  }

  @override
  bool operator ==(Object other) =>
      other is CubeMove && other.face == face && other.turns == turns;

  @override
  int get hashCode => Object.hash(face, turns);

  @override
  String toString() => notation;
}

/// An immutable sequence of moves in cube notation.
abstract base class CubeAlgorithm {
  CubeAlgorithm(Iterable<CubeMove> moves) : moves = List.unmodifiable(moves);

  final List<CubeMove> moves;

  @override
  String toString() => moves.map((move) => move.notation).join(' ');
}

/// Moves that transform a solved cube into a target state.
final class CubeScramble extends CubeAlgorithm {
  CubeScramble(super.moves);

  factory CubeScramble.parse(String value) {
    final tokens = value.trim().split(RegExp(r'\s+'));
    if (tokens.length == 1 && tokens.single.isEmpty) {
      return CubeScramble(const []);
    }
    return CubeScramble(tokens.map(CubeMove.parse));
  }

  CubeScramble get inverse =>
      CubeScramble(moves.reversed.map((move) => move.inverse));
}

final class CubeState {
  CubeState._(this._stickers);

  // Standard Kociemba cubie indexing, shared with GAN packet conversion.
  // The protocol-side mapping provenance remains in THIRD_PARTY_NOTICES.md.
  static const _cornerFacelets = [
    [8, 9, 20],
    [6, 18, 38],
    [0, 36, 47],
    [2, 45, 11],
    [29, 26, 15],
    [27, 44, 24],
    [33, 53, 42],
    [35, 17, 51],
  ];

  static const _edgeFacelets = [
    [5, 10],
    [7, 19],
    [3, 37],
    [1, 46],
    [32, 16],
    [28, 25],
    [30, 43],
    [34, 52],
    [23, 12],
    [21, 41],
    [50, 39],
    [48, 14],
  ];

  factory CubeState.solved() {
    final stickers = <_StickerKey, StickerColor>{};
    for (final face in CubeFace.values) {
      final color = _solvedColor(face);
      for (var row = 0; row < 3; row++) {
        for (var column = 0; column < 3; column++) {
          stickers[_keyFor(face, row, column)] = color;
        }
      }
    }
    return CubeState._(stickers);
  }

  factory CubeState.fromFacelets(String facelets) {
    if (facelets.length != 54) {
      throw const FormatException(
        'A 3x3 cube state must contain exactly 54 facelets.',
      );
    }
    final stickers = <_StickerKey, StickerColor>{};
    for (var faceIndex = 0; faceIndex < CubeFace.values.length; faceIndex++) {
      final face = CubeFace.values[faceIndex];
      for (var stickerIndex = 0; stickerIndex < 9; stickerIndex++) {
        final symbol = facelets[faceIndex * 9 + stickerIndex];
        final color = switch (symbol) {
          'U' => StickerColor.white,
          'R' => StickerColor.red,
          'F' => StickerColor.green,
          'D' => StickerColor.yellow,
          'L' => StickerColor.orange,
          'B' => StickerColor.blue,
          _ => throw FormatException('Invalid facelet symbol: $symbol'),
        };
        stickers[_keyFor(face, stickerIndex ~/ 3, stickerIndex % 3)] = color;
      }
    }
    return CubeState._(stickers);
  }

  /// Builds a physical 3x3 state from Kociemba cubie coordinates.
  ///
  /// The constructor rejects coordinates that cannot occur on a real cube:
  /// corner twists must sum to zero modulo 3, edge flips modulo 2, and the
  /// corner and edge permutations must have the same parity.
  factory CubeState.fromCubieCoordinates({
    required List<int> cornerPermutation,
    required List<int> cornerOrientations,
    required List<int> edgePermutation,
    required List<int> edgeOrientations,
  }) {
    _validatePermutation(cornerPermutation, 8, 'corner permutation');
    _validatePermutation(edgePermutation, 12, 'edge permutation');
    _validateOrientations(cornerOrientations, 8, 3, 'corner orientations');
    _validateOrientations(edgeOrientations, 12, 2, 'edge orientations');
    if (cornerOrientations.fold(0, (sum, value) => sum + value) % 3 != 0) {
      throw const FormatException('Corner twist sum must be divisible by 3.');
    }
    if (edgeOrientations.fold(0, (sum, value) => sum + value) % 2 != 0) {
      throw const FormatException('Edge flip sum must be even.');
    }
    if (_permutationParity(cornerPermutation) !=
        _permutationParity(edgePermutation)) {
      throw const FormatException(
        'Corner and edge permutations must have matching parity.',
      );
    }

    const faces = 'URFDLB';
    final facelets = List<String>.generate(54, (index) => faces[index ~/ 9]);
    for (var cubie = 0; cubie < 8; cubie++) {
      for (var position = 0; position < 3; position++) {
        facelets[_cornerFacelets[cubie][(position + cornerOrientations[cubie]) %
                3]] =
            faces[_cornerFacelets[cornerPermutation[cubie]][position] ~/ 9];
      }
    }
    for (var cubie = 0; cubie < 12; cubie++) {
      for (var position = 0; position < 2; position++) {
        facelets[_edgeFacelets[cubie][(position + edgeOrientations[cubie]) %
                2]] =
            faces[_edgeFacelets[edgePermutation[cubie]][position] ~/ 9];
      }
    }
    return CubeState.fromFacelets(facelets.join());
  }

  final Map<_StickerKey, StickerColor> _stickers;

  CubeState copy() => CubeState._(Map.of(_stickers));

  List<StickerColor> colorsFor(CubeFace face) => List.unmodifiable(
    List.generate(9, (index) {
      final row = index ~/ 3;
      final column = index % 3;
      return _stickers[_keyFor(face, row, column)]!;
    }),
  );

  String get facelets {
    return CubeFace.values
        .expand(colorsFor)
        .map(
          (color) => switch (color) {
            StickerColor.white => 'U',
            StickerColor.red => 'R',
            StickerColor.green => 'F',
            StickerColor.yellow => 'D',
            StickerColor.orange => 'L',
            StickerColor.blue => 'B',
          },
        )
        .join();
  }

  bool get isSolved {
    for (final face in CubeFace.values) {
      final colors = colorsFor(face);
      if (colors.any((color) => color != colors.first)) {
        return false;
      }
    }
    return true;
  }

  void apply(CubeMove move) {
    final (axis, layer) = _layerFor(move.face);
    final clockwiseDirection = -layer;

    for (var turn = 0; turn < move.turns; turn++) {
      final updates = <_StickerKey, StickerColor>{};
      for (final entry in _stickers.entries) {
        final key = entry.key;
        if (key.position.component(axis) != layer) {
          updates[key] = entry.value;
          continue;
        }

        updates[_StickerKey(
              _rotate(key.position, axis, clockwiseDirection),
              _rotate(key.normal, axis, clockwiseDirection),
            )] =
            entry.value;
      }
      _stickers
        ..clear()
        ..addAll(updates);
    }
  }

  void applyAll(Iterable<CubeMove> moves) {
    for (final move in moves) {
      apply(move);
    }
  }

  static StickerColor _solvedColor(CubeFace face) => switch (face) {
    CubeFace.up => StickerColor.white,
    CubeFace.right => StickerColor.red,
    CubeFace.front => StickerColor.green,
    CubeFace.down => StickerColor.yellow,
    CubeFace.left => StickerColor.orange,
    CubeFace.back => StickerColor.blue,
  };

  static (CubeAxis, int) _layerFor(CubeFace face) => switch (face) {
    CubeFace.right => (CubeAxis.x, 1),
    CubeFace.left => (CubeAxis.x, -1),
    CubeFace.up => (CubeAxis.y, 1),
    CubeFace.down => (CubeAxis.y, -1),
    CubeFace.front => (CubeAxis.z, 1),
    CubeFace.back => (CubeAxis.z, -1),
  };

  static _Vec3 _rotate(_Vec3 value, CubeAxis axis, int direction) {
    assert(direction == 1 || direction == -1);
    return switch ((axis, direction)) {
      (CubeAxis.x, 1) => _Vec3(value.x, -value.z, value.y),
      (CubeAxis.x, -1) => _Vec3(value.x, value.z, -value.y),
      (CubeAxis.y, 1) => _Vec3(value.z, value.y, -value.x),
      (CubeAxis.y, -1) => _Vec3(-value.z, value.y, value.x),
      (CubeAxis.z, 1) => _Vec3(-value.y, value.x, value.z),
      (CubeAxis.z, -1) => _Vec3(value.y, -value.x, value.z),
      _ => throw StateError('Unsupported rotation'),
    };
  }

  static _StickerKey _keyFor(CubeFace face, int row, int column) {
    final position = switch (face) {
      CubeFace.front => _Vec3(column - 1, 1 - row, 1),
      CubeFace.back => _Vec3(1 - column, 1 - row, -1),
      CubeFace.right => _Vec3(1, 1 - row, 1 - column),
      CubeFace.left => _Vec3(-1, 1 - row, column - 1),
      CubeFace.up => _Vec3(column - 1, 1, row - 1),
      CubeFace.down => _Vec3(column - 1, -1, 1 - row),
    };
    final normal = switch (face) {
      CubeFace.front => const _Vec3(0, 0, 1),
      CubeFace.back => const _Vec3(0, 0, -1),
      CubeFace.right => const _Vec3(1, 0, 0),
      CubeFace.left => const _Vec3(-1, 0, 0),
      CubeFace.up => const _Vec3(0, 1, 0),
      CubeFace.down => const _Vec3(0, -1, 0),
    };
    return _StickerKey(position, normal);
  }

  static void _validatePermutation(
    List<int> permutation,
    int length,
    String name,
  ) {
    if (permutation.length != length ||
        permutation.toSet().length != length ||
        permutation.any((value) => value < 0 || value >= length)) {
      throw FormatException(
        '$name must contain each value from 0 to ${length - 1} exactly once.',
      );
    }
  }

  static void _validateOrientations(
    List<int> orientations,
    int length,
    int base,
    String name,
  ) {
    if (orientations.length != length ||
        orientations.any((value) => value < 0 || value >= base)) {
      throw FormatException(
        '$name must contain $length values from 0 to ${base - 1}.',
      );
    }
  }

  static int _permutationParity(List<int> permutation) {
    var inversions = 0;
    for (var left = 0; left < permutation.length; left++) {
      for (var right = left + 1; right < permutation.length; right++) {
        if (permutation[left] > permutation[right]) inversions++;
      }
    }
    return inversions % 2;
  }
}

final class _StickerKey {
  const _StickerKey(this.position, this.normal);

  final _Vec3 position;
  final _Vec3 normal;

  @override
  bool operator ==(Object other) =>
      other is _StickerKey &&
      other.position == position &&
      other.normal == normal;

  @override
  int get hashCode => Object.hash(position, normal);
}

final class _Vec3 {
  const _Vec3(this.x, this.y, this.z);

  final int x;
  final int y;
  final int z;

  int component(CubeAxis axis) => switch (axis) {
    CubeAxis.x => x,
    CubeAxis.y => y,
    CubeAxis.z => z,
  };

  @override
  bool operator ==(Object other) =>
      other is _Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);
}
