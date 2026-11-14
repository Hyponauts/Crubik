import 'dart:math' as math;

import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/smart_cube_event.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/practice/application/solve_analyzer.dart';
import 'package:crubik/features/practice/domain/solve_analysis.dart';
import 'package:crubik/features/practice/domain/solve_method.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
import 'package:crubik/features/practice/domain/solve_recording.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('presets end in their named last-layer stage', () {
    expect(
      SolveMethodConfig.preset(SolveMethodPreset.cfop).stages.last,
      SolveStageKind.lastLayerPermuted,
    );
    expect(
      SolveMethodConfig.preset(SolveMethodPreset.twoLookCfop).stages.skip(5),
      [
        SolveStageKind.lastLayerEdgesOriented,
        SolveStageKind.lastLayerCornersOriented,
        SolveStageKind.lastLayerPermuted,
      ],
    );
    expect(
      SolveMethodConfig.preset(SolveMethodPreset.fourLookCfop).stages.skip(5),
      [
        SolveStageKind.lastLayerEdgesOriented,
        SolveStageKind.lastLayerCornersOriented,
        SolveStageKind.lastLayerCornersPermuted,
        SolveStageKind.lastLayerEdgesPermuted,
      ],
    );
    expect(SolveStageKind.lastLayerCornersOriented.shortLabel, 'COLL');
    expect(SolveStageKind.lastLayerPermuted.shortLabel, 'PLL');
  });

  test('legacy solved stage is read as the named PLL stage', () {
    final method = SolveMethodConfig.fromJson({
      'preset': 'custom',
      'stages': ['cross', 'solved'],
    });

    expect(method.stages.last, SolveStageKind.lastLayerPermuted);
    expect(method.toJson()['stages'], ['cross', 'last_layer_permuted']);
  });

  test(
    'last-layer stage predicates distinguish orientation and permutation',
    () {
      const orientation = SolveOrientation(crossFace: CubeFace.up);
      final cornerTwist = CubeState.fromCubieCoordinates(
        cornerPermutation: List.generate(8, (index) => index),
        cornerOrientations: [0, 0, 0, 0, 1, 2, 0, 0],
        edgePermutation: List.generate(12, (index) => index),
        edgeOrientations: List.filled(12, 0),
      );
      final edgeFlip = CubeState.fromCubieCoordinates(
        cornerPermutation: List.generate(8, (index) => index),
        cornerOrientations: List.filled(8, 0),
        edgePermutation: List.generate(12, (index) => index),
        edgeOrientations: [0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0],
      );
      final cornerCycle = CubeState.fromCubieCoordinates(
        cornerPermutation: [0, 1, 2, 3, 4, 6, 7, 5],
        cornerOrientations: List.filled(8, 0),
        edgePermutation: List.generate(12, (index) => index),
        edgeOrientations: List.filled(12, 0),
      );
      final edgeCycle = CubeState.fromCubieCoordinates(
        cornerPermutation: List.generate(8, (index) => index),
        cornerOrientations: List.filled(8, 0),
        edgePermutation: [0, 1, 2, 3, 5, 6, 4, 7, 8, 9, 10, 11],
        edgeOrientations: List.filled(12, 0),
      );

      expect(
        descriptorFor(
          SolveStageKind.lastLayerEdgesOriented,
        ).isAchieved(cornerTwist, orientation),
        isTrue,
      );
      expect(
        descriptorFor(
          SolveStageKind.lastLayerCornersOriented,
        ).isAchieved(cornerTwist, orientation),
        isFalse,
      );
      expect(
        descriptorFor(
          SolveStageKind.lastLayerEdgesOriented,
        ).isAchieved(edgeFlip, orientation),
        isFalse,
      );
      expect(
        descriptorFor(
          SolveStageKind.lastLayerCornersOriented,
        ).isAchieved(edgeFlip, orientation),
        isTrue,
      );
      expect(
        descriptorFor(
          SolveStageKind.lastLayerEdgesPermuted,
        ).isAchieved(cornerCycle, orientation),
        isTrue,
      );
      expect(
        descriptorFor(
          SolveStageKind.lastLayerCornersPermuted,
        ).isAchieved(cornerCycle, orientation),
        isFalse,
      );
      expect(
        descriptorFor(
          SolveStageKind.lastLayerCornersPermuted,
        ).isAchieved(edgeCycle, orientation),
        isTrue,
      );
      expect(
        descriptorFor(
          SolveStageKind.lastLayerEdgesPermuted,
        ).isAchieved(edgeCycle, orientation),
        isFalse,
      );
    },
  );

  test('implicit solved check closes the last named custom stage', () {
    final solve = SolveRecord(
      id: 'implicit-solved',
      scramble: 'D',
      elapsed: const Duration(seconds: 1),
      moveCount: 1,
      createdAt: DateTime.utc(2026, 10, 28),
      inputSource: SolveInputSource.smartCube,
      method: SolveMethodConfig(
        preset: SolveMethodPreset.custom,
        customStages: const [
          SolveStageKind.cross,
          SolveStageKind.lastLayerEdgesOriented,
        ],
      ),
    );
    SolveAnalysis analyze(String notation) => const SolveAnalyzer().analyze(
      solve: solve,
      recording: SolveRecording(
        protocolFamily: CubeProtocolFamily.gan,
        cubeTimestampsAvailable: false,
        orientationAvailable: false,
        events: [
          RecordedMove(
            sequence: 0,
            hostOffset: const Duration(seconds: 1),
            move: CubeMove.parse(notation),
            serial: 1,
            recovered: false,
          ),
        ],
      ),
    );

    final complete = analyze("D'");
    final incomplete = analyze('D');

    expect(complete.isComplete, isTrue);
    expect(complete.stages.last.kind, SolveStageKind.lastLayerEdgesOriented);
    expect(complete.stages.last.moves.single.notation, "D'");
    expect(incomplete.isComplete, isFalse);
  });

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
        SolveStageKind.lastLayerPermuted,
      ]),
    );
    expect(analysis.stages.first.moves.single.notation, "R'");
    expect(analysis.stages.skip(1).every((stage) => stage.skipped), isTrue);
    expect(analysis.stages.first.regripCount, isNull);
  });

  test('analyzes a double quarter turn as one turn with full step TPS', () {
    final solve = SolveRecord(
      id: 'double-turn',
      scramble: 'B2',
      elapsed: const Duration(seconds: 2),
      moveCount: 1,
      createdAt: DateTime.utc(2026, 10, 29),
      inputSource: SolveInputSource.smartCube,
      method: SolveMethodConfig(
        preset: SolveMethodPreset.custom,
        customStages: const [SolveStageKind.lastLayerPermuted],
      ),
    );
    final recording = SolveRecording(
      protocolFamily: CubeProtocolFamily.gan,
      cubeTimestampsAvailable: false,
      orientationAvailable: false,
      events: [
        for (var index = 0; index < 2; index++)
          RecordedMove(
            sequence: index,
            hostOffset: Duration(seconds: index + 1),
            move: CubeMove.parse('B'),
            serial: index,
            recovered: false,
          ),
      ],
    );

    final analysis = const SolveAnalyzer().analyze(
      solve: solve,
      recording: recording,
    );
    final stage = analysis.stages.single;

    expect(analysis.isComplete, isTrue);
    expect(analysis.moveCount, 1);
    expect(stage.moves.single.notation, 'B2');
    expect(stage.recognitionTime, const Duration(seconds: 1));
    expect(stage.executionTime, const Duration(seconds: 1));
    expect(stage.stepTime, const Duration(seconds: 2));
    expect(stage.turnsPerSecond, 0.5);
    expect(solve.turnsPerSecond, 0.5);
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
    expect(
      analysis.failureReason,
      contains('telemetry gap (missed_moves, 1 missing moves)'),
    );
  });

  test('keeps the first Cross boundary when later turns break it', () {
    final solve = SolveRecord(
      id: 'regression',
      scramble: 'D R',
      elapsed: const Duration(seconds: 4),
      moveCount: 4,
      createdAt: DateTime.utc(2026, 10, 28),
      inputSource: SolveInputSource.smartCube,
      method: SolveMethodConfig(
        preset: SolveMethodPreset.custom,
        customStages: const [
          SolveStageKind.cross,
          SolveStageKind.lastLayerPermuted,
        ],
      ),
    );
    final moves = ["R'", 'R', "R'", "D'"];
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
    expect(analysis.stages.first.moves.map((move) => move.notation), ["R'"]);
    expect(analysis.stages.last.moves.map((move) => move.notation), [
      'R',
      "R'",
      "D'",
    ]);
  });

  test(
    'auto-detects a yellow Cross instead of assigning the solve to Cross',
    () {
      final solve = SolveRecord(
        id: 'yellow-cross',
        scramble: 'U',
        elapsed: const Duration(seconds: 1),
        moveCount: 1,
        createdAt: DateTime.utc(2026, 10, 28),
        inputSource: SolveInputSource.smartCube,
        method: SolveMethodConfig(
          preset: SolveMethodPreset.custom,
          customStages: const [
            SolveStageKind.cross,
            SolveStageKind.lastLayerPermuted,
          ],
        ),
      );
      final recording = SolveRecording(
        protocolFamily: CubeProtocolFamily.gan,
        cubeTimestampsAvailable: false,
        orientationAvailable: false,
        events: [
          RecordedMove(
            sequence: 0,
            hostOffset: const Duration(seconds: 1),
            move: CubeMove.parse("U'"),
            serial: 1,
            recovered: false,
          ),
        ],
      );

      final analysis = const SolveAnalyzer().analyze(
        solve: solve,
        recording: recording,
      );

      expect(analysis.isComplete, isTrue);
      expect(analysis.stages.first.skipped, isTrue);
      expect(analysis.stages.last.moves.single.notation, "U'");
    },
  );

  test('counts a continuous cube rotation as one regrip episode', () {
    final angles = [0.0, 10.0, 20.0, 35.0, 55.0, 75.0, 90.0, 90.5, 90.0];
    final events = <SolveRecordingEvent>[
      for (var index = 0; index < angles.length; index++)
        RecordedOrientation(
          sequence: index,
          hostOffset: Duration(milliseconds: index * 100),
          orientation: _orientationForDegrees(angles[index]),
        ),
      RecordedMove(
        sequence: angles.length,
        hostOffset: const Duration(seconds: 1),
        move: CubeMove.parse("R'"),
        serial: 1,
        recovered: false,
      ),
    ];
    final recording = SolveRecording(
      protocolFamily: CubeProtocolFamily.gan,
      cubeTimestampsAvailable: false,
      orientationAvailable: true,
      events: events,
    );

    final analysis = const SolveAnalyzer().analyze(
      solve: _solve(scramble: 'R'),
      recording: recording,
    );

    expect(analysis.stages.first.regripCount, 1);
  });

  test('gyro capability without two samples does not report zero regrips', () {
    final analysis = const SolveAnalyzer().analyze(
      solve: _solve(scramble: 'R'),
      recording: SolveRecording(
        protocolFamily: CubeProtocolFamily.gan,
        cubeTimestampsAvailable: false,
        orientationAvailable: true,
        events: [
          RecordedOrientation(
            sequence: 0,
            hostOffset: Duration.zero,
            orientation: _orientationForDegrees(0),
          ),
          RecordedMove(
            sequence: 1,
            hostOffset: const Duration(seconds: 1),
            move: CubeMove.parse("R'"),
            serial: 1,
            recovered: false,
          ),
        ],
      ),
    );

    expect(analysis.isComplete, isTrue);
    expect(analysis.stages.first.regripCount, isNull);
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

CubeOrientation _orientationForDegrees(double degrees) {
  final halfAngle = degrees * math.pi / 360;
  return CubeOrientation(
    x: 0,
    y: math.sin(halfAngle),
    z: 0,
    w: math.cos(halfAngle),
  );
}
