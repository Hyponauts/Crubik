import 'dart:async';
import 'dart:typed_data';

import '../../../application/cube_connection_gateway.dart';
import '../../../domain/cube_connection_diagnostics.dart';
import '../../../domain/smart_cube_device.dart';
import '../../../domain/smart_cube_event.dart';
import '../../ble/ble_central.dart';
import '../../cube_packet_cipher.dart';
import '../../moyu32_cube_protocol.dart';
import '../ble_adapter_setup.dart';
import '../ble_smart_cube_session.dart';
import '../smart_cube_adapter.dart';

final class Moyu32CubeAdapter implements SmartCubeAdapter {
  const Moyu32CubeAdapter({
    this.initialStateTimeout = const Duration(seconds: 3),
  });

  static const adapterId = 'moyu32';

  final Duration initialStateTimeout;

  @override
  String get id => adapterId;

  @override
  List<String> get supportedProtocolDisplayNames => const ['MoYu32'];

  @override
  CubeDeviceMatch? match(BleAdvertisement advertisement) {
    final name = advertisement.displayName.toUpperCase();
    final hasMoyu32Name = RegExp(r'^WCU_MY32(?:_|$)').hasMatch(name);
    final hasMoyu32Service = advertisement.services.any(
      (service) => service.toLowerCase() == moyu32Service,
    );
    if (!hasMoyu32Name && !hasMoyu32Service) return null;
    return CubeDeviceMatch(
      vendor: CubeVendor.moyu,
      protocolFamily: CubeProtocolFamily.moyu32,
      supportStatus: CubeSupportStatus.supported,
      adapterId: id,
      protocolIdentity: resolveMoyu32ProtocolIdentity(advertisement),
    );
  }

  @override
  Future<SmartCubeSession> connect(
    BleCentral central,
    CubeDeviceCandidate device, {
    CubeDiagnosticSink? onDiagnostic,
  }) async {
    return connectAndSetUpBleDevice(
      central: central,
      deviceId: device.id,
      onDiagnostic: onDiagnostic,
      resolveProtocol: (services) =>
          services.any((service) => service.toLowerCase() == moyu32Service)
          ? moyu32Service
          : null,
      unsupportedFailure: () => CubeConnectionFailure(
        CubeConnectionFailureCode.unsupportedProtocol,
        'The MoYu32 service was not found on ${device.name}.',
      ),
      createSession: (_) {
        final identity =
            device.protocolIdentity ??
            _resolveMoyu32PlatformOrNameIdentity(device.id, device.name);
        if (identity == null) {
          onDiagnostic?.call('protocol.identity.unavailable', null);
          throw const CubeConnectionFailure(
            CubeConnectionFailureCode.identityUnavailable,
            'Unable to determine the MoYu32 cube MAC address for decryption.',
          );
        }
        onDiagnostic?.call(
          'protocol.identity.available',
          'source=${identity.source.name}',
        );
        return _Moyu32CubeSession(
          central,
          deviceId: device.id,
          cipher: Moyu32CubeCipher(macSalt: cubeMacSalt(identity.value)),
          decoder: Moyu32PacketDecoder(),
          initialStateTimeout: initialStateTimeout,
          onDiagnostic: onDiagnostic,
        );
      },
    );
  }
}

final class _Moyu32CubeSession extends BleSmartCubeSession {
  _Moyu32CubeSession(
    super.central, {
    required super.deviceId,
    required this.cipher,
    required this.decoder,
    required super.initialStateTimeout,
    super.onDiagnostic,
  }) : super(
         service: moyu32Service,
         readCharacteristic: moyu32ReadCharacteristic,
         handshakeFailureMessage:
             'The MoYu32 cube did not return a valid initial state.',
         sessionLabel: 'MoYu32',
       );

  final Moyu32CubeCipher cipher;
  final Moyu32PacketDecoder decoder;
  final StreamController<int> _batteryController = StreamController.broadcast();
  bool _resyncPending = false;

  @override
  CubeCapabilities get capabilities => const CubeCapabilities(
    initialState: true,
    moveHistory: true,
    cubeTimestamps: true,
    battery: true,
  );

  @override
  Stream<int> get batteryLevels => _batteryController.stream;

  @override
  Future<void> sendInitialRequests() async {
    // WCU_MY32 cubes require the 0xA1 info request to initialize their
    // protocol session before they will answer state and battery requests.
    onDiagnostic?.call('protocol.request.started', 'message=info');
    await _sendCommand(decoder.requestInfoCommand);
    onDiagnostic?.call('protocol.request.completed', 'message=info');
    onDiagnostic?.call('protocol.request.started', 'message=state');
    await _sendCommand(decoder.requestStateCommand);
    onDiagnostic?.call('protocol.request.completed', 'message=state');
    onDiagnostic?.call('protocol.request.started', 'message=battery');
    await _sendCommand(decoder.requestBatteryCommand);
    onDiagnostic?.call('protocol.request.completed', 'message=battery');
  }

  @override
  void handleEncryptedPacket(Uint8List encryptedPacket) {
    if (isClosed) return;
    handshake.recordNotification();
    onDiagnostic?.call(
      'protocol.notification.received',
      'length=${encryptedPacket.length}',
    );
    try {
      final decrypted = cipher.decrypt(encryptedPacket);
      if (_isRecognizedOpcode(decrypted.first)) {
        handshake.recordRecognizedPacket();
      }
      final decoded = decoder.decode(decrypted, DateTime.now().toUtc());
      onDiagnostic?.call(
        'protocol.message.decoded',
        _diagnosticMessageType(decrypted.first),
      );
      for (final event in decoded.events) {
        if (isClosed) return;
        emitEvent(event);
        if (event is SmartCubeStateEvent) {
          _resyncPending = false;
          handshake.completeState();
        }
      }
      final batteryLevel = decoded.batteryLevel;
      if (batteryLevel != null) {
        _batteryController.add(batteryLevel);
      }
      if (decoded.dataLoss) {
        emitError(
          const CubeConnectionFailure(
            CubeConnectionFailureCode.dataLoss,
            'The MoYu32 move history exceeded its five-move recovery window.',
          ),
        );
        _requestResync();
      }
    } catch (error, stackTrace) {
      handshake.recordRejectedPacket();
      onDiagnostic?.call(
        'protocol.message.rejected',
        'type=${error.runtimeType}',
      );
      final failure = CubeConnectionFailure(
        CubeConnectionFailureCode.packetMalformed,
        'A MoYu32 packet could not be decoded: $error',
      );
      final wasStarted = isStarted;
      routePacketFailure(failure, stackTrace);
      if (wasStarted && !isClosed) _requestResync();
    }
  }

  static String _diagnosticMessageType(int opcode) => switch (opcode) {
    0xa1 => 'message=info',
    0xa3 => 'message=state',
    0xa4 => 'message=battery',
    0xa5 => 'message=moves',
    _ => 'message=unknown',
  };

  static bool _isRecognizedOpcode(int opcode) =>
      opcode == 0xa1 || opcode == 0xa3 || opcode == 0xa4 || opcode == 0xa5;

  void _requestResync() {
    if (isClosed || _resyncPending) return;
    _resyncPending = true;
    unawaited(
      requestState().onError((error, stackTrace) {
        _resyncPending = false;
        if (isClosed) return;
        emitError(
          CubeConnectionFailure(
            CubeConnectionFailureCode.connectionFailed,
            error?.toString() ?? 'Unable to request a MoYu32 state resync.',
          ),
          stackTrace,
        );
      }),
    );
  }

  Future<void> _sendCommand(Uint8List command) => central.write(
    deviceId,
    moyu32Service,
    moyu32WriteCharacteristic,
    cipher.encrypt(command),
  );

  @override
  Future<void> requestState() {
    ensureStartedForStateRequest();
    return _sendCommand(decoder.requestStateCommand);
  }

  @override
  Future<void> closeAdditionalResources() => _batteryController.close();
}

CubeProtocolIdentity? resolveMoyu32ProtocolIdentity(
  BleAdvertisement advertisement,
) {
  final deviceIdMac = normalizeCubeMac(advertisement.deviceId);
  if (deviceIdMac != null) {
    return CubeProtocolIdentity(
      value: deviceIdMac,
      source: CubeProtocolIdentitySource.platformDeviceId,
    );
  }
  for (final data in advertisement.manufacturerData) {
    if (data.payload.length < 6) continue;
    final bytes = data.payload.sublist(data.payload.length - 6).reversed;
    return CubeProtocolIdentity(
      value: bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(':'),
      source: CubeProtocolIdentitySource.manufacturerData,
    );
  }
  return _moyu32NameIdentity(advertisement.displayName);
}

CubeProtocolIdentity? _resolveMoyu32PlatformOrNameIdentity(
  String deviceId,
  String name,
) {
  final deviceIdMac = normalizeCubeMac(deviceId);
  if (deviceIdMac != null) {
    return CubeProtocolIdentity(
      value: deviceIdMac,
      source: CubeProtocolIdentitySource.platformDeviceId,
    );
  }
  return _moyu32NameIdentity(name);
}

CubeProtocolIdentity? _moyu32NameIdentity(String name) {
  final nameIdentity = moyu32MacFromName(name);
  return nameIdentity == null
      ? null
      : CubeProtocolIdentity(
          value: nameIdentity,
          source: CubeProtocolIdentitySource.advertisedName,
        );
}

String? moyu32MacFromName(String name) {
  final match = RegExp(
    r'^WCU_MY32_([0-9A-F]{4})$',
    caseSensitive: false,
  ).firstMatch(name.trim());
  if (match == null) return null;
  final suffix = match.group(1)!.toUpperCase();
  return 'CF:30:16:00:${suffix.substring(0, 2)}:${suffix.substring(2, 4)}';
}
