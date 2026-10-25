import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../features/cube/application/remembered_cube_store.dart';
import '../../features/cube/application/scramble_cache.dart';
import '../../features/cube/domain/cube_model.dart';
import '../../features/practice/domain/solve_record.dart';
import '../../features/practice/domain/solve_recording.dart';
import 'solve_recording_codec.dart';

part 'crubik_database.g.dart';

class SolveEntries extends Table {
  TextColumn get id => text()();

  TextColumn get scramble => text()();

  IntColumn get elapsedMs => integer()();

  IntColumn get moveCount => integer()();

  BoolColumn get timingReliable =>
      boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime()();

  TextColumn get inputSource => text()();

  IntColumn get inspectionElapsedMs => integer().nullable()();

  TextColumn get startTrigger => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DataClassName('SolveRecordingRow')
class SolveRecordings extends Table {
  TextColumn get solveId =>
      text().references(SolveEntries, #id, onDelete: KeyAction.cascade)();

  BlobColumn get payload => blob()();

  @override
  Set<Column<Object>> get primaryKey => {solveId};
}

@DriftDatabase(tables: [SolveEntries, AppSettings, SolveRecordings])
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
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(
          solveEntries,
          solveEntries.inspectionElapsedMs,
        );
        await migrator.addColumn(solveEntries, solveEntries.startTrigger);
      }
      if (from < 3) {
        await migrator.createTable(appSettings);
      }
      if (from < 4) {
        await migrator.createTable(solveRecordings);
        await migrator.addColumn(solveEntries, solveEntries.timingReliable);
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

final class DriftRememberedCubeStore implements RememberedCubeStore {
  const DriftRememberedCubeStore(this._database);

  static const _deviceIdKey = 'recent_cube_device_id';
  static const _deviceNameKey = 'recent_cube_device_name';

  final CrubikDatabase _database;

  @override
  Future<RememberedCube?> load() async {
    final deviceId = await _loadSetting(_deviceIdKey);
    if (deviceId == null) return null;
    return RememberedCube(
      deviceId: deviceId,
      name: await _loadSetting(_deviceNameKey),
    );
  }

  Future<String?> _loadSetting(String key) async {
    final query = _database.select(_database.appSettings)
      ..where((setting) => setting.key.equals(key));
    return (await query.getSingleOrNull())?.value;
  }

  @override
  Future<void> save(RememberedCube cube) => _database.transaction(() async {
    await _database.batch((batch) {
      batch.insertAllOnConflictUpdate(_database.appSettings, [
        AppSettingsCompanion.insert(key: _deviceIdKey, value: cube.deviceId),
        if (cube.name case final name?)
          AppSettingsCompanion.insert(key: _deviceNameKey, value: name),
      ]);
    });
    if (cube.name == null) {
      await (_database.delete(
        _database.appSettings,
      )..where((setting) => setting.key.equals(_deviceNameKey))).go();
    }
  });
}

final class DriftScrambleCacheStore implements ScrambleCacheStore {
  const DriftScrambleCacheStore(this._database);

  static const _cacheKey = 'wca_scramble_cache_v1';

  final CrubikDatabase _database;

  @override
  Future<List<CubeScramble>> load() async {
    final query = _database.select(_database.appSettings)
      ..where((setting) => setting.key.equals(_cacheKey));
    final value = (await query.getSingleOrNull())?.value;
    if (value == null) return const [];

    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return decoded
          .whereType<String>()
          .map(CubeScramble.parse)
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> save(List<CubeScramble> scrambles) async {
    await _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _cacheKey,
            value: jsonEncode(
              scrambles.map((scramble) => scramble.toString()).toList(),
            ),
          ),
        );
  }
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
            isTimingReliable: row.timingReliable,
            moveCount: row.moveCount,
            createdAt: row.createdAt.toUtc(),
            inputSource: SolveInputSource.fromSerializedValue(row.inputSource),
            inspectionElapsed: row.inspectionElapsedMs == null
                ? null
                : Duration(milliseconds: row.inspectionElapsedMs!),
            startTrigger: SolveStartTrigger.fromSerializedValue(
              row.startTrigger,
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<SolveRecording?> loadRecording(String solveId) async {
    final query = _database.select(_database.solveRecordings)
      ..where((entry) => entry.solveId.equals(solveId));
    final row = await query.getSingleOrNull();
    return row == null ? null : decodeSolveRecording(row.payload);
  }

  @override
  Future<void> add(SolveRecord solve, {SolveRecording? recording}) =>
      _database.transaction(() async {
        await _database
            .into(_database.solveEntries)
            .insertOnConflictUpdate(
              SolveEntriesCompanion.insert(
                id: solve.id,
                scramble: solve.scramble,
                elapsedMs: solve.elapsed.inMilliseconds,
                moveCount: solve.moveCount,
                createdAt: solve.createdAt,
                inputSource: solve.inputSource.serializedValue,
                timingReliable: Value(solve.isTimingReliable),
                inspectionElapsedMs: Value(
                  solve.inspectionElapsed?.inMilliseconds,
                ),
                startTrigger: Value(solve.startTrigger?.serializedValue),
              ),
            );
        await (_database.delete(
          _database.solveRecordings,
        )..where((entry) => entry.solveId.equals(solve.id))).go();
        if (recording == null) return;

        await _database
            .into(_database.solveRecordings)
            .insert(
              SolveRecordingsCompanion.insert(
                solveId: solve.id,
                payload: encodeSolveRecording(recording),
              ),
            );
      });

  @override
  Future<void> delete(String id) async {
    await (_database.delete(
      _database.solveEntries,
    )..where((entry) => entry.id.equals(id))).go();
  }
}
