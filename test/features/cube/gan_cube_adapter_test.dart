import 'dart:async';
import 'dart:typed_data';

import 'package:crubik/features/cube/data/adapters/gan/gan_cube_adapter.dart';
import 'package:crubik/features/cube/data/ble/ble_central.dart';
import 'package:crubik/features/cube/data/gan_cube_protocol.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/cube/domain/smart_cube_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GAN adapter preserves an initial state emitted during setup', () async {
    final cipher = GanCubeCipher(macSalt: cubeMacSalt(_macAddress));
    final facelets = Uint8List(20);
    _setBits(facelets, 0, 4, 0x04);
    _setBits(facelets, 4, 8, 10);
    _setSolvedCubies(facelets, 12, 33, 47, 91);
    final central = _FakeBleCentral(
      services: const [ganGen2Service],
      responsePacket: cipher.encrypt(facelets),
    );

    final session = await const GanCubeAdapter().connect(
      central,
      _supportedGanCandidate(),
    );
    final event = await session.events.first;

    expect((event as SmartCubeStateEvent).state.isSolved, isTrue);
    expect(session.capabilities.initialState, isTrue);
    expect(session.capabilities.moveHistory, isTrue);
    expect(central.subscribed, isTrue);
    expect(central.writes, hasLength(1));

    await session.close();
    expect(central.unsubscribed, isTrue);
    expect(central.disconnected, isTrue);
    await central.close();
  });

  test('GAN adapter disconnects when no supported service is found', () async {
    final central = _FakeBleCentral(services: const ['unsupported']);

    await expectLater(
      const GanCubeAdapter().connect(central, _supportedGanCandidate()),
      throwsA(isA<Exception>()),
    );

    expect(central.connected, isTrue);
    expect(central.disconnected, isTrue);
    await central.close();
  });
}

const _macAddress = '11:22:33:44:55:66';

CubeDeviceCandidate _supportedGanCandidate() => const CubeDeviceCandidate(
  id: _macAddress,
  name: 'GAN12ui',
  vendor: CubeVendor.gan,
  protocolFamily: CubeProtocolFamily.gan,
  supportStatus: CubeSupportStatus.supported,
  adapterId: GanCubeAdapter.adapterId,
  macAddress: _macAddress,
);

final class _FakeBleCentral implements BleCentral {
  _FakeBleCentral({required this.services, this.responsePacket});

  final List<String> services;
  final Uint8List? responsePacket;
  final _advertisements = StreamController<BleAdvertisement>.broadcast();
  final _values = StreamController<Uint8List>.broadcast();
  final _connectionStates = StreamController<bool>.broadcast();
  final List<Uint8List> writes = [];
  bool connected = false;
  bool disconnected = false;
  bool subscribed = false;
  bool unsubscribed = false;

  @override
  Stream<BleAdvertisement> get advertisements => _advertisements.stream;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId) async {
    connected = true;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnected = true;
  }

  @override
  Stream<bool> connectionState(String deviceId) => _connectionStates.stream;

  @override
  Future<List<String>> discoverServiceUuids(String deviceId) async => services;

  @override
  Stream<Uint8List> characteristicValues(
    String deviceId,
    String characteristic,
  ) => _values.stream;

  @override
  Future<void> subscribe(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    subscribed = true;
  }

  @override
  Future<void> unsubscribe(
    String deviceId,
    String service,
    String characteristic,
  ) async {
    unsubscribed = true;
  }

  @override
  Future<void> write(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
  ) async {
    writes.add(Uint8List.fromList(value));
    final response = responsePacket;
    if (response != null) _values.add(response);
  }

  @override
  Future<void> close() async {
    await _advertisements.close();
    await _values.close();
    await _connectionStates.close();
  }
}

void _setSolvedCubies(
  Uint8List target,
  int cornerPermutationStart,
  int cornerOrientationStart,
  int edgePermutationStart,
  int edgeOrientationStart,
) {
  for (var index = 0; index < 7; index++) {
    _setBits(target, cornerPermutationStart + index * 3, 3, index);
    _setBits(target, cornerOrientationStart + index * 2, 2, 0);
  }
  for (var index = 0; index < 11; index++) {
    _setBits(target, edgePermutationStart + index * 4, 4, index);
    _setBits(target, edgeOrientationStart + index, 1, 0);
  }
}

void _setBits(Uint8List target, int startBit, int bitLength, int value) {
  for (var index = 0; index < bitLength; index++) {
    final absoluteBit = startBit + index;
    final valueBit = (value >> (bitLength - 1 - index)) & 1;
    final mask = 1 << (7 - absoluteBit % 8);
    final byteIndex = absoluteBit ~/ 8;
    target[byteIndex] =
        valueBit == 1 ? target[byteIndex] | mask : target[byteIndex] & ~mask;
  }
}
