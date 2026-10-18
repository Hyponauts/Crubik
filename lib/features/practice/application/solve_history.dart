import 'dart:async';
import 'dart:convert';

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
  Future<void> _persistenceQueue = Future.value();
  final List<({int sequence, Future<void> Function() operation})>
  _pendingWrites = [];
  Future<List<SolveRecord>>? _initializationFuture;
  final Set<String> _deletedDuringInitialization = {};
  int _lastWriteSequence = 0;
  bool _initializing = false;
  bool _mutatedDuringInitialization = false;
  Object? _persistenceError;

  List<SolveRecord> get records => List.unmodifiable(_records);
  bool get hasRecords => _records.isNotEmpty;
  Object? get persistenceError => _persistenceError;

  Duration? get bestTime {
    final times = _records
        .where((solve) => solve.isTimingReliable)
        .map((solve) => solve.elapsed);
    if (times.isEmpty) return null;
    return times.reduce((a, b) => a <= b ? a : b);
  }

  Duration? get sessionAverage {
    final timedSolves = _records
        .where((solve) => solve.isTimingReliable)
        .toList();
    if (timedSolves.isEmpty) return null;
    final milliseconds = timedSolves.fold<int>(
      0,
      (sum, solve) => sum + solve.elapsed.inMilliseconds,
    );
    return Duration(milliseconds: milliseconds ~/ timedSolves.length);
  }

  Duration? get averageOfFive {
    if (_records.length < 5) return null;
    final lastFive = _records.take(5).toList();
    if (lastFive.any((solve) => !solve.isTimingReliable)) return null;
    lastFive.sort((a, b) => a.elapsed.compareTo(b.elapsed));
    final middleThree = lastFive.sublist(1, 4);
    final milliseconds = middleThree.fold<int>(
      0,
      (sum, solve) => sum + solve.elapsed.inMilliseconds,
    );
    return Duration(milliseconds: milliseconds ~/ 3);
  }

  Future<String> exportJson() async {
    final output = StringBuffer();
    await writeExportJson(output);
    return output.toString();
  }

  /// Exports the history visible at this call, including initial persisted data.
  ///
  /// Earlier writes finish before recordings are read; later mutations wait
  /// outside this export even while initialization or persistence is pending.
  Future<void> writeExportJson(StringSink output) {
    final recordsAtRequest = List<SolveRecord>.of(_records);
    final deletedAtRequest = Set<String>.of(_deletedDuringInitialization);
    final needsPersistedHistory =
        _initializationFuture == null || _initializing;
    final exportedAt = _now().toUtc().toIso8601String();
    final writeSequence = _lastWriteSequence;
    final initialization = _loadInitialHistory();

    return _serialize(() async {
      final persisted = await initialization;
      final records = needsPersistedHistory
          ? _mergeRecords(recordsAtRequest, persisted, deletedAtRequest)
          : recordsAtRequest;
      await _persistPending(writeSequence);
      if (_persistenceError case final error?) throw error;

      output
        ..writeln('{')
        ..writeln('  "format": "crubik-solve-history",')
        ..writeln('  "version": 3,')
        ..writeln('  "exported_at": ${jsonEncode(exportedAt)},')
        ..writeln('  "solves": [');
      for (var index = 0; index < records.length; index++) {
        final solve = records[index];
        final recording = await _repository.loadRecording(solve.id);
        _writeIndentedJson(output, {
          ...solve.toJson(),
          if (recording != null) 'recording': recording.toJson(),
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
        );
        _records
          ..clear()
          ..addAll(merged);
      } else {
        _records
          ..clear()
          ..addAll(persisted);
      }
      return persisted;
    } finally {
      _initializing = false;
      _mutatedDuringInitialization = false;
      _deletedDuringInitialization.clear();
    }
  }

  void add(SolveRecord solve, {SolveRecording? recording}) {
    if (_initializing || _initializationFuture == null) {
      _mutatedDuringInitialization = true;
      _deletedDuringInitialization.remove(solve.id);
    }
    _records.insert(0, solve);
    _schedulePersistence(() => _repository.add(solve, recording: recording));
  }

  void delete(String id) {
    if (_initializing || _initializationFuture == null) {
      _mutatedDuringInitialization = true;
      _deletedDuringInitialization.add(id);
    }
    _records.removeWhere((solve) => solve.id == id);
    _schedulePersistence(() => _repository.delete(id));
  }

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

List<SolveRecord> _mergeRecords(
  List<SolveRecord> local,
  List<SolveRecord> persisted,
  Set<String> deletedIds,
) {
  final localIds = local.map((solve) => solve.id).toSet();
  return [
    ...local,
    ...persisted.where(
      (solve) => !localIds.contains(solve.id) && !deletedIds.contains(solve.id),
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
