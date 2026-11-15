import 'dart:math' as math;

import '../../cube/domain/cube_model.dart';
import '../../cube/domain/smart_cube_event.dart';
import '../domain/countable_solve.dart';
import '../domain/solve_analysis.dart';
import '../domain/solve_method.dart';
import '../domain/solve_record.dart';
import '../domain/solve_recording.dart';

final class SolveAnalyzer {
  const SolveAnalyzer({this.orientation});

  static const _regripThresholdRadians = 30 * math.pi / 180;
  static const _regripSettleThresholdRadians = 2 * math.pi / 180;
  static const _regripSettleSamples = 2;
  static const _supportedOrientations = [
    SolveOrientation(crossFace: CubeFace.up),
    SolveOrientation(crossFace: CubeFace.down),
  ];

  /// Fixes the Cross face when known. Otherwise white and yellow are compared.
  final SolveOrientation? orientation;

  SolveAnalysis analyze({
    required SolveRecord solve,
    required SolveRecording recording,
    DateTime? analyzedAt,
  }) {
    final gap = recording.events.whereType<RecordedDataGap>().firstOrNull;
    if (gap != null) {
      return _unavailable(
        solve,
        recording,
        analyzedAt,
        'The recording contains a telemetry gap (${gap.reason.serializedValue}${gap.missingMoveCount == null ? '' : ', ${gap.missingMoveCount} missing moves'}).',
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
    final countableSolve = CountableSolve.fromMoves(
      recording.moves.map((move) => move.move),
    );
    final initialState = state.copy();
    final statesAfterMove = <CubeState>[];
    for (final move in countableSolve.moves) {
      state.apply(move);
      statesAfterMove.add(state.copy());
    }
    final regripTimes = recording.orientationAvailable
        ? _detectRegripTimes(recording)
        : null;
    final orientations = orientation == null
        ? _supportedOrientations
        : [orientation!];
    List<SolveStageAnalysis>? stages;
    for (final candidateOrientation in orientations) {
      final reachesEveryStage =
          state.isSolved &&
          descriptors.every(
            (descriptor) => descriptor.isAchieved(state, candidateOrientation),
          );
      if (!reachesEveryStage) continue;
      final candidate = _buildStages(
        recording,
        countableSolve,
        initialState,
        statesAfterMove,
        descriptors,
        candidateOrientation,
        regripTimes,
      );
      if (candidate != null && _isBetterSegmentation(candidate, stages)) {
        stages = candidate;
      }
    }
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
    CountableSolve countableSolve,
    CubeState initialState,
    List<CubeState> statesAfterMove,
    List<StateDescriptor> descriptors,
    SolveOrientation orientation,
    List<Duration>? regripTimes,
  ) {
    final boundaries = List<int>.filled(descriptors.length, -1);
    var earliestBoundary = 0;

    for (var index = 0; index < descriptors.length; index++) {
      final descriptor = descriptors[index];
      final isFinalStage = index == descriptors.length - 1;
      bool isAchieved(CubeState state) =>
          descriptor.isAchieved(state, orientation) &&
          (!isFinalStage || state.isSolved);
      if (isAchieved(initialState)) continue;

      var boundary = earliestBoundary;
      while (boundary < statesAfterMove.length &&
          !isAchieved(statesAfterMove[boundary])) {
        boundary++;
      }
      if (boundary == statesAfterMove.length) return null;
      boundaries[index] = boundary;
      earliestBoundary = boundary;
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
          countableSolve,
          descriptors[index].kind,
          firstMoveIndex,
          boundary,
          regripTimes,
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
    CountableSolve countableSolve,
    SolveStageKind kind,
    int firstMoveIndex,
    int lastMoveIndex,
    List<Duration>? regripTimes,
  ) {
    final moves = countableSolve.moves.sublist(
      firstMoveIndex,
      lastMoveIndex + 1,
    );
    final firstRawMoveIndex = countableSolve.rawMoveSpans[firstMoveIndex].first;
    final lastRawMoveIndex = countableSolve.rawMoveSpans[lastMoveIndex].last;
    final recognition = firstRawMoveIndex == 0
        ? recording.firstMoveFromSolveStart.duration
        : recording.intervalForMove(firstRawMoveIndex).duration;

    Duration? execution = Duration.zero;
    for (
      var index = firstRawMoveIndex + 1;
      index <= lastRawMoveIndex;
      index++
    ) {
      final interval = recording.intervalForMove(index).duration;
      if (interval == null) {
        execution = null;
        break;
      }
      execution = execution! + interval;
    }

    final finalMove = recording.moves[lastRawMoveIndex];
    final stageStartedAt = firstRawMoveIndex == 0
        ? Duration.zero
        : recording.moves[firstRawMoveIndex - 1].hostOffset;
    return SolveStageAnalysis(
      kind: kind,
      recognitionTime: recognition,
      executionTime: execution,
      totalTime: finalMove.hostOffset.isNegative ? null : finalMove.hostOffset,
      moves: moves,
      regripCount: regripTimes
          ?.where(
            (time) => time > stageStartedAt && time <= finalMove.hostOffset,
          )
          .length,
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

  static bool _isBetterSegmentation(
    List<SolveStageAnalysis> candidate,
    List<SolveStageAnalysis>? current,
  ) {
    if (current == null) return true;
    final candidateStages = candidate.where((stage) => !stage.skipped).length;
    final currentStages = current.where((stage) => !stage.skipped).length;
    if (candidateStages != currentStages) {
      return candidateStages > currentStages;
    }

    final candidateCrossMoves = candidate.firstOrNull?.moves.length ?? 0;
    final currentCrossMoves = current.firstOrNull?.moves.length ?? 0;
    return candidateCrossMoves < currentCrossMoves;
  }

  List<Duration>? _detectRegripTimes(SolveRecording recording) {
    final samples = recording.events
        .whereType<RecordedOrientation>()
        .map((event) {
          final orientation = event.orientation.normalized();
          return orientation == null
              ? null
              : (time: event.hostOffset, orientation: orientation);
        })
        .whereType<({Duration time, CubeOrientation orientation})>()
        .toList();
    if (samples.length < 2) return null;

    final regripTimes = <Duration>[];
    var baseline = samples.first.orientation;
    var previous = baseline;
    var isRegripping = false;
    var settledSamples = 0;
    Duration? thresholdCrossedAt;

    for (final sample in samples.skip(1)) {
      final stepDistance = previous.angularDistanceRadians(sample.orientation);
      final baselineDistance = baseline.angularDistanceRadians(
        sample.orientation,
      );
      previous = sample.orientation;

      if (!isRegripping) {
        if (baselineDistance < _regripThresholdRadians) continue;
        isRegripping = true;
        thresholdCrossedAt = sample.time;
        settledSamples = 0;
        continue;
      }

      if (stepDistance <= _regripSettleThresholdRadians) {
        settledSamples++;
      } else {
        settledSamples = 0;
      }
      if (settledSamples < _regripSettleSamples) continue;

      regripTimes.add(thresholdCrossedAt!);
      baseline = sample.orientation;
      isRegripping = false;
      settledSamples = 0;
      thresholdCrossedAt = null;
    }
    if (isRegripping) regripTimes.add(thresholdCrossedAt!);
    return List.unmodifiable(regripTimes);
  }
}
