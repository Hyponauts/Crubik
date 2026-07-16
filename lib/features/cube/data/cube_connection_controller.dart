import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'gan_cube_protocol.dart';

enum CubeVendor { gan, moyu, unknown, demo }

enum CubeConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

final class CubeDeviceCandidate {
  const CubeDeviceCandidate({
    required this.id,
    required this.name,
    required this.vendor,
    this.rssi,
    this.isDemo = false,
    this.macAddress,
    this.isSupported = true,
    this.supportMessage,
  });

  final String id;
  final String name;
  final CubeVendor vendor;
  final int? rssi;
  final bool isDemo;
  final String? macAddress;
  final bool isSupported;
  final String? supportMessage;

  bool get isIdentifiedCube =>
      vendor == CubeVendor.gan || vendor == CubeVendor.moyu;

  bool get canConnect => isIdentifiedCube && isSupported;
}

final class CubeAdvertisementClassification {
  const CubeAdvertisementClassification({
    required this.vendor,
    required this.isSupported,
    this.supportMessage,
  });

  final CubeVendor vendor;
  final bool isSupported;
  final String? supportMessage;
}

abstract interface class BleCubeTransport {
  Stream<CubeDeviceCandidate> get scanResults;

  Stream<SmartCubeMoveEvent> get moveEvents;

  Stream<SmartCubeStateEvent> get stateEvents;

  Stream<bool> connectionState(String deviceId);

  Future<bool> hasPermissions();

  Future<void> requestPermissions();

  Future<void> startScan();

  Future<void> stopScan();

  Future<void> connect(CubeDeviceCandidate device);

  Future<void> disconnect(String deviceId);
}

final class UniversalBleCubeTransport implements BleCubeTransport {
  UniversalBleCubeTransport() {
    _scanSubscription = UniversalBle.scanStream.listen((device) {
      _scanController.add(cubeDeviceCandidateFromBleDevice(device));
    });
  }

  final StreamController<CubeDeviceCandidate> _scanController =
      StreamController.broadcast();
  final StreamController<SmartCubeMoveEvent> _moveController =
      StreamController.broadcast();
  final StreamController<SmartCubeStateEvent> _stateController =
      StreamController.broadcast();
  late final StreamSubscription<BleDevice> _scanSubscription;
  StreamSubscription<Uint8List>? _moveSubscription;
  GanProtocolDefinition? _activeProtocol;
  GanPacketDecoder? _decoder;
  GanCubeCipher? _cipher;
  String? _activeDeviceId;

  @override
  Stream<CubeDeviceCandidate> get scanResults => _scanController.stream;

  @override
  Stream<SmartCubeMoveEvent> get moveEvents => _moveController.stream;

  @override
  Stream<SmartCubeStateEvent> get stateEvents => _stateController.stream;

  @override
  Stream<bool> connectionState(String deviceId) =>
      UniversalBle.connectionStream(deviceId);

  @override
  Future<bool> hasPermissions() => UniversalBle.hasPermissions();

  @override
  Future<void> requestPermissions() => UniversalBle.requestPermissions();

  @override
  Future<void> startScan() => UniversalBle.startScan();

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(CubeDeviceCandidate device) async {
    await UniversalBle.connect(
      device.id,
      timeout: const Duration(seconds: 15),
      autoConnect: true,
    );

    try {
      final services = await UniversalBle.discoverServices(
        device.id,
        timeout: const Duration(seconds: 10),
      );
      final protocol = ganProtocolForServices(
        services.map((service) => service.uuid),
      );
      if (protocol == null) {
        throw UnsupportedError(
          'Unsupported GAN/MoYu protocol service for ${device.name}.',
        );
      }
      final macAddress = device.macAddress ?? normalizeCubeMac(device.id);
      if (macAddress == null) {
        throw const FormatException(
          'Unable to determine cube MAC address for packet decryption.',
        );
      }

      _activeDeviceId = device.id;
      _activeProtocol = protocol;
      _decoder = createGanPacketDecoder(protocol.generation);
      _cipher = GanCubeCipher(
        macSalt: cubeMacSalt(macAddress),
        useMoyuAiKey: device.vendor == CubeVendor.moyu,
      );

      await _moveSubscription?.cancel();
      _moveSubscription = UniversalBle.characteristicValueStream(
        device.id,
        protocol.stateCharacteristic,
      ).listen(_handleEncryptedPacket, onError: _moveController.addError);
      await UniversalBle.subscribeNotifications(
        device.id,
        protocol.service,
        protocol.stateCharacteristic,
        timeout: const Duration(seconds: 10),
      );
      await _sendProtocolCommand(_decoder!.requestFaceletsCommand);
    } catch (_) {
      await UniversalBle.disconnect(device.id);
      await _clearProtocolSession();
      rethrow;
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final protocol = _activeProtocol;
    if (_activeDeviceId == deviceId && protocol != null) {
      try {
        await UniversalBle.unsubscribe(
          deviceId,
          protocol.service,
          protocol.stateCharacteristic,
        );
      } catch (_) {
        // The characteristic can already be gone after a link loss.
      }
    }
    await _clearProtocolSession();
    await UniversalBle.disconnect(deviceId);
  }

  void _handleEncryptedPacket(Uint8List encryptedPacket) {
    try {
      final decoded = _cipher!.decrypt(encryptedPacket);
      final packet = _decoder!.decode(decoded, DateTime.now().toUtc());
      for (final event in packet.moves) {
        _moveController.add(event);
      }
      for (final event in packet.states) {
        _stateController.add(event);
      }
      for (final command in packet.commands) {
        unawaited(
          _sendProtocolCommand(command).onError((error, stackTrace) {
            _moveController.addError(
              error ?? StateError('Unknown BLE command error.'),
              stackTrace,
            );
          }),
        );
      }
    } catch (error, stackTrace) {
      _moveController.addError(error, stackTrace);
    }
  }

  Future<void> _sendProtocolCommand(Uint8List command) async {
    final deviceId = _activeDeviceId;
    final protocol = _activeProtocol;
    final cipher = _cipher;
    if (deviceId == null || protocol == null || cipher == null) return;
    await UniversalBle.write(
      deviceId,
      protocol.service,
      protocol.commandCharacteristic,
      cipher.encrypt(command),
    );
  }

  Future<void> _clearProtocolSession() async {
    await _moveSubscription?.cancel();
    _moveSubscription = null;
    _activeDeviceId = null;
    _activeProtocol = null;
    _decoder = null;
    _cipher = null;
  }

  Future<void> dispose() async {
    await _clearProtocolSession();
    await _scanSubscription.cancel();
    await _scanController.close();
    await _moveController.close();
    await _stateController.close();
  }
}

CubeDeviceCandidate cubeDeviceCandidateFromBleDevice(BleDevice device) {
  final sanitizedName = device.name?.trim();
  final rawName = device.rawName?.trim();
  final name =
      sanitizedName != null && sanitizedName.isNotEmpty
          ? sanitizedName
          : rawName != null && rawName.isNotEmpty
          ? rawName
          : 'Unnamed Bluetooth device';
  final classification = classifyCubeAdvertisement(name);
  return CubeDeviceCandidate(
    id: device.deviceId,
    name: name,
    vendor: classification?.vendor ?? CubeVendor.unknown,
    rssi: device.rssi,
    macAddress: classification == null ? null : extractGanMacAddress(device),
    isSupported: classification?.isSupported ?? false,
    supportMessage: classification?.supportMessage,
  );
}

CubeAdvertisementClassification? classifyCubeAdvertisement(
  String advertisedName,
) {
  final name = advertisedName.trim().toUpperCase();
  if (name.startsWith('GAN')) {
    return const CubeAdvertisementClassification(
      vendor: CubeVendor.gan,
      isSupported: true,
    );
  }
  if (name.startsWith('AICUBE') || name.startsWith('MOYU AI')) {
    return const CubeAdvertisementClassification(
      vendor: CubeVendor.moyu,
      isSupported: true,
    );
  }
  if (name.startsWith('WCU_MY3')) {
    return const CubeAdvertisementClassification(
      vendor: CubeVendor.moyu,
      isSupported: false,
      supportMessage:
          'This WCU MoYu cube uses the MoYu32 protocol, which is detected but not supported yet.',
    );
  }
  if (name.startsWith('MHC')) {
    return const CubeAdvertisementClassification(
      vendor: CubeVendor.moyu,
      isSupported: false,
      supportMessage:
          'MoYu MHC cubes such as the WeiLong V10 AI are detected, but their protocol is not supported yet.',
    );
  }
  if (name.startsWith('MOYU')) {
    return const CubeAdvertisementClassification(
      vendor: CubeVendor.moyu,
      isSupported: false,
      supportMessage:
          'This MoYu model is detected, but only the MoYu AI 2023 protocol is supported currently.',
    );
  }
  return null;
}

CubeVendor? classifyCubeVendor(String advertisedName) =>
    classifyCubeAdvertisement(advertisedName)?.vendor;

String? extractGanMacAddress(BleDevice device) {
  final deviceIdMac = normalizeCubeMac(device.deviceId);
  if (deviceIdMac != null) return deviceIdMac;
  for (final data in device.manufacturerDataList) {
    if ((data.companyId & 0xff) != 0x01 || data.payload.length < 6) continue;
    final bytes = data.payload.sublist(data.payload.length - 6).reversed;
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }
  return null;
}

String? normalizeCubeMac(String value) {
  final match = RegExp(
    r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  return value.trim().replaceAll('-', ':').toUpperCase();
}

List<int> cubeMacSalt(String macAddress) {
  final normalized = normalizeCubeMac(macAddress);
  if (normalized == null) {
    throw const FormatException('Invalid cube MAC address.');
  }
  return normalized
      .split(':')
      .map((part) => int.parse(part, radix: 16))
      .toList(growable: false)
      .reversed
      .toList(growable: false);
}

final class CubeConnectionController extends ChangeNotifier {
  CubeConnectionController({BleCubeTransport? transport})
    : _transport = transport ?? UniversalBleCubeTransport() {
    _scanSubscription = _transport.scanResults.listen(_onScanResult);
    _moveSubscription = _transport.moveEvents.listen(
      _moveController.add,
      onError: _onProtocolError,
    );
    _stateSubscription = _transport.stateEvents.listen(
      _stateController.add,
      onError: _onProtocolError,
    );
  }

  final BleCubeTransport _transport;
  late final StreamSubscription<CubeDeviceCandidate> _scanSubscription;
  late final StreamSubscription<SmartCubeMoveEvent> _moveSubscription;
  late final StreamSubscription<SmartCubeStateEvent> _stateSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  final StreamController<SmartCubeMoveEvent> _moveController =
      StreamController.broadcast();
  final StreamController<SmartCubeStateEvent> _stateController =
      StreamController.broadcast();
  Timer? _scanTimeout;

  final Map<String, CubeDeviceCandidate> _discovered = {};
  CubeConnectionStatus _status = CubeConnectionStatus.disconnected;
  CubeDeviceCandidate? _connectedDevice;
  String? _errorMessage;

  CubeConnectionStatus get status => _status;
  CubeDeviceCandidate? get connectedDevice => _connectedDevice;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == CubeConnectionStatus.connected;
  bool get isDemo => _connectedDevice?.isDemo ?? false;
  Stream<SmartCubeMoveEvent> get moveEvents => _moveController.stream;
  Stream<SmartCubeStateEvent> get stateEvents => _stateController.stream;
  List<CubeDeviceCandidate> get discoveredDevices {
    final devices =
        _discovered.values.toList()..sort((a, b) {
          if (a.isIdentifiedCube != b.isIdentifiedCube) {
            return a.isIdentifiedCube ? -1 : 1;
          }
          return (b.rssi ?? -100).compareTo(a.rssi ?? -100);
        });
    return List.unmodifiable(devices);
  }

  List<CubeDeviceCandidate> get discoveredCubes => List.unmodifiable(
    discoveredDevices.where((device) => device.isIdentifiedCube),
  );

  List<CubeDeviceCandidate> get otherDiscoveredDevices => List.unmodifiable(
    discoveredDevices.where((device) => !device.isIdentifiedCube),
  );

  Future<void> startScan() async {
    if (_status == CubeConnectionStatus.connecting) return;
    _errorMessage = null;
    _discovered.clear();
    _status = CubeConnectionStatus.scanning;
    notifyListeners();

    try {
      if (!await _transport.hasPermissions()) {
        await _transport.requestPermissions();
      }
      if (!await _transport.hasPermissions()) {
        throw StateError('Bluetooth permission was not granted.');
      }
      await _transport.startScan();
      _scanTimeout?.cancel();
      _scanTimeout = Timer(const Duration(seconds: 7), stopScan);
    } catch (error) {
      _status = CubeConnectionStatus.error;
      _errorMessage = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    _scanTimeout?.cancel();
    _scanTimeout = null;
    try {
      await _transport.stopScan();
    } catch (_) {
      // Some platforms report an error when a scan already ended.
    }
    if (_status == CubeConnectionStatus.scanning) {
      _status = CubeConnectionStatus.disconnected;
      notifyListeners();
    }
  }

  Future<void> connect(CubeDeviceCandidate device) async {
    await stopScan();
    _errorMessage = null;
    if (!device.canConnect) {
      _status = CubeConnectionStatus.error;
      _errorMessage =
          device.supportMessage ??
          (device.isIdentifiedCube
              ? 'This smart-cube protocol is not supported.'
              : 'This Bluetooth device was not identified as a smart cube.');
      notifyListeners();
      return;
    }
    _status = CubeConnectionStatus.connecting;
    notifyListeners();

    try {
      await _transport.connect(device);
      _connectedDevice = device;
      _status = CubeConnectionStatus.connected;
      await _connectionSubscription?.cancel();
      _connectionSubscription = _transport.connectionState(device.id).listen((
        connected,
      ) {
        if (!connected && _connectedDevice?.id == device.id) {
          _connectedDevice = null;
          _status = CubeConnectionStatus.disconnected;
          unawaited(_transport.disconnect(device.id).onError((_, _) {}));
          notifyListeners();
        }
      });
      notifyListeners();
    } catch (error) {
      _connectedDevice = null;
      _status = CubeConnectionStatus.error;
      _errorMessage = _friendlyError(error);
      notifyListeners();
    }
  }

  void connectDemo() {
    _scanTimeout?.cancel();
    unawaited(stopScan());
    _connectedDevice = const CubeDeviceCandidate(
      id: 'demo-cube',
      name: 'Demo cube',
      vendor: CubeVendor.demo,
      rssi: -42,
      isDemo: true,
    );
    _errorMessage = null;
    _status = CubeConnectionStatus.connected;
    notifyListeners();
  }

  Future<void> disconnect() async {
    final device = _connectedDevice;
    _connectedDevice = null;
    _errorMessage = null;
    _status = CubeConnectionStatus.disconnected;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    notifyListeners();

    if (device != null && !device.isDemo) {
      try {
        await _transport.disconnect(device.id);
      } catch (error) {
        _errorMessage = _friendlyError(error);
        notifyListeners();
      }
    }
  }

  void _onScanResult(CubeDeviceCandidate device) {
    _discovered[device.id] = device;
    notifyListeners();
  }

  void _onProtocolError(Object error, StackTrace stackTrace) {
    _errorMessage =
        'A cube packet could not be decoded. The live state may need resyncing.';
    notifyListeners();
  }

  static String _friendlyError(Object error) {
    final message = error.toString();
    if (message.toLowerCase().contains('permission')) {
      return 'Bluetooth permission is required to find your cube. Enable Nearby devices in Android Settings, then scan again.';
    }
    if (message.toLowerCase().contains('powered') ||
        message.toLowerCase().contains('available')) {
      return 'Turn Bluetooth on, then try scanning again.';
    }
    if (message.toLowerCase().contains('mac address')) {
      return 'Crubik could not read this cube identity. Wake it, scan again, and keep it close.';
    }
    if (message.toLowerCase().contains('unsupported')) {
      return 'This cube or firmware does not expose a supported GAN Gen2–4 protocol.';
    }
    return 'Could not connect to the cube. Please wake it and try again.';
  }

  @override
  void dispose() {
    _scanTimeout?.cancel();
    unawaited(_scanSubscription.cancel());
    unawaited(_moveSubscription.cancel());
    unawaited(_stateSubscription.cancel());
    unawaited(_connectionSubscription?.cancel());
    unawaited(_moveController.close());
    unawaited(_stateController.close());
    if (_transport case UniversalBleCubeTransport transport) {
      unawaited(transport.dispose());
    }
    super.dispose();
  }
}
