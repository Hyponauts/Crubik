import '../../cube/domain/cube_model.dart';

typedef RawMoveSpan = ({int first, int last});

/// A solve sequence counted in face turns, retaining its raw move positions.
///
/// Two adjacent quarter turns in the same direction on the same face become
/// one half turn. Opposite turns are not cancelled: this describes what the
/// cuber did, not the shortest equivalent algorithm.
final class CountableSolve extends CubeAlgorithm {
  CountableSolve._(super.moves, this.rawMoveSpans);

  factory CountableSolve.fromMoves(Iterable<CubeMove> rawMoves) {
    final raw = rawMoves.toList();
    final moves = <CubeMove>[];
    final spans = <RawMoveSpan>[];

    for (var index = 0; index < raw.length; index++) {
      final move = raw[index];
      if (move.turns != 2 && index + 1 < raw.length && raw[index + 1] == move) {
        moves.add(CubeMove(move.face, turns: 2));
        spans.add((first: index, last: index + 1));
        index++;
      } else {
        moves.add(move);
        spans.add((first: index, last: index));
      }
    }

    return CountableSolve._(moves, List.unmodifiable(spans));
  }

  /// The inclusive raw move range represented by each move in [moves].
  final List<RawMoveSpan> rawMoveSpans;
}
