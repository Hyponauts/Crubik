import 'dart:io';

import 'package:crubik/core/data/crubik_database.dart';
import 'package:crubik/features/cube/application/remembered_cube_store.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/cube/domain/smart_cube_event.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
import 'package:crubik/features/practice/domain/solve_recording.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

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
        inputSource: SolveInputSource.smartCube,
        inspectionElapsed: const Duration(milliseconds: 4321),
        startTrigger: SolveStartTrigger.firstMove,
      ),
    ];

    await repository.add(records.single);
    final restored = await repository.load();

    expect(restored, hasLength(1));
    expect(restored.single.id, records.single.id);
    expect(restored.single.scramble, records.single.scramble);
    expect(restored.single.elapsed, records.single.elapsed);
    expect(restored.single.moveCount, records.single.moveCount);
    expect(restored.single.createdAt, records.single.createdAt);
    expect(restored.single.inputSource, records.single.inputSource);
    expect(restored.single.inspectionElapsed, records.single.inspectionElapsed);
    expect(restored.single.startTrigger, records.single.startTrigger);
    expect(restored.single.isTimingReliable, isTrue);
  });

  test('round trips every solve input source through Drift', () async {
    final database = CrubikDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSolveHistoryRepository(database);
    final sources = [
      ...SolveInputSource.values,
      SolveInputSource.fromSerializedValue('future_sensor'),
    ];
    final records = [
      for (var index = 0; index < sources.length; index++)
        SolveRecord(
          id: 'source-$index',
          scramble: 'R U',
          elapsed: const Duration(seconds: 8),
          moveCount: index,
          createdAt: DateTime.utc(2026, 1, index + 1),
          inputSource: sources[index],
        ),
    ];

    for (final result in records) {
      await repository.add(result);
    }
    final restoredById = {
      for (final result in await repository.load()) result.id: result,
    };

    for (var index = 0; index < sources.length; index++) {
      final restored = restoredById['source-$index']!;
      expect(restored.inputSource, sources[index]);
      expect(restored.toJson()['input_source'], sources[index].serializedValue);
    }
  });

  test('delete removes a solve atomically', () async {
    final database = CrubikDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSolveHistoryRepository(database);
    final result = SolveRecord(
      id: 'solve-1',
      scramble: 'R U',
      elapsed: const Duration(seconds: 10),
      moveCount: 2,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    await repository.add(result);
    await repository.delete(result.id);

    expect(await repository.load(), isEmpty);
  });

  test('round trips ordered recording after closing and reopening', () async {
    final directory = await Directory.systemTemp.createTemp(
      'crubik-recording-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/crubik.sqlite');
    final solve = SolveRecord(
      id: 'recording-solve',
      scramble: 'R U',
      elapsed: const Duration(seconds: 10),
      moveCount: 1,
      createdAt: DateTime.utc(2026, 1, 1),
      inputSource: SolveInputSource.smartCubeState,
      isTimingReliable: false,
    );
    final recording = SolveRecording(
      protocolFamily: CubeProtocolFamily.gan,
      cubeTimestampsAvailable: true,
      orientationAvailable: true,
      events: [
        const RecordedOrientation(
          sequence: 0,
          hostOffset: Duration(milliseconds: -5),
          orientation: CubeOrientation(x: 0, y: 0, z: 0, w: 1),
          angularVelocity: CubeAngularVelocity(
            x: 1,
            y: -2,
            z: 0,
            unit: 'gan_odr_step',
          ),
        ),
        RecordedMove(
          sequence: 1,
          hostOffset: Duration.zero,
          move: CubeMove.parse('R'),
          serial: 7,
          recovered: false,
          cubeTimestamp: const Duration(milliseconds: 100),
        ),
        RecordedState(
          sequence: 2,
          hostOffset: const Duration(milliseconds: 80),
          facelets: CubeState.solved().facelets,
          serial: 8,
        ),
        const RecordedDataGap(
          sequence: 3,
          hostOffset: Duration(milliseconds: 80),
          reason: RecordingGapReason.stateTransition,
          missingMoveCount: 1,
        ),
      ],
    );

    final firstDatabase = CrubikDatabase(NativeDatabase(file));
    await DriftSolveHistoryRepository(
      firstDatabase,
    ).add(solve, recording: recording);
    await firstDatabase.close();

    final reopenedDatabase = CrubikDatabase(NativeDatabase(file));
    addTearDown(reopenedDatabase.close);
    final repository = DriftSolveHistoryRepository(reopenedDatabase);
    final summaries = await repository.load();
    final restored = await repository.loadRecording(solve.id);

    expect(summaries.single.id, solve.id);
    expect(summaries.single.isTimingReliable, isFalse);
    final stored = await reopenedDatabase
        .select(reopenedDatabase.solveRecordings)
        .getSingle();
    expect(stored.payload, isNot(contains('interval_us')));
    expect(restored?.protocolFamily, CubeProtocolFamily.gan);
    expect(restored?.orientationReduction, adaptiveQuaternionReduction);
    expect(
      restored?.events.map((event) => event.sequence),
      orderedEquals([0, 1, 2, 3]),
    );
    final orientation = restored?.events.first as RecordedOrientation;
    expect(orientation.angularVelocity?.y, -2);
    final move = restored?.events[1] as RecordedMove;
    expect(move.move.notation, 'R');
    expect(move.cubeTimestamp, const Duration(milliseconds: 100));
    expect(restored?.events[2], isA<RecordedState>());
    final gap = restored?.events[3] as RecordedDataGap;
    expect(gap.reason, RecordingGapReason.stateTransition);
    expect(gap.missingMoveCount, 1);
  });

  test('solve and recording insertion is atomic', () async {
    final database = CrubikDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSolveHistoryRepository(database);
    final solve = SolveRecord(
      id: 'atomic-solve',
      scramble: 'R',
      elapsed: const Duration(seconds: 2),
      moveCount: 2,
      createdAt: DateTime.utc(2026),
    );
    final recording = SolveRecording(
      protocolFamily: CubeProtocolFamily.gan,
      cubeTimestampsAvailable: false,
      orientationAvailable: false,
      events: const [],
    );
    await database.customStatement("""
      CREATE TRIGGER reject_recording BEFORE INSERT ON solve_recordings
      BEGIN SELECT RAISE(ABORT, 'recording write failed'); END
    """);

    await expectLater(
      repository.add(solve, recording: recording),
      throwsA(anything),
    );

    expect(await repository.load(), isEmpty);
    expect(await repository.loadRecording(solve.id), isNull);
  });

  test('deleting a solve cascades to its recording', () async {
    final database = CrubikDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftSolveHistoryRepository(database);
    final solve = SolveRecord(
      id: 'cascade-solve',
      scramble: 'R',
      elapsed: const Duration(seconds: 2),
      moveCount: 1,
      createdAt: DateTime.utc(2026),
    );
    final recording = SolveRecording(
      protocolFamily: CubeProtocolFamily.moyu32,
      cubeTimestampsAvailable: true,
      orientationAvailable: false,
      events: [
        RecordedMove(
          sequence: 0,
          hostOffset: Duration.zero,
          move: CubeMove.parse('R'),
          serial: 1,
          recovered: false,
        ),
      ],
    );

    await repository.add(solve, recording: recording);
    await repository.delete(solve.id);

    expect(await repository.loadRecording(solve.id), isNull);
    final eventCount = await database
        .customSelect('SELECT COUNT(*) AS count FROM solve_recordings')
        .getSingle();
    expect(eventCount.read<int>('count'), 0);
  });

  test('persists the recently connected cube locally', () async {
    final database = CrubikDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = DriftRememberedCubeStore(database);

    expect(await store.load(), isNull);

    await store.save(
      const RememberedCube(deviceId: 'platform-cube-id', name: 'GAN12ui'),
    );
    var rememberedCube = await store.load();
    expect(rememberedCube?.deviceId, 'platform-cube-id');
    expect(rememberedCube?.name, 'GAN12ui');

    await store.save(
      const RememberedCube(deviceId: 'new-platform-cube-id', name: 'WCU_MY32'),
    );
    rememberedCube = await store.load();
    expect(rememberedCube?.deviceId, 'new-platform-cube-id');
    expect(rememberedCube?.name, 'WCU_MY32');

    await store.save(const RememberedCube(deviceId: 'unnamed-cube-id'));
    rememberedCube = await store.load();
    expect(rememberedCube?.deviceId, 'unnamed-cube-id');
    expect(rememberedCube?.name, isNull);
  });

  for (final version in [1, 2, 3]) {
    test('migrates version $version without losing legacy evidence', () async {
      final directory = await Directory.systemTemp.createTemp(
        'crubik-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/crubik.sqlite');
      final legacy = sqlite.sqlite3.open(file.path);
      final inspectionColumns = version >= 2
          ? ', inspection_elapsed_ms INTEGER, start_trigger TEXT'
          : '';
      legacy.execute("""
        CREATE TABLE solve_entries (
          id TEXT NOT NULL PRIMARY KEY, scramble TEXT NOT NULL, elapsed_ms INTEGER NOT NULL,
          move_count INTEGER NOT NULL, created_at INTEGER NOT NULL, input_source TEXT NOT NULL
          $inspectionColumns
        )
      """);
      legacy.execute(
        'INSERT INTO solve_entries (id, scramble, elapsed_ms, move_count, created_at, input_source) VALUES (?, ?, ?, ?, ?, ?)',
        [
          'legacy-solve',
          'R U',
          12000,
          2,
          DateTime.utc(2025).millisecondsSinceEpoch ~/ 1000,
          'smart_cube',
        ],
      );
      if (version >= 3) {
        legacy.execute(
          'CREATE TABLE app_settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
        );
      }
      if (version >= 2) {
        legacy.execute(
          "UPDATE solve_entries SET inspection_elapsed_ms = 4000, start_trigger = 'first_move'",
        );
      }
      if (version == 3) {
        legacy.execute(
          "INSERT INTO app_settings VALUES ('recent_cube_device_id', 'legacy-cube-id')",
        );
      }
      legacy
        ..userVersion = version
        ..dispose();

      final database = CrubikDatabase(NativeDatabase(file));
      addTearDown(database.close);
      final repository = DriftSolveHistoryRepository(database);
      final restored = (await repository.load()).single;
      final recording = await repository.loadRecording(restored.id);

      expect(database.schemaVersion, 4);
      expect(restored.id, 'legacy-solve');
      expect(restored.elapsed, const Duration(seconds: 12));
      expect(
        restored.inspectionElapsed,
        version >= 2 ? const Duration(seconds: 4) : null,
      );
      expect(
        restored.startTrigger,
        version >= 2 ? SolveStartTrigger.firstMove : null,
      );
      expect(restored.isTimingReliable, isTrue);
      expect(recording, isNull);
      final rememberedCube = await DriftRememberedCubeStore(database).load();
      expect(rememberedCube?.deviceId, version == 3 ? 'legacy-cube-id' : null);
    });
  }
}
