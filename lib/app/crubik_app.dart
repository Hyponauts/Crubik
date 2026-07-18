import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/cube/application/cube_connection_controller.dart';
import '../features/practice/application/practice_controller.dart';
import '../features/practice/application/practice_input_controller.dart';
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
  late final PracticeInputController _inputController;
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
    _inputController = PracticeInputController(
      practiceController: _practiceController,
      connectionController: _connectionController,
    );
    _practiceController.initialize();
  }

  @override
  void dispose() {
    _inputController.dispose();
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
        inputController: _inputController,
      ),
    );
  }
}
