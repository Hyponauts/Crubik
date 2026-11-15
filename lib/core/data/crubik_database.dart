import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../features/cube/application/remembered_cube_store.dart';
import '../../features/cube/application/scramble_cache.dart';
import '../../features/cube/domain/cube_model.dart';
import '../../features/practice/domain/practice_session.dart';
import '../../features/practice/domain/solve_average.dart';
import '../../features/practice/domain/solve_analysis.dart';
import '../../features/practice/domain/solve_method.dart';
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

  TextColumn get outcome => text().withDefault(const Constant('completed'))();

  DateTimeColumn get createdAt => dateTime()();

  TextColumn get inputSource => text()();

  IntColumn get inspectionElapsedMs => integer().nullable()();

  TextColumn get startTrigger => text().nullable()();

  TextColumn get sessionId =>
      text().withDefault(const Constant(defaultPracticeSessionId))();

  TextColumn get sessionName =>
      text().withDefault(const Constant('SpeedSolving'))();

  TextColumn get methodJson => text().withDefault(
    const Constant(
      '{"preset":"cfop","stages":["cross","f2l_pair_1",'
      '"f2l_pair_2","f2l_pair_3","f2l_pair_4",'
      '"last_layer_oriented","solved"]}',
    ),
  )();

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

@DataClassName('SolveAnalysisRow')
class SolveAnalyses extends Table {
  TextColumn get solveId =>
      text().references(SolveEntries, #id, onDelete: KeyAction.cascade)();

  IntColumn get analyzerVersion => integer()();

  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {solveId};
}

@DataClassName('SolveAverageRow')
@TableIndex(name: 'solve_averages_end_solve_id', columns: {#endSolveId})
class SolveAverages extends Table {
  TextColumn get kind => text()();

  TextColumn get endSolveId =>
      text().references(SolveEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get sessionId => text()();

  DateTimeColumn get createdAt => dateTime()();

  TextColumn get status => text()();

  IntColumn get elapsedMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {kind, endSolveId};
}

@DriftDatabase(
  tables: [
    SolveEntries,
    AppSettings,
    SolveRecordings,
    SolveAnalyses,
    SolveAverages,
  ],
)
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
  int get schemaVersion => 7;

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
      if (from < 5) {
        await migrator.addColumn(solveEntries, solveEntries.sessionId);
        await migrator.addColumn(solveEntries, solveEntries.sessionName);
        await migrator.addColumn(solveEntries, solveEntries.methodJson);
        await migrator.createTable(solveAnalyses);
      }
      if (from < 6) {
        await migrator.addColumn(solveEntries, solveEntries.outcome);
        await migrator.createTable(solveAverages);
      }
      if (from < 7) {
        await migrator.createIndex(solveAveragesEndSolveId);
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

final class DriftPracticeSessionStore implements PracticeSessionStore {
  const DriftPracticeSessionStore(this._database);

  static const _sessionsKey = 'practice_sessions_v1';

  final CrubikDatabase _database;

  @override
  Future<({List<PracticeSession> sessions, String selectedId})?> load() async {
    final query = _database.select(_database.appSettings)
      ..where((setting) => setting.key.equals(_sessionsKey));
    final value = (await query.getSingleOrNull())?.value;
    if (value == null) return null;

    try {
      final json = jsonDecode(value) as Map<String, Object?>;
      final sessions = [
        for (final item in json['sessions']! as List<Object?>)
          PracticeSession.fromJson((item! as Map).cast<String, Object?>()),
      ];
      final selectedId = json['selected_id']! as String;
      if (sessions.isEmpty ||
          !sessions.any((session) => session.id == selectedId)) {
        return null;
      }
      return (sessions: sessions, selectedId: selectedId);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(List<PracticeSession> sessions, String selectedId) async {
    await _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _sessionsKey,
            value: jsonEncode({
              'selected_id': selectedId,
              'sessions': sessions.map((session) => session.toJson()).toList(),
            }),
          ),
        );
  }
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

final class DriftSolveHistoryRepository
    implements
        SolveHistoryRepository,
        SolveAnalysisRepository,
        SolveAverageRepository {
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
            outcome: SolveOutcome.values.firstWhere(
              (value) => value.name == row.outcome,
              orElse: () => SolveOutcome.completed,
            ),
            moveCount: row.moveCount,
            createdAt: row.createdAt.toUtc(),
            inputSource: SolveInputSource.fromSerializedValue(row.inputSource),
            inspectionElapsed: row.inspectionElapsedMs == null
                ? null
                : Duration(milliseconds: row.inspectionElapsedMs!),
            startTrigger: SolveStartTrigger.fromSerializedValue(
              row.startTrigger,
            ),
            sessionId: row.sessionId,
            sessionName: row.sessionName,
            method: _decodeMethod(row.methodJson),
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
  Future<SolveAnalysis?> loadAnalysis(String solveId) async {
    final query = _database.select(_database.solveAnalyses)
      ..where((entry) => entry.solveId.equals(solveId));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    try {
      return SolveAnalysis.fromJson(
        (jsonDecode(row.payload) as Map).cast<String, Object?>(),
      );
    } on Object {
      return null;
    }
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
                outcome: Value(solve.outcome.name),
                inspectionElapsedMs: Value(
                  solve.inspectionElapsed?.inMilliseconds,
                ),
                startTrigger: Value(solve.startTrigger?.serializedValue),
                sessionId: Value(solve.sessionId),
                sessionName: Value(solve.sessionName),
                methodJson: Value(jsonEncode(solve.method.toJson())),
              ),
            );
        await (_database.delete(
          _database.solveRecordings,
        )..where((entry) => entry.solveId.equals(solve.id))).go();
        if (recording != null) {
          await _database
              .into(_database.solveRecordings)
              .insert(
                SolveRecordingsCompanion.insert(
                  solveId: solve.id,
                  payload: encodeSolveRecording(recording),
                ),
              );
        }
      });

  @override
  Future<List<SolveAverageRecord>> loadAverages() async {
    final rows = await _database.select(_database.solveAverages).get();
    return [
      for (final row in rows)
        SolveAverageRecord(
          kind: SolveAverageKind.values.byName(row.kind),
          endSolveId: row.endSolveId,
          sessionId: row.sessionId,
          createdAt: row.createdAt.toUtc(),
          status: SolveAverageStatus.values.byName(row.status),
          elapsed: row.elapsedMs == null
              ? null
              : Duration(milliseconds: row.elapsedMs!),
        ),
    ];
  }

  @override
  Future<void> addWithAverages(
    SolveRecord solve, {
    SolveRecording? recording,
    required List<SolveAverageRecord> averages,
  }) => _database.transaction(() async {
    await add(solve, recording: recording);
    await _insertAverages(averages);
  });

  @override
  Future<void> deleteWithAverages(
    String solveId, {
    required Set<String> affectedEndSolveIds,
    required List<SolveAverageRecord> replacements,
  }) => _database.transaction(() async {
    if (affectedEndSolveIds.isNotEmpty) {
      await (_database.delete(
        _database.solveAverages,
      )..where((entry) => entry.endSolveId.isIn(affectedEndSolveIds))).go();
    }
    await delete(solveId);
    await _insertAverages(replacements);
  });

  @override
  Future<void> replaceAllAverages(List<SolveAverageRecord> averages) =>
      _database.transaction(() async {
        await _database.delete(_database.solveAverages).go();
        await _insertAverages(averages);
      });

  Future<void> _insertAverages(List<SolveAverageRecord> averages) async {
    if (averages.isEmpty) return;
    await _database.batch((batch) {
      batch.insertAllOnConflictUpdate(_database.solveAverages, [
        for (final average in averages)
          SolveAveragesCompanion.insert(
            kind: average.kind.name,
            endSolveId: average.endSolveId,
            sessionId: average.sessionId,
            createdAt: average.createdAt,
            status: average.status.name,
            elapsedMs: Value(average.elapsed?.inMilliseconds),
          ),
      ]);
    });
  }

  @override
  Future<void> saveAnalysis(String solveId, SolveAnalysis analysis) async {
    await _database
        .into(_database.solveAnalyses)
        .insertOnConflictUpdate(
          SolveAnalysesCompanion.insert(
            solveId: solveId,
            analyzerVersion: analysis.analyzerVersion,
            payload: jsonEncode(analysis.toJson()),
          ),
        );
  }

  @override
  Future<void> delete(String id) async {
    await (_database.delete(
      _database.solveEntries,
    )..where((entry) => entry.id.equals(id))).go();
  }

  @override
  Future<void> deleteSession(
    String sessionId, {
    Future<void> Function()? saveSessionSettings,
  }) => _database.transaction(() async {
    await (_database.delete(
      _database.solveAverages,
    )..where((entry) => entry.sessionId.equals(sessionId))).go();
    await (_database.delete(
      _database.solveEntries,
    )..where((entry) => entry.sessionId.equals(sessionId))).go();
    await saveSessionSettings?.call();
  });
}

SolveMethodConfig _decodeMethod(String value) {
  try {
    return SolveMethodConfig.fromJson(
      (jsonDecode(value) as Map).cast<String, Object?>(),
    );
  } on Object {
    return SolveMethodConfig.preset(SolveMethodPreset.cfop);
  }
}
