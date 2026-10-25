import 'dart:async';

import 'package:flutter/material.dart';

import '../core/data/crubik_database.dart';
import '../core/theme/app_theme.dart';
import '../features/cube/application/cube_connection_controller.dart';
import '../features/cube/application/scramble_cache.dart';
import '../features/cube/data/ble_cube_connection_gateway.dart';
import '../features/cube/data/solver/cuber_cube_solver.dart';
import '../features/cube/domain/scramble_generator.dart';
import '../features/practice/application/practice_controller.dart';
import '../features/practice/application/practice_input_coordinator.dart';
import '../features/practice/presentation/practice_page.dart';

class CrubikApp extends StatefulWidget {
  const CrubikApp({
    super.key,
    this.practiceController,
    this.connectionController,
  });

  final PracticeController? practiceController;
  final CubeConnectionController? connectionController;

  @override
  State<CrubikApp> createState() => _CrubikAppState();
}

class _CrubikAppState extends State<CrubikApp> {
  late final PracticeController _practiceController;
  late final CubeConnectionController _connectionController;
  late final PracticeInputCoordinator _inputCoordinator;
  CrubikDatabase? _database;
  ScrambleCache? _scrambleCache;
  CuberCubeSolver? _cubeSolver;
  late final bool _ownsPracticeController;
  late final bool _ownsConnectionController;

  @override
  void initState() {
    super.initState();
    _ownsPracticeController = widget.practiceController == null;
    _ownsConnectionController = widget.connectionController == null;
    if (_ownsPracticeController) {
      _database = CrubikDatabase();
      _cubeSolver = CuberCubeSolver();
      final generator = WcaScrambleGenerator(solver: _cubeSolver!);
      _scrambleCache = ScrambleCache(
        generate: generator.generate,
        store: DriftScrambleCacheStore(_database!),
      );
      _practiceController = PracticeController(
        nextScramble: _scrambleCache!.take,
        repository: DriftSolveHistoryRepository(_database!),
      );
    } else {
      _practiceController = widget.practiceController!;
    }
    _connectionController =
        widget.connectionController ??
        CubeConnectionController(
          gateway: BleCubeConnectionGateway(),
          rememberedCubeStore: _database == null
              ? null
              : DriftRememberedCubeStore(_database!),
        );
    _inputCoordinator = PracticeInputCoordinator(
      practiceController: _practiceController,
      connectionController: _connectionController,
    );
    _practiceController.initialize();
    unawaited(_connectionController.reconnectRememberedCube());
  }

  @override
  void dispose() {
    _inputCoordinator.dispose();
    if (_ownsPracticeController) {
      final database = _database;
      final scrambleCache = _scrambleCache;
      scrambleCache?.dispose();
      _cubeSolver?.dispose();
      final flush = () async {
        await Future.wait([
          _practiceController.flushPersistence(),
          if (scrambleCache != null) scrambleCache.flush(),
        ]);
      }();
      _practiceController.dispose();
      if (database != null) {
        unawaited(flush.whenComplete(database.close));
      }
    }
    if (_ownsConnectionController) _connectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crubik',
      debugShowCheckedModeBanner: false,
      theme: CrubikTheme.dark,
      home: PracticePage(
        practiceController: _practiceController,
        inputCoordinator: _inputCoordinator,
        connectionController: _connectionController,
      ),
    );
  }
}
