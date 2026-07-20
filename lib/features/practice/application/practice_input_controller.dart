import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../cube/application/cube_connection_controller.dart';
import '../../cube/domain/smart_cube_device.dart';
import '../../cube/domain/smart_cube_event.dart';
import 'practice_controller.dart';

/// Coordinates the selected practice input with the physical BLE session.
///
/// Demo selection belongs here rather than in [CubeConnectionController],
/// which is intentionally limited to discovery and physical cube sessions.
final class PracticeInputController extends ChangeNotifier {
  PracticeInputController({
    required PracticeController practiceController,
    required CubeConnectionController connectionController,
  }) : _practice = practiceController,
       _connection = connectionController {
    _practice.addListener(_relayPracticeChange);
    _connection.addListener(_handleConnectionChange);
    _cubeEventSubscription = _connection.events.listen(_handleCubeEvent);
    _handleConnectionChange();
  }

  final PracticeController _practice;
  final CubeConnectionController _connection;
  late final StreamSubscription<SmartCubeEvent> _cubeEventSubscription;
  SmartCubeStateEvent? _lastAppliedStateEvent;
  bool _batchingPracticeChanges = false;
  bool _disposed = false;

  PracticeInputMode get mode => _practice.inputMode;
  bool get isUnselected => mode == PracticeInputMode.unselected;
  bool get isDemo => mode == PracticeInputMode.demo;
  bool get isSmartCubeSelected => mode == PracticeInputMode.smartCube;
  bool get isPhysicalCubeConnected => _connection.isConnected;
  bool get needsReconnect => isSmartCubeSelected && !isPhysicalCubeConnected;

  CubeConnectionStatus get connectionStatus => _connection.status;
  bool get isAutomaticReconnectSearching =>
      _connection.automaticReconnectPhase == AutomaticReconnectPhase.searching;
  bool get isAutomaticReconnectActive =>
      _connection.automaticReconnectPhase != AutomaticReconnectPhase.inactive;
  String? get automaticReconnectDeviceName =>
      _connection.automaticReconnectDeviceName;
  String? get connectingDeviceId => _connection.connectingDeviceId;
  ConnectedCube? get connectedCube => _connection.connectedCube;
  int? get batteryLevel => _connection.batteryLevel;
  String? get errorMessage => _connection.errorMessage;
  bool get hasDiagnostics => _connection.hasDiagnostics;
  String get diagnosticReport => _connection.diagnosticReport;
  List<CubeDeviceCandidate> get discoveredDevices =>
      _connection.discoveredDevices;
  List<CubeDeviceCandidate> get discoveredCubes => _connection.discoveredCubes;
  List<CubeDeviceCandidate> get otherDiscoveredDevices =>
      _connection.otherDiscoveredDevices;

  Future<void> useDemoCube() async {
    await _connection.stopScan();
    if (_connection.status != CubeConnectionStatus.disconnected ||
        _connection.connectedCube != null) {
      await _connection.disconnect();
    }
    _practice.activateDemoInput();
  }

  void exitDemo() => _practice.clearDemoInput();

  Future<void> startScan() => _connection.startScan();

  Future<void> stopScan() => _connection.stopScan();

  Future<void> stopAutomaticReconnect() => _connection.stopAutomaticReconnect();

  Future<void> connect(CubeDeviceCandidate device) async {
    if (isDemo) _practice.clearDemoInput();
    await _connection.connect(device);
  }

  Future<void> disconnectPhysicalCube() => _connection.disconnect();

  void _handleConnectionChange() {
    if (_disposed) return;
    _batchingPracticeChanges = true;
    try {
      switch (_connection.status) {
        case CubeConnectionStatus.connected:
          _practice.activateSmartCubeInput();
          final latestState = _connection.latestStateEvent;
          if (latestState != null) _applyCubeEvent(latestState);
        case CubeConnectionStatus.disconnected || CubeConnectionStatus.error:
          _lastAppliedStateEvent = null;
          if (_practice.smartCubeWorkflowActive) {
            _practice.markSmartCubeDisconnected();
          }
        case CubeConnectionStatus.scanning || CubeConnectionStatus.connecting:
        // These are transitional states, not a lost physical link.
      }
    } finally {
      _batchingPracticeChanges = false;
    }
    notifyListeners();
  }

  void _handleCubeEvent(SmartCubeEvent event) {
    if (_disposed) return;
    if (_connection.status != CubeConnectionStatus.connecting &&
        _connection.status != CubeConnectionStatus.connected) {
      return;
    }
    // Initial state can be replayed while the BLE controller is still
    // completing its subscriptions. Select the physical workflow first so
    // the event and its lifecycle transition are applied in one place.
    _batchingPracticeChanges = true;
    try {
      _practice.activateSmartCubeInput();
      _applyCubeEvent(event);
    } finally {
      _batchingPracticeChanges = false;
    }
    notifyListeners();
  }

  void _applyCubeEvent(SmartCubeEvent event) {
    switch (event) {
      case SmartCubeMoveEvent(:final move, :final receivedAt):
        _practice.applyMove(move, fromSmartCube: true, occurredAt: receivedAt);
      case final SmartCubeStateEvent stateEvent:
        if (identical(stateEvent, _lastAppliedStateEvent)) return;
        _lastAppliedStateEvent = stateEvent;
        _practice.syncCubeState(
          stateEvent.state,
          occurredAt: stateEvent.receivedAt,
        );
    }
  }

  void _relayPracticeChange() {
    if (!_disposed && !_batchingPracticeChanges) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _practice.removeListener(_relayPracticeChange);
    _connection.removeListener(_handleConnectionChange);
    unawaited(_cubeEventSubscription.cancel());
    super.dispose();
  }
}
