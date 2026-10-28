import 'dart:math' as math;

import '../../cube/domain/cube_model.dart';
import '../../cube/domain/smart_cube_event.dart';
import '../domain/solve_analysis.dart';
import '../domain/solve_method.dart';
import '../domain/solve_record.dart';
import '../domain/solve_recording.dart';

final class SolveAnalyzer {
  const SolveAnalyzer({this.orientation = const SolveOrientation()});

  static const _regripThresholdRadians = 20 * math.pi / 180;

  final SolveOrientation orientation;

  SolveAnalysis analyze({
    required SolveRecord solve,
    required SolveRecording recording,
    DateTime? analyzedAt,
  }) {
    if (recording.events.any((event) => event is RecordedDataGap)) {
      return _unavailable(
        solve,
        recording,
        analyzedAt,
        'The recording contains a telemetry gap.',
      );
    }
    if (recording.moves.isEmpty) {
      return _unavailable(
        solve,
        recording,
        analyzedAt,
        'No recorded moves are available.',
      );
    }

    final state = CubeState.solved();
    try {
      state.applyAll(CubeScramble.parse(solve.scramble).moves);
    } on FormatException {
      return _unavailable(
        solve,
        recording,
        analyzedAt,
        'The recorded scramble is invalid.',
      );
    }

    final descriptors = solve.method.stages.map(descriptorFor).toList();
    final initialState = state.copy();
    final statesAfterMove = <CubeState>[];
    for (final move in recording.moves) {
      state.apply(move.move);
      statesAfterMove.add(state.copy());
    }
    final reachesEveryStage = descriptors.every(
      (descriptor) => descriptor.isAchieved(state, orientation),
    );
    final stages = reachesEveryStage
        ? _buildStages(recording, initialState, statesAfterMove, descriptors)
        : null;
    final complete = stages != null;
    return SolveAnalysis(
      analyzerVersion: currentSolveAnalyzerVersion,
      method: solve.method,
      protocolFamily: recording.protocolFamily.recordingSerializedValue,
      createdAt: (analyzedAt ?? DateTime.now()).toUtc(),
      isComplete: complete,
      failureReason: complete
          ? null
          : 'The recorded moves do not finish the configured method.',
      stages: stages ?? const [],
    );
  }

  List<SolveStageAnalysis>? _buildStages(
    SolveRecording recording,
    CubeState initialState,
    List<CubeState> statesAfterMove,
    List<StateDescriptor> descriptors,
  ) {
    final boundaries = List<int>.filled(descriptors.length, -1);
    var nextBoundary = statesAfterMove.length - 1;

    for (var index = descriptors.length - 1; index >= 0; index--) {
      final descriptor = descriptors[index];
      if (descriptor.isAchieved(initialState, orientation)) continue;

      var boundary = nextBoundary;
      while (boundary >= 0 &&
          !descriptor.isAchieved(statesAfterMove[boundary], orientation)) {
        boundary--;
      }
      if (boundary < 0) return null;
      while (boundary > 0 &&
          descriptor.isAchieved(statesAfterMove[boundary - 1], orientation)) {
        boundary--;
      }
      boundaries[index] = boundary;
      nextBoundary = boundary;
    }

    final stages = <SolveStageAnalysis>[];
    var firstMoveIndex = 0;
    for (var index = 0; index < descriptors.length; index++) {
      final boundary = boundaries[index];
      if (boundary < firstMoveIndex) {
        stages.add(_skippedStage(descriptors[index].kind));
        continue;
      }
      stages.add(
        _analyzeStage(
          recording,
          descriptors[index].kind,
          firstMoveIndex,
          boundary,
        ),
      );
      firstMoveIndex = boundary + 1;
    }
    return stages;
  }

  SolveAnalysis _unavailable(
    SolveRecord solve,
    SolveRecording recording,
    DateTime? analyzedAt,
    String reason,
  ) => SolveAnalysis(
    analyzerVersion: currentSolveAnalyzerVersion,
    method: solve.method,
    protocolFamily: recording.protocolFamily.recordingSerializedValue,
    createdAt: (analyzedAt ?? DateTime.now()).toUtc(),
    isComplete: false,
    failureReason: reason,
    stages: const [],
  );

  SolveStageAnalysis _analyzeStage(
    SolveRecording recording,
    SolveStageKind kind,
    int firstMoveIndex,
    int lastMoveIndex,
  ) {
    final moves = recording.moves
        .sublist(firstMoveIndex, lastMoveIndex + 1)
        .map((move) => move.move)
        .toList();
    final recognition = firstMoveIndex == 0
        ? recording.firstMoveFromSolveStart.duration
        : recording.intervalForMove(firstMoveIndex).duration;

    Duration? execution = Duration.zero;
    for (var index = firstMoveIndex + 1; index <= lastMoveIndex; index++) {
      final interval = recording.intervalForMove(index).duration;
      if (interval == null) {
        execution = null;
        break;
      }
      execution = execution! + interval;
    }

    final finalMove = recording.moves[lastMoveIndex];
    return SolveStageAnalysis(
      kind: kind,
      recognitionTime: recognition,
      executionTime: execution,
      totalTime: finalMove.hostOffset.isNegative ? null : finalMove.hostOffset,
      moves: moves,
      regripCount: recording.orientationAvailable
          ? _estimateRegrips(
              recording,
              recording.moves[firstMoveIndex].hostOffset,
              finalMove.hostOffset,
            )
          : null,
      skipped: false,
    );
  }

  SolveStageAnalysis _skippedStage(SolveStageKind kind) => SolveStageAnalysis(
    kind: kind,
    recognitionTime: Duration.zero,
    executionTime: Duration.zero,
    totalTime: null,
    moves: const [],
    regripCount: 0,
    skipped: true,
  );

  int _estimateRegrips(SolveRecording recording, Duration start, Duration end) {
    final orientations = recording.events
        .whereType<RecordedOrientation>()
        .where((event) => event.hostOffset >= start && event.hostOffset <= end)
        .map((event) => event.orientation.normalized())
        .whereType<CubeOrientation>()
        .toList();
    if (orientations.length < 2) return 0;

    var regrips = 0;
    var accumulated = 0.0;
    for (var index = 1; index < orientations.length; index++) {
      accumulated += orientations[index - 1].angularDistanceRadians(
        orientations[index],
      );
      if (accumulated < _regripThresholdRadians) continue;
      regrips++;
      accumulated = 0;
    }
    return regrips;
  }
}
