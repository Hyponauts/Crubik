import 'dart:async';
import 'dart:convert';

import '../domain/solve_analysis.dart';
import '../domain/solve_average.dart';
import '../domain/solve_record.dart';
import '../domain/solve_recording.dart';

/// Owns solve-history storage, statistics, and portable export.
///
/// Keeping persistence out of [PracticeController] lets that controller focus
/// on the live practice state machine. Writes are serialized so local history
/// remains authoritative even when solves are completed in quick succession.
final class SolveHistory {
  SolveHistory({
    required SolveHistoryRepository repository,
    required DateTime Function() now,
  }) : this._(repository, now);

  SolveHistory._(this._repository, this._now);

  final SolveHistoryRepository _repository;
  final DateTime Function() _now;
  final List<SolveRecord> _records = [];
  final List<SolveAverageRecord> _averages = [];
  Future<void> _persistenceQueue = Future.value();
  final List<({int sequence, Future<void> Function() operation})>
  _pendingWrites = [];
  Future<List<SolveRecord>>? _initializationFuture;
  final Set<String> _deletedDuringInitialization = {};
  final Set<String> _deletedSessionsDuringInitialization = {};
  int _lastWriteSequence = 0;
  bool _initializing = false;
  bool _mutatedDuringInitialization = false;
  Object? _persistenceError;

  List<SolveRecord> get records => List.unmodifiable(_records);
  List<SolveAverageRecord> get averages => List.unmodifiable(_averages);

  List<SolveAverageRecord> averagesFor(
    String sessionId,
    SolveAverageKind kind,
  ) => List.unmodifiable(
    _averages.where(
      (average) => average.sessionId == sessionId && average.kind == kind,
    ),
  );

  SolveAverageWindow? windowFor(SolveAverageRecord average) {
    final sessionSolves = _records
        .where((solve) => solve.sessionId == average.sessionId)
        .toList();
    final anchorIndex = sessionSolves.indexWhere(
      (solve) => solve.id == average.endSolveId,
    );
    if (anchorIndex < 0) return null;
    return SolveAverageWindow.calculate(
      average.kind,
      sessionSolves.sublist(
        anchorIndex,
        (anchorIndex + average.kind.windowSize).clamp(0, sessionSolves.length),
      ),
    );
  }

  bool get hasRecords => _records.isNotEmpty;
  Object? get persistenceError => _persistenceError;

  Duration? get bestTime {
    final times = _records
        .where(
          (solve) =>
              solve.outcome == SolveOutcome.completed && solve.isTimingReliable,
        )
        .map((solve) => solve.elapsed);
    if (times.isEmpty) return null;
    return times.reduce((a, b) => a <= b ? a : b);
  }

  Duration? get sessionAverage {
    final timedSolves = _records
        .where(
          (solve) =>
              solve.outcome == SolveOutcome.completed && solve.isTimingReliable,
        )
        .toList();
    if (timedSolves.isEmpty) return null;
    final milliseconds = timedSolves.fold<int>(
      0,
      (sum, solve) => sum + solve.elapsed.inMilliseconds,
    );
    return Duration(milliseconds: milliseconds ~/ timedSolves.length);
  }

  Future<String> exportJson({String? sessionId}) async {
    final output = StringBuffer();
    await writeExportJson(output, sessionId: sessionId);
    return output.toString();
  }

  /// Exports the history visible at this call, including initial persisted data.
  ///
  /// Earlier writes finish before recordings are read; later mutations wait
  /// outside this export even while initialization or persistence is pending.
  Future<void> writeExportJson(StringSink output, {String? sessionId}) {
    final recordsAtRequest = [
      for (final solve in _records)
        if (sessionId == null || solve.sessionId == sessionId) solve,
    ];
    final averagesAtRequest = [
      for (final average in _averages)
        if (sessionId == null || average.sessionId == sessionId) average,
    ];
    final deletedAtRequest = Set<String>.of(_deletedDuringInitialization);
    final deletedSessionsAtRequest = Set<String>.of(
      _deletedSessionsDuringInitialization,
    );
    final needsPersistedHistory =
        _initializationFuture == null || _initializing;
    final exportedAt = _now().toUtc().toIso8601String();
    final writeSequence = _lastWriteSequence;
    final initialization = _loadInitialHistory();

    return _serialize(() async {
      final persisted = await initialization;
      final records = needsPersistedHistory
          ? _mergeRecords(
              recordsAtRequest,
              sessionId == null
                  ? persisted
                  : persisted
                        .where((solve) => solve.sessionId == sessionId)
                        .toList(),
              deletedAtRequest,
              deletedSessionsAtRequest,
            )
          : recordsAtRequest;
      final averages = needsPersistedHistory
          ? _calculateAllAverages(records)
          : averagesAtRequest;
      await _persistPending(writeSequence);
      if (_persistenceError case final error?) throw error;

      output
        ..writeln('{')
        ..writeln('  "format": "crubik-solve-history",')
        ..writeln('  "version": 5,')
        ..writeln('  "exported_at": ${jsonEncode(exportedAt)},')
        ..writeln(
          '  "averages": ${jsonEncode([
            for (final average in averages) {'kind': average.kind.name, 'end_solve_id': average.endSolveId, 'session_id': average.sessionId, 'created_at': average.createdAt.toUtc().toIso8601String(), 'status': average.status.name, 'elapsed_ms': average.elapsed?.inMilliseconds},
          ])},',
        )
        ..writeln('  "solves": [');
      for (var index = 0; index < records.length; index++) {
        final solve = records[index];
        final recording = await _repository.loadRecording(solve.id);
        final analysisRepository = _repository is SolveAnalysisRepository
            ? _repository as SolveAnalysisRepository
            : null;
        final analysis = await analysisRepository?.loadAnalysis(solve.id);
        _writeIndentedJson(output, {
          ...solve.toJson(),
          if (recording != null) 'recording': recording.toJson(),
          if (analysis != null) 'analysis': analysis.toJson(),
        }, trailingComma: index != records.length - 1);
      }
      output
        ..writeln('  ]')
        ..write('}');
    });
  }

  Future<void> initialize() => _loadInitialHistory();

  Future<List<SolveRecord>> _loadInitialHistory() =>
      _initializationFuture ??= _initialize(_persistenceQueue);

  Future<List<SolveRecord>> _initialize(Future<void> pendingPersistence) async {
    _initializing = true;
    try {
      await pendingPersistence;
      final persisted = [...await _repository.load()]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (_mutatedDuringInitialization) {
        final merged = _mergeRecords(
          _records,
          persisted,
          _deletedDuringInitialization,
          _deletedSessionsDuringInitialization,
        );
        _records
          ..clear()
          ..addAll(merged);
      } else {
        _records
          ..clear()
          ..addAll(persisted);
      }
      if (_repository case final SolveAverageRepository averageRepository) {
        final persistedAverages = await averageRepository.loadAverages();
        final expectedCount = _expectedAverageCount(_records);
        final expectedAnchors = _expectedAverageAnchors(_records);
        if (persistedAverages.length == expectedCount &&
            persistedAverages.every(
              (average) => expectedAnchors.contains(average.id),
            )) {
          _averages
            ..clear()
            ..addAll(persistedAverages);
        } else {
          _averages
            ..clear()
            ..addAll(_calculateAllAverages(_records));
          final rebuilt = List<SolveAverageRecord>.of(_averages);
          if (_mutatedDuringInitialization) {
            _schedulePersistence(
              () => averageRepository.replaceAllAverages(rebuilt),
            );
          } else {
            await averageRepository.replaceAllAverages(rebuilt);
          }
        }
      } else {
        _averages
          ..clear()
          ..addAll(_calculateAllAverages(_records));
      }
      _sortAverages();
      return persisted;
    } finally {
      _initializing = false;
      _mutatedDuringInitialization = false;
      _deletedDuringInitialization.clear();
      _deletedSessionsDuringInitialization.clear();
    }
  }

  void add(
    SolveRecord solve, {
    SolveRecording? recording,
    SolveAnalysis? analysis,
  }) {
    if (_initializing || _initializationFuture == null) {
      _mutatedDuringInitialization = true;
      _deletedDuringInitialization.remove(solve.id);
    }
    _records.insert(0, solve);
    final sessionSolves = _records
        .where((record) => record.sessionId == solve.sessionId)
        .toList();
    final newAverages = [
      for (final kind in SolveAverageKind.values)
        if (SolveAverageWindow.calculate(kind, sessionSolves)?.record
            case final average?)
          average,
    ];
    _averages.addAll(newAverages);
    _sortAverages();
    _schedulePersistence(() async {
      if (_repository case final SolveAverageRepository averageRepository) {
        await averageRepository.addWithAverages(
          solve,
          recording: recording,
          averages: newAverages,
        );
      } else {
        await _repository.add(solve, recording: recording);
      }
      if (analysis != null && _repository is SolveAnalysisRepository) {
        await (_repository as SolveAnalysisRepository).saveAnalysis(
          solve.id,
          analysis,
        );
      }
    });
  }

  Future<SolveRecording?> loadRecording(String solveId) =>
      _repository.loadRecording(solveId);

  Future<SolveAnalysis?> loadAnalysis(String solveId) =>
      _repository is SolveAnalysisRepository
      ? (_repository as SolveAnalysisRepository).loadAnalysis(solveId)
      : Future.value();

  Future<void> saveAnalysis(String solveId, SolveAnalysis analysis) =>
      _repository is SolveAnalysisRepository
      ? (_repository as SolveAnalysisRepository).saveAnalysis(solveId, analysis)
      : Future.value();

  void delete(String id) {
    final solve = _records.where((record) => record.id == id).firstOrNull;
    if (solve == null) {
      if (_initializing || _initializationFuture == null) {
        _mutatedDuringInitialization = true;
        _deletedDuringInitialization.add(id);
        _schedulePersistence(() => _repository.delete(id));
      }
      return;
    }
    final oldSessionSolves = _records
        .where((record) => record.sessionId == solve.sessionId)
        .toList();
    final deletedIndex = oldSessionSolves.indexWhere(
      (record) => record.id == id,
    );
    final affectedEndSolveIds = <String>{id};
    for (final kind in SolveAverageKind.values) {
      final firstAffected = deletedIndex - kind.windowSize + 1;
      for (
        var index = firstAffected < 0 ? 0 : firstAffected;
        index < deletedIndex;
        index++
      ) {
        affectedEndSolveIds.add(oldSessionSolves[index].id);
      }
    }
    if (_initializing || _initializationFuture == null) {
      _mutatedDuringInitialization = true;
      _deletedDuringInitialization.add(id);
    }
    _records.removeWhere((solve) => solve.id == id);
    _averages.removeWhere(
      (average) => affectedEndSolveIds.contains(average.endSolveId),
    );
    final sessionSolves = _records
        .where((record) => record.sessionId == solve.sessionId)
        .toList();
    final replacements = <SolveAverageRecord>[];
    for (final kind in SolveAverageKind.values) {
      for (var index = 0; index < sessionSolves.length; index++) {
        if (!affectedEndSolveIds.contains(sessionSolves[index].id)) continue;
        final window = SolveAverageWindow.calculate(
          kind,
          sessionSolves.sublist(
            index,
            (index + kind.windowSize).clamp(0, sessionSolves.length),
          ),
        );
        if (window != null) replacements.add(window.record);
      }
    }
    _averages.addAll(replacements);
    _sortAverages();
    _schedulePersistence(() async {
      if (_repository case final SolveAverageRepository averageRepository) {
        await averageRepository.deleteWithAverages(
          id,
          affectedEndSolveIds: affectedEndSolveIds,
          replacements: replacements,
        );
      } else {
        await _repository.delete(id);
      }
    });
  }

  /// Removes a whole session without recalculating averages for other sessions.
  void deleteSession(
    String sessionId, {
    Future<void> Function()? saveSessionSettings,
  }) {
    if (_initializing || _initializationFuture == null) {
      _mutatedDuringInitialization = true;
      _deletedSessionsDuringInitialization.add(sessionId);
    }
    _records.removeWhere((solve) => solve.sessionId == sessionId);
    _averages.removeWhere((average) => average.sessionId == sessionId);
    _schedulePersistence(
      () => _repository.deleteSession(
        sessionId,
        saveSessionSettings: saveSessionSettings,
      ),
    );
  }

  /// Keeps settings writes ordered with session deletion and its retries.
  void saveSessionSettings(Future<void> Function() save) =>
      _schedulePersistence(save);

  void _sortAverages() => _averages.sort((first, second) {
    final timeOrder = second.createdAt.compareTo(first.createdAt);
    return timeOrder != 0
        ? timeOrder
        : first.kind.index.compareTo(second.kind.index);
  });

  /// Attempts writes queued before this call; failures stay in [persistenceError].
  Future<void> flush() {
    final writeSequence = _lastWriteSequence;
    final initialization = _initializationFuture;

    return _serialize(() async {
      if (initialization != null) await initialization;
      await _persistPending(writeSequence);
    });
  }

  void _schedulePersistence(Future<void> Function() operation) {
    final sequence = ++_lastWriteSequence;
    _pendingWrites.add((sequence: sequence, operation: operation));
    final initialization = _initializationFuture;
    unawaited(
      _serialize<void>(() async {
        if (initialization != null) await initialization;
        await _persistPending(sequence);
      }).onError((error, _) {
        _persistenceError = error;
      }),
    );
  }

  Future<void> _persistPending(int throughSequence) async {
    // Retries keep their original boundary so later writes cannot pass an export.
    try {
      while (_pendingWrites.isNotEmpty &&
          _pendingWrites.first.sequence <= throughSequence) {
        await _pendingWrites.first.operation();
        _pendingWrites.removeAt(0);
      }
      _persistenceError = null;
    } catch (error) {
      _persistenceError = error;
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final scheduled = _persistenceQueue.then((_) => operation());
    _persistenceQueue = scheduled.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return scheduled;
  }
}

int _expectedAverageCount(List<SolveRecord> records) {
  final counts = <String, int>{};
  for (final solve in records) {
    counts.update(solve.sessionId, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts.values.fold<int>(
    0,
    (sum, count) =>
        sum +
        SolveAverageKind.values.fold<int>(
          0,
          (kindSum, kind) =>
              kindSum +
              (count >= kind.windowSize ? count - kind.windowSize + 1 : 0),
        ),
  );
}

Set<String> _expectedAverageAnchors(List<SolveRecord> records) {
  final bySession = <String, List<SolveRecord>>{};
  for (final solve in records) {
    bySession.putIfAbsent(solve.sessionId, () => []).add(solve);
  }
  return {
    for (final solves in bySession.values)
      for (final kind in SolveAverageKind.values)
        for (var index = 0; index <= solves.length - kind.windowSize; index++)
          '${kind.name}:${solves[index].id}',
  };
}

List<SolveAverageRecord> _calculateAllAverages(List<SolveRecord> records) {
  final bySession = <String, List<SolveRecord>>{};
  for (final solve in records) {
    bySession.putIfAbsent(solve.sessionId, () => []).add(solve);
  }
  return [
    for (final solves in bySession.values)
      for (final kind in SolveAverageKind.values)
        for (var index = 0; index <= solves.length - kind.windowSize; index++)
          SolveAverageWindow.calculate(
            kind,
            solves.sublist(index, index + kind.windowSize),
          )!.record,
  ];
}

List<SolveRecord> _mergeRecords(
  List<SolveRecord> local,
  List<SolveRecord> persisted,
  Set<String> deletedIds,
  Set<String> deletedSessionIds,
) {
  final localIds = local.map((solve) => solve.id).toSet();
  return [
    ...local.where((solve) => !deletedSessionIds.contains(solve.sessionId)),
    ...persisted.where(
      (solve) =>
          !localIds.contains(solve.id) &&
          !deletedIds.contains(solve.id) &&
          !deletedSessionIds.contains(solve.sessionId),
    ),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

void _writeIndentedJson(
  StringSink output,
  Object? value, {
  required bool trailingComma,
}) {
  final lines = const JsonEncoder.withIndent('  ').convert(value).split('\n');
  for (var index = 0; index < lines.length; index++) {
    output
      ..write('    ')
      ..write(lines[index]);
    if (index == lines.length - 1 && trailingComma) output.write(',');
    output.writeln();
  }
}
