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
import 'package:crubik/features/cube/data/remembered_cube_store.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/cube_connection_diagnostics.dart';
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
    expect(mhc.supportMessage, contains('Legacy MoYu MHC'));
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

  test('reconnects the remembered cube from a startup scan', () async {
    final gateway = _FakeCubeConnectionGateway();
    final store = _FakeRememberedCubeStore('gan-remembered', name: 'GAN12ui');
    final controller = CubeConnectionController(
      gateway: gateway,
      rememberedCubeStore: store,
    );
    const device = CubeDeviceCandidate(
      id: 'gan-remembered',
      name: 'GAN12ui',
      vendor: CubeVendor.gan,
      protocolFamily: CubeProtocolFamily.gan,
      supportStatus: CubeSupportStatus.supported,
      adapterId: 'gan-family',
    );

    await controller.reconnectRememberedCube();

    expect(gateway.permissionRequestCount, 0);
    expect(gateway.scanStartCount, 1);
    expect(controller.status, CubeConnectionStatus.scanning);
    expect(
      controller.automaticReconnectPhase,
      AutomaticReconnectPhase.searching,
    );
    expect(controller.automaticReconnectDeviceName, 'GAN12ui');

    gateway.addDevice(
      const CubeDeviceCandidate(
        id: 'another-gan',
        name: 'GAN14ui',
        vendor: CubeVendor.gan,
        protocolFamily: CubeProtocolFamily.gan,
        supportStatus: CubeSupportStatus.supported,
        adapterId: 'gan-family',
      ),
    );
    await pumpEventQueue();
    expect(gateway.connectCount, 0);
    expect(controller.status, CubeConnectionStatus.scanning);
    expect(
      controller.automaticReconnectPhase,
      AutomaticReconnectPhase.searching,
    );

    gateway.addDevice(device);
    await pumpEventQueue();

    expect(gateway.connectCount, 1);
    expect(controller.status, CubeConnectionStatus.connected);
    expect(
      controller.automaticReconnectPhase,
      AutomaticReconnectPhase.inactive,
    );
    expect(controller.connectedCube?.id, device.id);
    expect(store.deviceId, device.id);
    expect(store.name, device.name);

    await controller.close();
    controller.dispose();
  });

  test(
    'startup reconnect does not request permission or scan without access',
    () async {
      final permissionGateway = _FakeCubeConnectionGateway(
        permissionsGranted: false,
      );
      final permissionController = CubeConnectionController(
        gateway: permissionGateway,
        rememberedCubeStore: _FakeRememberedCubeStore('gan-remembered'),
      );

      await permissionController.reconnectRememberedCube();

      expect(permissionGateway.permissionRequestCount, 0);
      expect(permissionGateway.scanStartCount, 0);
      expect(permissionController.status, CubeConnectionStatus.disconnected);

      final unavailableGateway = _FakeCubeConnectionGateway(
        bluetoothAvailable: false,
      );
      final unavailableController = CubeConnectionController(
        gateway: unavailableGateway,
        rememberedCubeStore: _FakeRememberedCubeStore('gan-remembered'),
      );

      await unavailableController.reconnectRememberedCube();

      expect(unavailableGateway.scanStartCount, 0);
      expect(unavailableController.status, CubeConnectionStatus.disconnected);

      await permissionController.close();
      permissionController.dispose();
      await unavailableController.close();
      unavailableController.dispose();
    },
  );

  test('stops automatic searching before connection begins', () async {
    final gateway = _FakeCubeConnectionGateway();
    final controller = CubeConnectionController(
      gateway: gateway,
      rememberedCubeStore: _FakeRememberedCubeStore('gan-remembered'),
    );

    await controller.reconnectRememberedCube();
    await controller.stopAutomaticReconnect();

    expect(gateway.scanStopCount, 1);
    expect(gateway.connectCount, 0);
    expect(controller.status, CubeConnectionStatus.disconnected);
    expect(
      controller.automaticReconnectPhase,
      AutomaticReconnectPhase.inactive,
    );

    await controller.close();
    controller.dispose();
  });

  test('remembers a cube only after a successful connection', () async {
    final gateway = _FakeCubeConnectionGateway();
    final store = _FakeRememberedCubeStore(null);
    final controller = CubeConnectionController(
      gateway: gateway,
      rememberedCubeStore: store,
    );
    const device = CubeDeviceCandidate(
      id: 'moyu-remembered',
      name: 'WCU_MY32',
      vendor: CubeVendor.moyu,
      protocolFamily: CubeProtocolFamily.moyu32,
      supportStatus: CubeSupportStatus.supported,
      adapterId: 'moyu32',
    );

    await controller.connect(device);

    expect(store.deviceId, device.id);
    await controller.close();
    controller.dispose();
  });

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
    expect(gateway.sessionFor(device.id).startCount, 1);
    expect(gateway.sessionFor(device.id).stateRequestCount, 0);
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

  test('GAN adapter prefers manufacturer MAC over the platform BLE id', () {
    final native = _advertisement('GAN12ui', deviceId: 'AA:BB:CC:DD:EE:FF');
    final advertised = _advertisement(
      'AiCube',
      deviceId: 'AA:BB:CC:DD:EE:FF',
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

    expect(resolveGanProtocolIdentity(native)?.value, 'AA:BB:CC:DD:EE:FF');
    expect(
      resolveGanProtocolIdentity(native)?.source,
      CubeProtocolIdentitySource.platformDeviceId,
    );
    expect(resolveGanProtocolIdentity(advertised)?.value, '11:22:33:44:55:66');
    expect(
      resolveGanProtocolIdentity(advertised)?.source,
      CubeProtocolIdentitySource.manufacturerData,
    );
    expect(cubeMacSalt('11:22:33:44:55:66'), [
      0x66,
      0x55,
      0x44,
      0x33,
      0x22,
      0x11,
    ]);
  });

  test('forwards events and retains the latest physical state', () async {
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
    final stateEvent = SmartCubeStateEvent(
      state: CubeState.solved()..apply(CubeMove.parse('F')),
      serial: 0,
      receivedAt: DateTime.utc(2026),
    );
    final moveEvent = SmartCubeMoveEvent(
      move: CubeMove.parse("R'"),
      serial: 1,
      receivedAt: DateTime.utc(2026),
    );
    final received = <SmartCubeEvent>[];
    final subscription = controller.events.listen(received.add);

    gateway.sessionFor(device.id)
      ..addEvent(stateEvent)
      ..addEvent(moveEvent);
    await Future<void>.delayed(Duration.zero);

    expect(received, [stateEvent, moveEvent]);
    expect(controller.latestStateEvent, same(stateEvent));
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

      await controller.disconnect();
      expect(controller.batteryLevel, isNull);
      await controller.close();
      controller.dispose();
    },
  );

  test('disconnect closes the active adapter session', () async {
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

    await controller.disconnect();

    expect(session.isClosed, isTrue);
    expect(controller.connectedCube, isNull);
    expect(controller.status, CubeConnectionStatus.disconnected);
    await controller.close();
    controller.dispose();
  });

  test('late session startup cannot restore a disconnected cube', () async {
    final startGate = Completer<void>();
    final gateway = _FakeCubeConnectionGateway(sessionStartGate: startGate);
    final controller = CubeConnectionController(gateway: gateway);
    const device = CubeDeviceCandidate(
      id: 'gan-pending',
      name: 'GAN12ui',
      vendor: CubeVendor.gan,
      protocolFamily: CubeProtocolFamily.gan,
      supportStatus: CubeSupportStatus.supported,
      adapterId: 'gan-family',
    );

    final connection = controller.connect(device);
    await Future<void>.delayed(Duration.zero);
    await controller.disconnect();
    startGate.complete();
    await connection;

    expect(controller.status, CubeConnectionStatus.disconnected);
    expect(controller.connectedCube, isNull);
    expect(gateway.sessionFor(device.id).isClosed, isTrue);
    await controller.close();
    controller.dispose();
  });

  test(
    'exports connection stages without cube identifiers or packet data',
    () async {
      final gateway = _FakeCubeConnectionGateway();
      final controller = CubeConnectionController(gateway: gateway);
      const device = CubeDeviceCandidate(
        id: 'AA:BB:CC:DD:EE:FF',
        name: 'WCU_MY32_CDEF',
        vendor: CubeVendor.moyu,
        protocolFamily: CubeProtocolFamily.moyu32,
        supportStatus: CubeSupportStatus.supported,
        adapterId: 'moyu32',
        protocolIdentity: CubeProtocolIdentity(
          value: 'AA:BB:CC:DD:EE:FF',
          source: CubeProtocolIdentitySource.platformDeviceId,
        ),
      );

      await controller.connect(device);

      final report = controller.diagnosticReport;
      expect(report, contains('protocol=moyu32'));
      expect(report, contains('adapter.selected moyu32'));
      expect(report, contains('connection.ready'));
      expect(report, isNot(contains(device.id)));
      expect(report, isNot(contains(device.name)));
      expect(report, isNot(contains(device.protocolIdentity!.value)));

      await controller.close();
      controller.dispose();
    },
  );
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
    this.bluetoothAvailable = true,
    this.permissionsGranted = true,
    this.grantPermissionOnRequest = true,
    this.sessionStartGate,
  });

  final _scanController = StreamController<CubeDeviceCandidate>.broadcast();
  final _sessions = <String, _FakeSmartCubeSession>{};
  final bool bluetoothAvailable;
  bool permissionsGranted;
  final bool grantPermissionOnRequest;
  final Completer<void>? sessionStartGate;
  int permissionRequestCount = 0;
  int scanStartCount = 0;
  int scanStopCount = 0;
  int connectCount = 0;
  bool _closed = false;

  @override
  Stream<CubeDeviceCandidate> get scanResults => _scanController.stream;

  @override
  Future<bool> isBluetoothAvailable() async => bluetoothAvailable;

  @override
  Future<SmartCubeSession> connect(
    CubeDeviceCandidate device, {
    CubeDiagnosticSink? onDiagnostic,
  }) async {
    connectCount++;
    onDiagnostic?.call('adapter.selected', device.adapterId);
    return _sessions.putIfAbsent(
      device.id,
      () => _FakeSmartCubeSession(startGate: sessionStartGate),
    );
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
  Future<void> stopScan() async {
    scanStopCount++;
  }

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
  _FakeSmartCubeSession({this.startGate});

  final Completer<void>? startGate;
  final _eventController = StreamController<SmartCubeEvent>.broadcast();
  final _batteryController = StreamController<int>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  bool _closed = false;
  int startCount = 0;
  int stateRequestCount = 0;

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
  Future<void> start() async {
    startCount++;
    await startGate?.future;
  }

  @override
  Future<void> requestState() async {
    stateRequestCount++;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _eventController.close();
    await _batteryController.close();
    await _connectionController.close();
  }
}

final class _FakeRememberedCubeStore implements RememberedCubeStore {
  _FakeRememberedCubeStore(this.deviceId, {this.name});

  String? deviceId;
  String? name;

  @override
  Future<RememberedCube?> load() async {
    final id = deviceId;
    return id == null ? null : RememberedCube(deviceId: id, name: name);
  }

  @override
  Future<void> save(RememberedCube cube) async {
    deviceId = cube.deviceId;
    name = cube.name;
  }
}
