import 'dart:async';
import 'dart:collection';

import '../domain/cube_model.dart';

abstract interface class ScrambleCacheStore {
  Future<List<CubeScramble>> load();

  Future<void> save(List<CubeScramble> scrambles);
}

final class ScrambleCache {
  ScrambleCache({
    required Future<CubeScramble> Function() generate,
    required ScrambleCacheStore store,
    int targetSize = 15,
  }) : this._(generate, store, targetSize);

  ScrambleCache._(this._generate, this._store, this.targetSize)
    : assert(targetSize > 0);

  final Future<CubeScramble> Function() _generate;
  final ScrambleCacheStore _store;
  final int targetSize;
  final Queue<CubeScramble> _items = Queue();

  Future<void> _operations = Future.value();
  Future<void> _writes = Future.value();
  Future<void>? _initialization;
  Future<void>? _refill;
  bool _disposed = false;

  Future<CubeScramble> take() async {
    await _initialize();
    if (_disposed) throw StateError('The scramble cache has been disposed.');

    final CubeScramble scramble;
    if (_items.isNotEmpty) {
      scramble = _items.removeFirst();
    } else {
      scramble = await _exclusive(() async {
        if (_disposed) {
          throw StateError('The scramble cache has been disposed.');
        }
        return _items.isEmpty ? await _generate() : _items.removeFirst();
      });
    }

    unawaited(_saveBestEffort());
    unawaited(refill());
    return scramble;
  }

  Future<void> refill() {
    if (_disposed) return Future.value();
    final running = _refill;
    if (running != null) return running;

    final future = _refillBestEffort();
    _refill = future;
    return future;
  }

  Future<void> _refillBestEffort() async {
    try {
      await _initialize();
      while (!_disposed) {
        final added = await _exclusive(() async {
          if (_disposed || _items.length >= targetSize) return false;
          final scramble = await _generate();
          if (_disposed) return false;
          _items.add(scramble);
          return true;
        });
        if (!added) break;
        await _saveBestEffort();
      }
    } catch (_) {
      // A cached item is an optimization. Empty-cache generation in take()
      // still reports failures to the caller.
    } finally {
      _refill = null;
    }
  }

  Future<void> _initialize() => _initialization ??= () async {
    try {
      _items.addAll((await _store.load()).take(targetSize));
    } catch (_) {
      // Corrupt or unavailable cache storage must not block a fresh scramble.
    }
  }();

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<void> _saveBestEffort() async {
    final snapshot = List<CubeScramble>.unmodifiable(_items);
    _writes = _writes.then((_) async {
      try {
        await _store.save(snapshot);
      } catch (_) {
        // The pool remains usable in memory when persistence is unavailable.
      }
    });
    await _writes;
  }

  Future<void> flush() async {
    await _initialize();
    await _refill;
    await _operations;
    await _saveBestEffort();
  }

  void dispose() {
    _disposed = true;
  }
}
