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
  final List<Future<void> Function()> _pendingWrites = [];
  Future<void>? _initializationFuture;
  final Set<String> _deletedDuringInitialization = {};
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

  Future<void> writeExportJson(StringSink output) async {
    await initialize();
    await _serialize(() async {
      final records = List<SolveRecord>.of(_records);
      final exportedAt = _now().toUtc().toIso8601String();
      await _persistPending();
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

  Future<void> initialize() =>
      _initializationFuture ??= _initialize(_persistenceQueue);

  Future<void> _initialize(Future<void> pendingPersistence) async {
    _initializing = true;
    try {
      await pendingPersistence;
      final persisted = [...await _repository.load()]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (_mutatedDuringInitialization) {
        final localIds = _records.map((solve) => solve.id).toSet();
        _records.addAll(
          persisted.where(
            (solve) =>
                !localIds.contains(solve.id) &&
                !_deletedDuringInitialization.contains(solve.id),
          ),
        );
        _records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      } else {
        _records
          ..clear()
          ..addAll(persisted);
      }
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

  /// Attempts pending writes again; failures remain available in [persistenceError].
  Future<void> flush() async {
    final initialization = _initializationFuture;
    if (initialization != null) await initialization;
    await _serialize(_persistPending);
  }

  void _schedulePersistence(Future<void> Function() operation) {
    _pendingWrites.add(operation);
    final initialization = _initializationFuture;
    unawaited(
      _serialize<void>(() async {
        if (initialization != null) await initialization;
        await _persistPending();
      }).onError((error, _) {
        _persistenceError = error;
      }),
    );
  }

  Future<void> _persistPending() async {
    // Bound the batch so mutations made during export wait for its snapshot.
    final writeCount = _pendingWrites.length;
    try {
      for (var index = 0; index < writeCount; index++) {
        await _pendingWrites.first();
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
