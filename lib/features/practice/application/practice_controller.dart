import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/time/monotonic_clock.dart';
import '../../cube/domain/cube_model.dart';
import '../../cube/domain/smart_cube_device.dart';
import '../../cube/domain/smart_cube_event.dart';
import '../domain/solve_record.dart';
import '../domain/solve_recording.dart';
import 'solve_history.dart';
import 'solve_recording_builder.dart';

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

  void startAt(Duration hostTimestamp);

  void stopAt(Duration hostTimestamp);
}

final class MonotonicSolveClock implements SolveClock {
  MonotonicSolveClock(this._monotonicClock);

  final MonotonicClock _monotonicClock;
  Duration? _startedAt;
  Duration? _stoppedAt;

  @override
  Duration get elapsed {
    final startedAt = _startedAt;
    if (startedAt == null) return Duration.zero;
    final end = _stoppedAt ?? _monotonicClock.now;
    if (end < startedAt) return Duration.zero;
    return end - startedAt;
  }

  @override
  void reset() {
    _startedAt = null;
    _stoppedAt = null;
  }

  @override
  void startAt(Duration hostTimestamp) {
    _startedAt = hostTimestamp;
    _stoppedAt = null;
  }

  @override
  void stopAt(Duration hostTimestamp) {
    final startedAt = _startedAt;
    if (startedAt == null) return;
    _stoppedAt = hostTimestamp < startedAt ? startedAt : hostTimestamp;
  }
}

final class PracticeController extends ChangeNotifier {
  static const defaultPreInspectionDelay = Duration(seconds: 3);
  static const defaultInspectionDuration = Duration(seconds: 15);

  PracticeController({
    required FutureOr<CubeScramble> Function() nextScramble,
    SolveHistoryRepository? repository,
    SolveClock? clock,
    MonotonicClock? monotonicClock,
    DateTime Function()? now,
    Duration preInspectionDelay = defaultPreInspectionDelay,
    Duration inspectionDuration = defaultInspectionDuration,
  }) : this._(
         nextScramble,
         repository,
         clock,
         monotonicClock,
         now,
         preInspectionDelay,
         inspectionDuration,
       );

  PracticeController._(
    this._nextScramble,
    SolveHistoryRepository? repository,
    SolveClock? clock,
    MonotonicClock? monotonicClock,
    DateTime Function()? now,
    this.preInspectionDelay,
    this.inspectionDuration,
  ) : _now = now ?? DateTime.now {
    _monotonicClock = monotonicClock ?? StopwatchMonotonicClock();
    _clock = clock ?? MonotonicSolveClock(_monotonicClock);
    _history = SolveHistory(
      repository: repository ?? MemorySolveHistoryRepository(),
      now: _now,
    );
    _requestNextScramble(notify: false);
  }

  final FutureOr<CubeScramble> Function() _nextScramble;
  late final SolveClock _clock;
  late final MonotonicClock _monotonicClock;
  final DateTime Function() _now;
  late final SolveHistory _history;
  final Duration preInspectionDelay;
  final Duration inspectionDuration;
  final ChangeNotifier _clockTicks = ChangeNotifier();

  CubeScramble? _scramble;
  CubeState? _scrambleTarget;
  CubeState _cubeState = CubeState.solved();
  final List<CubeMove> _preparationMoves = [];
  final List<CubeMove> _currentMoves = [];
  final SolveRecordingBuilder _recordingBuilder = SolveRecordingBuilder();
  PracticePhase _phase = PracticePhase.manualReady;
  PracticeInputMode _inputMode = PracticeInputMode.unselected;
  Timer? _ticker;
  bool _hasAuthoritativeCubeState = false;
  PracticeInputMode? _attemptInputMode;
  Duration? _preInspectionDeadline;
  Duration? _inspectionStartedAt;
  Duration? _inspectionDeadline;
  Duration? _inspectionElapsed;
  Duration? _solveStartedAt;
  bool _isTimingReliable = true;
  SolveStartTrigger? _startTrigger;
  CubeMove? _lastAppliedMove;
  int _cubeMoveRevision = 0;
  SolveRecord? _pendingSolveReview;
  bool _isPreparingScramble = false;
  Object? _scramblePreparationError;
  int _scrambleRequest = 0;
  bool _disposed = false;

  CubeScramble get scramble => _scramble!;

  /// The latest generated sequence, including while a replacement is prepared.
  CubeScramble? get displayedScramble => _scramble;

  bool get hasScramble =>
      _scramble != null &&
      _scrambleTarget != null &&
      !_isPreparingScramble &&
      _scramblePreparationError == null;
  bool get isPreparingScramble => _isPreparingScramble;
  Object? get scramblePreparationError => _scramblePreparationError;
  CubeState get cubeState => _cubeState;
  List<CubeMove> get currentMoves => List.unmodifiable(_currentMoves);
  List<SolveRecord> get solves => _history.records;
  PracticePhase get phase => _phase;
  PracticeInputMode get inputMode => _inputMode;
  Duration get elapsed => _clock.elapsed;
  bool get attemptInProgress => _phase.isAttemptInProgress;
  bool get canChangeScramble =>
      hasScramble &&
      !_isPreparingScramble &&
      _inputMode != PracticeInputMode.unselected &&
      !attemptInProgress;
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
    final remaining = deadline - _monotonicClock.now;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration get inspectionRemaining {
    if (_phase != PracticePhase.inspection) return Duration.zero;
    final deadline = _inspectionDeadline;
    if (deadline == null) return Duration.zero;
    final remaining = deadline - _monotonicClock.now;
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
    final scramble = _scramble;
    if (!smartCubeWorkflowActive || scramble == null) {
      return (completedMoves: 0, partialTurns: 0, isCorrection: false);
    }
    if (_phase.isAttemptInProgress) {
      return (
        completedMoves: scramble.moves.length,
        partialTurns: 0,
        isCorrection: false,
      );
    }

    var preparationIndex = 0;
    var completedMoves = 0;
    for (final expected in scramble.moves) {
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
    if (!hasScramble || _isPreparingScramble) return false;
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

  Future<String> exportJson() => _history.exportJson();

  Future<void> flushPersistence() => _history.flush();

  Future<void> initialize() async {
    await _history.initialize();
    if (!_disposed) notifyListeners();
  }

  void newScramble() {
    if (!canChangeScramble) return;
    _requestNextScramble();
  }

  void retryScramble() {
    if (_isPreparingScramble || _scramblePreparationError == null) return;
    _requestNextScramble();
  }

  void activateDemoInput() {
    if (_inputMode == PracticeInputMode.demo) return;
    _cancelAttemptForModeChange();
    _inputMode = PracticeInputMode.demo;
    _recordingBuilder.resetSource();
    _hasAuthoritativeCubeState = false;
    _cubeState = _scrambleTarget?.copy() ?? CubeState.solved();
    _phase = PracticePhase.manualReady;
    notifyListeners();
  }

  void clearDemoInput() {
    if (_inputMode != PracticeInputMode.demo) return;
    _cancelAttemptForModeChange();
    _inputMode = PracticeInputMode.unselected;
    _recordingBuilder.resetSource();
    _hasAuthoritativeCubeState = false;
    _cubeState = _scrambleTarget?.copy() ?? CubeState.solved();
    _phase = PracticePhase.manualReady;
    notifyListeners();
  }

  void activateSmartCubeInput({
    CubeProtocolFamily? protocolFamily,
    CubeCapabilities? capabilities,
  }) {
    _recordingBuilder.configureSource(
      protocolFamily: protocolFamily,
      capabilities: capabilities,
    );
    if (smartCubeWorkflowActive) return;
    _cancelAttemptForModeChange();
    _inputMode = PracticeInputMode.smartCube;
    _hasAuthoritativeCubeState = false;
    _phase = PracticePhase.awaitingCubeState;
    notifyListeners();
  }

  void markSmartCubeDisconnected() {
    if (!smartCubeWorkflowActive) return;
    if (_phase == PracticePhase.solving) {
      _recordingBuilder.recordGap(
        RecordingGapReason.connectionDiscontinuity,
        _monotonicClock.now,
      );
    } else if (_phase == PracticePhase.inspectionDelay ||
        _phase == PracticePhase.inspection) {
      _recordingBuilder.queueGap(
        RecordingGapReason.connectionDiscontinuity,
        _monotonicClock.now,
      );
    }
    _recordingBuilder.clearPose();
    _hasAuthoritativeCubeState = false;
    if (!attemptInProgress) {
      _phase = PracticePhase.awaitingCubeState;
    }
    notifyListeners();
  }

  void handleSmartCubeEvent(SmartCubeEvent event) {
    if (!smartCubeWorkflowActive) return;
    switch (event) {
      case SmartCubeUpdate():
        _processSmartCubeUpdate(event);
      case SmartCubeOrientationEvent():
        _recordingBuilder.observeOrientation(event);
      case SmartCubeCapabilitiesEvent(:final capabilities):
        _recordingBuilder.configureSource(capabilities: capabilities);
      case SmartCubeDataGapEvent():
        if (_phase == PracticePhase.solving) {
          _recordingBuilder.recordSmartCubeGap(event);
        } else if (_phase == PracticePhase.inspectionDelay ||
            _phase == PracticePhase.inspection) {
          _recordingBuilder.queueSmartCubeGap(event);
        }
    }
  }

  void syncCubeState(
    CubeState state, {
    Duration? hostTimestamp,
    int serial = 0,
  }) {
    if (!smartCubeWorkflowActive) return;
    _processSmartCubeUpdate(
      SmartCubeStateEvent(
        state: state,
        serial: serial,
        receivedAt: _now(),
        hostTimestamp: hostTimestamp ?? _monotonicClock.now,
      ),
    );
  }

  void _processSmartCubeUpdate(SmartCubeUpdate update) {
    final previousFacelets = _cubeState.facelets;
    switch (update) {
      case SmartCubeMoveEvent(:final move):
        _lastAppliedMove = move;
        _cubeMoveRevision++;
        _cubeState.apply(move);
      case SmartCubeStateEvent(:final state):
        _cubeState = state.copy();
        _hasAuthoritativeCubeState = true;
    }

    if (!hasScramble) {
      notifyListeners();
      return;
    }

    final completedInternally = switch (_phase) {
      PracticePhase.inspectionDelay => _handleReadinessUpdate(update),
      PracticePhase.inspection => _handleInspectionUpdate(update),
      PracticePhase.solving => _handleSolvingUpdate(update, previousFacelets),
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

  bool _handleReadinessUpdate(SmartCubeUpdate update) {
    final scrambleTarget = _scrambleTarget!;
    switch (update) {
      case SmartCubeStateEvent():
        if (_cubeState.facelets == scrambleTarget.facelets) return false;
        _cancelPreInspectionDelay();
        _preparationMoves.clear();
        _phase = _cubeState.isSolved
            ? PracticePhase.scrambling
            : PracticePhase.needsSolvedCube;
      case SmartCubeMoveEvent(:final move):
        _cancelPreInspectionDelay();
        _recordPreparationMove(move);
        if (_cubeState.isSolved) _preparationMoves.clear();
        _phase = PracticePhase.scrambling;
    }
    return false;
  }

  bool _handleInspectionUpdate(SmartCubeUpdate update) {
    final scrambleTarget = _scrambleTarget!;
    switch (update) {
      case SmartCubeStateEvent():
        if (_cubeState.facelets == scrambleTarget.facelets) return false;
      case SmartCubeMoveEvent(:final move):
        _currentMoves.add(move);
    }
    if (update
        case SmartCubeStateEvent() || SmartCubeMoveEvent(recovered: true)) {
      _isTimingReliable = false;
    }
    _startSolvingFromInspection(update.hostTimestamp);
    if (update is SmartCubeStateEvent) {
      _recordingBuilder.recordGap(
        RecordingGapReason.stateTransition,
        update.hostTimestamp,
      );
    }
    _recordSmartCubeUpdate(update);
    return _completeSmartCubeSolveIfSolved(update);
  }

  bool _handleSolvingUpdate(SmartCubeUpdate update, String previousFacelets) {
    if (update case SmartCubeMoveEvent(:final move)) {
      _currentMoves.add(move);
    }
    if (update case SmartCubeStateEvent(
      :final state,
    ) when state.facelets != previousFacelets) {
      _recordingBuilder.recordGap(
        RecordingGapReason.stateTransition,
        update.hostTimestamp,
      );
    }
    _recordSmartCubeUpdate(update);
    return _completeSmartCubeSolveIfSolved(update);
  }

  bool _handlePreparationUpdate(
    SmartCubeUpdate update,
    String previousFacelets,
  ) {
    final scrambleTarget = _scrambleTarget!;
    switch (update) {
      case SmartCubeMoveEvent(:final move):
        if (_phase == PracticePhase.scrambling) {
          _recordPreparationMove(move);
          if (_cubeState.facelets == scrambleTarget.facelets) {
            _beginPreInspectionDelay();
            return true;
          }
        } else if (_phase == PracticePhase.needsSolvedCube &&
            _cubeState.isSolved) {
          _preparationMoves.clear();
          _phase = PracticePhase.scrambling;
        }
      case SmartCubeStateEvent():
        if (_cubeState.facelets == scrambleTarget.facelets) {
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

  bool _completeSmartCubeSolveIfSolved(SmartCubeUpdate update) {
    if (!_cubeState.isSolved) return false;
    if (update
        case SmartCubeStateEvent() || SmartCubeMoveEvent(recovered: true)) {
      _isTimingReliable = false;
    }
    _completeSolve(
      inputSource: update is SmartCubeMoveEvent
          ? SolveInputSource.smartCube
          : SolveInputSource.smartCubeState,
      completedAtHostTimestamp: update.hostTimestamp,
    );
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
    if (!hasScramble ||
        _inputMode != PracticeInputMode.demo ||
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
    _completeSolve(
      inputSource: inputSource,
      completedAtHostTimestamp: _monotonicClock.now,
    );
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
      _cubeState = _scrambleTarget?.copy() ?? CubeState.solved();
      _phase = PracticePhase.manualReady;
    }
    notifyListeners();
  }

  void _completeSolve({
    required SolveInputSource inputSource,
    required Duration completedAtHostTimestamp,
  }) {
    if (_phase != PracticePhase.solving) return;
    if (completedAtHostTimestamp < _solveStartedAt!) {
      _isTimingReliable = false;
    }
    _clock.stopAt(completedAtHostTimestamp);
    _ticker?.cancel();
    _ticker = null;

    final createdAt = _now();
    final solve = SolveRecord(
      id: createdAt.microsecondsSinceEpoch.toString(),
      scramble: _scramble!.toString(),
      elapsed: _clock.elapsed,
      moveCount: _currentMoves.length,
      createdAt: createdAt,
      inputSource: inputSource,
      inspectionElapsed: _inspectionElapsed,
      startTrigger: _startTrigger,
      isTimingReliable: _isTimingReliable,
    );
    final recording = _recordingBuilder.finish();
    _history.add(solve, recording: recording);
    _pendingSolveReview = solve;
    _requestNextScramble(notify: false);
    notifyListeners();
  }

  void applyMove(
    CubeMove move, {
    bool fromSmartCube = false,
    Duration? hostTimestamp,
    int serial = 0,
    Duration? cubeTimestamp,
    bool recovered = false,
  }) {
    if (fromSmartCube) {
      if (!smartCubeWorkflowActive) return;
      _processSmartCubeUpdate(
        SmartCubeMoveEvent(
          move: move,
          serial: serial,
          receivedAt: _now(),
          recovered: recovered,
          hostTimestamp: hostTimestamp ?? _monotonicClock.now,
          cubeTimestamp: cubeTimestamp,
        ),
      );
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
      _startSolvingFromInspection(hostTimestamp ?? _monotonicClock.now);
    }
    _cubeState.apply(move);
    _currentMoves.add(move);
    if (_cubeState.isSolved) {
      _completeSolve(
        inputSource: SolveInputSource.manualMoves,
        completedAtHostTimestamp: hostTimestamp ?? _monotonicClock.now,
      );
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
    final startedAt = _monotonicClock.now;
    if (preInspectionDelay == Duration.zero) {
      _beginInspection(startedAt: startedAt);
      return;
    }
    _preInspectionDeadline = startedAt + preInspectionDelay;
    _phase = PracticePhase.inspectionDelay;
    _startTicker();
    notifyListeners();
  }

  void _beginInspection({Duration? startedAt}) {
    _currentMoves.clear();
    _clock.reset();
    _preInspectionDeadline = null;
    _inspectionStartedAt = startedAt ?? _monotonicClock.now;
    _inspectionDeadline = _inspectionStartedAt! + inspectionDuration;
    _inspectionElapsed = null;
    _startTrigger = null;
    _phase = PracticePhase.inspection;
    final now = _monotonicClock.now;
    if (now >= _inspectionDeadline!) {
      _startSolvingFromInspection(now);
      notifyListeners();
      return;
    }
    _startTicker();
    notifyListeners();
  }

  void _startSolvingFromInspection(Duration hostTimestamp) {
    if (_phase != PracticePhase.inspection) return;
    final startedAt = _inspectionStartedAt!;
    final deadline = _inspectionDeadline!;
    final solveStartedAt = hostTimestamp >= deadline ? deadline : hostTimestamp;
    if (hostTimestamp >= deadline) {
      _inspectionElapsed = inspectionDuration;
      _startTrigger = SolveStartTrigger.inspectionTimeout;
    } else {
      final inspectedFor = hostTimestamp - startedAt;
      _inspectionElapsed = inspectedFor.isNegative
          ? Duration.zero
          : inspectedFor;
      _startTrigger = SolveStartTrigger.firstMove;
    }
    _solveStartedAt = solveStartedAt;
    _clock.startAt(solveStartedAt);
    _phase = PracticePhase.solving;
    if (_attemptInputMode == PracticeInputMode.smartCube) {
      _recordingBuilder.start(solveStartedAt);
    }
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 31), (_) {
      if (_phase == PracticePhase.inspectionDelay) {
        final now = _monotonicClock.now;
        final deadline = _preInspectionDeadline!;
        if (now >= deadline) {
          _beginInspection(startedAt: deadline);
          return;
        }
      } else if (_phase == PracticePhase.inspection) {
        final now = _monotonicClock.now;
        final deadline = _inspectionDeadline!;
        if (now >= deadline) {
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

  void _requestNextScramble({bool notify = true}) {
    final request = ++_scrambleRequest;
    _scrambleTarget = null;
    _isPreparingScramble = true;
    _scramblePreparationError = null;
    _preparationMoves.clear();
    _currentMoves.clear();
    _clock.reset();
    _clearAttemptTiming();
    if (smartCubeWorkflowActive) {
      _phase = PracticePhase.awaitingCubeState;
    } else {
      _cubeState = CubeState.solved();
      _phase = PracticePhase.manualReady;
    }

    FutureOr<CubeScramble> result;
    try {
      result = _nextScramble();
    } catch (error) {
      _failScrambleRequest(request, error, notify: notify);
      return;
    }
    if (result is CubeScramble) {
      _completeScrambleRequest(request, result, notify: notify);
      return;
    }
    if (notify) notifyListeners();
    result.then(
      (scramble) => _completeScrambleRequest(request, scramble),
      onError: (Object error, StackTrace _) =>
          _failScrambleRequest(request, error),
    );
  }

  void _completeScrambleRequest(
    int request,
    CubeScramble scramble, {
    bool notify = true,
  }) {
    if (_disposed || request != _scrambleRequest) return;
    _scramble = scramble;
    _scrambleTarget = _stateForScramble(scramble);
    _isPreparingScramble = false;
    _scramblePreparationError = null;
    if (smartCubeWorkflowActive) {
      _phase = !_hasAuthoritativeCubeState
          ? PracticePhase.awaitingCubeState
          : _cubeState.isSolved
          ? PracticePhase.scrambling
          : PracticePhase.needsSolvedCube;
    } else {
      _cubeState = _scrambleTarget!.copy();
      _phase = PracticePhase.manualReady;
    }
    if (notify) notifyListeners();
  }

  void _failScrambleRequest(int request, Object error, {bool notify = true}) {
    if (_disposed || request != _scrambleRequest) return;
    _isPreparingScramble = false;
    _scramblePreparationError = error;
    if (notify) notifyListeners();
  }

  List<CubeMove> _buildScrambleGuidance() {
    final scramble = _scramble;
    if (scramble == null) return const [];
    final progress = _scrambleProgress;
    if (progress.isCorrection) {
      return [
        ..._buildScrambleRecoveryMoves(completedMoves: progress.completedMoves),
        ...scramble.moves.skip(progress.completedMoves),
      ];
    }
    return _reduceMoves([
      ..._preparationMoves.reversed.map((move) => move.inverse),
      ...scramble.moves,
    ]);
  }

  List<CubeMove> _buildScrambleRecoveryMoves({int? completedMoves}) {
    final scramble = _scramble;
    if (scramble == null) return const [];
    final completed = completedMoves ?? _scrambleProgress.completedMoves;
    return _reduceMoves([
      ..._preparationMoves.reversed.map((move) => move.inverse),
      ...scramble.moves.take(completed),
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

  void _recordSmartCubeUpdate(SmartCubeUpdate update) {
    switch (update) {
      case SmartCubeMoveEvent():
        _recordingBuilder.recordMove(update);
      case SmartCubeStateEvent():
        _recordingBuilder.recordState(update);
    }
  }

  static CubeState _stateForScramble(CubeScramble scramble) =>
      CubeState.solved()..applyAll(scramble.moves);

  void _clearAttemptTiming() {
    _recordingBuilder.discardAttempt();
    _preInspectionDeadline = null;
    _inspectionStartedAt = null;
    _inspectionDeadline = null;
    _inspectionElapsed = null;
    _startTrigger = null;
    _solveStartedAt = null;
    _isTimingReliable = true;
    _attemptInputMode = null;
  }

  void _cancelPreInspectionDelay() {
    _ticker?.cancel();
    _ticker = null;
    _preInspectionDeadline = null;
    _attemptInputMode = null;
    _recordingBuilder.discardAttempt();
  }

  void deleteSolve(String id) {
    _history.delete(id);
    if (_pendingSolveReview?.id == id) _pendingSolveReview = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _scrambleRequest++;
    _ticker?.cancel();
    _clockTicks.dispose();
    super.dispose();
  }
}
