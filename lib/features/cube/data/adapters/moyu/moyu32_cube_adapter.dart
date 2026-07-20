import 'dart:async';
import 'dart:typed_data';

import '../../../domain/cube_connection_diagnostics.dart';
import '../../../domain/smart_cube_device.dart';
import '../../../domain/smart_cube_event.dart';
import '../../ble/ble_central.dart';
import '../../cube_packet_cipher.dart';
import '../../moyu32_cube_protocol.dart';
import '../initial_state_handshake.dart';
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
      final serviceMatched = services.any(
        (service) => service.toLowerCase() == moyu32Service,
      );
      onDiagnostic?.call(
        'gatt.discovery.succeeded',
        'serviceCount=${services.length} protocolMatched=$serviceMatched',
      );
      if (!serviceMatched) {
        throw CubeConnectionFailure(
          CubeConnectionFailureCode.unsupportedProtocol,
          'The MoYu32 service was not found on ${device.name}.',
        );
      }
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

final class _Moyu32CubeSession implements SmartCubeSession {
  _Moyu32CubeSession(
    this._central, {
    required this.deviceId,
    required this.cipher,
    required this.decoder,
    required Duration initialStateTimeout,
    this.onDiagnostic,
  }) : _handshake = InitialStateHandshake(
         timeout: initialStateTimeout,
         failureMessage:
             'The MoYu32 cube did not return a valid initial state.',
         onDiagnostic: onDiagnostic,
       );

  final BleCentral _central;
  final String deviceId;
  final Moyu32CubeCipher cipher;
  final Moyu32PacketDecoder decoder;
  final CubeDiagnosticSink? onDiagnostic;
  final InitialStateHandshake _handshake;
  final StreamController<SmartCubeEvent> _eventController =
      StreamController.broadcast();
  final StreamController<int> _batteryController = StreamController.broadcast();
  StreamSubscription<Uint8List>? _valueSubscription;
  Future<void>? _startFuture;
  bool _subscribed = false;
  bool _started = false;
  bool _resyncPending = false;
  bool _closed = false;

  @override
  CubeCapabilities get capabilities => const CubeCapabilities(
    initialState: true,
    moveHistory: true,
    cubeTimestamps: true,
    battery: true,
  );

  @override
  Stream<SmartCubeEvent> get events => _eventController.stream;

  @override
  Stream<int> get batteryLevels => _batteryController.stream;

  @override
  Stream<bool> get connectionStates => _central.connectionState(deviceId);

  @override
  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    if (_closed) {
      throw const CubeConnectionFailure(
        CubeConnectionFailureCode.connectionFailed,
        'Cannot start a closed MoYu32 cube session.',
      );
    }
    onDiagnostic?.call('notifications.subscribe.started', null);
    _valueSubscription = _central
        .characteristicValues(deviceId, moyu32ReadCharacteristic)
        .listen(_handleEncryptedPacket, onError: _handleTransportError);
    await _central.subscribe(deviceId, moyu32Service, moyu32ReadCharacteristic);
    _subscribed = true;
    onDiagnostic?.call('notifications.subscribe.succeeded', null);
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
    await _handshake.wait();
    if (_closed) {
      throw const CubeConnectionFailure(
        CubeConnectionFailureCode.connectionFailed,
        'The MoYu32 cube session closed during startup.',
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
      if (_isRecognizedOpcode(decrypted.first)) {
        _handshake.recordRecognizedPacket();
      }
      final decoded = decoder.decode(decrypted, DateTime.now().toUtc());
      onDiagnostic?.call(
        'protocol.message.decoded',
        _diagnosticMessageType(decrypted.first),
      );
      for (final event in decoded.events) {
        if (_closed) return;
        _eventController.add(event);
        if (event is SmartCubeStateEvent) {
          _resyncPending = false;
          _handshake.completeState();
        }
      }
      final batteryLevel = decoded.batteryLevel;
      if (batteryLevel != null) {
        _batteryController.add(batteryLevel);
      }
      if (decoded.dataLoss) {
        _eventController.addError(
          const CubeConnectionFailure(
            CubeConnectionFailureCode.dataLoss,
            'The MoYu32 move history exceeded its five-move recovery window.',
          ),
        );
        _requestResync();
      }
    } catch (error, stackTrace) {
      _handshake.recordRejectedPacket();
      onDiagnostic?.call(
        'protocol.message.rejected',
        'type=${error.runtimeType}',
      );
      final failure = CubeConnectionFailure(
        CubeConnectionFailureCode.packetMalformed,
        'A MoYu32 packet could not be decoded: $error',
      );
      if (!_started) {
        _handshake.completeError(failure, stackTrace);
      } else if (!_closed) {
        _eventController.addError(failure, stackTrace);
        _requestResync();
      }
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

  void _handleTransportError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    if (!_started) {
      _handshake.completeError(error, stackTrace);
    } else {
      _eventController.addError(error, stackTrace);
    }
  }

  void _requestResync() {
    if (_closed || _resyncPending) return;
    _resyncPending = true;
    unawaited(
      requestState().onError((error, stackTrace) {
        _resyncPending = false;
        if (_closed) return;
        _eventController.addError(
          CubeConnectionFailure(
            CubeConnectionFailureCode.connectionFailed,
            error?.toString() ?? 'Unable to request a MoYu32 state resync.',
          ),
          stackTrace,
        );
      }),
    );
  }

  Future<void> _sendCommand(Uint8List command) => _central.write(
    deviceId,
    moyu32Service,
    moyu32WriteCharacteristic,
    cipher.encrypt(command),
  );

  @override
  Future<void> requestState() {
    if (!_started || _closed) {
      throw const CubeConnectionFailure(
        CubeConnectionFailureCode.connectionFailed,
        'Cannot request state before MoYu32 session startup completes.',
      );
    }
    return _sendCommand(decoder.requestStateCommand);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _handshake.completeError(
      const CubeConnectionFailure(
        CubeConnectionFailureCode.connectionFailed,
        'The MoYu32 cube session closed during startup.',
      ),
    );
    try {
      if (_subscribed) {
        await _central.unsubscribe(
          deviceId,
          moyu32Service,
          moyu32ReadCharacteristic,
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
    await _batteryController.close();
  }
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
