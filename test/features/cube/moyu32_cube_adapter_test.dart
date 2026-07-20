import 'dart:async';
import 'dart:typed_data';

import 'package:crubik/features/cube/data/adapters/moyu/moyu32_cube_adapter.dart';
import 'package:crubik/features/cube/data/adapters/smart_cube_adapter.dart';
import 'package:crubik/features/cube/data/ble/ble_central.dart';
import 'package:crubik/features/cube/data/cube_packet_cipher.dart';
import 'package:crubik/features/cube/data/moyu32_cube_protocol.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/cube/domain/smart_cube_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'MoYu32 adapter initializes state and battery before connecting',
    () async {
      final cipher = Moyu32CubeCipher(macSalt: cubeMacSalt(_macAddress));
      final central = _FakeBleCentral(
        services: const [moyu32Service],
        cipher: cipher,
        statePacket: _statePacket(CubeState.solved().facelets, serial: 10),
        batteryLevel: 78,
      );
      final diagnostics = <String>[];

      final session = await const Moyu32CubeAdapter().connect(
        central,
        _candidate(),
        onDiagnostic: (stage, detail) =>
            diagnostics.add(detail == null ? stage : '$stage $detail'),
      );
      final eventsFuture = session.events.take(2).toList();
      final batteryFuture = session.batteryLevels.first;
      await session.start();
      await Future<void>.delayed(Duration.zero);
      central.addPacket(_movePacket(serial: 11, moves: ['R'], offsets: [23]));
      final events = await eventsFuture;

      expect((events[0] as SmartCubeStateEvent).state.isSolved, isTrue);
      expect((events[1] as SmartCubeMoveEvent).move.notation, 'R');
      expect(await batteryFuture, 78);
      expect(session.capabilities.initialState, isTrue);
      expect(session.capabilities.moveHistory, isTrue);
      expect(session.capabilities.cubeTimestamps, isTrue);
      expect(session.capabilities.battery, isTrue);
      expect(central.decryptedWrites.map((packet) => packet[0]), [
        0xa1,
        0xa3,
        0xa4,
      ]);
      expect(central.subscribedService, moyu32Service);
      expect(central.subscribedCharacteristic, moyu32ReadCharacteristic);
      expect(
        diagnostics,
        containsAllInOrder([
          'ble.connect.succeeded',
          'gatt.discovery.succeeded serviceCount=1 protocolMatched=true',
          'protocol.identity.available source=platformDeviceId',
          'notifications.subscribe.succeeded',
          'protocol.request.started message=info',
          'protocol.request.completed message=info',
          'protocol.request.started message=state',
          'protocol.message.decoded message=state',
          'protocol.request.completed message=state',
          'handshake.succeeded notifications=2 recognized=2 rejected=0 states=1',
        ]),
      );
      expect(diagnostics.join('\n'), isNot(contains(_macAddress)));

      await session.close();
      expect(central.unsubscribed, isTrue);
      expect(central.disconnected, isTrue);
      await central.close();
    },
  );

  test(
    'MoYu32 adapter reports data loss and requests a state resync',
    () async {
      final cipher = Moyu32CubeCipher(macSalt: cubeMacSalt(_macAddress));
      final central = _FakeBleCentral(
        services: const [moyu32Service],
        cipher: cipher,
        statePacket: _statePacket(CubeState.solved().facelets, serial: 1),
        batteryLevel: 50,
      );
      final session = await const Moyu32CubeAdapter().connect(
        central,
        _candidate(),
      );
      final events = <SmartCubeEvent>[];
      final errors = <Object>[];
      final subscription = session.events.listen(
        events.add,
        onError: errors.add,
      );
      await session.start();
      await Future<void>.delayed(Duration.zero);

      central.addPacket(
        _movePacket(
          serial: 8,
          moves: ['F', 'R', 'U', 'B', 'L'],
          offsets: [5, 5, 5, 5, 5],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(errors.single, isA<CubeConnectionFailure>());
      expect(
        (errors.single as CubeConnectionFailure).code,
        CubeConnectionFailureCode.dataLoss,
      );
      expect(events.whereType<SmartCubeMoveEvent>(), hasLength(5));
      expect(events.whereType<SmartCubeStateEvent>(), hasLength(2));
      expect(central.decryptedWrites.map((packet) => packet[0]), [
        0xa1,
        0xa3,
        0xa4,
        0xa3,
      ]);

      await subscription.cancel();
      await session.close();
      await central.close();
    },
  );

  test(
    'MoYu32 adapter times out and cleans up without initial state',
    () async {
      final cipher = Moyu32CubeCipher(macSalt: cubeMacSalt(_macAddress));
      final central = _FakeBleCentral(
        services: const [moyu32Service],
        cipher: cipher,
        respondToState: false,
      );

      final session = await const Moyu32CubeAdapter(
        initialStateTimeout: Duration(milliseconds: 10),
      ).connect(central, _candidate());

      await expectLater(
        session.start(),
        throwsA(
          isA<CubeConnectionFailure>().having(
            (error) => error.code,
            'code',
            CubeConnectionFailureCode.handshakeFailed,
          ),
        ),
      );

      await session.close();
      expect(central.unsubscribed, isTrue);
      expect(central.disconnected, isTrue);
      await central.close();
    },
  );

  test('MoYu32 adapter disconnects when automatic MAC lookup fails', () async {
    final central = _FakeBleCentral(services: const [moyu32Service]);
    const candidate = CubeDeviceCandidate(
      id: 'platform-device-id',
      name: 'WCU_MY32',
      vendor: CubeVendor.moyu,
      protocolFamily: CubeProtocolFamily.moyu32,
      supportStatus: CubeSupportStatus.supported,
      adapterId: Moyu32CubeAdapter.adapterId,
    );

    await expectLater(
      const Moyu32CubeAdapter().connect(central, candidate),
      throwsA(
        isA<CubeConnectionFailure>().having(
          (error) => error.code,
          'code',
          CubeConnectionFailureCode.identityUnavailable,
        ),
      ),
    );

    expect(central.disconnected, isTrue);
    await central.close();
  });

  test('MoYu32 adapter rejects devices without the expected service', () async {
    final central = _FakeBleCentral(services: const ['unsupported']);

    await expectLater(
      const Moyu32CubeAdapter().connect(central, _candidate()),
      throwsA(
        isA<CubeConnectionFailure>().having(
          (error) => error.code,
          'code',
          CubeConnectionFailureCode.unsupportedProtocol,
        ),
      ),
    );

    expect(central.disconnected, isTrue);
    await central.close();
  });

  test('MoYu32 MAC lookup uses native id, manufacturer data, then name', () {
    final native = _advertisement(
      name: 'WCU_MY32',
      deviceId: 'AA:BB:CC:DD:EE:FF',
    );
    final advertised = _advertisement(
      name: 'WCU_MY32',
      manufacturerData: [
        BleManufacturerData(
          companyId: 0x1200,
          payload: Uint8List.fromList([
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
    final named = _advertisement(name: 'WCU_MY32_ABCD');

    expect(resolveMoyu32ProtocolIdentity(native)?.value, 'AA:BB:CC:DD:EE:FF');
    expect(
      resolveMoyu32ProtocolIdentity(native)?.source,
      CubeProtocolIdentitySource.platformDeviceId,
    );
    expect(
      resolveMoyu32ProtocolIdentity(advertised)?.value,
      '11:22:33:44:55:66',
    );
    expect(
      resolveMoyu32ProtocolIdentity(advertised)?.source,
      CubeProtocolIdentitySource.manufacturerData,
    );
    expect(resolveMoyu32ProtocolIdentity(named)?.value, 'CF:30:16:00:AB:CD');
    expect(
      resolveMoyu32ProtocolIdentity(named)?.source,
      CubeProtocolIdentitySource.advertisedName,
    );
    expect(moyu32MacFromName('WCU_MY32'), isNull);
  });
}

const _macAddress = '11:22:33:44:55:66';

CubeDeviceCandidate _candidate() => const CubeDeviceCandidate(
  id: _macAddress,
  name: 'WCU_MY32_5566',
  vendor: CubeVendor.moyu,
  protocolFamily: CubeProtocolFamily.moyu32,
  supportStatus: CubeSupportStatus.supported,
  adapterId: Moyu32CubeAdapter.adapterId,
  protocolIdentity: CubeProtocolIdentity(
    value: _macAddress,
    source: CubeProtocolIdentitySource.platformDeviceId,
  ),
);

BleAdvertisement _advertisement({
  required String name,
  String deviceId = 'platform-device-id',
  List<BleManufacturerData> manufacturerData = const [],
}) => BleAdvertisement(
  deviceId: deviceId,
  name: name,
  rawName: name,
  rssi: -42,
  services: const [],
  manufacturerData: manufacturerData,
);

final class _FakeBleCentral implements BleCentral {
  _FakeBleCentral({
    required this.services,
    this.cipher,
    this.statePacket,
    this.batteryLevel,
    this.respondToState = true,
  });

  final List<String> services;
  final Moyu32CubeCipher? cipher;
  final Uint8List? statePacket;
  final int? batteryLevel;
  final bool respondToState;
  final _advertisements = StreamController<BleAdvertisement>.broadcast();
  final _values = StreamController<Uint8List>.broadcast();
  final _connectionStates = StreamController<bool>.broadcast();
  final List<Uint8List> decryptedWrites = [];
  bool disconnected = false;
  bool unsubscribed = false;
  String? subscribedService;
  String? subscribedCharacteristic;

  @override
  Stream<BleAdvertisement> get advertisements => _advertisements.stream;

  @override
  Future<bool> isBluetoothAvailable() async => true;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId) async {}

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
    subscribedService = service;
    subscribedCharacteristic = characteristic;
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
    final activeCipher = cipher;
    if (activeCipher == null) return;
    final command = activeCipher.decrypt(value);
    decryptedWrites.add(command);
    if (command[0] == 0xa3 && respondToState) {
      final packet = statePacket;
      if (packet != null) _values.add(activeCipher.encrypt(packet));
    } else if (command[0] == 0xa4 && batteryLevel != null) {
      final packet = Uint8List(20)
        ..[0] = 0xa4
        ..[1] = batteryLevel!;
      _values.add(activeCipher.encrypt(packet));
    }
  }

  void addPacket(Uint8List packet) {
    _values.add(cipher!.encrypt(packet));
  }

  @override
  Future<void> close() async {
    await _advertisements.close();
    await _values.close();
    await _connectionStates.close();
  }
}

Uint8List _statePacket(String facelets, {required int serial}) {
  const protocolFaces = 'FBUDLR';
  const canonicalFaceForProtocolFace = [2, 5, 0, 3, 4, 1];
  const stickerIndexes = [0, 1, 2, 3, 5, 6, 7, 8];
  final packet = Uint8List(20)..[0] = 0xa3;
  for (var protocolFace = 0; protocolFace < 6; protocolFace++) {
    final canonicalFace = canonicalFaceForProtocolFace[protocolFace];
    for (var sticker = 0; sticker < 8; sticker++) {
      final symbol = facelets[canonicalFace * 9 + stickerIndexes[sticker]];
      _setBits(
        packet,
        8 + protocolFace * 24 + sticker * 3,
        3,
        protocolFaces.indexOf(symbol),
      );
    }
  }
  packet[19] = serial;
  return packet;
}

Uint8List _movePacket({
  required int serial,
  required List<String> moves,
  required List<int> offsets,
}) {
  const protocolFaces = 'FBUDLR';
  final packet = Uint8List(20)
    ..[0] = 0xa5
    ..[11] = serial;
  for (var index = 0; index < moves.length; index++) {
    final move = moves[index];
    final code =
        protocolFaces.indexOf(move[0]) * 2 + (move.endsWith("'") ? 1 : 0);
    _setBits(packet, 8 + index * 16, 16, offsets[index]);
    _setBits(packet, 96 + index * 5, 5, code);
  }
  return packet;
}

void _setBits(Uint8List target, int startBit, int bitLength, int value) {
  for (var index = 0; index < bitLength; index++) {
    final absoluteBit = startBit + index;
    final valueBit = (value >> (bitLength - 1 - index)) & 1;
    final mask = 1 << (7 - absoluteBit % 8);
    final byteIndex = absoluteBit ~/ 8;
    target[byteIndex] = valueBit == 1
        ? target[byteIndex] | mask
        : target[byteIndex] & ~mask;
  }
}
