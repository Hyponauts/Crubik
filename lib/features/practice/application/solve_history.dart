import 'dart:convert';

import '../domain/solve_record.dart';

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
  Future<void>? _initializationFuture;
  final Set<String> _deletedDuringInitialization = {};
  bool _initializing = false;
  bool _mutatedDuringInitialization = false;
  Object? _persistenceError;

  List<SolveRecord> get records => List.unmodifiable(_records);
  bool get hasRecords => _records.isNotEmpty;
  Object? get persistenceError => _persistenceError;

  Duration? get bestTime {
    if (_records.isEmpty) return null;
    return _records
        .map((solve) => solve.elapsed)
        .reduce((a, b) => a <= b ? a : b);
  }

  Duration? get sessionAverage {
    if (_records.isEmpty) return null;
    final milliseconds = _records.fold<int>(
      0,
      (sum, solve) => sum + solve.elapsed.inMilliseconds,
    );
    return Duration(milliseconds: milliseconds ~/ _records.length);
  }

  Duration? get averageOfFive {
    if (_records.length < 5) return null;
    final lastFive = _records.take(5).toList()
      ..sort((a, b) => a.elapsed.compareTo(b.elapsed));
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
      'solves': _records.map((solve) => solve.toJson()).toList(growable: false),
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

  void add(SolveRecord solve) {
    if (_initializing) {
      _mutatedDuringInitialization = true;
      _deletedDuringInitialization.remove(solve.id);
    }
    _records.insert(0, solve);
    _schedulePersistence();
  }

  void delete(String id) {
    if (_initializing) {
      _mutatedDuringInitialization = true;
      _deletedDuringInitialization.add(id);
    }
    _records.removeWhere((solve) => solve.id == id);
    _schedulePersistence();
  }

  Future<void> flush() async {
    final initialization = _initializationFuture;
    if (initialization != null) await initialization;
    await _persistenceQueue;
  }

  void _schedulePersistence() {
    final initialization = _initializationFuture;
    _persistenceQueue = _persistenceQueue
        .then((_) async {
          if (initialization != null) await initialization;
          await _repository.replaceAll(List<SolveRecord>.of(_records));
          _persistenceError = null;
        })
        .onError((error, _) {
          _persistenceError = error;
        });
  }
}
