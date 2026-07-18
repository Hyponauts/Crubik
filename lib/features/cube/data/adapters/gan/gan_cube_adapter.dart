import 'dart:async';
import 'dart:typed_data';

import '../../../domain/cube_connection_diagnostics.dart';
import '../../../domain/smart_cube_device.dart';
import '../../../domain/smart_cube_event.dart';
import '../../ble/ble_central.dart';
import '../../gan_cube_protocol.dart';
import '../smart_cube_adapter.dart';

final class GanCubeAdapter implements SmartCubeAdapter {
  const GanCubeAdapter();

  static const adapterId = 'gan-family';

  @override
  String get id => adapterId;

  @override
  CubeDeviceMatch? match(BleAdvertisement advertisement) {
    final name = advertisement.displayName.toUpperCase();
    if (name.startsWith('GAN')) {
      return CubeDeviceMatch(
        vendor: CubeVendor.gan,
        protocolFamily: CubeProtocolFamily.gan,
        supportStatus: CubeSupportStatus.supported,
        adapterId: id,
        macAddress: extractGanMacAddress(advertisement),
      );
    }
    if (name.startsWith('AICUBE') || name.startsWith('MOYU AI')) {
      return CubeDeviceMatch(
        vendor: CubeVendor.moyu,
        protocolFamily: CubeProtocolFamily.moyuAi2023,
        supportStatus: CubeSupportStatus.supported,
        adapterId: id,
        macAddress: extractGanMacAddress(advertisement),
      );
    }
    return null;
  }

  @override
  Future<SmartCubeSession> connect(
    BleCentral central,
    CubeDeviceCandidate device, {
    CubeDiagnosticSink? onDiagnostic,
  }) async {
    onDiagnostic?.call('ble.connect.started', null);
    try {
      await central.connect(device.id);
      onDiagnostic?.call('ble.connect.succeeded', null);
    } catch (_) {
      onDiagnostic?.call('ble.connect.failed', null);
      rethrow;
    }
    _GanCubeSession? session;
    try {
      onDiagnostic?.call('gatt.discovery.started', null);
      final services = await central.discoverServiceUuids(device.id);
      final protocol = ganProtocolForServices(services);
      onDiagnostic?.call(
        'gatt.discovery.succeeded',
        'serviceCount=${services.length} protocolMatched=${protocol != null}',
      );
      if (protocol == null) {
        throw CubeConnectionFailure(
          CubeConnectionFailureCode.unsupportedProtocol,
          'Unsupported GAN/MoYu protocol service for ${device.name}.',
        );
      }
      final macAddress = device.macAddress ?? normalizeCubeMac(device.id);
      if (macAddress == null) {
        onDiagnostic?.call('protocol.identity.unavailable', null);
        throw const CubeConnectionFailure(
          CubeConnectionFailureCode.identityUnavailable,
          'Unable to determine cube MAC address for packet decryption.',
        );
      }
      onDiagnostic?.call('protocol.identity.available', null);
      session = _GanCubeSession(
        central,
        deviceId: device.id,
        protocol: protocol,
        decoder: createGanPacketDecoder(protocol.generation),
        cipher: GanCubeCipher(
          macSalt: cubeMacSalt(macAddress),
          encryptionKey: device.protocolFamily == CubeProtocolFamily.moyuAi2023
              ? GanEncryptionKey.moyuAi2023
              : GanEncryptionKey.gan,
        ),
      );
      await session.initialize();
      return session;
    } catch (_) {
      if (session != null) {
        try {
          await session.close();
        } catch (_) {
          // Preserve the original setup error when cleanup also fails.
        }
      } else {
        try {
          await central.disconnect(device.id);
        } catch (_) {
          // Preserve the original setup error when cleanup also fails.
        }
      }
      rethrow;
    }
  }
}

final class _GanCubeSession implements SmartCubeSession {
  _GanCubeSession(
    this._central, {
    required this.deviceId,
    required this.protocol,
    required this.decoder,
    required this.cipher,
  });

  final BleCentral _central;
  final String deviceId;
  final GanProtocolDefinition protocol;
  final GanPacketDecoder decoder;
  final GanCubeCipher cipher;
  final StreamController<SmartCubeEvent> _eventController = StreamController();
  StreamSubscription<Uint8List>? _valueSubscription;
  bool _closed = false;

  @override
  CubeCapabilities get capabilities => const CubeCapabilities(
    initialState: true,
    moveHistory: true,
    cubeTimestamps: true,
  );

  @override
  Stream<SmartCubeEvent> get events => _eventController.stream;

  @override
  Stream<int> get batteryLevels => const Stream.empty();

  @override
  Stream<bool> get connectionStates => _central.connectionState(deviceId);

  Future<void> initialize() async {
    _valueSubscription = _central
        .characteristicValues(deviceId, protocol.stateCharacteristic)
        .listen(_handleEncryptedPacket, onError: _eventController.addError);
    await _central.subscribe(
      deviceId,
      protocol.service,
      protocol.stateCharacteristic,
    );
    await _sendProtocolCommand(decoder.requestFaceletsCommand);
  }

  void _handleEncryptedPacket(Uint8List encryptedPacket) {
    try {
      final packet = decoder.decode(
        cipher.decrypt(encryptedPacket),
        DateTime.now().toUtc(),
      );
      for (final event in packet.events) {
        _eventController.add(event);
      }
      for (final command in packet.commands) {
        unawaited(
          _sendProtocolCommand(command).onError((error, stackTrace) {
            _eventController.addError(
              CubeConnectionFailure(
                CubeConnectionFailureCode.connectionFailed,
                error?.toString() ?? 'Unknown BLE command error.',
              ),
              stackTrace,
            );
          }),
        );
      }
    } catch (error, stackTrace) {
      _eventController.addError(
        CubeConnectionFailure(
          CubeConnectionFailureCode.packetMalformed,
          'A GAN-family packet could not be decoded: $error',
        ),
        stackTrace,
      );
    }
  }

  Future<void> _sendProtocolCommand(Uint8List command) => _central.write(
    deviceId,
    protocol.service,
    protocol.commandCharacteristic,
    cipher.encrypt(command),
  );

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _central.unsubscribe(
        deviceId,
        protocol.service,
        protocol.stateCharacteristic,
      );
    } catch (_) {
      // The characteristic can already be gone after a link loss.
    }
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    try {
      await _central.disconnect(deviceId);
    } catch (_) {
      // A lost link is already disconnected.
    }
    await _eventController.close();
  }
}

String? extractGanMacAddress(BleAdvertisement advertisement) {
  final deviceIdMac = normalizeCubeMac(advertisement.deviceId);
  if (deviceIdMac != null) return deviceIdMac;
  for (final data in advertisement.manufacturerData) {
    if ((data.companyId & 0xff) != 0x01 || data.payload.length < 6) continue;
    final bytes = data.payload.sublist(data.payload.length - 6).reversed;
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }
  return null;
}
