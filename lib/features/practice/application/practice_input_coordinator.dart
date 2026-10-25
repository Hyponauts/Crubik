import 'dart:async';

import '../../cube/application/cube_connection_controller.dart';
import '../../cube/domain/smart_cube_device.dart';
import '../../cube/domain/smart_cube_event.dart';
import 'practice_controller.dart';

/// Coordinates the selected practice input with the physical BLE session.
///
/// Demo selection belongs here rather than in [CubeConnectionController],
/// which is intentionally limited to discovery and physical cube sessions.
final class PracticeInputCoordinator {
  PracticeInputCoordinator({
    required PracticeController practiceController,
    required CubeConnectionController connectionController,
  }) : _practice = practiceController,
       _connection = connectionController {
    _connection.addListener(_handleConnectionChange);
    _cubeEventSubscription = _connection.events.listen(_handleCubeEvent);
    _handleConnectionChange();
  }

  final PracticeController _practice;
  final CubeConnectionController _connection;
  late final StreamSubscription<SmartCubeEvent> _cubeEventSubscription;
  SmartCubeStateEvent? _lastAppliedStateEvent;
  bool _disposed = false;

  Future<void> useDemoCube() async {
    await _connection.stopScan();
    if (_connection.status != CubeConnectionStatus.disconnected ||
        _connection.connectedCube != null) {
      await _connection.disconnect();
    }
    _practice.activateDemoInput();
  }

  void exitDemo() => _practice.clearDemoInput();

  Future<void> connect(CubeDeviceCandidate device) async {
    if (_practice.inputMode == PracticeInputMode.demo) {
      _practice.clearDemoInput();
    }
    await _connection.connect(device);
  }

  void _handleConnectionChange() {
    if (_disposed) return;
    switch (_connection.status) {
      case CubeConnectionStatus.connected:
        final connectedCube = _connection.connectedCube;
        _practice.activateSmartCubeInput(
          protocolFamily: connectedCube?.protocolFamily,
          capabilities: connectedCube?.capabilities,
        );
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
    _practice.activateSmartCubeInput();
    _applyCubeEvent(event);
  }

  void _applyCubeEvent(SmartCubeEvent event) {
    switch (event) {
      case SmartCubeMoveEvent() ||
          SmartCubeOrientationEvent() ||
          SmartCubeCapabilitiesEvent() ||
          SmartCubeDataGapEvent():
        _practice.handleSmartCubeEvent(event);
      case final SmartCubeStateEvent stateEvent:
        if (identical(stateEvent, _lastAppliedStateEvent)) return;
        _lastAppliedStateEvent = stateEvent;
        _practice.handleSmartCubeEvent(stateEvent);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connection.removeListener(_handleConnectionChange);
    unawaited(_cubeEventSubscription.cancel());
  }
}
