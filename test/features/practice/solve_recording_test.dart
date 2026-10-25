import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crubik/core/time/monotonic_clock.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/cube/domain/smart_cube_event.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';
import 'package:crubik/features/practice/application/solve_recording_builder.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
import 'package:crubik/features/practice/domain/solve_recording.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/practice_controller_factory.dart';

void main() {
  test(
    'derives honest intervals for cube, host, recovered, and gap timing',
    () {
      final builder = SolveRecordingBuilder()..start(Duration.zero);
      for (final (serial, cubeTimestamp, recovered) in [
        (1, 100, false),
        (2, 180, true),
        (3, null, true),
        (4, null, false),
        (5, null, false),
      ]) {
        builder.recordMove(
          _move(
            serial,
            serial * 100,
            cubeTimestamp: cubeTimestamp,
            recovered: recovered,
          ),
        );
      }
      builder.recordGap(
        RecordingGapReason.missedMoves,
        const Duration(milliseconds: 550),
      );
      builder.recordMove(_move(6, 600));
      final recording = builder.finish()!;

      expect(recording.intervalForMove(0).duration, isNull);
      expect(
        recording.intervalForMove(1).duration,
        const Duration(milliseconds: 80),
      );
      expect(
        recording.intervalForMove(1).source,
        RecordingTimingSource.cubeClock,
      );
      expect(
        recording.intervalForMove(2).source,
        RecordingTimingSource.unavailable,
      );
      expect(
        recording.intervalForMove(3).source,
        RecordingTimingSource.unavailable,
      );
      expect(
        recording.intervalForMove(4).source,
        RecordingTimingSource.hostReceipt,
      );
      expect(
        recording.intervalForMove(5).source,
        RecordingTimingSource.unavailable,
      );
      expect(
        recording.firstMoveFromSolveStart.duration,
        const Duration(milliseconds: 100),
      );
      expect(
        SolveRecording.fromJson(recording.toJson()).toJson(),
        recording.toJson(),
      );
      expect(
        () => SolveRecording.fromJson({
          ...recording.toJson(),
          'format_version': 999,
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'retains normalized pose boundaries, source metadata, and queued gaps',
    () {
      final builder = SolveRecordingBuilder();
      builder.configureSource(protocolFamily: CubeProtocolFamily.gan);
      builder.observeOrientation(_pose(0, 950, sign: -2));
      builder.queueGap(
        RecordingGapReason.connectionDiscontinuity,
        const Duration(milliseconds: 990),
      );
      builder.start(const Duration(seconds: 1));
      builder.recordMove(_move(1, 1000));
      for (final (degrees, time) in [(0.5, 1010), (0.8, 1020), (1.2, 1030)]) {
        builder.observeOrientation(_pose(degrees, time));
      }
      builder.recordState(
        SmartCubeStateEvent(
          state: CubeState.solved(),
          serial: 1,
          receivedAt: DateTime.utc(2026),
          hostTimestamp: const Duration(milliseconds: 1040),
        ),
      );
      builder.observeOrientation(_pose(1.3, 1050));
      builder.configureSource(
        capabilities: const CubeCapabilities(gyroscope: true),
      );
      final recording = builder.finish()!;
      final poses = recording.events.whereType<RecordedOrientation>().toList();

      expect(recording.protocolFamily, CubeProtocolFamily.gan);
      expect(recording.orientationAvailable, isTrue);
      expect(recording.orientationReduction, adaptiveQuaternionReduction);
      expect(poses.map((pose) => pose.hostOffset.inMilliseconds), [
        -50,
        20,
        30,
        50,
      ]);
      expect(poses.first.orientation.w, -1);
      expect(
        poses.last.orientation.dot(poses.first.orientation),
        greaterThan(0),
      );
      expect(
        recording.events.map((event) => event.sequence),
        List.generate(recording.events.length, (index) => index),
      );
      expect(
        recording.events.whereType<RecordedDataGap>().single.reason,
        RecordingGapReason.connectionDiscontinuity,
      );
      expect(
        recording.events.whereType<RecordedState>().single.facelets,
        CubeState.solved().facelets,
      );
    },
  );

  test(
    'detects clock rollback and clears discarded or disconnected evidence',
    () {
      final builder = SolveRecordingBuilder();
      builder.configureSource(protocolFamily: CubeProtocolFamily.moyu32);
      builder.start(Duration.zero);
      builder.recordMove(_move(1, 100, cubeTimestamp: 200));
      builder.recordMove(_move(2, 200, cubeTimestamp: 100));
      final recording = builder.finish()!;

      expect(
        recording.events.whereType<RecordedDataGap>().single.reason,
        RecordingGapReason.cubeClockDiscontinuity,
      );
      expect(recording.intervalForMove(1).duration, isNull);
      builder.observeOrientation(_pose(0, 300));
      builder.queueGap(
        RecordingGapReason.missedMoves,
        const Duration(milliseconds: 350),
      );
      builder.start(const Duration(milliseconds: 400));
      builder.discardAttempt();
      expect(builder.finish(), isNull);
      builder.clearPose();
      builder.resetSource();
      builder.start(const Duration(milliseconds: 500));
      final empty = builder.finish()!;
      expect(empty.events, isEmpty);
      expect(empty.protocolFamily, CubeProtocolFamily.unknown);
      expect(empty.orientationAvailable, isFalse);
    },
  );

  test(
    'smart solve saves and exports ordered evidence with reliable timing',
    () async {
      final repository = MemorySolveHistoryRepository();
      final clock = _MonotonicClock();
      final controller = _preparedController(repository, clock);
      addTearDown(controller.dispose);
      final solution = controller.scramble.inverse.moves;
      clock.now = const Duration(seconds: 1);
      var serial = 1;
      for (final move in solution) {
        controller.applyMove(
          move,
          fromSmartCube: true,
          serial: serial++,
          hostTimestamp: clock.now,
          cubeTimestamp: clock.now,
        );
        clock.now += const Duration(milliseconds: 100);
      }
      final solve = controller.pendingSolveReview!;
      await controller.flushPersistence();
      final recording = (await repository.loadRecording(solve.id))!;
      final exported =
          jsonDecode(await controller.exportJson()) as Map<String, Object?>;
      final exportedSolve =
          (exported['solves']! as List<Object?>).single!
              as Map<String, Object?>;

      expect(solve.isTimingReliable, isTrue);
      expect(
        solve.elapsed,
        Duration(milliseconds: (solution.length - 1) * 100),
      );
      expect(recording.moves.map((event) => event.move), solution);
      expect(recording.moves.first.hostOffset, Duration.zero);
      expect(exported['version'], 3);
      expect(exportedSolve['recording'], recording.toJson());
    },
  );

  test(
    'unknown recovered timing is retained but excluded from statistics',
    () async {
      final repository = MemorySolveHistoryRepository();
      final clock = _MonotonicClock();
      final controller = _preparedController(repository, clock);
      addTearDown(controller.dispose);
      final solution = controller.scramble.inverse.moves;
      clock.now = const Duration(seconds: 2);
      for (var index = 0; index < solution.length; index++) {
        controller.applyMove(
          solution[index],
          fromSmartCube: true,
          serial: index + 1,
          recovered: index != solution.length - 1,
          hostTimestamp: Duration(
            seconds: index == solution.length - 1 ? 1 : 2,
          ),
        );
      }
      final solve = controller.pendingSolveReview!;
      await controller.flushPersistence();
      final recording = (await repository.loadRecording(solve.id))!;

      expect(solve.isTimingReliable, isFalse);
      expect(solve.toJson()['elapsed_ms'], isNull);
      expect(SolveRecord.fromJson(solve.toJson()).isTimingReliable, isFalse);
      expect(controller.bestTime, isNull);
      expect(controller.sessionAverage, isNull);
      expect(controller.averageOfFive, isNull);
      expect(recording.moves.last.hostOffset, const Duration(seconds: -1));
      expect(
        recording.firstMoveFromSolveStart.source,
        RecordingTimingSource.unavailable,
      );
    },
  );

  test('retains a completed recording while the next scramble loads', () async {
    final repository = MemorySolveHistoryRepository();
    final clock = _MonotonicClock();
    final nextScramble = Completer<CubeScramble>();
    var requests = 0;
    final controller = PracticeController(
      nextScramble: () =>
          requests++ == 0 ? CubeScramble.parse('R U') : nextScramble.future,
      repository: repository,
      monotonicClock: clock,
      now: () => DateTime.utc(2026),
      preInspectionDelay: Duration.zero,
    );
    addTearDown(controller.dispose);
    controller.activateSmartCubeInput(protocolFamily: CubeProtocolFamily.gan);
    controller.syncCubeState(CubeState.solved());
    for (final move in controller.scramble.moves) {
      controller.applyMove(move, fromSmartCube: true);
    }

    clock.now = const Duration(seconds: 1);
    controller.applyMove(CubeMove.parse("U'"), fromSmartCube: true);
    clock.now = const Duration(milliseconds: 1200);
    controller.applyMove(CubeMove.parse("R'"), fromSmartCube: true);
    final solve = controller.pendingSolveReview!;
    await controller.flushPersistence();
    final recording = (await repository.loadRecording(solve.id))!;

    expect(controller.isPreparingScramble, isTrue);
    expect(controller.hasScramble, isFalse);
    expect(controller.primaryActionEnabled, isFalse);
    expect(solve.scramble, 'R U');
    expect(solve.elapsed, const Duration(milliseconds: 200));
    expect(solve.isTimingReliable, isTrue);
    expect(recording.protocolFamily, CubeProtocolFamily.gan);
    expect(recording.moves.map((event) => event.move.toString()), ["U'", "R'"]);

    final physicalState = CubeState.solved()..apply(CubeMove.parse('L'));
    controller.syncCubeState(physicalState);
    nextScramble.complete(CubeScramble.parse('F D'));
    await nextScramble.future;
    final payload =
        jsonDecode(await controller.exportJson()) as Map<String, Object?>;
    final exportedSolve =
        (payload['solves']! as List<Object?>).single! as Map<String, Object?>;

    expect(controller.hasScramble, isTrue);
    expect(controller.scramble.toString(), 'F D');
    expect(controller.cubeState.facelets, physicalState.facelets);
    expect(controller.phase, PracticePhase.needsSolvedCube);
    expect(controller.pendingSolveReview, same(solve));
    expect(exportedSolve['scramble'], 'R U');
    expect(exportedSolve['recording'], recording.toJson());
  });

  for (final (completion, completesFromState) in [
    ('live moves finish the solve', false),
    ('the same state report finishes the solve', true),
  ]) {
    test('state-derived start excludes timing when $completion', () async {
      final repository = MemorySolveHistoryRepository();
      for (var index = 0; index < 4; index++) {
        await repository.add(
          SolveRecord(
            id: 'baseline-$index',
            scramble: 'R U',
            elapsed: const Duration(seconds: 10),
            moveCount: 2,
            createdAt: DateTime.utc(2025, 12, 31),
          ),
        );
      }
      final clock = _MonotonicClock();
      final controller = _preparedController(repository, clock);
      addTearDown(controller.dispose);
      await controller.initialize();
      final solution = controller.scramble.inverse.moves;
      clock.now = const Duration(seconds: 1);

      if (completesFromState) {
        controller.syncCubeState(CubeState.solved());
      } else {
        controller.syncCubeState(
          controller.cubeState.copy()..apply(solution.first),
        );
        for (final move in solution.skip(1)) {
          clock.now += const Duration(milliseconds: 100);
          controller.applyMove(move, fromSmartCube: true);
        }
      }
      final solve = controller.pendingSolveReview!;
      final payload =
          jsonDecode(await controller.exportJson()) as Map<String, Object?>;
      final exportedSolve =
          (payload['solves']! as List<Object?>).first! as Map<String, Object?>;
      final recording = (await repository.loadRecording(solve.id))!;

      expect(solve.isTimingReliable, isFalse);
      expect(solve.turnsPerSecond, isNull);
      expect(exportedSolve['timing_reliable'], isFalse);
      expect(exportedSolve['elapsed_ms'], isNull);
      expect(controller.bestTime, const Duration(seconds: 10));
      expect(controller.sessionAverage, const Duration(seconds: 10));
      expect(controller.averageOfFive, isNull);
      expect(recording.events.whereType<RecordedState>(), hasLength(1));
      expect(
        recording.events.whereType<RecordedDataGap>().single.reason,
        RecordingGapReason.stateTransition,
      );
    });
  }

  test('a state correction inside a solve preserves boundary timing', () async {
    final repository = MemorySolveHistoryRepository();
    final clock = _MonotonicClock();
    final controller = _preparedController(repository, clock);
    addTearDown(controller.dispose);
    final solution = controller.scramble.inverse.moves;
    clock.now = const Duration(seconds: 1);
    controller.applyMove(solution.first, fromSmartCube: true);

    clock.now = const Duration(seconds: 2);
    controller.syncCubeState(controller.cubeState.copy()..apply(solution[1]));
    for (final move in solution.skip(2)) {
      clock.now += const Duration(milliseconds: 100);
      controller.applyMove(move, fromSmartCube: true);
    }
    final solve = controller.pendingSolveReview!;
    await controller.flushPersistence();
    final recording = (await repository.loadRecording(solve.id))!;

    expect(solve.isTimingReliable, isTrue);
    expect(solve.elapsed, clock.now - const Duration(seconds: 1));
    expect(controller.bestTime, solve.elapsed);
    expect(controller.sessionAverage, solve.elapsed);
    expect(
      recording.events.whereType<RecordedDataGap>().single.reason,
      RecordingGapReason.stateTransition,
    );
  });

  test('state completion retains gaps and abort discards an attempt', () async {
    final repository = MemorySolveHistoryRepository();
    final clock = _MonotonicClock();
    final controller = _preparedController(repository, clock);
    addTearDown(controller.dispose);
    clock.now = const Duration(seconds: 1);
    controller.applyMove(
      controller.scramble.moves.last.inverse,
      fromSmartCube: true,
    );
    clock.now = const Duration(seconds: 2);
    controller.markSmartCubeDisconnected();
    clock.now = const Duration(seconds: 10);
    controller.syncCubeState(CubeState.solved(), serial: 25);
    await controller.flushPersistence();
    final recording = (await repository.loadRecording(
      controller.solves.single.id,
    ))!;

    final solve = controller.solves.single;
    expect(solve.elapsed, const Duration(seconds: 9));
    expect(solve.isTimingReliable, isFalse);
    expect(solve.toJson()['elapsed_ms'], isNull);
    expect(solve.turnsPerSecond, isNull);
    expect(controller.bestTime, isNull);
    expect(controller.sessionAverage, isNull);
    expect(recording.events.last, isA<RecordedState>());
    expect(
      recording.events.whereType<RecordedDataGap>().map(
        (event) => event.reason,
      ),
      containsAll([
        RecordingGapReason.connectionDiscontinuity,
        RecordingGapReason.stateTransition,
      ]),
    );
    for (final move in controller.scramble.moves) {
      controller.applyMove(move, fromSmartCube: true);
    }
    controller.applyMove(
      controller.scramble.moves.last.inverse,
      fromSmartCube: true,
    );
    controller.abortAttempt();
    await controller.flushPersistence();
    expect(await repository.load(), hasLength(1));
  });
}

PracticeController _preparedController(
  MemorySolveHistoryRepository repository,
  MonotonicClock clock,
) {
  final controller = createTestPracticeController(
    repository: repository,
    monotonicClock: clock,
    now: () => DateTime.utc(2026),
    preInspectionDelay: Duration.zero,
  );
  controller.activateSmartCubeInput(protocolFamily: CubeProtocolFamily.gan);
  controller.syncCubeState(CubeState.solved());
  for (final move in controller.scramble.moves) {
    controller.applyMove(move, fromSmartCube: true);
  }
  expect(controller.phase, PracticePhase.inspection);
  return controller;
}

SmartCubeMoveEvent _move(
  int serial,
  int hostMilliseconds, {
  int? cubeTimestamp,
  bool recovered = false,
}) => SmartCubeMoveEvent(
  move: CubeMove.parse('R'),
  serial: serial,
  recovered: recovered,
  receivedAt: DateTime.utc(2026),
  hostTimestamp: Duration(milliseconds: hostMilliseconds),
  cubeTimestamp: cubeTimestamp == null
      ? null
      : Duration(milliseconds: cubeTimestamp),
);

SmartCubeOrientationEvent _pose(
  double degrees,
  int milliseconds, {
  double sign = 1,
}) {
  final radians = degrees * math.pi / 180;
  return SmartCubeOrientationEvent(
    orientation: CubeOrientation(
      x: 0,
      y: 0,
      z: sign * math.sin(radians / 2),
      w: sign * math.cos(radians / 2),
    ),
    receivedAt: DateTime.utc(2026),
    hostTimestamp: Duration(milliseconds: milliseconds),
  );
}

final class _MonotonicClock implements MonotonicClock {
  @override
  Duration now = Duration.zero;
}
