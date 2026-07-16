import 'dart:async';
import 'dart:typed_data';

import 'package:crubik/features/cube/application/cube_connection_controller.dart';
import 'package:crubik/features/cube/data/adapters/cube_adapter_registry.dart';
import 'package:crubik/features/cube/data/adapters/gan/gan_cube_adapter.dart';
import 'package:crubik/features/cube/data/adapters/smart_cube_adapter.dart';
import 'package:crubik/features/cube/data/ble/ble_central.dart';
import 'package:crubik/features/cube/data/cube_connection_gateway.dart';
import 'package:crubik/features/cube/data/gan_cube_protocol.dart';
import 'package:crubik/features/cube/data/moyu32_cube_protocol.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/cube/domain/smart_cube_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry identifies known GAN and MoYu advertisement families', () {
    final registry = _registry();

    expect(registry.identify(_advertisement('GAN12ui')).vendor, CubeVendor.gan);
    expect(
      registry.identify(_advertisement('MoYu AI')).protocolFamily,
      CubeProtocolFamily.moyuAi2023,
    );
    expect(
      registry.identify(_advertisement('AiCube-AB12')).supportStatus,
      CubeSupportStatus.supported,
    );
    final wcu = registry.identify(_advertisement('WCU_MY32'));
    expect(wcu.vendor, CubeVendor.moyu);
    expect(wcu.protocolFamily, CubeProtocolFamily.moyu32);
    expect(wcu.supportStatus, CubeSupportStatus.supported);
    expect(wcu.adapterId, 'moyu32');
    expect(wcu.canConnect, isTrue);

    final serviceOnly = registry.identify(
      _advertisement(null, services: const [moyu32Service]),
    );
    expect(serviceOnly.protocolFamily, CubeProtocolFamily.moyu32);
    expect(serviceOnly.supportStatus, CubeSupportStatus.supported);

    final mhc = registry.identify(_advertisement('MHC-AB12'));
    expect(mhc.protocolFamily, CubeProtocolFamily.moyuMhc);
    expect(mhc.supportMessage, contains('WeiLong V10 AI'));
  });

  test('registry turns every BLE result into a visible device candidate', () {
    final registry = _registry();
    final headphones = registry.identify(_advertisement('Headphones'));
    final unnamed = registry.identify(_advertisement(null));

    expect(headphones.vendor, CubeVendor.unknown);
    expect(headphones.isIdentifiedCube, isFalse);
    expect(headphones.name, 'Headphones');
    expect(unnamed.name, 'Unnamed Bluetooth device');
  });

  test('requests Bluetooth permission before starting a scan', () async {
    final gateway = _FakeCubeConnectionGateway(permissionsGranted: false);
    final controller = CubeConnectionController(gateway: gateway);

    await controller.startScan();

    expect(gateway.permissionRequestCount, 1);
    expect(gateway.scanStartCount, 1);
    expect(controller.status, CubeConnectionStatus.scanning);

    await controller.close();
    controller.dispose();
  });

  test(
    'explains how to recover when Bluetooth permission stays disabled',
    () async {
      final gateway = _FakeCubeConnectionGateway(
        permissionsGranted: false,
        grantPermissionOnRequest: false,
      );
      final controller = CubeConnectionController(gateway: gateway);

      await controller.startScan();

      expect(gateway.permissionRequestCount, 1);
      expect(gateway.scanStartCount, 0);
      expect(controller.status, CubeConnectionStatus.error);
      expect(controller.errorMessage, contains('Enable Nearby devices'));

      await controller.close();
      controller.dispose();
    },
  );

  test('scans, connects, and reacts to disconnect events', () async {
    final gateway = _FakeCubeConnectionGateway();
    final controller = CubeConnectionController(gateway: gateway);
    const device = CubeDeviceCandidate(
      id: 'gan-1',
      name: 'GAN12ui',
      vendor: CubeVendor.gan,
      protocolFamily: CubeProtocolFamily.gan,
      supportStatus: CubeSupportStatus.supported,
      adapterId: 'gan-family',
      rssi: -40,
    );

    await controller.startScan();
    gateway.addDevice(device);
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, CubeConnectionStatus.scanning);
    expect(controller.discoveredDevices, [device]);

    await controller.connect(device);
    expect(controller.isConnected, isTrue);
    expect(controller.connectedCube?.name, device.name);
    expect(controller.connectedCube?.capabilities.initialState, isTrue);

    gateway.sessionFor(device.id).setConnected(false);
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, CubeConnectionStatus.disconnected);

    await controller.close();
    controller.dispose();
  });

  test(
    'groups cubes ahead of other devices and blocks other connections',
    () async {
      final gateway = _FakeCubeConnectionGateway();
      final controller = CubeConnectionController(gateway: gateway);
      const wcu = CubeDeviceCandidate(
        id: 'wcu',
        name: 'WCU_MY32',
        vendor: CubeVendor.moyu,
        protocolFamily: CubeProtocolFamily.moyu32,
        supportStatus: CubeSupportStatus.detectedUnsupported,
        rssi: -70,
      );
      const headphones = CubeDeviceCandidate(
        id: 'headphones',
        name: 'Headphones',
        rssi: -20,
      );
      const gan = CubeDeviceCandidate(
        id: 'gan',
        name: 'GAN12ui',
        vendor: CubeVendor.gan,
        protocolFamily: CubeProtocolFamily.gan,
        supportStatus: CubeSupportStatus.supported,
        adapterId: 'gan-family',
        rssi: -40,
      );

      await controller.startScan();
      gateway
        ..addDevice(headphones)
        ..addDevice(wcu)
        ..addDevice(gan);
      await Future<void>.delayed(Duration.zero);

      expect(controller.discoveredCubes, [gan, wcu]);
      expect(controller.otherDiscoveredDevices, [headphones]);
      expect(controller.discoveredDevices, [gan, wcu, headphones]);

      await controller.connect(headphones);

      expect(gateway.connectCount, 0);
      expect(controller.status, CubeConnectionStatus.error);
      expect(controller.errorMessage, contains('not identified'));

      await controller.close();
      controller.dispose();
    },
  );

  test('GAN adapter extracts MAC from native id or manufacturer data', () {
    final native = _advertisement('GAN12ui', deviceId: 'AA:BB:CC:DD:EE:FF');
    final advertised = _advertisement(
      'AiCube',
      manufacturerData: [
        BleManufacturerData(
          companyId: 0x1201,
          payload: Uint8List.fromList([
            0,
            0,
            0,
            0x66,
            0x55,
            0x44,
            0x33,
            0x22,
            0x11,
          ]),
        ),
      ],
    );

    expect(extractGanMacAddress(native), 'AA:BB:CC:DD:EE:FF');
    expect(extractGanMacAddress(advertised), '11:22:33:44:55:66');
    expect(cubeMacSalt('11:22:33:44:55:66'), [
      0x66,
      0x55,
      0x44,
      0x33,
      0x22,
      0x11,
    ]);
  });

  test('forwards ordered smart-cube events to subscribers', () async {
    final gateway = _FakeCubeConnectionGateway();
    final controller = CubeConnectionController(gateway: gateway);
    const device = CubeDeviceCandidate(
      id: 'gan-1',
      name: 'GAN12ui',
      vendor: CubeVendor.gan,
      protocolFamily: CubeProtocolFamily.gan,
      supportStatus: CubeSupportStatus.supported,
      adapterId: 'gan-family',
    );
    await controller.connect(device);
    final event = SmartCubeMoveEvent(
      move: CubeMove.parse("R'"),
      serial: 1,
      receivedAt: DateTime.utc(2026),
    );
    final received = <SmartCubeEvent>[];
    final subscription = controller.events.listen(received.add);

    gateway.sessionFor(device.id).addEvent(event);
    await Future<void>.delayed(Duration.zero);

    expect((received.single as SmartCubeMoveEvent).move.notation, "R'");
    await subscription.cancel();
    await controller.close();
    controller.dispose();
  });

  test(
    'publishes battery snapshots and keeps data-loss errors nonfatal',
    () async {
      final gateway = _FakeCubeConnectionGateway();
      final controller = CubeConnectionController(gateway: gateway);
      const device = CubeDeviceCandidate(
        id: 'moyu-1',
        name: 'WCU_MY32_ABCD',
        vendor: CubeVendor.moyu,
        protocolFamily: CubeProtocolFamily.moyu32,
        supportStatus: CubeSupportStatus.supported,
        adapterId: 'moyu32',
      );
      await controller.connect(device);
      final session = gateway.sessionFor(device.id);

      session.addBatteryLevel(72);
      session.addError(
        const CubeConnectionFailure(
          CubeConnectionFailureCode.dataLoss,
          'Move history gap.',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.batteryLevel, 72);
      expect(controller.status, CubeConnectionStatus.connected);
      expect(controller.errorMessage, contains('requested'));

      await controller.connectDemo();
      expect(controller.batteryLevel, isNull);
      await controller.close();
      controller.dispose();
    },
  );

  test('switching to demo mode closes the active adapter session', () async {
    final gateway = _FakeCubeConnectionGateway();
    final controller = CubeConnectionController(gateway: gateway);
    const device = CubeDeviceCandidate(
      id: 'gan-1',
      name: 'GAN12ui',
      vendor: CubeVendor.gan,
      protocolFamily: CubeProtocolFamily.gan,
      supportStatus: CubeSupportStatus.supported,
      adapterId: 'gan-family',
    );
    await controller.connect(device);
    final session = gateway.sessionFor(device.id);

    await controller.connectDemo();

    expect(session.isClosed, isTrue);
    expect(controller.connectedCube?.mode, CubeConnectionMode.demo);
    await controller.close();
    controller.dispose();
  });
}

CubeAdapterRegistry _registry() => CubeAdapterRegistry.defaults();

BleAdvertisement _advertisement(
  String? name, {
  String deviceId = 'platform-device-id',
  List<BleManufacturerData> manufacturerData = const [],
  List<String> services = const [],
}) => BleAdvertisement(
  deviceId: deviceId,
  name: name,
  rawName: name,
  rssi: -42,
  services: services,
  manufacturerData: manufacturerData,
);

final class _FakeCubeConnectionGateway implements CubeConnectionGateway {
  _FakeCubeConnectionGateway({
    this.permissionsGranted = true,
    this.grantPermissionOnRequest = true,
  });

  final _scanController = StreamController<CubeDeviceCandidate>.broadcast();
  final _sessions = <String, _FakeSmartCubeSession>{};
  bool permissionsGranted;
  final bool grantPermissionOnRequest;
  int permissionRequestCount = 0;
  int scanStartCount = 0;
  int connectCount = 0;
  bool _closed = false;

  @override
  Stream<CubeDeviceCandidate> get scanResults => _scanController.stream;

  @override
  Future<SmartCubeSession> connect(CubeDeviceCandidate device) async {
    connectCount++;
    return _sessions.putIfAbsent(device.id, _FakeSmartCubeSession.new);
  }

  @override
  Future<bool> hasPermissions() async => permissionsGranted;

  @override
  Future<void> requestPermissions() async {
    permissionRequestCount++;
    if (grantPermissionOnRequest) permissionsGranted = true;
  }

  @override
  Future<void> startScan() async {
    scanStartCount++;
  }

  @override
  Future<void> stopScan() async {}

  void addDevice(CubeDeviceCandidate device) => _scanController.add(device);

  _FakeSmartCubeSession sessionFor(String deviceId) => _sessions[deviceId]!;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _scanController.close();
    for (final session in _sessions.values) {
      await session.close();
    }
  }
}

final class _FakeSmartCubeSession implements SmartCubeSession {
  final _eventController = StreamController<SmartCubeEvent>.broadcast();
  final _batteryController = StreamController<int>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  bool _closed = false;

  bool get isClosed => _closed;

  @override
  CubeCapabilities get capabilities => const CubeCapabilities(
    initialState: true,
    moveHistory: true,
    cubeTimestamps: true,
    battery: true,
  );

  @override
  Stream<bool> get connectionStates => _connectionController.stream;

  @override
  Stream<int> get batteryLevels => _batteryController.stream;

  @override
  Stream<SmartCubeEvent> get events => _eventController.stream;

  void addEvent(SmartCubeEvent event) => _eventController.add(event);

  void addError(Object error) => _eventController.addError(error);

  void addBatteryLevel(int batteryLevel) =>
      _batteryController.add(batteryLevel);

  void setConnected(bool connected) => _connectionController.add(connected);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _eventController.close();
    await _batteryController.close();
    await _connectionController.close();
  }
}
