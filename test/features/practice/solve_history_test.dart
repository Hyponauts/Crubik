import 'dart:async';

import 'package:crubik/features/practice/application/solve_history.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
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

  void completeLoad() => _loadGate.complete();

  @override
  Future<List<SolveRecord>> load() async {
    loadStarted.complete();
    await _loadGate.future;
    return List.of(stored);
  }

  @override
  Future<void> replaceAll(List<SolveRecord> solves) async {
    stored = List.of(solves);
  }
}
