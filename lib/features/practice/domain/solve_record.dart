import 'solve_recording.dart';

enum SolveStartTrigger {
  manual('manual'),
  firstMove('first_move'),
  inspectionTimeout('inspection_timeout');

  const SolveStartTrigger(this.serializedValue);

  final String serializedValue;

  static SolveStartTrigger? fromSerializedValue(String? value) {
    if (value == null) return null;
    for (final trigger in values) {
      if (trigger.serializedValue == value) return trigger;
    }
    return null;
  }
}

/// The normalized source that completed a solve.
///
/// Known sources are constants so application code cannot persist accidental
/// spelling variants. Unknown serialized values are retained verbatim to keep
/// imported history forward-compatible and lossless.
final class SolveInputSource {
  const SolveInputSource._(this.serializedValue);

  static const manual = SolveInputSource._('manual');
  static const manualMoves = SolveInputSource._('manual_moves');
  static const smartCube = SolveInputSource._('smart_cube');
  static const smartCubeState = SolveInputSource._('smart_cube_state');

  static const values = [manual, manualMoves, smartCube, smartCubeState];

  factory SolveInputSource.fromSerializedValue(String value) {
    for (final source in values) {
      if (source.serializedValue == value) return source;
    }
    return SolveInputSource._(value);
  }

  final String serializedValue;

  String get displayLabel => switch (this) {
    manual => 'manual',
    manualMoves => 'manual moves',
    smartCube => 'smart cube',
    smartCubeState => 'smart cube state',
    _ => serializedValue.replaceAll('_', ' '),
  };

  @override
  bool operator ==(Object other) =>
      other is SolveInputSource && other.serializedValue == serializedValue;

  @override
  int get hashCode => serializedValue.hashCode;

  @override
  String toString() => serializedValue;
}

final class SolveRecord {
  const SolveRecord({
    required this.id,
    required this.scramble,
    required this.elapsed,
    required this.moveCount,
    required this.createdAt,
    this.inputSource = SolveInputSource.manual,
    this.inspectionElapsed,
    this.startTrigger,
    this.isTimingReliable = true,
  });

  final String id;
  final String scramble;

  /// The host timer reading; meaningful only when [isTimingReliable] is true.
  final Duration elapsed;
  final int moveCount;
  final DateTime createdAt;
  final SolveInputSource inputSource;
  final Duration? inspectionElapsed;
  final SolveStartTrigger? startTrigger;

  /// False when recovery or a state report leaves a solve boundary unobserved.
  final bool isTimingReliable;

  double? get turnsPerSecond => !isTimingReliable || elapsed.inMilliseconds == 0
      ? null
      : moveCount / (elapsed.inMilliseconds / 1000);

  Map<String, Object?> toJson() => {
    'id': id,
    'scramble': scramble,
    'elapsed_ms': isTimingReliable ? elapsed.inMilliseconds : null,
    'timing_reliable': isTimingReliable,
    'move_count': moveCount,
    'created_at': createdAt.toIso8601String(),
    'input_source': inputSource.serializedValue,
    'inspection_elapsed_ms': inspectionElapsed?.inMilliseconds,
    'start_trigger': startTrigger?.serializedValue,
  };

  factory SolveRecord.fromJson(Map<String, Object?> json) => SolveRecord(
    id: json['id']! as String,
    scramble: json['scramble']! as String,
    elapsed: Duration(milliseconds: (json['elapsed_ms'] as int?) ?? 0),
    isTimingReliable:
        (json['timing_reliable'] as bool?) ?? json['elapsed_ms'] != null,
    moveCount: json['move_count']! as int,
    createdAt: DateTime.parse(json['created_at']! as String),
    inputSource: SolveInputSource.fromSerializedValue(
      (json['input_source'] as String?) ??
          SolveInputSource.manual.serializedValue,
    ),
    inspectionElapsed: switch (json['inspection_elapsed_ms']) {
      final int milliseconds => Duration(milliseconds: milliseconds),
      _ => null,
    },
    startTrigger: SolveStartTrigger.fromSerializedValue(
      json['start_trigger'] as String?,
    ),
  );
}

abstract interface class SolveHistoryRepository {
  Future<List<SolveRecord>> load();

  Future<SolveRecording?> loadRecording(String solveId);

  Future<void> add(SolveRecord solve, {SolveRecording? recording});

  Future<void> delete(String id);
}

final class MemorySolveHistoryRepository implements SolveHistoryRepository {
  final List<SolveRecord> _solves = [];
  final Map<String, SolveRecording> _recordingsBySolveId = {};

  @override
  Future<List<SolveRecord>> load() async => List.unmodifiable(_solves);

  @override
  Future<SolveRecording?> loadRecording(String solveId) async =>
      _recordingsBySolveId[solveId];

  @override
  Future<void> add(SolveRecord solve, {SolveRecording? recording}) async {
    _solves.removeWhere((stored) => stored.id == solve.id);
    _solves.add(solve);
    if (recording == null) {
      _recordingsBySolveId.remove(solve.id);
    } else {
      _recordingsBySolveId[solve.id] = recording;
    }
  }

  @override
  Future<void> delete(String id) async {
    _solves.removeWhere((solve) => solve.id == id);
    _recordingsBySolveId.remove(id);
  }
}
