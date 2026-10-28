import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/practice/application/solve_analyzer.dart';
import 'package:crubik/features/practice/domain/solve_analysis.dart';
import 'package:crubik/features/practice/domain/solve_method.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
import 'package:crubik/features/practice/domain/solve_recording.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects all CFOP milestones including four separate F2L pairs', () {
    final solve = _solve(scramble: 'R');
    final recording = SolveRecording(
      protocolFamily: CubeProtocolFamily.gan,
      cubeTimestampsAvailable: true,
      orientationAvailable: false,
      events: [
        RecordedMove(
          sequence: 0,
          hostOffset: const Duration(seconds: 1),
          move: CubeMove.parse("R'"),
          serial: 1,
          recovered: false,
          cubeTimestamp: const Duration(milliseconds: 800),
        ),
      ],
    );

    final analysis = const SolveAnalyzer().analyze(
      solve: solve,
      recording: recording,
      analyzedAt: DateTime.utc(2026, 10, 28),
    );

    expect(analysis.isComplete, isTrue);
    expect(
      analysis.stages.map((stage) => stage.kind),
      containsAllInOrder(const [
        SolveStageKind.cross,
        SolveStageKind.f2lPair1,
        SolveStageKind.f2lPair2,
        SolveStageKind.f2lPair3,
        SolveStageKind.f2lPair4,
        SolveStageKind.lastLayerOriented,
        SolveStageKind.solved,
      ]),
    );
    expect(analysis.stages.first.moves.single.notation, "R'");
    expect(analysis.stages.skip(1).every((stage) => stage.skipped), isTrue);
    expect(analysis.stages.first.regripCount, isNull);
  });

  test('marks analysis unavailable when telemetry contains a gap', () {
    final recording = SolveRecording(
      protocolFamily: CubeProtocolFamily.moyu32,
      cubeTimestampsAvailable: false,
      orientationAvailable: false,
      events: const [
        RecordedDataGap(
          sequence: 0,
          hostOffset: Duration(milliseconds: 400),
          reason: RecordingGapReason.missedMoves,
          missingMoveCount: 1,
        ),
      ],
    );

    final analysis = const SolveAnalyzer().analyze(
      solve: _solve(scramble: 'R'),
      recording: recording,
    );

    expect(analysis.isComplete, isFalse);
    expect(analysis.stages, isEmpty);
    expect(analysis.failureReason, contains('telemetry gap'));
  });

  test('uses the final stable stage achievement after a regression', () {
    final solve = SolveRecord(
      id: 'regression',
      scramble: 'R',
      elapsed: const Duration(seconds: 3),
      moveCount: 3,
      createdAt: DateTime.utc(2026, 10, 28),
      inputSource: SolveInputSource.smartCube,
      method: SolveMethodConfig(
        preset: SolveMethodPreset.custom,
        customStages: const [SolveStageKind.cross, SolveStageKind.solved],
      ),
    );
    final moves = ["R'", 'R', "R'"];
    final recording = SolveRecording(
      protocolFamily: CubeProtocolFamily.gan,
      cubeTimestampsAvailable: false,
      orientationAvailable: false,
      events: [
        for (var index = 0; index < moves.length; index++)
          RecordedMove(
            sequence: index,
            hostOffset: Duration(seconds: index + 1),
            move: CubeMove.parse(moves[index]),
            serial: index,
            recovered: false,
          ),
      ],
    );

    final analysis = const SolveAnalyzer().analyze(
      solve: solve,
      recording: recording,
    );

    expect(analysis.isComplete, isTrue);
    expect(analysis.stages.first.moves, hasLength(3));
    expect(analysis.stages.last.skipped, isTrue);
  });

  test('round trips versioned analysis JSON', () {
    final analysis = SolveAnalysis(
      analyzerVersion: currentSolveAnalyzerVersion,
      method: SolveMethodConfig.preset(SolveMethodPreset.cfop),
      protocolFamily: 'gan',
      createdAt: DateTime.utc(2026, 10, 28),
      isComplete: true,
      stages: [
        SolveStageAnalysis(
          kind: SolveStageKind.cross,
          recognitionTime: const Duration(milliseconds: 800),
          executionTime: const Duration(milliseconds: 1200),
          totalTime: const Duration(seconds: 2),
          moves: [CubeMove.parse('F')],
          regripCount: 1,
          skipped: false,
        ),
      ],
    );

    final restored = SolveAnalysis.fromJson(analysis.toJson());

    expect(restored.analyzerVersion, currentSolveAnalyzerVersion);
    expect(restored.method.preset, SolveMethodPreset.cfop);
    expect(restored.stages.single.kind, SolveStageKind.cross);
    expect(restored.stages.single.moves.single.notation, 'F');
    expect(restored.stages.single.regripCount, 1);
  });
}

SolveRecord _solve({required String scramble}) => SolveRecord(
  id: 'solve',
  scramble: scramble,
  elapsed: const Duration(seconds: 1),
  moveCount: 1,
  createdAt: DateTime.utc(2026, 10, 28),
  inputSource: SolveInputSource.smartCube,
  method: SolveMethodConfig.preset(SolveMethodPreset.cfop),
);
