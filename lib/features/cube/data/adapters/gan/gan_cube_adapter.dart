import 'dart:async';
import 'dart:typed_data';

import '../../../domain/cube_connection_diagnostics.dart';
import '../../../domain/smart_cube_device.dart';
import '../../../domain/smart_cube_event.dart';
import '../../ble/ble_central.dart';
import '../../gan_cube_protocol.dart';
import '../initial_state_handshake.dart';
import '../smart_cube_adapter.dart';

final class GanCubeAdapter implements SmartCubeAdapter {
  const GanCubeAdapter({this.initialStateTimeout = const Duration(seconds: 3)});

  static const adapterId = 'gan-family';

  final Duration initialStateTimeout;

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
          encryptionKey: device.protocolFamily == CubeProtocolFamily.moyuAi2023
              ? GanEncryptionKey.moyuAi2023
              : GanEncryptionKey.gan,
        ),
        initialStateTimeout: initialStateTimeout,
        onDiagnostic: onDiagnostic,
      );
    } catch (_) {
      try {
        await central.disconnect(device.id);
      } catch (_) {
        // Preserve the original setup error when cleanup also fails.
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
    required Duration initialStateTimeout,
    this.onDiagnostic,
  }) : _handshake = InitialStateHandshake(
         timeout: initialStateTimeout,
         failureMessage:
             'The GAN-family cube did not return a valid initial state.',
         onDiagnostic: onDiagnostic,
       );

  final BleCentral _central;
  final String deviceId;
  final GanProtocolDefinition protocol;
  final GanPacketDecoder decoder;
  final GanCubeCipher cipher;
  final CubeDiagnosticSink? onDiagnostic;
  final InitialStateHandshake _handshake;
  final StreamController<SmartCubeEvent> _eventController =
      StreamController.broadcast();
  StreamSubscription<Uint8List>? _valueSubscription;
  Future<void>? _startFuture;
  bool _subscribed = false;
  bool _started = false;
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

  @override
  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    if (_closed) {
      throw const CubeConnectionFailure(
        CubeConnectionFailureCode.connectionFailed,
        'Cannot start a closed GAN-family cube session.',
      );
    }
    onDiagnostic?.call('notifications.subscribe.started', null);
    _valueSubscription = _central
        .characteristicValues(deviceId, protocol.stateCharacteristic)
        .listen(_handleEncryptedPacket, onError: _handleTransportError);
    await _central.subscribe(
      deviceId,
      protocol.service,
      protocol.stateCharacteristic,
    );
    _subscribed = true;
    onDiagnostic?.call('notifications.subscribe.succeeded', null);
    onDiagnostic?.call('protocol.request.started', 'message=state');
    await _sendProtocolCommand(decoder.requestFaceletsCommand);
    onDiagnostic?.call('protocol.request.completed', 'message=state');
    await _handshake.wait();
    if (_closed) {
      throw const CubeConnectionFailure(
        CubeConnectionFailureCode.connectionFailed,
        'The GAN-family cube session closed during startup.',
      );
    }
    _started = true;
  }

  void _handleEncryptedPacket(Uint8List encryptedPacket) {
    if (_closed) return;
    _handshake.recordNotification();
    onDiagnostic?.call(
      'protocol.notification.received',
      'length=${encryptedPacket.length}',
    );
    try {
      final decrypted = cipher.decrypt(encryptedPacket);
      final packet = decoder.decode(decrypted, DateTime.now().toUtc());
      if (packet.kind != GanPacketKind.ignored) {
        _handshake.recordRecognizedPacket();
      }
      onDiagnostic?.call(
        'protocol.message.decoded',
        'message=${packet.kind.name} events=${packet.events.length} '
            'commands=${packet.commands.length}',
      );
      for (final event in packet.events) {
        if (_closed) return;
        _eventController.add(event);
        if (event is SmartCubeStateEvent) _handshake.completeState();
      }
      for (final command in packet.commands) {
        unawaited(
          _sendProtocolCommand(command).onError((error, stackTrace) {
            if (_closed) return;
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
      _handshake.recordRejectedPacket();
      onDiagnostic?.call(
        'protocol.message.rejected',
        'type=${error.runtimeType}',
      );
      final failure = CubeConnectionFailure(
        CubeConnectionFailureCode.packetMalformed,
        'A GAN-family packet could not be decoded: $error',
      );
      if (!_started) {
        _handshake.completeError(failure, stackTrace);
      } else if (!_closed) {
        _eventController.addError(failure, stackTrace);
      }
    }
  }

  void _handleTransportError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    if (!_started) {
      _handshake.completeError(error, stackTrace);
    } else {
      _eventController.addError(error, stackTrace);
    }
  }

  Future<void> _sendProtocolCommand(Uint8List command) => _central.write(
    deviceId,
    protocol.service,
    protocol.commandCharacteristic,
    cipher.encrypt(command),
  );

  @override
  Future<void> requestState() {
    if (!_started || _closed) {
      throw const CubeConnectionFailure(
        CubeConnectionFailureCode.connectionFailed,
        'Cannot request state before GAN-family session startup completes.',
      );
    }
    return _sendProtocolCommand(decoder.requestFaceletsCommand);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _handshake.completeError(
      const CubeConnectionFailure(
        CubeConnectionFailureCode.connectionFailed,
        'The GAN-family cube session closed during startup.',
      ),
    );
    try {
      if (_subscribed) {
        await _central.unsubscribe(
          deviceId,
          protocol.service,
          protocol.stateCharacteristic,
        );
      }
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
