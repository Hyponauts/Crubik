import 'dart:async';
import 'dart:typed_data';

import '../../../../../core/time/monotonic_clock.dart';
import '../../../application/cube_connection_gateway.dart';
import '../../../domain/cube_connection_diagnostics.dart';
import '../../../domain/smart_cube_device.dart';
import '../../../domain/smart_cube_event.dart';
import '../../ble/ble_central.dart';
import '../../gan_cube_protocol.dart';
import '../ble_adapter_setup.dart';
import '../ble_smart_cube_session.dart';
import '../smart_cube_adapter.dart';

final class GanCubeAdapter implements SmartCubeAdapter {
  const GanCubeAdapter({this.initialStateTimeout = const Duration(seconds: 3)});

  static const adapterId = 'gan-family';

  final Duration initialStateTimeout;

  @override
  String get id => adapterId;

  @override
  List<String> get supportedProtocolDisplayNames => const [
    'GAN Gen2–4',
    'MoYu AI 2023',
  ];

  @override
  CubeDeviceMatch? match(BleAdvertisement advertisement) {
    final name = advertisement.displayName.toUpperCase();
    if (name.startsWith('GAN')) {
      return CubeDeviceMatch(
        vendor: CubeVendor.gan,
        protocolFamily: CubeProtocolFamily.gan,
        supportStatus: CubeSupportStatus.supported,
        adapterId: id,
        protocolIdentity: resolveGanProtocolIdentity(advertisement),
      );
    }
    if (name.startsWith('AICUBE') || name.startsWith('MOYU AI')) {
      return CubeDeviceMatch(
        vendor: CubeVendor.moyu,
        protocolFamily: CubeProtocolFamily.moyuAi2023,
        supportStatus: CubeSupportStatus.supported,
        adapterId: id,
        protocolIdentity: resolveGanProtocolIdentity(advertisement),
      );
    }
    return null;
  }

  @override
  Future<SmartCubeSession> connect(
    BleCentral central,
    CubeDeviceCandidate device, {
    required MonotonicClock monotonicClock,
    CubeDiagnosticSink? onDiagnostic,
  }) async {
    return connectAndSetUpBleDevice(
      central: central,
      deviceId: device.id,
      onDiagnostic: onDiagnostic,
      resolveProtocol: ganProtocolForServices,
      unsupportedFailure: () => CubeConnectionFailure(
        CubeConnectionFailureCode.unsupportedProtocol,
        'Unsupported GAN/MoYu protocol service for ${device.name}.',
      ),
      createSession: (protocol) {
        final identity =
            device.protocolIdentity ?? _platformGanProtocolIdentity(device.id);
        if (identity == null) {
          onDiagnostic?.call('protocol.identity.unavailable', null);
          throw const CubeConnectionFailure(
            CubeConnectionFailureCode.identityUnavailable,
            'Unable to determine cube MAC address for packet decryption.',
          );
        }
        onDiagnostic?.call(
          'protocol.identity.available',
          'source=${identity.source.name}',
        );
        return _GanCubeSession(
          central,
          deviceId: device.id,
          protocol: protocol,
          decoder: createGanPacketDecoder(protocol.generation),
          cipher: GanCubeCipher(
            macSalt: cubeMacSalt(identity.value),
            encryptionKey:
                device.protocolFamily == CubeProtocolFamily.moyuAi2023
                ? GanEncryptionKey.moyuAi2023
                : GanEncryptionKey.gan,
          ),
          initialStateTimeout: initialStateTimeout,
          monotonicClock: monotonicClock,
          onDiagnostic: onDiagnostic,
        );
      },
    );
  }
}

final class _GanCubeSession extends BleSmartCubeSession {
  _GanCubeSession(
    super.central, {
    required super.deviceId,
    required this.protocol,
    required this.decoder,
    required this.cipher,
    required super.monotonicClock,
    required super.initialStateTimeout,
    super.onDiagnostic,
  }) : super(
         service: protocol.service,
         readCharacteristic: protocol.stateCharacteristic,
         handshakeFailureMessage:
             'The GAN-family cube did not return a valid initial state.',
         sessionLabel: 'GAN-family',
       );

  final GanProtocolDefinition protocol;
  final GanPacketDecoder decoder;
  final GanCubeCipher cipher;
  CubeCapabilities _capabilities = const CubeCapabilities(
    initialState: true,
    moveHistory: true,
    cubeTimestamps: true,
  );

  @override
  CubeCapabilities get capabilities => _capabilities;

  @override
  Future<void> sendInitialRequests() async {
    onDiagnostic?.call('protocol.request.started', 'message=state');
    await _sendProtocolCommand(decoder.requestFaceletsCommand);
    onDiagnostic?.call('protocol.request.completed', 'message=state');
    onDiagnostic?.call('protocol.request.started', 'message=hardware');
    try {
      await _sendProtocolCommand(decoder.requestHardwareCommand);
      onDiagnostic?.call('protocol.request.completed', 'message=hardware');
    } catch (error) {
      onDiagnostic?.call(
        'protocol.request.optional-failed',
        'message=hardware type=${error.runtimeType}',
      );
    }
  }

  @override
  void handleEncryptedPacket(Uint8List encryptedPacket) {
    if (isClosed) return;
    final receivedAt = DateTime.now().toUtc();
    final hostTimestamp = monotonicClock.now;
    handshake.recordNotification();
    onDiagnostic?.call(
      'protocol.notification.received',
      'length=${encryptedPacket.length}',
    );
    try {
      final decrypted = cipher.decrypt(encryptedPacket);
      final packet = decoder.decode(
        decrypted,
        receivedAt,
        hostTimestamp: hostTimestamp,
      );
      if (packet.kind != GanPacketKind.ignored) {
        handshake.recordRecognizedPacket();
      }
      onDiagnostic?.call(
        'protocol.message.decoded',
        'message=${packet.kind.name} events=${packet.events.length} '
            'commands=${packet.commands.length}',
      );
      for (final event in packet.events) {
        if (isClosed) return;
        if (event case SmartCubeCapabilitiesEvent(:final capabilities)) {
          _capabilities = capabilities;
        }
        emitEvent(event);
        if (event is SmartCubeStateEvent) handshake.completeState();
      }
      for (final command in packet.commands) {
        unawaited(
          _sendProtocolCommand(command).onError((error, stackTrace) {
            if (isClosed) return;
            emitEvent(
              SmartCubeDataGapEvent(
                reason: SmartCubeDataGapReason.missedMoves,
                receivedAt: receivedAt,
                hostTimestamp: hostTimestamp,
              ),
            );
            emitError(
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
      if (isStarted) {
        emitEvent(
          SmartCubeDataGapEvent(
            reason: SmartCubeDataGapReason.malformedPacket,
            receivedAt: receivedAt,
            hostTimestamp: hostTimestamp,
          ),
        );
      }
      handshake.recordRejectedPacket();
      onDiagnostic?.call(
        'protocol.message.rejected',
        'type=${error.runtimeType}',
      );
      final failure = CubeConnectionFailure(
        CubeConnectionFailureCode.packetMalformed,
        'A GAN-family packet could not be decoded: $error',
      );
      routePacketFailure(failure, stackTrace);
    }
  }

  Future<void> _sendProtocolCommand(Uint8List command) => central.write(
    deviceId,
    protocol.service,
    protocol.commandCharacteristic,
    cipher.encrypt(command),
  );

  @override
  Future<void> requestState() {
    ensureStartedForStateRequest();
    return _sendProtocolCommand(decoder.requestFaceletsCommand);
  }
}

CubeProtocolIdentity? resolveGanProtocolIdentity(
  BleAdvertisement advertisement,
) {
  for (final data in advertisement.manufacturerData) {
    if ((data.companyId & 0xff) != 0x01 || data.payload.length < 6) continue;
    // GAN places the hardware identity used for AES key salting in the last
    // six bytes of its nine-byte manufacturer payload. The platform BLE
    // address can be private or otherwise differ from this identity.
    final payload = data.payload.take(9).toList(growable: false);
    final bytes = payload.sublist(payload.length - 6).reversed;
    return CubeProtocolIdentity(
      value: _formatGanIdentity(bytes),
      source: CubeProtocolIdentitySource.manufacturerData,
    );
  }
  return _platformGanProtocolIdentity(advertisement.deviceId);
}

CubeProtocolIdentity? _platformGanProtocolIdentity(String deviceId) {
  final value = normalizeCubeMac(deviceId);
  return value == null
      ? null
      : CubeProtocolIdentity(
          value: value,
          source: CubeProtocolIdentitySource.platformDeviceId,
        );
}

String _formatGanIdentity(Iterable<int> bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');
