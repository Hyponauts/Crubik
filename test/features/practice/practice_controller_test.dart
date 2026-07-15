import 'dart:convert';

import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records a timed solve and calculates basic statistics', () {
    final clock = _FakeSolveClock();
    var timestamp = DateTime.utc(2026, 1, 1);
    final controller = PracticeController(
      clock: clock,
      now: () {
        timestamp = timestamp.add(const Duration(seconds: 1));
        return timestamp;
      },
    );

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

    controller.dispose();
  });

  test('new scramble resets timer and captured moves', () {
    final clock = _FakeSolveClock();
    final controller = PracticeController(clock: clock);
    final original = controller.scramble.toString();
    controller.applyMove(CubeMove.parse('R'));

    controller.newScramble();

    expect(controller.timerPhase, SolveTimerPhase.ready);
    expect(controller.currentMoves, isEmpty);
    expect(controller.scramble.toString(), isNot(original));
    expect(controller.elapsed, Duration.zero);

    controller.dispose();
  });

  test('publishes monotonic move metadata only for applied moves', () {
    final controller = PracticeController();

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

  test('exports a versioned and lossless JSON solve history', () {
    final clock = _FakeSolveClock();
    final exportedAt = DateTime.utc(2026, 1, 1, 12);
    final controller = PracticeController(clock: clock, now: () => exportedAt);

    controller.startSolve();
    clock.value = const Duration(milliseconds: 12345);
    controller.applyMove(CubeMove.parse('R'));
    controller.stopSolve(inputSource: 'smart_cube');

    final payload = jsonDecode(controller.exportJson()) as Map<String, Object?>;
    final solves = payload['solves']! as List<Object?>;
    final solve = solves.single! as Map<String, Object?>;

    expect(payload['format'], 'crubik-solve-history');
    expect(payload['version'], 1);
    expect(solve['elapsed_ms'], 12345);
    expect(solve['move_count'], 1);
    expect(solve['input_source'], 'smart_cube');
    expect(solve['scramble'], isNotEmpty);

    controller.dispose();
  });

  test(
    'preserves the physical state when a smart cube gets a new scramble',
    () {
      final controller = PracticeController();
      final physicalState = CubeState.solved()..apply(CubeMove.parse('R'));
      controller.setSmartCubeConnected(true);
      controller.syncCubeState(physicalState);

      controller.newScramble();

      expect(controller.cubeState.facelets, physicalState.facelets);
      controller.dispose();
    },
  );

  test('a synced solved state stops a running smart-cube solve', () {
    final clock = _FakeSolveClock();
    final controller = PracticeController(clock: clock);
    controller.setSmartCubeConnected(true);
    controller.syncCubeState(CubeState.solved()..apply(CubeMove.parse('R')));
    controller.startSolve();
    clock.value = const Duration(seconds: 8);
    controller.applyMove(CubeMove.parse('U'), fromSmartCube: true);

    controller.syncCubeState(CubeState.solved());

    expect(controller.timerPhase, SolveTimerPhase.stopped);
    expect(controller.solves.single.inputSource, 'smart_cube_state');
    controller.dispose();
  });
}

final class _FakeSolveClock implements SolveClock {
  Duration value = Duration.zero;

  @override
  Duration get elapsed => value;

  @override
  void reset() => value = Duration.zero;

  @override
  void start() {}

  @override
  void stop() {}
}
