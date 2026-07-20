import '../../domain/cube_connection_diagnostics.dart';
import '../../domain/smart_cube_device.dart';
import '../../domain/smart_cube_event.dart';
import '../ble/ble_central.dart';

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

final class CubeDeviceMatch {
  const CubeDeviceMatch({
    required this.vendor,
    required this.protocolFamily,
    required this.supportStatus,
    this.adapterId,
    this.protocolIdentity,
    this.supportMessage,
  });

  final CubeVendor vendor;
  final CubeProtocolFamily protocolFamily;
  final CubeSupportStatus supportStatus;
  final String? adapterId;
  final CubeProtocolIdentity? protocolIdentity;
  final String? supportMessage;
}

abstract interface class CubeDeviceRecognizer {
  CubeDeviceMatch? match(BleAdvertisement advertisement);
}

abstract interface class SmartCubeAdapter implements CubeDeviceRecognizer {
  String get id;

  Future<SmartCubeSession> connect(
    BleCentral central,
    CubeDeviceCandidate device, {
    CubeDiagnosticSink? onDiagnostic,
  });
}

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
