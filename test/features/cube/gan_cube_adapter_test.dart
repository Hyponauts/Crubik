import 'dart:async';
import 'dart:typed_data';

import 'package:crubik/features/cube/application/cube_connection_controller.dart';
import 'package:crubik/features/cube/data/adapters/cube_adapter_registry.dart';
import 'package:crubik/features/cube/data/adapters/gan/gan_cube_adapter.dart';
import 'package:crubik/features/cube/data/adapters/smart_cube_adapter.dart';
import 'package:crubik/features/cube/data/ble/ble_central.dart';
import 'package:crubik/features/cube/data/cube_connection_gateway.dart';
import 'package:crubik/features/cube/data/gan_cube_protocol.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/cube/domain/smart_cube_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GAN adapter publishes initial state after listeners attach', () async {
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
    final eventFuture = session.events.first;
    await session.start();
    final event = await eventFuture;

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

  test(
    'GAN12 ui Maglev uses advertised hardware MAC instead of platform id',
    () async {
      const hardwareMac = '11:22:33:44:55:66';
      final adapter = const GanCubeAdapter();
      final advertisement = BleAdvertisement(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        name: 'GAN12uiM_CBOF',
        rawName: null,
        rssi: -40,
        services: const [ganGen4Service],
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
      final match = adapter.match(advertisement)!;
      final cipher = GanCubeCipher(macSalt: cubeMacSalt(hardwareMac));
      final facelets = Uint8List(20)
        ..[0] = 0xed
        ..[1] = 0x01
        ..[2] = 20;
      _setSolvedCubies(facelets, 32, 53, 69, 113);
      final central = _FakeBleCentral(
        services: const [ganGen4Service],
        responsePacket: cipher.encrypt(facelets),
      );
      final candidate = CubeDeviceCandidate(
        id: advertisement.deviceId,
        name: advertisement.displayName,
        vendor: match.vendor,
        protocolFamily: match.protocolFamily,
        supportStatus: match.supportStatus,
        adapterId: match.adapterId,
        protocolIdentity: match.protocolIdentity,
      );

      final session = await adapter.connect(central, candidate);
      final stateFuture = session.events
          .where((event) => event is SmartCubeStateEvent)
          .cast<SmartCubeStateEvent>()
          .first;
      await session.start();
      final state = await stateFuture;

      expect(match.protocolIdentity?.value, hardwareMac);
      expect(
        match.protocolIdentity?.source,
        CubeProtocolIdentitySource.manufacturerData,
      );
      expect(state.state.isSolved, isTrue);
      expect(central.writes, hasLength(1));

      await session.close();
      await central.close();
    },
  );

  test('GAN adapter times out and cleans up without initial state', () async {
    final central = _FakeBleCentral(services: const [ganGen4Service]);
    final diagnostics = <String>[];

    final session =
        await const GanCubeAdapter(
          initialStateTimeout: Duration(milliseconds: 10),
        ).connect(
          central,
          _supportedGanCandidate(),
          onDiagnostic: (stage, detail) =>
              diagnostics.add(detail == null ? stage : '$stage $detail'),
        );

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

    expect(
      diagnostics,
      contains(
        'handshake.timed_out notifications=0 recognized=0 rejected=0 '
        'states=0',
      ),
    );
    await session.close();
    expect(central.unsubscribed, isTrue);
    expect(central.disconnected, isTrue);
    await central.close();
  });

  test('GAN session startup is idempotent', () async {
    final cipher = GanCubeCipher(macSalt: cubeMacSalt(_macAddress));
    final facelets = Uint8List(20);
    _setBits(facelets, 0, 4, 0x04);
    _setSolvedCubies(facelets, 12, 33, 47, 91);
    final central = _FakeBleCentral(
      services: const [ganGen2Service],
      responsePacket: cipher.encrypt(facelets),
    );
    final session = await const GanCubeAdapter().connect(
      central,
      _supportedGanCandidate(),
    );
    final stateFuture = session.events.first;

    await Future.wait([session.start(), session.start()]);

    expect(await stateFuture, isA<SmartCubeStateEvent>());
    expect(central.writes, hasLength(1));
    await session.close();
    await central.close();
  });

  test(
    'controller receives state and immediate move through the full stack',
    () async {
      const hardwareMac = '11:22:33:44:55:66';
      final cipher = GanCubeCipher(macSalt: cubeMacSalt(hardwareMac));
      final statePacket = Uint8List(20)
        ..[0] = 0xed
        ..[1] = 0x01
        ..[2] = 20;
      _setSolvedCubies(statePacket, 32, 53, 69, 113);
      final movePacket = Uint8List(20)
        ..[0] = 0x01
        ..[1] = 0x08
        ..[2] = 0xd0
        ..[3] = 0x07
        ..[6] = 21
        ..[8] = 0x44;
      final central = _FakeBleCentral(
        services: const [ganGen4Service],
        responsePackets: [
          cipher.encrypt(statePacket),
          cipher.encrypt(movePacket),
        ],
      );
      final registry = CubeAdapterRegistry(const [GanCubeAdapter()]);
      final advertisement = BleAdvertisement(
        deviceId: 'platform-id-not-used-for-encryption',
        name: 'GAN12uiM_CBOF',
        rawName: null,
        rssi: -40,
        services: const [ganGen4Service],
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
      final gateway = BleCubeConnectionGateway(
        central: central,
        registry: registry,
      );
      final controller = CubeConnectionController(gateway: gateway);
      final received = <SmartCubeEvent>[];
      final subscription = controller.events.listen(received.add);

      await controller.connect(registry.identify(advertisement));
      await Future<void>.delayed(Duration.zero);

      expect(controller.status, CubeConnectionStatus.connected);
      expect(received, hasLength(2));
      expect(received[0], isA<SmartCubeStateEvent>());
      expect((received[1] as SmartCubeMoveEvent).move.notation, "B'");
      expect(central.writes, hasLength(1));

      await subscription.cancel();
      await controller.close();
      controller.dispose();
    },
  );

  test(
    'wrong protocol identity produces redacted handshake evidence',
    () async {
      const wrongIdentity = 'AA:BB:CC:DD:EE:FF';
      final wrongCipher = GanCubeCipher(macSalt: cubeMacSalt(wrongIdentity));
      final facelets = Uint8List(20)
        ..[0] = 0xed
        ..[1] = 0x01
        ..[2] = 20;
      _setSolvedCubies(facelets, 32, 53, 69, 113);
      final central = _FakeBleCentral(
        services: const [ganGen4Service],
        responsePacket: wrongCipher.encrypt(facelets),
      );
      final diagnostics = <String>[];
      final session =
          await const GanCubeAdapter(
            initialStateTimeout: Duration(milliseconds: 10),
          ).connect(
            central,
            _supportedGanCandidate(),
            onDiagnostic: (stage, detail) =>
                diagnostics.add(detail == null ? stage : '$stage $detail'),
          );

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

      final report = diagnostics.join('\n');
      expect(report, contains('notifications=1 recognized=0'));
      expect(report, contains('states=0'));
      expect(report, isNot(contains(_macAddress)));
      expect(report, isNot(contains(wrongIdentity)));
      await session.close();
      await central.close();
    },
  );

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
  protocolIdentity: CubeProtocolIdentity(
    value: _macAddress,
    source: CubeProtocolIdentitySource.platformDeviceId,
  ),
);

final class _FakeBleCentral implements BleCentral {
  _FakeBleCentral({
    required this.services,
    this.responsePacket,
    this.responsePackets = const [],
  });

  final List<String> services;
  final Uint8List? responsePacket;
  final List<Uint8List> responsePackets;
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
    for (final packet in responsePackets) {
      _values.add(packet);
    }
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
    target[byteIndex] = valueBit == 1
        ? target[byteIndex] | mask
        : target[byteIndex] & ~mask;
  }
}
