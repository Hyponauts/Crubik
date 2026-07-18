import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../cube/domain/cube_model.dart';
import '../../cube/domain/scramble_generator.dart';
import '../domain/solve_record.dart';

enum PracticePhase {
  manualReady,
  awaitingCubeState,
  needsSolvedCube,
  scrambling,
  inspectionDelay,
  inspection,
  solving,
  stopped,
}

abstract interface class SolveClock {
  Duration get elapsed;

  void reset();

  void start({Duration initialElapsed = Duration.zero});

  void stop();
}

final class StopwatchSolveClock implements SolveClock {
  final Stopwatch _stopwatch = Stopwatch();
  Duration _initialElapsed = Duration.zero;

  @override
  Duration get elapsed => _initialElapsed + _stopwatch.elapsed;

  @override
  void reset() {
    _stopwatch
      ..stop()
      ..reset();
    _initialElapsed = Duration.zero;
  }

  @override
  void start({Duration initialElapsed = Duration.zero}) {
    _stopwatch
      ..stop()
      ..reset()
      ..start();
    _initialElapsed = initialElapsed;
  }

  @override
  void stop() => _stopwatch.stop();
}

final class PracticeController extends ChangeNotifier {
  static const defaultPreInspectionDelay = Duration(seconds: 3);
  static const defaultInspectionDuration = Duration(seconds: 15);

  PracticeController({
    ScrambleGenerator? scrambleGenerator,
    SolveHistoryRepository? repository,
    SolveClock? clock,
    DateTime Function()? now,
    this.preInspectionDelay = defaultPreInspectionDelay,
    this.inspectionDuration = defaultInspectionDuration,
  }) : _scrambleGenerator = scrambleGenerator ?? ScrambleGenerator(),
       _repository = repository ?? MemorySolveHistoryRepository(),
       _clock = clock ?? StopwatchSolveClock(),
       _now = now ?? DateTime.now {
    _scramble = _scrambleGenerator.generate();
    _scrambleTarget = _stateForScramble(_scramble);
    _cubeState = _scrambleTarget.copy();
  }

  final ScrambleGenerator _scrambleGenerator;
  final SolveHistoryRepository _repository;
  final SolveClock _clock;
  final DateTime Function() _now;
  final Duration preInspectionDelay;
  final Duration inspectionDuration;

  late Scramble _scramble;
  late CubeState _scrambleTarget;
  late CubeState _cubeState;
  final List<CubeMove> _preparationMoves = [];
  final List<CubeMove> _currentMoves = [];
  final List<SolveRecord> _solves = [];
  PracticePhase _phase = PracticePhase.manualReady;
  Timer? _ticker;
  bool _smartCubeConnected = false;
  bool _smartCubeWorkflowActive = false;
  bool _hasAuthoritativeCubeState = false;
  bool _activeAttemptUsesSmartCube = false;
  DateTime? _preInspectionDeadline;
  DateTime? _inspectionStartedAt;
  DateTime? _inspectionDeadline;
  Duration? _inspectionElapsed;
  SolveStartTrigger? _startTrigger;
  CubeMove? _lastAppliedMove;
  int _cubeMoveRevision = 0;
  Future<void> _persistenceQueue = Future.value();
  Object? _persistenceError;

  Scramble get scramble => _scramble;
  CubeState get cubeState => _cubeState;
  List<CubeMove> get currentMoves => List.unmodifiable(_currentMoves);
  List<SolveRecord> get solves => List.unmodifiable(_solves);
  PracticePhase get phase => _phase;
  Duration get elapsed => _clock.elapsed;
  bool get smartCubeConnected => _smartCubeConnected;
  bool get smartCubeWorkflowActive => _smartCubeWorkflowActive;
  CubeMove? get lastAppliedMove => _lastAppliedMove;
  int get cubeMoveRevision => _cubeMoveRevision;
  Object? get persistenceError => _persistenceError;

  Duration get preInspectionRemaining {
    if (_phase != PracticePhase.inspectionDelay) return Duration.zero;
    final deadline = _preInspectionDeadline;
    if (deadline == null) return Duration.zero;
    final remaining = deadline.difference(_now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration get inspectionRemaining {
    if (_phase != PracticePhase.inspection) return Duration.zero;
    final deadline = _inspectionDeadline;
    if (deadline == null) return Duration.zero;
    final remaining = deadline.difference(_now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  List<CubeMove> get scrambleGuidance {
    if (_phase != PracticePhase.scrambling) return const [];
    return List.unmodifiable(_buildScrambleGuidance());
  }

  CubeMove? get nextScrambleMove => scrambleGuidance.firstOrNull;

  int get completedScrambleMoveCount => _scrambleProgress.completedMoves;

  int get partialScrambleMoveTurnCount => _scrambleProgress.partialTurns;

  List<CubeMove> get scrambleRecoveryMoves {
    if (_phase != PracticePhase.scrambling || !guidanceIsCorrection) {
      return const [];
    }
    return List.unmodifiable(_buildScrambleRecoveryMoves());
  }

  ({int completedMoves, int partialTurns, bool isCorrection})
  get _scrambleProgress {
    if (!_smartCubeWorkflowActive) {
      return (completedMoves: 0, partialTurns: 0, isCorrection: false);
    }
    if (_phase == PracticePhase.inspectionDelay ||
        _phase == PracticePhase.inspection ||
        _phase == PracticePhase.solving ||
        _phase == PracticePhase.stopped) {
      return (
        completedMoves: _scramble.moves.length,
        partialTurns: 0,
        isCorrection: false,
      );
    }

    var preparationIndex = 0;
    var completedMoves = 0;
    for (final expected in _scramble.moves) {
      if (preparationIndex >= _preparationMoves.length) break;
      final actual = _preparationMoves[preparationIndex];
      if (actual == expected) {
        preparationIndex++;
        completedMoves++;
        continue;
      }

      final isDirectionNeutralDoublePartial =
          expected.turns == 2 &&
          actual.face == expected.face &&
          actual.turns != 2 &&
          preparationIndex == _preparationMoves.length - 1;
      if (isDirectionNeutralDoublePartial) {
        return (
          completedMoves: completedMoves,
          partialTurns: 1,
          isCorrection: false,
        );
      }

      return (
        completedMoves: completedMoves,
        partialTurns: 0,
        isCorrection: true,
      );
    }

    return (
      completedMoves: completedMoves,
      partialTurns: 0,
      isCorrection: preparationIndex < _preparationMoves.length,
    );
  }

  bool get guidanceIsCorrection {
    if (_phase != PracticePhase.scrambling) return false;
    return _scrambleProgress.isCorrection;
  }

  bool get primaryActionEnabled {
    if (_smartCubeWorkflowActive) {
      return _phase == PracticePhase.inspection ||
          _phase == PracticePhase.solving;
    }
    return _phase == PracticePhase.manualReady ||
        _phase == PracticePhase.solving ||
        _phase == PracticePhase.stopped;
  }

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
      'version': 2,
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
    if (_phase == PracticePhase.inspectionDelay ||
        _phase == PracticePhase.inspection ||
        _phase == PracticePhase.solving) {
      return;
    }
    _scramble = _scrambleGenerator.generate();
    _scrambleTarget = _stateForScramble(_scramble);
    _preparationMoves.clear();
    _currentMoves.clear();
    _clock.reset();
    _clearAttemptTiming();
    if (_smartCubeWorkflowActive) {
      _phase = !_hasAuthoritativeCubeState
          ? PracticePhase.awaitingCubeState
          : _cubeState.isSolved
          ? PracticePhase.scrambling
          : PracticePhase.needsSolvedCube;
    } else {
      _cubeState = _scrambleTarget.copy();
      _phase = PracticePhase.manualReady;
    }
    notifyListeners();
  }

  void resetCubeToScramble() {
    if (_phase == PracticePhase.solving || _smartCubeWorkflowActive) return;
    _cubeState = _scrambleTarget.copy();
    _currentMoves.clear();
    notifyListeners();
  }

  void setSmartCubeConnected(bool connected, {bool demoMode = false}) {
    if (demoMode) {
      _activateManualMode();
      return;
    }
    if (_smartCubeConnected == connected &&
        (_smartCubeWorkflowActive || !connected)) {
      return;
    }
    final wasSmartCubeWorkflowActive = _smartCubeWorkflowActive;
    _smartCubeConnected = connected;
    if (connected) {
      _smartCubeWorkflowActive = true;
      if (!wasSmartCubeWorkflowActive && _phase == PracticePhase.stopped) {
        _phase = PracticePhase.awaitingCubeState;
      }
      _classifyConnectedPreparationState();
    } else if (_smartCubeWorkflowActive) {
      _hasAuthoritativeCubeState = false;
      if (_phase != PracticePhase.inspectionDelay &&
          _phase != PracticePhase.inspection &&
          _phase != PracticePhase.solving &&
          _phase != PracticePhase.stopped) {
        _phase = PracticePhase.awaitingCubeState;
      }
    }
    notifyListeners();
  }

  void syncCubeState(CubeState state, {DateTime? occurredAt}) {
    final trackedFacelets = _cubeState.facelets;
    _cubeState = state.copy();
    _hasAuthoritativeCubeState = true;
    if (!_smartCubeWorkflowActive) {
      notifyListeners();
      return;
    }

    if (_phase == PracticePhase.inspectionDelay) {
      if (_cubeState.facelets == _scrambleTarget.facelets) {
        notifyListeners();
        return;
      }
      _cancelPreInspectionDelay();
      if (_cubeState.isSolved) {
        _preparationMoves.clear();
        _phase = PracticePhase.scrambling;
      } else {
        _preparationMoves.clear();
        _phase = PracticePhase.needsSolvedCube;
      }
      notifyListeners();
      return;
    }
    if (_phase == PracticePhase.inspection) {
      if (_cubeState.facelets != _scrambleTarget.facelets) {
        _startSolvingFromInspection(occurredAt ?? _now());
        if (_cubeState.isSolved) {
          _completeSolve(inputSource: 'smart_cube_state');
          return;
        }
      }
      notifyListeners();
      return;
    }
    if (_phase == PracticePhase.solving) {
      if (_cubeState.isSolved) {
        _completeSolve(inputSource: 'smart_cube_state');
        return;
      }
      notifyListeners();
      return;
    }

    switch (_phase) {
      case PracticePhase.awaitingCubeState:
        if (_cubeState.facelets == _scrambleTarget.facelets) {
          _beginPreInspectionDelay();
          return;
        }
        if (_cubeState.isSolved) {
          _preparationMoves.clear();
          _phase = PracticePhase.scrambling;
        } else if (_preparationMoves.isNotEmpty &&
            _cubeState.facelets == trackedFacelets) {
          _phase = PracticePhase.scrambling;
        } else {
          _preparationMoves.clear();
          _phase = PracticePhase.needsSolvedCube;
        }
        break;
      case PracticePhase.needsSolvedCube:
        if (_cubeState.facelets == _scrambleTarget.facelets) {
          _beginPreInspectionDelay();
          return;
        }
        if (_cubeState.isSolved) {
          _preparationMoves.clear();
          _phase = PracticePhase.scrambling;
        }
        break;
      case PracticePhase.scrambling:
        if (_cubeState.facelets == _scrambleTarget.facelets) {
          _beginPreInspectionDelay();
          return;
        }
        if (_cubeState.isSolved) {
          _preparationMoves.clear();
        } else if (_cubeState.facelets != trackedFacelets) {
          _preparationMoves.clear();
          _phase = PracticePhase.needsSolvedCube;
        }
        break;
      case PracticePhase.manualReady ||
          PracticePhase.inspectionDelay ||
          PracticePhase.inspection ||
          PracticePhase.solving ||
          PracticePhase.stopped:
        break;
    }
    notifyListeners();
  }

  void toggleTimer() {
    if (!primaryActionEnabled) return;
    if (_smartCubeWorkflowActive) {
      abortAttempt();
      return;
    }
    if (_phase == PracticePhase.solving) {
      stopSolve();
    } else {
      startSolve();
    }
  }

  void startSolve() {
    if (_smartCubeWorkflowActive || _phase == PracticePhase.solving) return;
    _currentMoves.clear();
    _clock
      ..reset()
      ..start();
    _phase = PracticePhase.solving;
    _activeAttemptUsesSmartCube = false;
    _inspectionElapsed = null;
    _startTrigger = SolveStartTrigger.manual;
    _startTicker();
    notifyListeners();
  }

  void stopSolve({String inputSource = 'manual'}) {
    if (_phase != PracticePhase.solving || _activeAttemptUsesSmartCube) return;
    _completeSolve(inputSource: inputSource);
  }

  void abortAttempt() {
    if (_phase != PracticePhase.inspection && _phase != PracticePhase.solving) {
      return;
    }
    _ticker?.cancel();
    _ticker = null;
    _clock.reset();
    _currentMoves.clear();
    _clearAttemptTiming();
    _activeAttemptUsesSmartCube = false;
    if (_smartCubeWorkflowActive) {
      _preparationMoves.clear();
      _phase = !_hasAuthoritativeCubeState
          ? PracticePhase.awaitingCubeState
          : _cubeState.isSolved
          ? PracticePhase.scrambling
          : PracticePhase.needsSolvedCube;
    } else {
      _phase = PracticePhase.manualReady;
    }
    notifyListeners();
  }

  void _completeSolve({required String inputSource}) {
    if (_phase != PracticePhase.solving) return;
    _clock.stop();
    _ticker?.cancel();
    _ticker = null;
    _phase = PracticePhase.stopped;

    final createdAt = _now();
    final solve = SolveRecord(
      id: createdAt.microsecondsSinceEpoch.toString(),
      scramble: _scramble.toString(),
      elapsed: _clock.elapsed,
      moveCount: _currentMoves.length,
      createdAt: createdAt,
      inputSource: inputSource,
      inspectionElapsed: _inspectionElapsed,
      startTrigger: _startTrigger,
    );
    _solves.insert(0, solve);
    _activeAttemptUsesSmartCube = false;
    _schedulePersistence();
    notifyListeners();
  }

  void applyMove(
    CubeMove move, {
    bool fromSmartCube = false,
    DateTime? occurredAt,
  }) {
    if (_smartCubeWorkflowActive && !fromSmartCube) return;
    _lastAppliedMove = move;
    _cubeMoveRevision++;

    if (fromSmartCube && _smartCubeWorkflowActive) {
      _applySmartCubeMove(move, occurredAt: occurredAt ?? _now());
      return;
    }

    _cubeState.apply(move);
    if (_phase == PracticePhase.solving) {
      _currentMoves.add(move);
    }
    if (_phase == PracticePhase.solving && _cubeState.isSolved) {
      _completeSolve(inputSource: 'manual_moves');
      return;
    }
    notifyListeners();
  }

  void _applySmartCubeMove(CubeMove move, {required DateTime occurredAt}) {
    if (_phase == PracticePhase.inspectionDelay) {
      _cancelPreInspectionDelay();
      _cubeState.apply(move);
      final reducedPreparation = _reduceMoves([..._preparationMoves, move]);
      _preparationMoves
        ..clear()
        ..addAll(reducedPreparation);
      if (_cubeState.isSolved) {
        _preparationMoves.clear();
      }
      _phase = PracticePhase.scrambling;
      notifyListeners();
      return;
    }
    if (_phase == PracticePhase.inspection) {
      _startSolvingFromInspection(occurredAt);
      _cubeState.apply(move);
      _currentMoves.add(move);
      if (_cubeState.isSolved) {
        _completeSolve(inputSource: 'smart_cube');
        return;
      }
      notifyListeners();
      return;
    }
    if (_phase == PracticePhase.solving) {
      _cubeState.apply(move);
      _currentMoves.add(move);
      if (_cubeState.isSolved) {
        _completeSolve(inputSource: 'smart_cube');
        return;
      }
      notifyListeners();
      return;
    }
    if (_phase == PracticePhase.scrambling) {
      _cubeState.apply(move);
      final reducedPreparation = _reduceMoves([..._preparationMoves, move]);
      _preparationMoves
        ..clear()
        ..addAll(reducedPreparation);
      if (_cubeState.facelets == _scrambleTarget.facelets) {
        _beginPreInspectionDelay();
        return;
      }
      notifyListeners();
      return;
    }
    if (_phase == PracticePhase.needsSolvedCube) {
      _cubeState.apply(move);
      if (_cubeState.isSolved) {
        _preparationMoves.clear();
        _phase = PracticePhase.scrambling;
      }
      notifyListeners();
      return;
    }

    _cubeState.apply(move);
    notifyListeners();
  }

  void _beginPreInspectionDelay() {
    _currentMoves.clear();
    _clock.reset();
    _clearAttemptTiming();
    final startedAt = _now();
    if (preInspectionDelay == Duration.zero) {
      _beginInspection(startedAt: startedAt);
      return;
    }
    _preInspectionDeadline = startedAt.add(preInspectionDelay);
    _phase = PracticePhase.inspectionDelay;
    _startTicker();
    notifyListeners();
  }

  void _beginInspection({DateTime? startedAt}) {
    _currentMoves.clear();
    _clock.reset();
    _preInspectionDeadline = null;
    _inspectionStartedAt = startedAt ?? _now();
    _inspectionDeadline = _inspectionStartedAt!.add(inspectionDuration);
    _inspectionElapsed = null;
    _startTrigger = null;
    _activeAttemptUsesSmartCube = true;
    _phase = PracticePhase.inspection;
    final now = _now();
    if (!now.isBefore(_inspectionDeadline!)) {
      _startSolvingFromInspection(now);
      notifyListeners();
      return;
    }
    _startTicker();
    notifyListeners();
  }

  void _startSolvingFromInspection(DateTime occurredAt) {
    if (_phase != PracticePhase.inspection) return;
    final startedAt = _inspectionStartedAt!;
    final deadline = _inspectionDeadline!;
    if (!occurredAt.isBefore(deadline)) {
      _inspectionElapsed = inspectionDuration;
      _startTrigger = SolveStartTrigger.inspectionTimeout;
      _clock.start(initialElapsed: occurredAt.difference(deadline));
    } else {
      final inspectedFor = occurredAt.difference(startedAt);
      _inspectionElapsed = inspectedFor.isNegative
          ? Duration.zero
          : inspectedFor;
      _startTrigger = SolveStartTrigger.firstMove;
      _clock.start();
    }
    _phase = PracticePhase.solving;
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 31), (_) {
      if (_phase == PracticePhase.inspectionDelay) {
        final now = _now();
        final deadline = _preInspectionDeadline!;
        if (!now.isBefore(deadline)) {
          _beginInspection(startedAt: deadline);
        }
      } else if (_phase == PracticePhase.inspection) {
        final now = _now();
        final deadline = _inspectionDeadline!;
        if (!now.isBefore(deadline)) {
          _startSolvingFromInspection(now);
        }
      }
      notifyListeners();
    });
  }

  void _classifyConnectedPreparationState() {
    if (_phase == PracticePhase.inspectionDelay ||
        _phase == PracticePhase.inspection ||
        _phase == PracticePhase.solving ||
        _phase == PracticePhase.stopped) {
      return;
    }
    if (!_hasAuthoritativeCubeState) {
      _phase = PracticePhase.awaitingCubeState;
    } else if (_cubeState.facelets == _scrambleTarget.facelets) {
      _beginPreInspectionDelay();
    } else if (_cubeState.isSolved) {
      _preparationMoves.clear();
      _phase = PracticePhase.scrambling;
    } else {
      _preparationMoves.clear();
      _phase = PracticePhase.needsSolvedCube;
    }
  }

  void _activateManualMode() {
    final alreadyManual = !_smartCubeConnected && !_smartCubeWorkflowActive;
    _smartCubeConnected = false;
    _smartCubeWorkflowActive = false;
    _hasAuthoritativeCubeState = false;
    if (alreadyManual) return;
    if (_phase == PracticePhase.inspectionDelay ||
        _phase == PracticePhase.inspection ||
        (_phase == PracticePhase.solving && _activeAttemptUsesSmartCube)) {
      _ticker?.cancel();
      _ticker = null;
      _clock.reset();
      _currentMoves.clear();
      _clearAttemptTiming();
    }
    _preparationMoves.clear();
    _activeAttemptUsesSmartCube = false;
    _cubeState = _scrambleTarget.copy();
    _phase = PracticePhase.manualReady;
    notifyListeners();
  }

  List<CubeMove> _buildScrambleGuidance() {
    final progress = _scrambleProgress;
    if (progress.isCorrection) {
      return [
        ..._buildScrambleRecoveryMoves(completedMoves: progress.completedMoves),
        ..._scramble.moves.skip(progress.completedMoves),
      ];
    }
    return _reduceMoves([
      ..._preparationMoves.reversed.map((move) => move.inverse),
      ..._scramble.moves,
    ]);
  }

  List<CubeMove> _buildScrambleRecoveryMoves({int? completedMoves}) {
    final completed = completedMoves ?? _scrambleProgress.completedMoves;
    return _reduceMoves([
      ..._preparationMoves.reversed.map((move) => move.inverse),
      ..._scramble.moves.take(completed),
    ]);
  }

  static List<CubeMove> _reduceMoves(Iterable<CubeMove> moves) {
    final reduced = <CubeMove>[];
    for (final move in moves) {
      if (reduced.isEmpty || reduced.last.face != move.face) {
        reduced.add(move);
        continue;
      }
      final turns = (reduced.removeLast().turns + move.turns) % 4;
      if (turns != 0) reduced.add(CubeMove(move.face, turns: turns));
    }
    return reduced;
  }

  static CubeState _stateForScramble(Scramble scramble) =>
      CubeState.solved()..applyAll(scramble.moves);

  void _clearAttemptTiming() {
    _preInspectionDeadline = null;
    _inspectionStartedAt = null;
    _inspectionDeadline = null;
    _inspectionElapsed = null;
    _startTrigger = null;
  }

  void _cancelPreInspectionDelay() {
    _ticker?.cancel();
    _ticker = null;
    _preInspectionDeadline = null;
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
