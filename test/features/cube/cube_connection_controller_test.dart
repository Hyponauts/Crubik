import 'dart:async';
import 'dart:typed_data';

import 'package:crubik/features/cube/data/cube_connection_controller.dart';
import 'package:crubik/features/cube/data/gan_cube_protocol.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  test('classifies only GAN and MoYu advertisement names', () {
    expect(classifyCubeVendor('GAN12ui'), CubeVendor.gan);
    expect(classifyCubeVendor('MoYu AI'), CubeVendor.moyu);
    expect(classifyCubeVendor('AiCube-AB12'), CubeVendor.moyu);
    expect(classifyCubeVendor('MHC-AB12'), CubeVendor.moyu);
    expect(classifyCubeAdvertisement('MHC-AB12')?.isSupported, isFalse);
    expect(
      classifyCubeAdvertisement('MHC-AB12')?.supportMessage,
      contains('WeiLong V10 AI'),
    );
    expect(classifyCubeVendor('GoCube'), isNull);
    expect(classifyCubeVendor('Giiker'), isNull);
  });

  test('requests Bluetooth permission before starting a scan', () async {
    final transport = _FakeBleTransport(permissionsGranted: false);
    final controller = CubeConnectionController(transport: transport);

    await controller.startScan();

    expect(transport.permissionRequestCount, 1);
    expect(transport.scanStartCount, 1);
    expect(controller.status, CubeConnectionStatus.scanning);

    controller.dispose();
    await transport.dispose();
  });

  test(
    'explains how to recover when Bluetooth permission stays disabled',
    () async {
      final transport = _FakeBleTransport(
        permissionsGranted: false,
        grantPermissionOnRequest: false,
      );
      final controller = CubeConnectionController(transport: transport);

      await controller.startScan();

      expect(transport.permissionRequestCount, 1);
      expect(transport.scanStartCount, 0);
      expect(controller.status, CubeConnectionStatus.error);
      expect(controller.errorMessage, contains('Enable Nearby devices'));

      controller.dispose();
      await transport.dispose();
    },
  );

  test('scans, connects, and reacts to disconnect events', () async {
    final transport = _FakeBleTransport();
    final controller = CubeConnectionController(transport: transport);
    const device = CubeDeviceCandidate(
      id: 'gan-1',
      name: 'GAN12ui',
      vendor: CubeVendor.gan,
      rssi: -40,
    );

    await controller.startScan();
    transport.addDevice(device);
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, CubeConnectionStatus.scanning);
    expect(controller.discoveredDevices, [device]);

    await controller.connect(device);
    expect(controller.isConnected, isTrue);
    expect(controller.connectedDevice, device);

    transport.setConnected(device.id, false);
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, CubeConnectionStatus.disconnected);

    controller.dispose();
    await transport.dispose();
  });

  test('extracts GAN MAC from native id or manufacturer payload', () {
    final native = BleDevice(deviceId: 'AA:BB:CC:DD:EE:FF', name: 'GAN12ui');
    final advertised = BleDevice(
      deviceId: 'platform-device-id',
      name: 'AiCube',
      manufacturerDataList: [
        ManufacturerData(
          0x1201,
          Uint8List.fromList([0, 0, 0, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11]),
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

  test('forwards decoded cube moves to subscribers', () async {
    final transport = _FakeBleTransport();
    final controller = CubeConnectionController(transport: transport);
    final event = SmartCubeMoveEvent(
      move: CubeMove.parse("R'"),
      serial: 1,
      receivedAt: DateTime.utc(2026),
    );
    final received = <SmartCubeMoveEvent>[];
    final subscription = controller.moveEvents.listen(received.add);

    transport.addMove(event);
    await Future<void>.delayed(Duration.zero);

    expect(received.single.move.notation, "R'");
    await subscription.cancel();
    controller.dispose();
    await transport.dispose();
  });
}

final class _FakeBleTransport implements BleCubeTransport {
  _FakeBleTransport({
    this.permissionsGranted = true,
    this.grantPermissionOnRequest = true,
  });

  final _scanController = StreamController<CubeDeviceCandidate>.broadcast();
  final _moveController = StreamController<SmartCubeMoveEvent>.broadcast();
  final _stateController = StreamController<SmartCubeStateEvent>.broadcast();
  final _connections = <String, StreamController<bool>>{};
  bool permissionsGranted;
  final bool grantPermissionOnRequest;
  int permissionRequestCount = 0;
  int scanStartCount = 0;

  @override
  Stream<CubeDeviceCandidate> get scanResults => _scanController.stream;

  @override
  Stream<SmartCubeMoveEvent> get moveEvents => _moveController.stream;

  @override
  Stream<SmartCubeStateEvent> get stateEvents => _stateController.stream;

  @override
  Future<void> connect(CubeDeviceCandidate device) async {
    _connections.putIfAbsent(device.id, StreamController<bool>.broadcast);
  }

  @override
  Stream<bool> connectionState(String deviceId) =>
      _connections
          .putIfAbsent(deviceId, StreamController<bool>.broadcast)
          .stream;

  @override
  Future<void> disconnect(String deviceId) async {
    setConnected(deviceId, false);
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

  void addMove(SmartCubeMoveEvent event) => _moveController.add(event);

  void setConnected(String deviceId, bool connected) {
    _connections
        .putIfAbsent(deviceId, StreamController<bool>.broadcast)
        .add(connected);
  }

  Future<void> dispose() async {
    await _scanController.close();
    await _moveController.close();
    await _stateController.close();
    for (final controller in _connections.values) {
      await controller.close();
    }
  }
}
