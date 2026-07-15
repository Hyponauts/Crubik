import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../cube/domain/cube_model.dart';
import '../../cube/domain/scramble_generator.dart';
import '../domain/solve_record.dart';

enum SolveTimerPhase { ready, running, stopped }

abstract interface class SolveClock {
  Duration get elapsed;

  void reset();

  void start();

  void stop();
}

final class StopwatchSolveClock implements SolveClock {
  final Stopwatch _stopwatch = Stopwatch();

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  void reset() => _stopwatch.reset();

  @override
  void start() => _stopwatch.start();

  @override
  void stop() => _stopwatch.stop();
}

final class PracticeController extends ChangeNotifier {
  PracticeController({
    ScrambleGenerator? scrambleGenerator,
    SolveHistoryRepository? repository,
    SolveClock? clock,
    DateTime Function()? now,
  }) : _scrambleGenerator = scrambleGenerator ?? ScrambleGenerator(),
       _repository = repository ?? MemorySolveHistoryRepository(),
       _clock = clock ?? StopwatchSolveClock(),
       _now = now ?? DateTime.now {
    _scramble = _scrambleGenerator.generate();
    _cubeState = CubeState.solved()..applyAll(_scramble.moves);
  }

  final ScrambleGenerator _scrambleGenerator;
  final SolveHistoryRepository _repository;
  final SolveClock _clock;
  final DateTime Function() _now;

  late Scramble _scramble;
  late CubeState _cubeState;
  final List<CubeMove> _currentMoves = [];
  final List<SolveRecord> _solves = [];
  SolveTimerPhase _timerPhase = SolveTimerPhase.ready;
  Timer? _ticker;
  bool _smartCubeConnected = false;
  Future<void> _persistenceQueue = Future.value();
  Object? _persistenceError;

  Scramble get scramble => _scramble;
  CubeState get cubeState => _cubeState;
  List<CubeMove> get currentMoves => List.unmodifiable(_currentMoves);
  List<SolveRecord> get solves => List.unmodifiable(_solves);
  SolveTimerPhase get timerPhase => _timerPhase;
  Duration get elapsed => _clock.elapsed;
  bool get smartCubeConnected => _smartCubeConnected;
  Object? get persistenceError => _persistenceError;

  bool get hasSolves => _solves.isNotEmpty;

  Duration? get bestTime {
    if (_solves.isEmpty) return null;
    return _solves
        .map((solve) => solve.elapsed)
        .reduce((a, b) => a <= b ? a : b);
  }

  Duration? get sessionAverage {
    if (_solves.isEmpty) return null;
    final milliseconds = _solves.fold<int>(
      0,
      (sum, solve) => sum + solve.elapsed.inMilliseconds,
    );
    return Duration(milliseconds: milliseconds ~/ _solves.length);
  }

  Duration? get averageOfFive {
    if (_solves.length < 5) return null;
    final lastFive = _solves.take(5).toList();
    lastFive.sort((a, b) => a.elapsed.compareTo(b.elapsed));
    final middleThree = lastFive.sublist(1, 4);
    final milliseconds = middleThree.fold<int>(
      0,
      (sum, solve) => sum + solve.elapsed.inMilliseconds,
    );
    return Duration(milliseconds: milliseconds ~/ 3);
  }

  String exportJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'crubik-solve-history',
      'version': 1,
      'exported_at': _now().toUtc().toIso8601String(),
      'solves': _solves.map((solve) => solve.toJson()).toList(growable: false),
    });
  }

  Future<void> flushPersistence() => _persistenceQueue;

  Future<void> initialize() async {
    final persisted = [...await _repository.load()]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _solves
      ..clear()
      ..addAll(persisted);
    notifyListeners();
  }

  void newScramble() {
    if (_timerPhase == SolveTimerPhase.running) return;
    _scramble = _scrambleGenerator.generate();
    if (!_smartCubeConnected) {
      _cubeState = CubeState.solved()..applyAll(_scramble.moves);
    }
    _currentMoves.clear();
    _clock.reset();
    _timerPhase = SolveTimerPhase.ready;
    notifyListeners();
  }

  void resetCubeToScramble() {
    if (_timerPhase == SolveTimerPhase.running || _smartCubeConnected) return;
    _cubeState = CubeState.solved()..applyAll(_scramble.moves);
    _currentMoves.clear();
    notifyListeners();
  }

  void setSmartCubeConnected(bool connected) {
    if (_smartCubeConnected == connected) return;
    _smartCubeConnected = connected;
    notifyListeners();
  }

  void syncCubeState(CubeState state) {
    _cubeState = state.copy();
    if (_timerPhase == SolveTimerPhase.running &&
        _currentMoves.isNotEmpty &&
        _cubeState.isSolved) {
      stopSolve(inputSource: 'smart_cube_state');
      return;
    }
    notifyListeners();
  }

  void toggleTimer() {
    if (_timerPhase == SolveTimerPhase.running) {
      stopSolve();
    } else {
      startSolve();
    }
  }

  void startSolve() {
    _currentMoves.clear();
    _clock
      ..reset()
      ..start();
    _timerPhase = SolveTimerPhase.running;
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 31),
      (_) => notifyListeners(),
    );
    notifyListeners();
  }

  void stopSolve({String inputSource = 'manual'}) {
    if (_timerPhase != SolveTimerPhase.running) return;
    _clock.stop();
    _ticker?.cancel();
    _ticker = null;
    _timerPhase = SolveTimerPhase.stopped;

    final createdAt = _now();
    final solve = SolveRecord(
      id: createdAt.microsecondsSinceEpoch.toString(),
      scramble: _scramble.toString(),
      elapsed: _clock.elapsed,
      moveCount: _currentMoves.length,
      createdAt: createdAt,
      inputSource: inputSource,
    );
    _solves.insert(0, solve);
    _schedulePersistence();
    notifyListeners();
  }

  void applyMove(CubeMove move, {bool fromSmartCube = false}) {
    _cubeState.apply(move);
    _currentMoves.add(move);
    if (_timerPhase == SolveTimerPhase.running &&
        _currentMoves.isNotEmpty &&
        _cubeState.isSolved) {
      stopSolve(inputSource: fromSmartCube ? 'smart_cube' : 'manual_moves');
      return;
    }
    notifyListeners();
  }

  void deleteSolve(String id) {
    _solves.removeWhere((solve) => solve.id == id);
    _schedulePersistence();
    notifyListeners();
  }

  void _schedulePersistence() {
    final snapshot = List<SolveRecord>.of(_solves);
    _persistenceQueue = _persistenceQueue
        .then((_) => _repository.replaceAll(snapshot))
        .onError((error, _) {
          _persistenceError = error;
        });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
