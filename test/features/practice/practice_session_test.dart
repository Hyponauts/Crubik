import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';
import 'package:crubik/features/practice/domain/practice_session.dart';
import 'package:crubik/features/practice/domain/solve_method.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filters history and statistics by selected session', () async {
    final repository = MemorySolveHistoryRepository();
    final sessionStore = MemoryPracticeSessionStore();
    final speed = PracticeSession.defaultSession();
    final layerByLayer = PracticeSession(
      id: 'lbl',
      name: 'Layer practice',
      method: SolveMethodConfig.preset(SolveMethodPreset.layerByLayer),
    );
    await sessionStore.save([speed, layerByLayer], speed.id);
    await repository.add(_solve('speed-1', speed, 20));
    await repository.add(_solve('speed-2', speed, 15));
    await repository.add(_solve('lbl-1', layerByLayer, 40));
    final controller = PracticeController(
      nextScramble: () => CubeScramble.parse('R U'),
      repository: repository,
      sessionStore: sessionStore,
      now: () => DateTime.utc(2026, 10, 28),
    );

    await controller.initialize();

    expect(controller.selectedSession.id, speed.id);
    expect(controller.solves.map((solve) => solve.id), ['speed-1', 'speed-2']);
    expect(controller.bestTime, const Duration(seconds: 15));

    controller.selectSession(layerByLayer.id);

    expect(controller.solves.single.id, 'lbl-1');
    expect(controller.bestTime, const Duration(seconds: 40));
    controller.dispose();
  });

  test('session deletion removes only that session and its solves', () async {
    final repository = MemorySolveHistoryRepository();
    final sessionStore = MemoryPracticeSessionStore();
    final speed = PracticeSession.defaultSession();
    final other = PracticeSession(
      id: 'other',
      name: 'Other',
      method: SolveMethodConfig.preset(SolveMethodPreset.twoLookCfop),
    );
    await sessionStore.save([speed, other], other.id);
    await repository.add(_solve('speed', speed, 10));
    await repository.add(_solve('other', other, 20));
    final controller = PracticeController(
      nextScramble: () => CubeScramble.parse('R U'),
      repository: repository,
      sessionStore: sessionStore,
    );
    await controller.initialize();

    controller.deleteSelectedSession();
    await controller.flushPersistence();

    expect(controller.sessions.map((session) => session.id), [speed.id]);
    expect(controller.solves.single.id, 'speed');
    expect((await repository.load()).map((solve) => solve.id), ['speed']);
    controller.dispose();
  });
}

SolveRecord _solve(String id, PracticeSession session, int seconds) =>
    SolveRecord(
      id: id,
      scramble: 'R U',
      elapsed: Duration(seconds: seconds),
      moveCount: 20,
      createdAt: DateTime.utc(2026, 10, 28).add(Duration(seconds: seconds)),
      sessionId: session.id,
      sessionName: session.name,
      method: session.method,
    );
