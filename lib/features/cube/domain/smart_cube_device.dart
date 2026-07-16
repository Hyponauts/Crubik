enum CubeVendor { gan, moyu, unknown }

enum CubeProtocolFamily { gan, moyuAi2023, moyu32, moyuMhc, unknown }

enum CubeSupportStatus { supported, detectedUnsupported, unidentified }

enum CubeConnectionMode { bluetooth, demo }

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
    required this.mode,
    required this.vendor,
    required this.protocolFamily,
    required this.capabilities,
  });

  const ConnectedCube.demo()
    : id = 'demo-cube',
      name = 'Demo cube',
      mode = CubeConnectionMode.demo,
      vendor = CubeVendor.unknown,
      protocolFamily = CubeProtocolFamily.unknown,
      capabilities = const CubeCapabilities();

  factory ConnectedCube.bluetooth(
    CubeDeviceCandidate device,
    CubeCapabilities capabilities,
  ) => ConnectedCube(
    id: device.id,
    name: device.name,
    mode: CubeConnectionMode.bluetooth,
    vendor: device.vendor,
    protocolFamily: device.protocolFamily,
    capabilities: capabilities,
  );

  final String id;
  final String name;
  final CubeConnectionMode mode;
  final CubeVendor vendor;
  final CubeProtocolFamily protocolFamily;
  final CubeCapabilities capabilities;

  bool get isDemo => mode == CubeConnectionMode.demo;
}
