import 'dart:io';

import 'package:crubik/core/data/crubik_database.dart';
import 'package:crubik/features/cube/application/remembered_cube_store.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
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

    await repository.replaceAll(records);
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

    await repository.replaceAll(records);
    final restoredById = {
      for (final record in await repository.load()) record.id: record,
    };

    for (var index = 0; index < sources.length; index++) {
      final restored = restoredById['source-$index']!;
      expect(restored.inputSource, sources[index]);
      expect(restored.toJson()['input_source'], sources[index].serializedValue);
    }
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

  test('persists the expendable scramble pool in app settings', () async {
    final database = CrubikDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final store = DriftScrambleCacheStore(database);

    await store.save([CubeScramble.parse('R U'), CubeScramble.parse("F2 D'")]);

    expect((await store.load()).map((scramble) => scramble.toString()), [
      'R U',
      "F2 D'",
    ]);
  });

  test(
    'migrates version 1 history without inventing inspection data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'crubik-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/crubik.sqlite');
      final legacy = sqlite.sqlite3.open(file.path);
      legacy
        ..execute('''
        CREATE TABLE solve_entries (
          id TEXT NOT NULL PRIMARY KEY,
          scramble TEXT NOT NULL,
          elapsed_ms INTEGER NOT NULL,
          move_count INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          input_source TEXT NOT NULL
        )
      ''')
        ..execute('INSERT INTO solve_entries VALUES (?, ?, ?, ?, ?, ?)', [
          'legacy-solve',
          'R U',
          12000,
          2,
          DateTime.utc(2025).millisecondsSinceEpoch ~/ 1000,
          SolveInputSource.smartCube.serializedValue,
        ])
        ..userVersion = 1
        ..dispose();

      final database = CrubikDatabase(NativeDatabase(file));
      addTearDown(database.close);
      final restored = await DriftSolveHistoryRepository(database).load();

      expect(restored, hasLength(1));
      expect(restored.single.id, 'legacy-solve');
      expect(restored.single.inspectionElapsed, isNull);
      expect(restored.single.startTrigger, isNull);

      final columns = await database
          .customSelect('PRAGMA table_info(solve_entries)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        containsAll(['inspection_elapsed_ms', 'start_trigger']),
      );
      final tables = await database
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      expect(
        tables.map((row) => row.read<String>('name')),
        contains('app_settings'),
      );
    },
  );
}
