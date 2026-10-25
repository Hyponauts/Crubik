import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'cuber_solver_backend_contract.dart';

CuberSolverBackend createCuberSolverBackend() => _WebCuberSolverBackend();

final class _WebCuberSolverBackend implements CuberSolverBackend {
  _WebCuberSolverBackend() {
    _startWorker();
  }

  static const _workerUrl = 'cube_solver_worker.dart.js';

  late Worker _worker;
  Completer<List<String>>? _pending;
  Timer? _timeoutTimer;
  bool _disposed = false;

  @override
  Future<List<String>> solve(
    String facelets, {
    required int maxDepth,
    required Duration timeout,
  }) {
    if (_disposed) {
      return Future.error(StateError('The cube solver has been disposed.'));
    }
    if (_pending != null) {
      return Future.error(StateError('The cube solver is already running.'));
    }

    final completer = Completer<List<String>>();
    _pending = completer;
    _timeoutTimer = Timer(timeout + const Duration(seconds: 1), () {
      _completeError(TimeoutException('Cube solver timed out.', timeout));
    });
    _worker.postMessage(
      <String, Object>{
        'facelets': facelets,
        'maxDepth': maxDepth,
        'timeoutMs': timeout.inMilliseconds,
      }.jsify(),
    );
    return completer.future;
  }

  void _startWorker() {
    _worker = Worker(_workerUrl.toJS)
      ..onmessage = _handleMessage.toJS
      ..onerror = _handleError.toJS;
  }

  void _handleMessage(Event event) {
    final data = (event as MessageEvent).data.dartify();
    if (data is! Map) {
      _completeError(const FormatException('Invalid cube solver response.'));
      return;
    }
    final error = data['error'];
    if (error != null) {
      _completeError(StateError(error.toString()));
      return;
    }
    final moves = data['moves'];
    if (moves is! List) {
      _completeError(const FormatException('Invalid cube solver response.'));
      return;
    }
    _complete(moves.map((move) => move.toString()).toList(growable: false));
  }

  void _handleError(Event event) {
    _completeError(StateError('The cube solver worker failed.'));
  }

  void _complete(List<String> moves) {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    pending.complete(moves);
  }

  void _completeError(Object error) {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    pending.completeError(error);
  }

  @override
  void restart() {
    _worker.terminate();
    if (!_disposed) _startWorker();
  }

  @override
  void dispose() {
    _disposed = true;
    _worker.terminate();
    _completeError(StateError('The cube solver has been disposed.'));
  }
}
