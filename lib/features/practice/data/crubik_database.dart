import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../domain/solve_record.dart';

part 'crubik_database.g.dart';

class SolveEntries extends Table {
  TextColumn get id => text()();

  TextColumn get scramble => text()();

  IntColumn get elapsedMs => integer()();

  IntColumn get moveCount => integer()();

  DateTimeColumn get createdAt => dateTime()();

  TextColumn get inputSource => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [SolveEntries])
final class CrubikDatabase extends _$CrubikDatabase {
  CrubikDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'crubik',
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.dart.js'),
              ),
            ),
      );

  @override
  int get schemaVersion => 1;
}

final class DriftSolveHistoryRepository implements SolveHistoryRepository {
  const DriftSolveHistoryRepository(this._database);

  final CrubikDatabase _database;

  @override
  Future<List<SolveRecord>> load() async {
    final query = _database.select(_database.solveEntries)
      ..orderBy([(entry) => OrderingTerm.desc(entry.createdAt)]);
    final rows = await query.get();
    return rows
        .map(
          (row) => SolveRecord(
            id: row.id,
            scramble: row.scramble,
            elapsed: Duration(milliseconds: row.elapsedMs),
            moveCount: row.moveCount,
            createdAt: row.createdAt.toUtc(),
            inputSource: row.inputSource,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> replaceAll(List<SolveRecord> solves) async {
    await _database.transaction(() async {
      await _database.delete(_database.solveEntries).go();
      await _database.batch((batch) {
        batch.insertAll(
          _database.solveEntries,
          solves
              .map(
                (solve) => SolveEntriesCompanion.insert(
                  id: solve.id,
                  scramble: solve.scramble,
                  elapsedMs: solve.elapsed.inMilliseconds,
                  moveCount: solve.moveCount,
                  createdAt: solve.createdAt,
                  inputSource: solve.inputSource,
                ),
              )
              .toList(growable: false),
        );
      });
    });
  }
}
