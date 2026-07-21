import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/cube_connection_gateway.dart';
import '../../domain/cube_connection_diagnostics.dart';
import '../../domain/smart_cube_event.dart';
import '../ble/ble_central.dart';
import 'initial_state_handshake.dart';

abstract base class BleSmartCubeSession implements SmartCubeSession {
  BleSmartCubeSession(
    this.central, {
    required this.deviceId,
    required this.service,
    required this.readCharacteristic,
    required Duration initialStateTimeout,
    required String handshakeFailureMessage,
    required this.sessionLabel,
    this.onDiagnostic,
  }) : handshake = InitialStateHandshake(
         timeout: initialStateTimeout,
         failureMessage: handshakeFailureMessage,
         onDiagnostic: onDiagnostic,
       );

  @protected
  final BleCentral central;
  @protected
  final String deviceId;
  @protected
  final String service;
  @protected
  final String readCharacteristic;
  @protected
  final String sessionLabel;
  @protected
  final CubeDiagnosticSink? onDiagnostic;
  @protected
  final InitialStateHandshake handshake;

  final StreamController<SmartCubeEvent> _eventController =
      StreamController.broadcast();
  StreamSubscription<Uint8List>? _valueSubscription;
  Future<void>? _startFuture;
  bool _subscribed = false;
  bool _started = false;
  bool _closed = false;

  @protected
  bool get isStarted => _started;
  @protected
  bool get isClosed => _closed;

  @override
  Stream<SmartCubeEvent> get events => _eventController.stream;

  @override
  Stream<int> get batteryLevels => const Stream.empty();

  @override
  Stream<bool> get connectionStates => central.connectionState(deviceId);

  @override
  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    if (_closed) {
      throw CubeConnectionFailure(
        CubeConnectionFailureCode.connectionFailed,
        'Cannot start a closed $sessionLabel cube session.',
      );
    }
    onDiagnostic?.call('notifications.subscribe.started', null);
    _valueSubscription = central
        .characteristicValues(deviceId, readCharacteristic)
        .listen(handleEncryptedPacket, onError: _handleTransportError);
    await central.subscribe(deviceId, service, readCharacteristic);
    _subscribed = true;
    onDiagnostic?.call('notifications.subscribe.succeeded', null);
    await sendInitialRequests();
    await handshake.wait();
    if (_closed) throw _closedDuringStartupFailure;
    _started = true;
  }

  @protected
  Future<void> sendInitialRequests();

  @protected
  void handleEncryptedPacket(Uint8List encryptedPacket);

  @protected
  void emitEvent(SmartCubeEvent event) {
    if (!_closed) _eventController.add(event);
  }

  @protected
  void emitError(Object error, [StackTrace? stackTrace]) {
    if (!_closed) _eventController.addError(error, stackTrace);
  }

  @protected
  void routePacketFailure(Object error, StackTrace stackTrace) {
    if (!_started) {
      handshake.completeError(error, stackTrace);
    } else {
      emitError(error, stackTrace);
    }
  }

  @protected
  void ensureStartedForStateRequest() {
    if (!_started || _closed) {
      throw CubeConnectionFailure(
        CubeConnectionFailureCode.connectionFailed,
        'Cannot request state before $sessionLabel session startup completes.',
      );
    }
  }

  void _handleTransportError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    routePacketFailure(error, stackTrace);
  }

  CubeConnectionFailure get _closedDuringStartupFailure =>
      CubeConnectionFailure(
        CubeConnectionFailureCode.connectionFailed,
        'The $sessionLabel cube session closed during startup.',
      );

  @protected
  Future<void> closeAdditionalResources() async {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    handshake.completeError(_closedDuringStartupFailure);
    try {
      if (_subscribed) {
        await central.unsubscribe(deviceId, service, readCharacteristic);
      }
    } catch (_) {
      // The characteristic can already be gone after a link loss.
    }
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    try {
      await central.disconnect(deviceId);
    } catch (_) {
      // A lost link is already disconnected.
    }
    await closeAdditionalResources();
    await _eventController.close();
  }
}
