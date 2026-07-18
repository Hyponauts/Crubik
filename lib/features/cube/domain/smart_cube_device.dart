enum CubeVendor { gan, moyu, unknown }

enum CubeProtocolFamily { gan, moyuAi2023, moyu32, moyuMhc, unknown }

enum CubeSupportStatus { supported, detectedUnsupported, unidentified }

final class CubeCapabilities {
  const CubeCapabilities({
    this.initialState = false,
    this.moveHistory = false,
    this.cubeTimestamps = false,
    this.battery = false,
    this.gyroscope = false,
  });

  final bool initialState;
  final bool moveHistory;
  final bool cubeTimestamps;
  final bool battery;
  final bool gyroscope;
}

final class CubeDeviceCandidate {
  const CubeDeviceCandidate({
    required this.id,
    required this.name,
    this.vendor = CubeVendor.unknown,
    this.protocolFamily = CubeProtocolFamily.unknown,
    this.supportStatus = CubeSupportStatus.unidentified,
    this.adapterId,
    this.rssi,
    this.macAddress,
    this.supportMessage,
  }) : assert(
         supportStatus != CubeSupportStatus.supported || adapterId != null,
         'A supported cube must identify its adapter.',
       );

  final String id;
  final String name;
  final CubeVendor vendor;
  final CubeProtocolFamily protocolFamily;
  final CubeSupportStatus supportStatus;
  final String? adapterId;
  final int? rssi;
  final String? macAddress;
  final String? supportMessage;

  bool get isIdentifiedCube => supportStatus != CubeSupportStatus.unidentified;

  bool get isSupported => supportStatus == CubeSupportStatus.supported;

  bool get canConnect => isSupported && adapterId != null;
}

final class ConnectedCube {
  const ConnectedCube({
    required this.id,
    required this.name,
    required this.vendor,
    required this.protocolFamily,
    required this.capabilities,
  });

  factory ConnectedCube.bluetooth(
    CubeDeviceCandidate device,
    CubeCapabilities capabilities,
  ) => ConnectedCube(
    id: device.id,
    name: device.name,
    vendor: device.vendor,
    protocolFamily: device.protocolFamily,
    capabilities: capabilities,
  );

  final String id;
  final String name;
  final CubeVendor vendor;
  final CubeProtocolFamily protocolFamily;
  final CubeCapabilities capabilities;
}
