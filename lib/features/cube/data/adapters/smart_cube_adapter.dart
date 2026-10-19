import '../../../../core/time/monotonic_clock.dart';
import '../../application/cube_connection_gateway.dart';
import '../../domain/cube_connection_diagnostics.dart';
import '../../domain/smart_cube_device.dart';
import '../ble/ble_central.dart';

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

  List<String> get supportedProtocolDisplayNames;

  Future<SmartCubeSession> connect(
    BleCentral central,
    CubeDeviceCandidate device, {
    required MonotonicClock monotonicClock,
    CubeDiagnosticSink? onDiagnostic,
  });
}
