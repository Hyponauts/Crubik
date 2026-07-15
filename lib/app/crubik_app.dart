import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/cube/data/cube_connection_controller.dart';
import '../features/cube/data/gan_cube_protocol.dart';
import '../features/practice/application/practice_controller.dart';
import '../features/practice/data/crubik_database.dart';
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
  late final StreamSubscription<SmartCubeMoveEvent> _cubeMoveSubscription;
  late final StreamSubscription<SmartCubeStateEvent> _cubeStateSubscription;
  CrubikDatabase? _database;
  late final bool _ownsPracticeController;
  late final bool _ownsConnectionController;

  @override
  void initState() {
    super.initState();
    _ownsPracticeController = widget.practiceController == null;
    _ownsConnectionController = widget.connectionController == null;
    if (_ownsPracticeController) {
      _database = CrubikDatabase();
      _practiceController = PracticeController(
        repository: DriftSolveHistoryRepository(_database!),
      );
    } else {
      _practiceController = widget.practiceController!;
    }
    _connectionController =
        widget.connectionController ?? CubeConnectionController();
    _cubeMoveSubscription = _connectionController.moveEvents.listen(
      (event) => _practiceController.applyMove(event.move, fromSmartCube: true),
    );
    _cubeStateSubscription = _connectionController.stateEvents.listen(
      (event) => _practiceController.syncCubeState(event.state),
    );
    _connectionController.addListener(_syncCubeConnectionMode);
    _syncCubeConnectionMode();
    _practiceController.initialize();
  }

  void _syncCubeConnectionMode() {
    _practiceController.setSmartCubeConnected(
      _connectionController.isConnected && !_connectionController.isDemo,
    );
  }

  @override
  void dispose() {
    _connectionController.removeListener(_syncCubeConnectionMode);
    unawaited(_cubeMoveSubscription.cancel());
    unawaited(_cubeStateSubscription.cancel());
    if (_ownsPracticeController) {
      final database = _database;
      final flush = _practiceController.flushPersistence();
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
        connectionController: _connectionController,
      ),
    );
  }
}
