import 'dart:async';

import 'package:crubik/features/cube/application/scramble_cache.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps fifteen ready scrambles by default', () {
    final cache = ScrambleCache(
      store: _FakeStore([]),
      generate: () async => CubeScramble.parse('R'),
    );
    addTearDown(cache.dispose);

    expect(cache.targetSize, 15);
  });

  test(
    'takes persisted scrambles in FIFO order and refills the pool',
    () async {
      final store = _FakeStore([
        CubeScramble.parse('R'),
        CubeScramble.parse('U'),
      ]);
      var generated = 0;
      final cache = ScrambleCache(
        targetSize: 2,
        store: store,
        generate: () async =>
            [CubeScramble.parse('F'), CubeScramble.parse('B')][generated++],
      );
      addTearDown(cache.dispose);

      expect((await cache.take()).toString(), 'R');
      await cache.refill();
      expect(store.items.map((item) => item.toString()), ['U', 'F']);

      final restored = ScrambleCache(
        targetSize: 2,
        store: store,
        generate: () async => CubeScramble.parse('L'),
      );
      addTearDown(restored.dispose);
      expect((await restored.take()).toString(), 'U');
    },
  );

  test(
    'reports empty-cache generation failure and supports another take',
    () async {
      var calls = 0;
      final cache = ScrambleCache(
        targetSize: 1,
        store: _FakeStore([]),
        generate: () async {
          if (calls++ == 0) throw StateError('solver failed');
          return CubeScramble.parse('R U');
        },
      );
      addTearDown(cache.dispose);

      await expectLater(cache.take(), throwsStateError);
      expect((await cache.take()).toString(), 'R U');
    },
  );

  test(
    'takes a ready scramble while background refill is generating',
    () async {
      final generationStarted = Completer<void>();
      final finishGeneration = Completer<void>();
      final cache = ScrambleCache(
        targetSize: 2,
        store: _FakeStore([CubeScramble.parse('R'), CubeScramble.parse('U')]),
        generate: () async {
          if (!generationStarted.isCompleted) generationStarted.complete();
          await finishGeneration.future;
          return CubeScramble.parse('F');
        },
      );
      addTearDown(() async {
        cache.dispose();
        if (!finishGeneration.isCompleted) finishGeneration.complete();
        await cache.flush();
      });

      expect((await cache.take()).toString(), 'R');
      await generationStarted.future;

      final next = Completer<CubeScramble>();
      cache.take().then(next.complete, onError: next.completeError);
      await Future<void>.delayed(Duration.zero);
      final completedBeforeGeneration = next.isCompleted;

      finishGeneration.complete();
      expect((await next.future).toString(), 'U');
      expect(completedBeforeGeneration, isTrue);
    },
  );

  test('returns a ready scramble before persistence completes', () async {
    final store = _BlockingFirstSaveStore([CubeScramble.parse('R')]);
    final generated = Completer<CubeScramble>();
    final cache = ScrambleCache(
      targetSize: 1,
      store: store,
      generate: () => generated.future,
    );
    addTearDown(() async {
      if (!store.releaseSave.isCompleted) store.releaseSave.complete();
      if (!generated.isCompleted) generated.complete(CubeScramble.parse('U'));
      cache.dispose();
      await cache.flush();
    });

    final taken = Completer<CubeScramble>();
    cache.take().then(taken.complete, onError: taken.completeError);
    await store.saveStarted.future;
    await Future<void>.delayed(Duration.zero);

    expect(taken.isCompleted, isTrue);
    expect((await taken.future).toString(), 'R');

    store.releaseSave.complete();
    generated.complete(CubeScramble.parse('U'));
    await cache.flush();
  });

  test('never runs two generators concurrently', () async {
    var active = 0;
    var maximumActive = 0;
    final cache = ScrambleCache(
      targetSize: 1,
      store: _FakeStore([]),
      generate: () async {
        active++;
        maximumActive = active > maximumActive ? active : maximumActive;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return CubeScramble.parse('R U');
      },
    );
    addTearDown(cache.dispose);

    await Future.wait([cache.take(), cache.take()]);
    await cache.refill();

    expect(maximumActive, 1);
  });
}

final class _FakeStore implements ScrambleCacheStore {
  _FakeStore(List<CubeScramble> items) : items = List.of(items);

  List<CubeScramble> items;

  @override
  Future<List<CubeScramble>> load() async => List.of(items);

  @override
  Future<void> save(List<CubeScramble> scrambles) async {
    items = List.of(scrambles);
  }
}

final class _BlockingFirstSaveStore implements ScrambleCacheStore {
  _BlockingFirstSaveStore(List<CubeScramble> items) : items = List.of(items);

  List<CubeScramble> items;
  final saveStarted = Completer<void>();
  final releaseSave = Completer<void>();

  @override
  Future<List<CubeScramble>> load() async => List.of(items);

  @override
  Future<void> save(List<CubeScramble> scrambles) async {
    if (!saveStarted.isCompleted) {
      saveStarted.complete();
      await releaseSave.future;
    }
    items = List.of(scrambles);
  }
}
