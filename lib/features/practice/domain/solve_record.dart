final class SolveRecord {
  const SolveRecord({
    required this.id,
    required this.scramble,
    required this.elapsed,
    required this.moveCount,
    required this.createdAt,
    this.inputSource = 'manual',
  });

  final String id;
  final String scramble;
  final Duration elapsed;
  final int moveCount;
  final DateTime createdAt;
  final String inputSource;

  double? get turnsPerSecond =>
      elapsed.inMilliseconds == 0
          ? null
          : moveCount / (elapsed.inMilliseconds / 1000);

  Map<String, Object?> toJson() => {
    'id': id,
    'scramble': scramble,
    'elapsed_ms': elapsed.inMilliseconds,
    'move_count': moveCount,
    'created_at': createdAt.toIso8601String(),
    'input_source': inputSource,
  };

  factory SolveRecord.fromJson(Map<String, Object?> json) => SolveRecord(
    id: json['id']! as String,
    scramble: json['scramble']! as String,
    elapsed: Duration(milliseconds: json['elapsed_ms']! as int),
    moveCount: json['move_count']! as int,
    createdAt: DateTime.parse(json['created_at']! as String),
    inputSource: (json['input_source'] as String?) ?? 'manual',
  );
}

abstract interface class SolveHistoryRepository {
  Future<List<SolveRecord>> load();

  Future<void> replaceAll(List<SolveRecord> solves);
}

final class MemorySolveHistoryRepository implements SolveHistoryRepository {
  final List<SolveRecord> _solves = [];

  @override
  Future<List<SolveRecord>> load() async => List.unmodifiable(_solves);

  @override
  Future<void> replaceAll(List<SolveRecord> solves) async {
    _solves
      ..clear()
      ..addAll(solves);
  }
}
