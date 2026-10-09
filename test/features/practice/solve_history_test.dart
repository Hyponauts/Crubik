import 'dart:math' as math;
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'dart:async';

import 'package:crubik/features/practice/application/solve_history.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
import 'package:crubik/features/practice/domain/solve_recording.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merges a solve completed while persisted history is loading', () async {
    final repository = _DelayedSolveHistoryRepository([_solve('persisted', 1)]);
    final history = SolveHistory(
      repository: repository,
      now: () => DateTime.utc(2026),
    );

    final initialization = history.initialize();
    await repository.loadStarted.future;
    history.add(_solve('new', 2));
    repository.completeLoad();

    await initialization;
    await history.flush();

    expect(history.records.map((solve) => solve.id), ['new', 'persisted']);
    expect(repository.stored.map((solve) => solve.id), ['new', 'persisted']);
  });

  test('preserves a deletion requested while history is loading', () async {
    final repository = _DelayedSolveHistoryRepository([_solve('persisted', 1)]);
    final history = SolveHistory(
      repository: repository,
      now: () => DateTime.utc(2026),
    );

    final initialization = history.initialize();
    await repository.loadStarted.future;
    history.delete('persisted');
    repository.completeLoad();

    await initialization;
    await history.flush();

    expect(history.records, isEmpty);
    expect(repository.stored, isEmpty);
  });

  test('flush waits for an in-flight history initialization', () async {
    final repository = _DelayedSolveHistoryRepository(const []);
    final history = SolveHistory(
      repository: repository,
      now: () => DateTime.utc(2026),
    );
    var flushed = false;

    history.initialize();
    await repository.loadStarted.future;
    final flush = history.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);

    expect(flushed, isFalse);
    repository.completeLoad();
    await flush;
    expect(flushed, isTrue);
  });

  test(
    'retains failed writes and retries them in order before export',
    () async {
      final repository = _ControlledRepository()..failWrites = true;
      final history = SolveHistory(
        repository: repository,
        now: () => DateTime.utc(2026),
      );
      history.add(_solve('one', 1));
      history.add(_solve('two', 2));
      await history.flush();

      expect(history.persistenceError, isNotNull);
      expect(await repository.load(), isEmpty);
      await expectLater(history.exportJson(), throwsStateError);
      expect(history.records, hasLength(2));

      repository.failWrites = false;
      final export = await history.exportJson();
      expect(export, contains('one'));
      expect(export, contains('two'));
      expect(history.persistenceError, isNull);
      expect(repository.addedIds, ['one', 'two']);
      expect(repository.maximumConcurrentWrites, 1);
      expect(await repository.load(), hasLength(2));
    },
  );

  test(
    'export holds one snapshot while deletion waits for its recording',
    () async {
      final repository = _ControlledRepository();
      final history = SolveHistory(
        repository: repository,
        now: () => DateTime.utc(2026),
      );
      history.add(
        _solve('one', 1),
        recording: SolveRecording(
          protocolFamily: CubeProtocolFamily.gan,
          cubeTimestampsAvailable: false,
          orientationAvailable: false,
          events: const [],
        ),
      );
      await history.flush();
      repository.readGate = Completer<void>();
      final export = history.exportJson();
      await repository.readStarted.future;
      history.delete('one');
      repository.readGate!.complete();

      expect(await export, contains('recording'));
      await history.flush();
      expect(await repository.load(), isEmpty);
      expect(await repository.loadRecording('one'), isNull);
    },
  );
}

SolveRecord _solve(String id, int second) => SolveRecord(
  id: id,
  scramble: 'R U',
  elapsed: const Duration(seconds: 10),
  moveCount: 2,
  createdAt: DateTime.utc(2026, 1, 1, 0, 0, second),
);

final class _DelayedSolveHistoryRepository implements SolveHistoryRepository {
  _DelayedSolveHistoryRepository(List<SolveRecord> solves)
    : stored = List.of(solves);

  final Completer<void> loadStarted = Completer<void>();
  final Completer<void> _loadGate = Completer<void>();
  List<SolveRecord> stored;
  final Map<String, SolveRecording> recordingsBySolveId = {};

  void completeLoad() => _loadGate.complete();

  @override
  Future<List<SolveRecord>> load() async {
    loadStarted.complete();
    await _loadGate.future;
    return List.of(stored);
  }

  @override
  Future<void> add(SolveRecord solve, {SolveRecording? recording}) async {
    stored.removeWhere((result) => result.id == solve.id);
    stored.add(solve);
    stored.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (recording != null) recordingsBySolveId[solve.id] = recording;
  }

  @override
  Future<void> delete(String id) async {
    stored.removeWhere((solve) => solve.id == id);
    recordingsBySolveId.remove(id);
  }

  @override
  Future<SolveRecording?> loadRecording(String solveId) async =>
      recordingsBySolveId[solveId];
}

final class _ControlledRepository implements SolveHistoryRepository {
  final _memory = MemorySolveHistoryRepository();
  bool failWrites = false;
  int _activeWrites = 0;
  int maximumConcurrentWrites = 0;
  final List<String> addedIds = [];
  final readStarted = Completer<void>();
  Completer<void>? readGate;

  @override
  Future<List<SolveRecord>> load() => _memory.load();

  @override
  Future<SolveRecording?> loadRecording(String solveId) async {
    if (readGate case final gate?) {
      if (!readStarted.isCompleted) readStarted.complete();
      await gate.future;
    }
    return _memory.loadRecording(solveId);
  }

  @override
  Future<void> add(SolveRecord solve, {SolveRecording? recording}) async {
    _activeWrites++;
    maximumConcurrentWrites = math.max(maximumConcurrentWrites, _activeWrites);
    try {
      await Future<void>.delayed(Duration.zero);
      if (failWrites) throw StateError('temporary write failure');
      await _memory.add(solve, recording: recording);
      addedIds.add(solve.id);
    } finally {
      _activeWrites--;
    }
  }

  @override
  Future<void> delete(String id) => _memory.delete(id);
}
