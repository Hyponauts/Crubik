import 'dart:async';
import 'dart:typed_data';

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
    CubeDeviceCandidate device,
  ) async {
    await central.connect(device.id);
    _Moyu32CubeSession? session;
    try {
      final services = await central.discoverServiceUuids(device.id);
      if (!services.any((service) => service.toLowerCase() == moyu32Service)) {
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
        throw const CubeConnectionFailure(
          CubeConnectionFailureCode.identityUnavailable,
          'Unable to determine the MoYu32 cube MAC address for decryption.',
        );
      }
      session = _Moyu32CubeSession(
        central,
        deviceId: device.id,
        cipher: Moyu32CubeCipher(macSalt: cubeMacSalt(macAddress)),
        decoder: Moyu32PacketDecoder(),
        handshakeTimeout: handshakeTimeout,
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
  });

  final BleCentral _central;
  final String deviceId;
  final Moyu32CubeCipher cipher;
  final Moyu32PacketDecoder decoder;
  final Duration handshakeTimeout;
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
    _valueSubscription = _central
        .characteristicValues(deviceId, moyu32ReadCharacteristic)
        .listen(_handleEncryptedPacket, onError: _handleTransportError);
    await _central.subscribe(deviceId, moyu32Service, moyu32ReadCharacteristic);
    await _sendCommand(decoder.requestStateCommand);
    await _sendCommand(decoder.requestBatteryCommand);
    try {
      await _initialState.future.timeout(handshakeTimeout);
    } on TimeoutException {
      throw const CubeConnectionFailure(
        CubeConnectionFailureCode.connectionFailed,
        'The MoYu32 cube did not return a valid initial state.',
      );
    }
  }

  void _handleEncryptedPacket(Uint8List encryptedPacket) {
    try {
      final decoded = decoder.decode(
        cipher.decrypt(encryptedPacket),
        DateTime.now().toUtc(),
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
