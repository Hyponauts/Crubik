import '../domain/cube_connection_diagnostics.dart';
import '../domain/smart_cube_device.dart';
import '../domain/smart_cube_event.dart';

enum CubeConnectionFailureCode {
  permissionDenied,
  bluetoothUnavailable,
  unsupportedProtocol,
  identityUnavailable,
  handshakeFailed,
  packetMalformed,
  dataLoss,
  connectionFailed,
}

final class CubeConnectionFailure implements Exception {
  const CubeConnectionFailure(this.code, this.message);

  final CubeConnectionFailureCode code;
  final String message;

  @override
  String toString() => message;
}

/// A normalized smart-cube session exposed to the application layer.
///
/// Vendor adapters implement this contract without leaking BLE or packet
/// details into connection and practice state.
abstract interface class SmartCubeSession {
  CubeCapabilities get capabilities;

  Stream<SmartCubeEvent> get events;

  Stream<int> get batteryLevels;

  Stream<bool> get connectionStates;

  /// Starts notifications and waits for the initial authoritative state.
  ///
  /// Consumers must subscribe to [events], [batteryLevels], and
  /// [connectionStates] before calling this method. Repeated calls return the
  /// same startup operation.
  Future<void> start();

  /// Requests a fresh authoritative state after startup has completed.
  Future<void> requestState();

  Future<void> close();
}

/// Transport boundary used by [CubeConnectionController].
///
/// BLE is the production implementation today, while tests and future input
/// transports can implement the same application-owned contract.
abstract interface class CubeConnectionGateway {
  Stream<CubeDeviceCandidate> get scanResults;

  List<String> get supportedProtocolDisplayNames;

  Future<bool> isBluetoothAvailable();

  Future<bool> hasPermissions();

  Future<void> requestPermissions();

  Future<void> startScan();

  Future<void> stopScan();

  Future<SmartCubeSession> connect(
    CubeDeviceCandidate device, {
    CubeDiagnosticSink? onDiagnostic,
  });

  Future<void> close();
}
