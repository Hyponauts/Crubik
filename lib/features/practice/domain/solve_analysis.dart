import '../../cube/domain/cube_model.dart';
import 'solve_method.dart';

const currentSolveAnalyzerVersion = 3;

final class SolveStageAnalysis {
  SolveStageAnalysis({
    required this.kind,
    required this.recognitionTime,
    required this.executionTime,
    required this.totalTime,
    required List<CubeMove> moves,
    required this.regripCount,
    required this.skipped,
  }) : moves = List.unmodifiable(moves);

  final SolveStageKind kind;
  final Duration? recognitionTime;
  final Duration? executionTime;
  final Duration? totalTime;
  final List<CubeMove> moves;
  final int? regripCount;
  final bool skipped;

  Duration? get stepTime {
    final recognition = recognitionTime;
    final execution = executionTime;
    return recognition == null || execution == null
        ? null
        : recognition + execution;
  }

  double? get turnsPerSecond {
    final execution = executionTime;
    if (moves.isEmpty || execution == null || execution.inMicroseconds == 0) {
      return null;
    }
    return moves.length / (execution.inMicroseconds / 1000000);
  }

  Map<String, Object?> toJson() => {
    'stage': kind.serializedValue,
    'recognition_us': recognitionTime?.inMicroseconds,
    'execution_us': executionTime?.inMicroseconds,
    'total_us': totalTime?.inMicroseconds,
    'moves': moves.map((move) => move.notation).toList(),
    'regrips': regripCount,
    'skipped': skipped,
  };

  factory SolveStageAnalysis.fromJson(Map<String, Object?> json) =>
      SolveStageAnalysis(
        kind: SolveStageKind.fromSerializedValue(json['stage']! as String),
        recognitionTime: _durationFromJson(json['recognition_us']),
        executionTime: _durationFromJson(json['execution_us']),
        totalTime: _durationFromJson(json['total_us']),
        moves: [
          for (final move in json['moves']! as List<Object?>)
            CubeMove.parse(move! as String),
        ],
        regripCount: json['regrips'] as int?,
        skipped: json['skipped']! as bool,
      );
}

final class SolveAnalysis {
  SolveAnalysis({
    required this.analyzerVersion,
    required this.method,
    required this.protocolFamily,
    required this.createdAt,
    required this.isComplete,
    required List<SolveStageAnalysis> stages,
    this.failureReason,
  }) : stages = List.unmodifiable(stages);

  final int analyzerVersion;
  final SolveMethodConfig method;
  final String protocolFamily;
  final DateTime createdAt;
  final bool isComplete;
  final String? failureReason;
  final List<SolveStageAnalysis> stages;

  bool get isOutdated => analyzerVersion != currentSolveAnalyzerVersion;
  int get skippedStageCount => stages.where((stage) => stage.skipped).length;
  int get moveCount => stages.fold(0, (sum, stage) => sum + stage.moves.length);

  Duration? get totalRecognitionTime =>
      _sumAvailable(stages.map((stage) => stage.recognitionTime));

  Duration? get totalExecutionTime =>
      _sumAvailable(stages.map((stage) => stage.executionTime));

  Map<String, Object?> toJson() => {
    'analyzer_version': analyzerVersion,
    'method': method.toJson(),
    'protocol_family': protocolFamily,
    'created_at': createdAt.toUtc().toIso8601String(),
    'complete': isComplete,
    'failure_reason': failureReason,
    'stages': stages.map((stage) => stage.toJson()).toList(),
  };

  factory SolveAnalysis.fromJson(Map<String, Object?> json) => SolveAnalysis(
    analyzerVersion: json['analyzer_version']! as int,
    method: SolveMethodConfig.fromJson(json['method']! as Map<String, Object?>),
    protocolFamily: json['protocol_family']! as String,
    createdAt: DateTime.parse(json['created_at']! as String),
    isComplete: json['complete']! as bool,
    failureReason: json['failure_reason'] as String?,
    stages: [
      for (final stage in json['stages']! as List<Object?>)
        SolveStageAnalysis.fromJson(stage! as Map<String, Object?>),
    ],
  );
}

Duration? _durationFromJson(Object? value) => switch (value) {
  final int microseconds => Duration(microseconds: microseconds),
  _ => null,
};

Duration? _sumAvailable(Iterable<Duration?> values) {
  var sum = Duration.zero;
  var hasValue = false;
  for (final value in values) {
    if (value == null) continue;
    hasValue = true;
    sum += value;
  }
  return hasValue ? sum : null;
}
