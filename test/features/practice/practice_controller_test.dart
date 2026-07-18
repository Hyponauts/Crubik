import 'dart:convert';
import 'dart:math';

import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/scramble_generator.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts unselected and ignores manual practice actions', () {
    final controller = PracticeController();
    final scramble = controller.scramble.toString();
    final facelets = controller.cubeState.facelets;

    controller.startSolve();
    controller.toggleTimer();
    controller.applyMove(CubeMove.parse('R'));
    controller.resetCubeToScramble();
    controller.newScramble();

    expect(controller.inputMode, PracticeInputMode.unselected);
    expect(controller.primaryActionEnabled, isFalse);
    expect(controller.phase, PracticePhase.manualReady);
    expect(controller.scramble.toString(), scramble);
    expect(controller.cubeState.facelets, facelets);
    expect(controller.currentMoves, isEmpty);
    expect(controller.solves, isEmpty);
    controller.dispose();
  });

  test('demo mode enables manual timing and virtual moves', () {
    final clock = _FakeSolveClock();
    final controller = PracticeController(clock: clock);

    controller.activateDemoInput();
    controller.startSolve();
    clock.value = const Duration(seconds: 12);
    controller.applyMove(CubeMove.parse('R'));
    controller.stopSolve();

    expect(controller.inputMode, PracticeInputMode.demo);
    expect(controller.solves.single.elapsed, const Duration(seconds: 12));
    expect(controller.solves.single.moveCount, 1);
    expect(controller.solves.single.inputSource, 'manual');
    controller.dispose();
  });

  test('leaving demo cancels an unsaved attempt and returns unselected', () {
    final clock = _FakeSolveClock();
    final controller = PracticeController(clock: clock);
    controller.activateDemoInput();
    controller.startSolve();
    clock.value = const Duration(seconds: 5);
    controller.applyMove(CubeMove.parse('R'));

    controller.clearDemoInput();

    expect(controller.inputMode, PracticeInputMode.unselected);
    expect(controller.phase, PracticePhase.manualReady);
    expect(controller.elapsed, Duration.zero);
    expect(controller.currentMoves, isEmpty);
    expect(controller.solves, isEmpty);
    expect(controller.primaryActionEnabled, isFalse);
    controller.dispose();
  });

  test('records a manual solve and calculates basic statistics', () {
    final clock = _FakeSolveClock();
    var timestamp = DateTime.utc(2026, 1, 1);
    final controller = PracticeController(
      clock: clock,
      now: () {
        timestamp = timestamp.add(const Duration(seconds: 1));
        return timestamp;
      },
    );
    controller.activateDemoInput();

    for (final seconds in [12, 10, 15, 11, 13]) {
      controller.startSolve();
      clock.value = Duration(seconds: seconds);
      controller.applyMove(CubeMove.parse('R'));
      controller.stopSolve();
    }

    expect(controller.solves, hasLength(5));
    expect(controller.bestTime, const Duration(seconds: 10));
    expect(controller.sessionAverage, const Duration(milliseconds: 12200));
    expect(controller.averageOfFive, const Duration(seconds: 12));
    expect(controller.solves.first.moveCount, 1);
    expect(controller.solves.first.startTrigger, SolveStartTrigger.manual);
    expect(controller.solves.first.inspectionElapsed, isNull);

    controller.dispose();
  });

  test('new scramble resets timer and captured solve moves', () {
    final clock = _FakeSolveClock();
    final controller = PracticeController(clock: clock);
    controller.activateDemoInput();
    final original = controller.scramble.toString();
    controller.startSolve();
    controller.applyMove(CubeMove.parse('R'));
    controller.stopSolve();

    controller.newScramble();

    expect(controller.phase, PracticePhase.manualReady);
    expect(controller.currentMoves, isEmpty);
    expect(controller.scramble.toString(), isNot(original));
    expect(controller.elapsed, Duration.zero);

    controller.dispose();
  });

  test('publishes monotonic move metadata only for applied moves', () {
    final controller = PracticeController();
    controller.activateDemoInput();

    expect(controller.lastAppliedMove, isNull);
    expect(controller.cubeMoveRevision, 0);

    controller.syncCubeState(CubeState.solved());
    expect(controller.cubeMoveRevision, 0);

    controller.applyMove(CubeMove.parse('R'));
    expect(controller.lastAppliedMove, CubeMove.parse('R'));
    expect(controller.cubeMoveRevision, 1);

    controller.applyMove(CubeMove.parse("U'"));
    expect(controller.lastAppliedMove, CubeMove.parse("U'"));
    expect(controller.cubeMoveRevision, 2);

    controller.dispose();
  });

  test('exports version 2 solve history while retaining manual metadata', () {
    final clock = _FakeSolveClock();
    final exportedAt = DateTime.utc(2026, 1, 1, 12);
    final controller = PracticeController(clock: clock, now: () => exportedAt);
    controller.activateDemoInput();

    controller.startSolve();
    clock.value = const Duration(milliseconds: 12345);
    controller.applyMove(CubeMove.parse('R'));
    controller.stopSolve(inputSource: 'manual');

    final payload = jsonDecode(controller.exportJson()) as Map<String, Object?>;
    final solves = payload['solves']! as List<Object?>;
    final solve = solves.single! as Map<String, Object?>;

    expect(payload['format'], 'crubik-solve-history');
    expect(payload['version'], 2);
    expect(solve['elapsed_ms'], 12345);
    expect(solve['move_count'], 1);
    expect(solve['input_source'], 'manual');
    expect(solve['start_trigger'], 'manual');
    expect(solve['inspection_elapsed_ms'], isNull);
    expect(solve['scramble'], isNotEmpty);

    controller.dispose();
  });

  test(
    'preserves the physical state when a smart cube gets a new scramble',
    () {
      final controller = PracticeController();
      final physicalState = CubeState.solved()..apply(CubeMove.parse('R'));
      controller.activateSmartCubeInput();
      controller.syncCubeState(physicalState);

      controller.newScramble();

      expect(controller.cubeState.facelets, physicalState.facelets);
      expect(controller.phase, PracticePhase.needsSolvedCube);
      controller.dispose();
    },
  );

  test('connected cube waits for state and requires a solved baseline', () {
    final controller = PracticeController();

    controller.activateSmartCubeInput();
    expect(controller.phase, PracticePhase.awaitingCubeState);
    expect(controller.primaryActionEnabled, isFalse);

    controller.syncCubeState(CubeState.solved()..apply(CubeMove.parse('R')));
    expect(controller.phase, PracticePhase.needsSolvedCube);

    controller.syncCubeState(CubeState.solved());
    expect(controller.phase, PracticePhase.scrambling);
    expect(controller.scrambleGuidance, controller.scramble.moves);

    controller.dispose();
  });

  test('wrong turns create a corrective route to the exact target', () {
    final controller = PracticeController(
      scrambleGenerator: ScrambleGenerator(random: Random(7)),
    );
    controller.activateSmartCubeInput();
    controller.syncCubeState(CubeState.solved());

    final first = controller.scramble.moves.first;
    final wrongFace = first.face == CubeFace.up ? CubeFace.right : CubeFace.up;
    controller.applyMove(
      CubeMove(wrongFace),
      fromSmartCube: true,
      occurredAt: DateTime.utc(2026),
    );

    expect(controller.guidanceIsCorrection, isTrue);
    expect(controller.completedScrambleMoveCount, 0);
    final corrected = controller.cubeState.copy()
      ..applyAll(controller.scrambleGuidance);
    final target = CubeState.solved()..applyAll(controller.scramble.moves);
    expect(corrected.facelets, target.facelets);

    for (final move in [...controller.scrambleGuidance]) {
      controller.applyMove(
        move,
        fromSmartCube: true,
        occurredAt: DateTime.utc(2026),
      );
    }

    expect(controller.phase, PracticePhase.inspectionDelay);
    expect(
      controller.completedScrambleMoveCount,
      controller.scramble.moves.length,
    );
    expect(controller.currentMoves, isEmpty);
    controller.dispose();
  });

  test('recovery moves stay ahead of the original suffix and replan live', () {
    final controller = PracticeController(
      scrambleGenerator: ScrambleGenerator(random: Random(7)),
    );
    final occurredAt = DateTime.utc(2026);
    controller.activateSmartCubeInput();
    controller.syncCubeState(CubeState.solved());

    final first = controller.scramble.moves.first;
    final expectedNext = controller.scramble.moves[1];
    controller.applyMove(first, fromSmartCube: true, occurredAt: occurredAt);

    final wrongFace = CubeFace.values.firstWhere(
      (face) => face != first.face && face != expectedNext.face,
    );
    final secondWrongFace = CubeFace.values.firstWhere(
      (face) =>
          face != first.face && face != expectedNext.face && face != wrongFace,
    );
    final wrong = CubeMove(wrongFace);
    final secondWrong = CubeMove(secondWrongFace);
    controller.applyMove(wrong, fromSmartCube: true, occurredAt: occurredAt);
    controller.applyMove(
      secondWrong,
      fromSmartCube: true,
      occurredAt: occurredAt,
    );

    expect(controller.completedScrambleMoveCount, 1);
    expect(controller.scrambleRecoveryMoves, [
      secondWrong.inverse,
      wrong.inverse,
    ]);
    expect(controller.scrambleGuidance, [
      secondWrong.inverse,
      wrong.inverse,
      ...controller.scramble.moves.skip(1),
    ]);
    expect(
      () => controller.scrambleRecoveryMoves.add(CubeMove.parse('R')),
      throwsUnsupportedError,
    );

    controller.applyMove(
      secondWrong.inverse,
      fromSmartCube: true,
      occurredAt: occurredAt,
    );
    expect(controller.scrambleRecoveryMoves, [wrong.inverse]);

    final replanningFace = CubeFace.values.firstWhere(
      (face) => face != first.face && face != wrongFace,
    );
    final replanningWrong = CubeMove(replanningFace);
    controller.applyMove(
      replanningWrong,
      fromSmartCube: true,
      occurredAt: occurredAt,
    );
    expect(controller.scrambleRecoveryMoves, [
      replanningWrong.inverse,
      wrong.inverse,
    ]);

    for (final move in [...controller.scrambleRecoveryMoves]) {
      controller.applyMove(move, fromSmartCube: true, occurredAt: occurredAt);
    }
    expect(controller.scrambleRecoveryMoves, isEmpty);
    expect(controller.guidanceIsCorrection, isFalse);
    expect(controller.nextScrambleMove, expectedNext);

    for (final move in [...controller.scrambleGuidance]) {
      controller.applyMove(move, fromSmartCube: true, occurredAt: occurredAt);
    }
    expect(controller.phase, PracticePhase.inspectionDelay);
    final target = CubeState.solved()..applyAll(controller.scramble.moves);
    expect(controller.cubeState.facelets, target.facelets);
    controller.dispose();
  });

  test('same-face recovery does not merge with the original next move', () {
    final controller = PracticeController(
      scrambleGenerator: ScrambleGenerator(random: Random(7)),
    );
    final occurredAt = DateTime.utc(2026);
    controller.activateSmartCubeInput();
    controller.syncCubeState(CubeState.solved());

    final expectedIndex = controller.scramble.moves.indexWhere(
      (move) => move.turns != 2,
    );
    expect(expectedIndex, isNonNegative);
    for (final move in controller.scramble.moves.take(expectedIndex)) {
      controller.applyMove(move, fromSmartCube: true, occurredAt: occurredAt);
    }
    final expected = controller.scramble.moves[expectedIndex];
    controller.applyMove(
      expected.inverse,
      fromSmartCube: true,
      occurredAt: occurredAt,
    );

    expect(controller.scrambleRecoveryMoves, [expected]);
    expect(controller.scrambleGuidance.take(2), [expected, expected]);

    controller.applyMove(expected, fromSmartCube: true, occurredAt: occurredAt);
    expect(controller.scrambleRecoveryMoves, isEmpty);
    expect(controller.guidanceIsCorrection, isFalse);
    expect(controller.nextScrambleMove, expected);
    controller.dispose();
  });

  test('either turn direction satisfies a double-turn scramble move', () {
    for (final quarterTurns in [1, 3]) {
      final controller = PracticeController(
        scrambleGenerator: ScrambleGenerator(random: Random(7)),
      );
      controller.activateSmartCubeInput();
      controller.syncCubeState(CubeState.solved());
      var splitDoubleTurn = false;

      for (final move in controller.scramble.moves) {
        if (!splitDoubleTurn && move.turns == 2) {
          splitDoubleTurn = true;
          final completedBeforeDoubleTurn =
              controller.completedScrambleMoveCount;
          final quarterMove = CubeMove(move.face, turns: quarterTurns);
          controller.applyMove(
            quarterMove,
            fromSmartCube: true,
            occurredAt: DateTime.utc(2026),
          );
          expect(controller.guidanceIsCorrection, isFalse);
          expect(controller.nextScrambleMove, quarterMove);
          expect(
            controller.completedScrambleMoveCount,
            completedBeforeDoubleTurn,
          );
          expect(controller.partialScrambleMoveTurnCount, 1);
          controller.applyMove(
            quarterMove,
            fromSmartCube: true,
            occurredAt: DateTime.utc(2026),
          );
          expect(
            controller.completedScrambleMoveCount,
            completedBeforeDoubleTurn + 1,
          );
          expect(controller.partialScrambleMoveTurnCount, 0);
        } else {
          controller.applyMove(
            move,
            fromSmartCube: true,
            occurredAt: DateTime.utc(2026),
          );
        }
      }

      expect(splitDoubleTurn, isTrue);
      expect(controller.phase, PracticePhase.inspectionDelay);
      controller.dispose();
    }
  });

  test('double turns accept either direction on every cube face', () {
    for (final face in CubeFace.values) {
      for (final quarterTurns in [1, 3]) {
        final controller = PracticeController(
          scrambleGenerator: ScrambleGenerator(
            random: _FaceFirstDoubleTurnRandom(face),
          ),
        );
        controller.activateSmartCubeInput();
        controller.syncCubeState(CubeState.solved());

        final doubleTurn = controller.scramble.moves.first;
        expect(doubleTurn, CubeMove(face, turns: 2));
        final quarterMove = CubeMove(face, turns: quarterTurns);

        controller.applyMove(
          quarterMove,
          fromSmartCube: true,
          occurredAt: DateTime.utc(2026),
        );

        expect(
          controller.guidanceIsCorrection,
          isFalse,
          reason: '${doubleTurn.notation} must accept $quarterMove first',
        );
        expect(controller.partialScrambleMoveTurnCount, 1);
        expect(controller.nextScrambleMove, quarterMove);

        controller.applyMove(
          quarterMove,
          fromSmartCube: true,
          occurredAt: DateTime.utc(2026),
        );

        expect(controller.completedScrambleMoveCount, 1);
        expect(controller.partialScrambleMoveTurnCount, 0);
        expect(controller.guidanceIsCorrection, isFalse);
        controller.dispose();
      }
    }
  });

  test('verified scramble waits three seconds before inspection', () {
    var now = DateTime.utc(2026);
    final controller = PracticeController(
      scrambleGenerator: ScrambleGenerator(random: Random(7)),
      now: () => now,
    );

    _matchConnectedScramble(controller, now);

    expect(controller.phase, PracticePhase.inspectionDelay);
    expect(
      controller.preInspectionRemaining,
      PracticeController.defaultPreInspectionDelay,
    );

    now = now.add(const Duration(seconds: 1));
    controller.applyMove(
      CubeMove.parse('R'),
      fromSmartCube: true,
      occurredAt: now,
    );
    expect(controller.phase, PracticePhase.scrambling);
    controller.applyMove(
      CubeMove.parse("R'"),
      fromSmartCube: true,
      occurredAt: now,
    );

    expect(controller.phase, PracticePhase.inspectionDelay);
    expect(
      controller.preInspectionRemaining,
      PracticeController.defaultPreInspectionDelay,
    );
    controller.dispose();
  });

  test('pre-inspection delay automatically enters inspection', () async {
    final controller = PracticeController(
      scrambleGenerator: ScrambleGenerator(random: Random(7)),
      preInspectionDelay: const Duration(milliseconds: 20),
    );
    _matchConnectedScramble(controller, DateTime.now());

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(controller.phase, PracticePhase.inspection);
    controller.dispose();
  });

  test('mismatching authoritative resync requires a solved cube', () {
    final controller = PracticeController(
      scrambleGenerator: ScrambleGenerator(random: Random(7)),
    );
    controller.activateSmartCubeInput();
    controller.syncCubeState(CubeState.solved());
    controller.applyMove(
      controller.scramble.moves.first,
      fromSmartCube: true,
      occurredAt: DateTime.utc(2026),
    );

    final unexpected = CubeState.solved()
      ..apply(CubeMove(controller.scramble.moves.first.face.inverseFace));
    controller.syncCubeState(unexpected);

    expect(controller.phase, PracticePhase.needsSolvedCube);
    expect(controller.scrambleGuidance, isEmpty);
    controller.dispose();
  });

  test('first inspection move starts timing and is captured', () {
    final clock = _FakeSolveClock();
    var now = DateTime.utc(2026);
    final controller = PracticeController(
      clock: clock,
      now: () => now,
      preInspectionDelay: Duration.zero,
    );
    _prepareConnectedCube(controller, now);

    now = now.add(const Duration(seconds: 4));
    controller.applyMove(
      CubeMove.parse('R'),
      fromSmartCube: true,
      occurredAt: now,
    );

    expect(controller.phase, PracticePhase.solving);
    expect(controller.currentMoves, [CubeMove.parse('R')]);
    clock.value = const Duration(seconds: 8);
    controller.syncCubeState(CubeState.solved(), occurredAt: now);

    expect(controller.phase, PracticePhase.stopped);
    expect(
      controller.solves.single.inspectionElapsed,
      const Duration(seconds: 4),
    );
    expect(controller.solves.single.startTrigger, SolveStartTrigger.firstMove);
    expect(controller.solves.single.moveCount, 1);
    controller.dispose();
  });

  test('an overdue inspection starts at the deadline', () {
    final clock = _FakeSolveClock();
    var now = DateTime.utc(2026);
    final controller = PracticeController(
      clock: clock,
      now: () => now,
      preInspectionDelay: Duration.zero,
    );
    _prepareConnectedCube(controller, now);

    now = now.add(const Duration(seconds: 17));
    controller.applyMove(
      CubeMove.parse('R'),
      fromSmartCube: true,
      occurredAt: now,
    );

    expect(controller.phase, PracticePhase.solving);
    expect(controller.elapsed, const Duration(seconds: 2));
    controller.syncCubeState(CubeState.solved(), occurredAt: now);
    expect(
      controller.solves.single.inspectionElapsed,
      PracticeController.defaultInspectionDuration,
    );
    expect(
      controller.solves.single.startTrigger,
      SolveStartTrigger.inspectionTimeout,
    );
    controller.dispose();
  });

  test('inspection timeout automatically enters solving', () async {
    final clock = _FakeSolveClock();
    final controller = PracticeController(
      clock: clock,
      preInspectionDelay: Duration.zero,
      inspectionDuration: const Duration(milliseconds: 20),
    );
    _prepareConnectedCube(controller, DateTime.now());

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(controller.phase, PracticePhase.solving);
    controller.syncCubeState(CubeState.solved());
    expect(
      controller.solves.single.startTrigger,
      SolveStartTrigger.inspectionTimeout,
    );
    controller.dispose();
  });

  test('changed state packet during inspection starts the solve', () {
    var now = DateTime.utc(2026);
    final controller = PracticeController(
      now: () => now,
      preInspectionDelay: Duration.zero,
    );
    _prepareConnectedCube(controller, now);
    now = now.add(const Duration(seconds: 3));
    final changedState = controller.cubeState.copy()
      ..apply(CubeMove.parse('R'));

    controller.syncCubeState(changedState, occurredAt: now);

    expect(controller.phase, PracticePhase.solving);
    expect(controller.currentMoves, isEmpty);
    controller.syncCubeState(CubeState.solved(), occurredAt: now);
    expect(
      controller.solves.single.inspectionElapsed,
      const Duration(seconds: 3),
    );
    expect(controller.solves.single.startTrigger, SolveStartTrigger.firstMove);
    controller.dispose();
  });

  test('aborting a connected attempt does not save a solve', () {
    final controller = PracticeController(preInspectionDelay: Duration.zero);
    _prepareConnectedCube(controller, DateTime.now());

    controller.abortAttempt();

    expect(controller.solves, isEmpty);
    expect(controller.currentMoves, isEmpty);
    expect(controller.phase, PracticePhase.needsSolvedCube);
    controller.dispose();
  });

  test('disconnect preserves an active attempt for state-based completion', () {
    final clock = _FakeSolveClock();
    final controller = PracticeController(
      clock: clock,
      preInspectionDelay: Duration.zero,
    );
    final now = DateTime.now();
    _prepareConnectedCube(controller, now);
    controller.applyMove(
      CubeMove.parse('R'),
      fromSmartCube: true,
      occurredAt: now,
    );
    clock.value = const Duration(seconds: 8);

    controller.markSmartCubeDisconnected();
    expect(controller.inputMode, PracticeInputMode.smartCube);
    expect(controller.phase, PracticePhase.solving);
    controller.activateSmartCubeInput();
    controller.syncCubeState(CubeState.solved(), occurredAt: now);

    expect(controller.phase, PracticePhase.stopped);
    expect(controller.solves.single.inputSource, 'smart_cube_state');
    controller.dispose();
  });
}

void _prepareConnectedCube(PracticeController controller, DateTime occurredAt) {
  _matchConnectedScramble(controller, occurredAt);
  expect(controller.phase, PracticePhase.inspection);
}

void _matchConnectedScramble(
  PracticeController controller,
  DateTime occurredAt,
) {
  controller.activateSmartCubeInput();
  controller.syncCubeState(CubeState.solved(), occurredAt: occurredAt);
  for (final move in [...controller.scramble.moves]) {
    controller.applyMove(move, fromSmartCube: true, occurredAt: occurredAt);
  }
}

extension on CubeFace {
  CubeFace get inverseFace => switch (this) {
    CubeFace.up => CubeFace.down,
    CubeFace.right => CubeFace.left,
    CubeFace.front => CubeFace.back,
    CubeFace.down => CubeFace.up,
    CubeFace.left => CubeFace.right,
    CubeFace.back => CubeFace.front,
  };
}

final class _FakeSolveClock implements SolveClock {
  Duration value = Duration.zero;

  @override
  Duration get elapsed => value;

  @override
  void reset() => value = Duration.zero;

  @override
  void start({Duration initialElapsed = Duration.zero}) {
    value = initialElapsed;
  }

  @override
  void stop() {}
}

final class _FaceFirstDoubleTurnRandom implements Random {
  _FaceFirstDoubleTurnRandom(CubeFace firstFace) : _faceIndex = firstFace.index;

  int _faceIndex;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) {
    if (max == CubeFace.values.length) {
      return _faceIndex++ % CubeFace.values.length;
    }
    if (max == 3) return 1;
    return 0;
  }
}
