import 'dart:async';

import '../../application/cube_connection_gateway.dart';
import '../../domain/cube_connection_diagnostics.dart';

/// Tracks the observable evidence for a session's initial-state handshake.
final class InitialStateHandshake {
  InitialStateHandshake({
    required this.timeout,
    required this.failureMessage,
    this.onDiagnostic,
  });

  final Duration timeout;
  final String failureMessage;
  final CubeDiagnosticSink? onDiagnostic;

  final Completer<void> _completion = Completer<void>();
  var _notifications = 0;
  var _recognizedPackets = 0;
  var _rejectedPackets = 0;
  var _states = 0;
  var _waiting = false;
  Object? _pendingError;
  StackTrace? _pendingStackTrace;

  void recordNotification() => _notifications++;

  void recordRecognizedPacket() => _recognizedPackets++;

  void recordRejectedPacket() => _rejectedPackets++;

  void completeState() {
    _states++;
    if (!_completion.isCompleted) _completion.complete();
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (_completion.isCompleted || _pendingError != null) return;
    if (_waiting) {
      _completion.completeError(error, stackTrace);
    } else {
      _pendingError = error;
      _pendingStackTrace = stackTrace;
    }
  }

  Future<void> wait() async {
    _waiting = true;
    final pendingError = _pendingError;
    if (pendingError != null && !_completion.isCompleted) {
      _completion.completeError(pendingError, _pendingStackTrace);
    }
    try {
      await _completion.future.timeout(
        timeout,
        onTimeout: () => throw const _InitialStateHandshakeTimeout(),
      );
      onDiagnostic?.call('handshake.succeeded', _summary);
    } on _InitialStateHandshakeTimeout {
      onDiagnostic?.call('handshake.timed_out', _summary);
      throw CubeConnectionFailure(
        CubeConnectionFailureCode.handshakeFailed,
        failureMessage,
      );
    }
  }

  String get _summary =>
      'notifications=$_notifications recognized=$_recognizedPackets '
      'rejected=$_rejectedPackets states=$_states';
}

final class _InitialStateHandshakeTimeout implements Exception {
  const _InitialStateHandshakeTimeout();
}
