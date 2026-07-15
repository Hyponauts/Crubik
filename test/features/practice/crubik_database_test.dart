import 'package:crubik/features/practice/data/crubik_database.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists and restores complete solve records', () async {
    final database = CrubikDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSolveHistoryRepository(database);
    final records = [
      SolveRecord(
        id: 'solve-1',
        scramble: "R U R' U'",
        elapsed: const Duration(milliseconds: 9876),
        moveCount: 24,
        createdAt: DateTime.utc(2026, 1, 1),
        inputSource: 'smart_cube',
      ),
    ];

    await repository.replaceAll(records);
    final restored = await repository.load();

    expect(restored, hasLength(1));
    expect(restored.single.id, records.single.id);
    expect(restored.single.scramble, records.single.scramble);
    expect(restored.single.elapsed, records.single.elapsed);
    expect(restored.single.moveCount, records.single.moveCount);
    expect(restored.single.createdAt, records.single.createdAt);
    expect(restored.single.inputSource, records.single.inputSource);
  });

  test('replaceAll removes deleted solves atomically', () async {
    final database = CrubikDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSolveHistoryRepository(database);
    final record = SolveRecord(
      id: 'solve-1',
      scramble: 'R U',
      elapsed: const Duration(seconds: 10),
      moveCount: 2,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await repository.replaceAll([record]);
    await repository.replaceAll(const []);

    expect(await repository.load(), isEmpty);
  });
}
