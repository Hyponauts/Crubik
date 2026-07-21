import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../cube/domain/cube_model.dart';
import '../../cube/domain/scramble_generator.dart';
import '../domain/solve_record.dart';
import 'solve_history.dart';

enum PracticePhase {
  manualReady,
  awaitingCubeState,
  needsSolvedCube,
  scrambling,
  inspectionDelay,
  inspection,
  solving,
}

enum PracticeInputMode { unselected, demo, smartCube }

extension PracticePhaseState on PracticePhase {
  bool get isAttemptInProgress => switch (this) {
    PracticePhase.inspectionDelay ||
    PracticePhase.inspection ||
    PracticePhase.solving => true,
    _ => false,
  };

  bool get isBeforeSolve => switch (this) {
    PracticePhase.awaitingCubeState ||
    PracticePhase.needsSolvedCube ||
    PracticePhase.scrambling => true,
    _ => false,
  };
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

sealed class _SmartCubeUpdate {
  const _SmartCubeUpdate(this.occurredAt);

  final DateTime occurredAt;

  SolveInputSource get completionSource => switch (this) {
    _SmartCubeMoveUpdate() => SolveInputSource.smartCube,
    _SmartCubeStateUpdate() => SolveInputSource.smartCubeState,
  };
}

final class _SmartCubeMoveUpdate extends _SmartCubeUpdate {
  const _SmartCubeMoveUpdate(this.move, super.occurredAt);

  final CubeMove move;
}

final class _SmartCubeStateUpdate extends _SmartCubeUpdate {
  const _SmartCubeStateUpdate(this.state, super.occurredAt);

  final CubeState state;
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
       _clock = clock ?? StopwatchSolveClock(),
       _now = now ?? DateTime.now {
    _history = SolveHistory(
      repository: repository ?? MemorySolveHistoryRepository(),
      now: _now,
    );
    _scramble = _scrambleGenerator.generate();
    _scrambleTarget = _stateForScramble(_scramble);
    _cubeState = _scrambleTarget.copy();
  }

  final ScrambleGenerator _scrambleGenerator;
  final SolveClock _clock;
  final DateTime Function() _now;
  late final SolveHistory _history;
  final Duration preInspectionDelay;
  final Duration inspectionDuration;
  final ChangeNotifier _clockTicks = ChangeNotifier();

  late Scramble _scramble;
  late CubeState _scrambleTarget;
  late CubeState _cubeState;
  final List<CubeMove> _preparationMoves = [];
  final List<CubeMove> _currentMoves = [];
  PracticePhase _phase = PracticePhase.manualReady;
  PracticeInputMode _inputMode = PracticeInputMode.unselected;
  Timer? _ticker;
  bool _hasAuthoritativeCubeState = false;
  PracticeInputMode? _attemptInputMode;
  DateTime? _preInspectionDeadline;
  DateTime? _inspectionStartedAt;
  DateTime? _inspectionDeadline;
  Duration? _inspectionElapsed;
  SolveStartTrigger? _startTrigger;
  CubeMove? _lastAppliedMove;
  int _cubeMoveRevision = 0;
  SolveRecord? _pendingSolveReview;
  bool _disposed = false;

  Scramble get scramble => _scramble;
  CubeState get cubeState => _cubeState;
  List<CubeMove> get currentMoves => List.unmodifiable(_currentMoves);
  List<SolveRecord> get solves => _history.records;
  PracticePhase get phase => _phase;
  PracticeInputMode get inputMode => _inputMode;
  Duration get elapsed => _clock.elapsed;
  bool get attemptInProgress => _phase.isAttemptInProgress;
  bool get canChangeScramble =>
      _inputMode != PracticeInputMode.unselected && !attemptInProgress;
  bool get smartCubeWorkflowActive => _inputMode == PracticeInputMode.smartCube;
  CubeMove? get lastAppliedMove => _lastAppliedMove;
  int get cubeMoveRevision => _cubeMoveRevision;
  SolveRecord? get pendingSolveReview => _pendingSolveReview;
  Listenable get clockTicks => _clockTicks;
  Object? get persistenceError => _history.persistenceError;

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
    if (!smartCubeWorkflowActive) {
      return (completedMoves: 0, partialTurns: 0, isCorrection: false);
    }
    if (_phase.isAttemptInProgress) {
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
    if (_inputMode == PracticeInputMode.smartCube) {
      return attemptInProgress;
    }
    if (_inputMode != PracticeInputMode.demo) return false;
    return _phase == PracticePhase.manualReady ||
        _phase == PracticePhase.inspectionDelay ||
        _phase == PracticePhase.inspection ||
        _phase == PracticePhase.solving;
  }

  bool get hasSolves => _history.hasRecords;

  Duration? get bestTime => _history.bestTime;

  Duration? get sessionAverage => _history.sessionAverage;

  Duration? get averageOfFive => _history.averageOfFive;

  String exportJson() => _history.exportJson();

  Future<void> flushPersistence() => _history.flush();

  Future<void> initialize() async {
    await _history.initialize();
    if (!_disposed) notifyListeners();
  }

  void newScramble() {
    if (!canChangeScramble) return;
    _generateNextScramble();
    notifyListeners();
  }

  void activateDemoInput() {
    if (_inputMode == PracticeInputMode.demo) return;
    _cancelAttemptForModeChange();
    _inputMode = PracticeInputMode.demo;
    _hasAuthoritativeCubeState = false;
    _cubeState = _scrambleTarget.copy();
    _phase = PracticePhase.manualReady;
    notifyListeners();
  }

  void clearDemoInput() {
    if (_inputMode != PracticeInputMode.demo) return;
    _cancelAttemptForModeChange();
    _inputMode = PracticeInputMode.unselected;
    _hasAuthoritativeCubeState = false;
    _cubeState = _scrambleTarget.copy();
    _phase = PracticePhase.manualReady;
    notifyListeners();
  }

  void activateSmartCubeInput() {
    if (smartCubeWorkflowActive) return;
    _cancelAttemptForModeChange();
    _inputMode = PracticeInputMode.smartCube;
    _hasAuthoritativeCubeState = false;
    _phase = PracticePhase.awaitingCubeState;
    notifyListeners();
  }

  void markSmartCubeDisconnected() {
    if (!smartCubeWorkflowActive) return;
    _hasAuthoritativeCubeState = false;
    if (!attemptInProgress) {
      _phase = PracticePhase.awaitingCubeState;
    }
    notifyListeners();
  }

  void syncCubeState(CubeState state, {DateTime? occurredAt}) {
    if (!smartCubeWorkflowActive) return;
    _processSmartCubeUpdate(_SmartCubeStateUpdate(state, occurredAt ?? _now()));
  }

  void _processSmartCubeUpdate(_SmartCubeUpdate update) {
    final previousFacelets = _cubeState.facelets;
    switch (update) {
      case _SmartCubeMoveUpdate(:final move):
        _lastAppliedMove = move;
        _cubeMoveRevision++;
        _cubeState.apply(move);
      case _SmartCubeStateUpdate(:final state):
        _cubeState = state.copy();
        _hasAuthoritativeCubeState = true;
    }

    final completedInternally = switch (_phase) {
      PracticePhase.inspectionDelay => _handleReadinessUpdate(update),
      PracticePhase.inspection => _handleInspectionUpdate(update),
      PracticePhase.solving => _handleSolvingUpdate(update),
      PracticePhase.awaitingCubeState ||
      PracticePhase.needsSolvedCube ||
      PracticePhase.scrambling => _handlePreparationUpdate(
        update,
        previousFacelets,
      ),
      PracticePhase.manualReady => false,
    };
    if (!completedInternally) notifyListeners();
  }

  bool _handleReadinessUpdate(_SmartCubeUpdate update) {
    switch (update) {
      case _SmartCubeStateUpdate():
        if (_cubeState.facelets == _scrambleTarget.facelets) return false;
        _cancelPreInspectionDelay();
        _preparationMoves.clear();
        _phase = _cubeState.isSolved
            ? PracticePhase.scrambling
            : PracticePhase.needsSolvedCube;
      case _SmartCubeMoveUpdate(:final move):
        _cancelPreInspectionDelay();
        _recordPreparationMove(move);
        if (_cubeState.isSolved) _preparationMoves.clear();
        _phase = PracticePhase.scrambling;
    }
    return false;
  }

  bool _handleInspectionUpdate(_SmartCubeUpdate update) {
    switch (update) {
      case _SmartCubeStateUpdate():
        if (_cubeState.facelets == _scrambleTarget.facelets) return false;
      case _SmartCubeMoveUpdate(:final move):
        _currentMoves.add(move);
    }
    _startSolvingFromInspection(update.occurredAt);
    return _completeSmartCubeSolveIfSolved(update);
  }

  bool _handleSolvingUpdate(_SmartCubeUpdate update) {
    if (update case _SmartCubeMoveUpdate(:final move)) {
      _currentMoves.add(move);
    }
    return _completeSmartCubeSolveIfSolved(update);
  }

  bool _handlePreparationUpdate(
    _SmartCubeUpdate update,
    String previousFacelets,
  ) {
    switch (update) {
      case _SmartCubeMoveUpdate(:final move):
        if (_phase == PracticePhase.scrambling) {
          _recordPreparationMove(move);
          if (_cubeState.facelets == _scrambleTarget.facelets) {
            _beginPreInspectionDelay();
            return true;
          }
        } else if (_phase == PracticePhase.needsSolvedCube &&
            _cubeState.isSolved) {
          _preparationMoves.clear();
          _phase = PracticePhase.scrambling;
        }
      case _SmartCubeStateUpdate():
        if (_cubeState.facelets == _scrambleTarget.facelets) {
          _beginPreInspectionDelay();
          return true;
        }
        switch (_phase) {
          case PracticePhase.awaitingCubeState:
            if (_cubeState.isSolved) {
              _preparationMoves.clear();
              _phase = PracticePhase.scrambling;
            } else if (_preparationMoves.isNotEmpty &&
                _cubeState.facelets == previousFacelets) {
              _phase = PracticePhase.scrambling;
            } else {
              _preparationMoves.clear();
              _phase = PracticePhase.needsSolvedCube;
            }
          case PracticePhase.needsSolvedCube:
            if (_cubeState.isSolved) {
              _preparationMoves.clear();
              _phase = PracticePhase.scrambling;
            }
          case PracticePhase.scrambling:
            if (_cubeState.isSolved) {
              _preparationMoves.clear();
            } else if (_cubeState.facelets != previousFacelets) {
              _preparationMoves.clear();
              _phase = PracticePhase.needsSolvedCube;
            }
          case _:
            break;
        }
    }
    return false;
  }

  bool _completeSmartCubeSolveIfSolved(_SmartCubeUpdate update) {
    if (!_cubeState.isSolved) return false;
    _completeSolve(inputSource: update.completionSource);
    return true;
  }

  void _recordPreparationMove(CubeMove move) {
    final reducedPreparation = _reduceMoves([..._preparationMoves, move]);
    _preparationMoves
      ..clear()
      ..addAll(reducedPreparation);
  }

  void toggleTimer() {
    if (!primaryActionEnabled) return;
    if (_phase == PracticePhase.inspectionDelay ||
        _phase == PracticePhase.inspection) {
      abortAttempt();
      return;
    }
    if (_phase == PracticePhase.solving) {
      if (_attemptInputMode == PracticeInputMode.smartCube) {
        abortAttempt();
      } else {
        stopSolve();
      }
    } else {
      startSolve();
    }
  }

  void startSolve() {
    if (_inputMode != PracticeInputMode.demo ||
        _phase != PracticePhase.manualReady) {
      return;
    }
    _beginPreInspectionDelay();
  }

  void stopSolve({SolveInputSource inputSource = SolveInputSource.manual}) {
    if (_phase != PracticePhase.solving ||
        _attemptInputMode != PracticeInputMode.demo) {
      return;
    }
    _completeSolve(inputSource: inputSource);
  }

  void continueAfterSolve() {
    if (_pendingSolveReview == null) return;
    _pendingSolveReview = null;
    notifyListeners();
  }

  void abortAttempt() {
    if (!attemptInProgress) return;
    final attemptInputMode = _attemptInputMode;
    _ticker?.cancel();
    _ticker = null;
    _clock.reset();
    _currentMoves.clear();
    _clearAttemptTiming();
    if (attemptInputMode == PracticeInputMode.smartCube &&
        smartCubeWorkflowActive) {
      _preparationMoves.clear();
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

  void _completeSolve({required SolveInputSource inputSource}) {
    if (_phase != PracticePhase.solving) return;
    _clock.stop();
    _ticker?.cancel();
    _ticker = null;

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
    _history.add(solve);
    _pendingSolveReview = solve;
    _generateNextScramble();
    notifyListeners();
  }

  void applyMove(
    CubeMove move, {
    bool fromSmartCube = false,
    DateTime? occurredAt,
  }) {
    if (fromSmartCube) {
      if (!smartCubeWorkflowActive) return;
      _processSmartCubeUpdate(_SmartCubeMoveUpdate(move, occurredAt ?? _now()));
      return;
    }
    if (_inputMode != PracticeInputMode.demo ||
        (_phase != PracticePhase.inspection &&
            _phase != PracticePhase.solving)) {
      return;
    }

    _lastAppliedMove = move;
    _cubeMoveRevision++;

    if (_phase == PracticePhase.inspection) {
      _startSolvingFromInspection(occurredAt ?? _now());
    }
    _cubeState.apply(move);
    _currentMoves.add(move);
    if (_cubeState.isSolved) {
      _completeSolve(inputSource: SolveInputSource.manualMoves);
      return;
    }
    notifyListeners();
  }

  void _beginPreInspectionDelay() {
    _pendingSolveReview = null;
    _currentMoves.clear();
    _clock.reset();
    _clearAttemptTiming();
    _attemptInputMode = _inputMode;
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
          return;
        }
      } else if (_phase == PracticePhase.inspection) {
        final now = _now();
        final deadline = _inspectionDeadline!;
        if (!now.isBefore(deadline)) {
          _startSolvingFromInspection(now);
          notifyListeners();
          return;
        }
      }
      _clockTicks.notifyListeners();
    });
  }

  void _cancelAttemptForModeChange() {
    _ticker?.cancel();
    _ticker = null;
    _clock.reset();
    _preparationMoves.clear();
    _currentMoves.clear();
    _clearAttemptTiming();
    _pendingSolveReview = null;
  }

  void _generateNextScramble() {
    _scramble = _scrambleGenerator.generate();
    _scrambleTarget = _stateForScramble(_scramble);
    _preparationMoves.clear();
    _currentMoves.clear();
    _clock.reset();
    _clearAttemptTiming();
    if (smartCubeWorkflowActive) {
      _phase = !_hasAuthoritativeCubeState
          ? PracticePhase.awaitingCubeState
          : _cubeState.isSolved
          ? PracticePhase.scrambling
          : PracticePhase.needsSolvedCube;
    } else {
      _cubeState = _scrambleTarget.copy();
      _phase = PracticePhase.manualReady;
    }
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
    _attemptInputMode = null;
  }

  void _cancelPreInspectionDelay() {
    _ticker?.cancel();
    _ticker = null;
    _preInspectionDeadline = null;
    _attemptInputMode = null;
  }

  void deleteSolve(String id) {
    _history.delete(id);
    if (_pendingSolveReview?.id == id) _pendingSolveReview = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _clockTicks.dispose();
    super.dispose();
  }
}
