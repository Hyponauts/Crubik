import 'dart:async';
import 'dart:typed_data';

import '../../../domain/cube_connection_diagnostics.dart';
import '../../../domain/smart_cube_device.dart';
import '../../../domain/smart_cube_event.dart';
import '../../ble/ble_central.dart';
import '../../cube_packet_cipher.dart';
import '../../moyu32_cube_protocol.dart';
import '../smart_cube_adapter.dart';

final class Moyu32CubeAdapter implements SmartCubeAdapter {
  const Moyu32CubeAdapter({this.handshakeTimeout = const Duration(seconds: 3)});

  static const adapterId = 'moyu32';

  final Duration handshakeTimeout;

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
      macAddress: extractMoyu32MacAddress(advertisement),
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
    _Moyu32CubeSession? session;
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
      final macAddress =
          device.macAddress ??
          normalizeCubeMac(device.id) ??
          moyu32MacFromName(device.name);
      if (macAddress == null) {
        onDiagnostic?.call('protocol.identity.unavailable', null);
        throw const CubeConnectionFailure(
          CubeConnectionFailureCode.identityUnavailable,
          'Unable to determine the MoYu32 cube MAC address for decryption.',
        );
      }
      onDiagnostic?.call('protocol.identity.available', null);
      session = _Moyu32CubeSession(
        central,
        deviceId: device.id,
        cipher: Moyu32CubeCipher(macSalt: cubeMacSalt(macAddress)),
        decoder: Moyu32PacketDecoder(),
        handshakeTimeout: handshakeTimeout,
        onDiagnostic: onDiagnostic,
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

final class _Moyu32CubeSession implements SmartCubeSession {
  _Moyu32CubeSession(
    this._central, {
    required this.deviceId,
    required this.cipher,
    required this.decoder,
    required this.handshakeTimeout,
    this.onDiagnostic,
  });

  final BleCentral _central;
  final String deviceId;
  final Moyu32CubeCipher cipher;
  final Moyu32PacketDecoder decoder;
  final Duration handshakeTimeout;
  final CubeDiagnosticSink? onDiagnostic;
  final StreamController<SmartCubeEvent> _eventController =
      StreamController.broadcast();
  final StreamController<int> _batteryController = StreamController.broadcast();
  final Completer<void> _initialState = Completer<void>();
  StreamSubscription<Uint8List>? _valueSubscription;
  SmartCubeStateEvent? _initialStateEvent;
  int? _batteryLevel;
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
  Stream<SmartCubeEvent> get events async* {
    final initialStateEvent = _initialStateEvent;
    if (initialStateEvent != null) yield initialStateEvent;
    yield* _eventController.stream;
  }

  @override
  Stream<int> get batteryLevels async* {
    final batteryLevel = _batteryLevel;
    if (batteryLevel != null) yield batteryLevel;
    yield* _batteryController.stream;
  }

  @override
  Stream<bool> get connectionStates => _central.connectionState(deviceId);

  Future<void> initialize() async {
    onDiagnostic?.call('notifications.subscribe.started', null);
    _valueSubscription = _central
        .characteristicValues(deviceId, moyu32ReadCharacteristic)
        .listen(_handleEncryptedPacket, onError: _handleTransportError);
    await _central.subscribe(deviceId, moyu32Service, moyu32ReadCharacteristic);
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
    try {
      await _initialState.future.timeout(handshakeTimeout);
      onDiagnostic?.call('protocol.handshake.succeeded', 'initialState=true');
    } on TimeoutException {
      onDiagnostic?.call('protocol.handshake.timedOut', 'initialState=false');
      throw const CubeConnectionFailure(
        CubeConnectionFailureCode.handshakeFailed,
        'The MoYu32 cube did not return a valid initial state.',
      );
    }
  }

  void _handleEncryptedPacket(Uint8List encryptedPacket) {
    onDiagnostic?.call(
      'protocol.notification.received',
      'length=${encryptedPacket.length}',
    );
    try {
      final decrypted = cipher.decrypt(encryptedPacket);
      final decoded = decoder.decode(decrypted, DateTime.now().toUtc());
      onDiagnostic?.call(
        'protocol.message.decoded',
        _diagnosticMessageType(decrypted.first),
      );
      for (final event in decoded.events) {
        if (event is SmartCubeStateEvent && !_initialState.isCompleted) {
          _initialStateEvent = event;
        }
        _eventController.add(event);
        if (event is SmartCubeStateEvent) {
          _resyncPending = false;
          if (!_initialState.isCompleted) _initialState.complete();
        }
      }
      final batteryLevel = decoded.batteryLevel;
      if (batteryLevel != null) {
        _batteryLevel = batteryLevel;
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
      onDiagnostic?.call(
        'protocol.message.rejected',
        'type=${error.runtimeType}',
      );
      final failure = CubeConnectionFailure(
        CubeConnectionFailureCode.packetMalformed,
        'A MoYu32 packet could not be decoded: $error',
      );
      if (!_initialState.isCompleted) {
        _initialState.completeError(failure, stackTrace);
      } else {
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

  void _handleTransportError(Object error, StackTrace stackTrace) {
    if (!_initialState.isCompleted) {
      _initialState.completeError(error, stackTrace);
    } else {
      _eventController.addError(error, stackTrace);
    }
  }

  void _requestResync() {
    if (_closed || _resyncPending) return;
    _resyncPending = true;
    unawaited(
      _sendCommand(decoder.requestStateCommand).onError((error, stackTrace) {
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
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _central.unsubscribe(
        deviceId,
        moyu32Service,
        moyu32ReadCharacteristic,
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
    await _batteryController.close();
  }
}

String? extractMoyu32MacAddress(BleAdvertisement advertisement) {
  final deviceIdMac = normalizeCubeMac(advertisement.deviceId);
  if (deviceIdMac != null) return deviceIdMac;
  for (final data in advertisement.manufacturerData) {
    if (data.payload.length < 6) continue;
    final bytes = data.payload.sublist(data.payload.length - 6).reversed;
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }
  return moyu32MacFromName(advertisement.displayName);
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
