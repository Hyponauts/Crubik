import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/adapters/smart_cube_adapter.dart';
import '../data/cube_connection_gateway.dart';
import '../domain/cube_connection_diagnostics.dart';
import '../domain/smart_cube_device.dart';
import '../domain/smart_cube_event.dart';

enum CubeConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

final class CubeConnectionController extends ChangeNotifier {
  CubeConnectionController({CubeConnectionGateway? gateway})
    : _gateway = gateway ?? BleCubeConnectionGateway() {
    _scanSubscription = _gateway.scanResults.listen(
      _onScanResult,
      onError: _onScanError,
    );
  }

  final CubeConnectionGateway _gateway;
  late final StreamSubscription<CubeDeviceCandidate> _scanSubscription;
  StreamSubscription<SmartCubeEvent>? _sessionEventSubscription;
  StreamSubscription<int>? _batterySubscription;
  StreamSubscription<bool>? _connectionSubscription;
  final StreamController<SmartCubeEvent> _eventController =
      StreamController.broadcast();
  final CubeConnectionDiagnostics _diagnostics = CubeConnectionDiagnostics();
  Timer? _scanTimeout;
  SmartCubeSession? _session;
  bool _closed = false;

  final Map<String, CubeDeviceCandidate> _discovered = {};
  CubeConnectionStatus _status = CubeConnectionStatus.disconnected;
  String? _connectingDeviceId;
  ConnectedCube? _connectedCube;
  int? _batteryLevel;
  String? _errorMessage;

  CubeConnectionStatus get status => _status;
  String? get connectingDeviceId => _connectingDeviceId;
  ConnectedCube? get connectedCube => _connectedCube;
  int? get batteryLevel => _batteryLevel;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == CubeConnectionStatus.connected;
  bool get isDemo => _connectedCube?.isDemo ?? false;
  Stream<SmartCubeEvent> get events => _eventController.stream;
  bool get hasDiagnostics => _diagnostics.isNotEmpty;
  String get diagnosticReport => _diagnostics.exportReport();

  List<CubeDeviceCandidate> get discoveredDevices {
    final devices = _discovered.values.toList()..sort(_compareDevices);
    return List.unmodifiable(devices);
  }

  List<CubeDeviceCandidate> get discoveredCubes => List.unmodifiable(
    discoveredDevices.where((device) => device.isIdentifiedCube),
  );

  List<CubeDeviceCandidate> get otherDiscoveredDevices => List.unmodifiable(
    discoveredDevices.where((device) => !device.isIdentifiedCube),
  );

  Future<void> startScan() async {
    if (_status == CubeConnectionStatus.connecting || _closed) return;
    _connectingDeviceId = null;
    _errorMessage = null;
    _discovered.clear();
    _status = CubeConnectionStatus.scanning;
    notifyListeners();

    try {
      if (!await _gateway.hasPermissions()) {
        await _gateway.requestPermissions();
      }
      if (!await _gateway.hasPermissions()) {
        throw const CubeConnectionFailure(
          CubeConnectionFailureCode.permissionDenied,
          'Bluetooth permission was not granted.',
        );
      }
      await _gateway.startScan();
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
      await _gateway.stopScan();
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
    _diagnostics.begin(platform: _platformName, device: device);
    if (!device.canConnect) {
      _diagnostics.add('connection.rejected', 'unsupported candidate');
      _status = CubeConnectionStatus.error;
      _errorMessage =
          device.supportMessage ??
          (device.isIdentifiedCube
              ? 'This smart-cube protocol is not supported.'
              : 'This Bluetooth device was not identified as a smart cube.');
      notifyListeners();
      return;
    }
    await _releaseActiveSession();
    _connectedCube = null;
    _batteryLevel = null;
    _connectingDeviceId = device.id;
    _status = CubeConnectionStatus.connecting;
    notifyListeners();

    try {
      final session = await _gateway.connect(
        device,
        onDiagnostic: _diagnostics.add,
      );
      if (_closed) {
        _diagnostics.add('connection.cancelled', 'controller closed');
        await session.close();
        return;
      }
      _session = session;
      _connectedCube = ConnectedCube.bluetooth(device, session.capabilities);
      await _sessionEventSubscription?.cancel();
      _sessionEventSubscription = session.events.listen(
        _eventController.add,
        onError: _onProtocolError,
      );
      await _batterySubscription?.cancel();
      _batterySubscription = session.batteryLevels.listen((batteryLevel) {
        if (_closed || !identical(_session, session)) return;
        _batteryLevel = batteryLevel;
        notifyListeners();
      }, onError: _onProtocolError);
      await _connectionSubscription?.cancel();
      _connectionSubscription = session.connectionStates.listen((connected) {
        if (!connected && identical(_session, session)) {
          unawaited(_handleLinkLoss(session));
        }
      });
      _connectingDeviceId = null;
      _status = CubeConnectionStatus.connected;
      _diagnostics.add('connection.ready');
      notifyListeners();
    } catch (error) {
      _diagnostics.add('connection.failed', _diagnosticError(error));
      await _releaseActiveSession();
      _connectedCube = null;
      _batteryLevel = null;
      _connectingDeviceId = null;
      _status = CubeConnectionStatus.error;
      _errorMessage = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> connectDemo() async {
    _scanTimeout?.cancel();
    await stopScan();
    await _releaseActiveSession();
    if (_closed) return;
    _connectingDeviceId = null;
    _connectedCube = const ConnectedCube.demo();
    _batteryLevel = null;
    _errorMessage = null;
    _status = CubeConnectionStatus.connected;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _connectingDeviceId = null;
    _connectedCube = null;
    _batteryLevel = null;
    _errorMessage = null;
    _status = CubeConnectionStatus.disconnected;
    notifyListeners();
    await _releaseActiveSession();
  }

  Future<void> _handleLinkLoss(SmartCubeSession session) async {
    if (!identical(_session, session)) return;
    _session = null;
    _connectingDeviceId = null;
    _connectedCube = null;
    _batteryLevel = null;
    _status = CubeConnectionStatus.disconnected;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _sessionEventSubscription?.cancel();
    _sessionEventSubscription = null;
    await _batterySubscription?.cancel();
    _batterySubscription = null;
    await session.close();
    if (!_closed) notifyListeners();
  }

  Future<void> _releaseActiveSession() async {
    final session = _session;
    _session = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _sessionEventSubscription?.cancel();
    _sessionEventSubscription = null;
    await _batterySubscription?.cancel();
    _batterySubscription = null;
    await session?.close();
  }

  void _onScanResult(CubeDeviceCandidate device) {
    if (_closed) return;
    _discovered[device.id] = device;
    notifyListeners();
  }

  void _onScanError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _status = CubeConnectionStatus.error;
    _errorMessage = _friendlyError(error);
    notifyListeners();
  }

  void _onProtocolError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _diagnostics.add('protocol.error', _diagnosticError(error));
    _errorMessage = error is CubeConnectionFailure
        ? switch (error.code) {
            CubeConnectionFailureCode.packetMalformed =>
              'A cube packet could not be decoded. The live state may need resyncing.',
            CubeConnectionFailureCode.dataLoss =>
              'Some cube moves were missed. Crubik requested the current physical state to resync.',
            _ => _friendlyError(error),
          }
        : _friendlyError(error);
    notifyListeners();
  }

  static int _compareDevices(CubeDeviceCandidate a, CubeDeviceCandidate b) {
    if (a.isIdentifiedCube != b.isIdentifiedCube) {
      return a.isIdentifiedCube ? -1 : 1;
    }
    return (b.rssi ?? -100).compareTo(a.rssi ?? -100);
  }

  static String get _platformName =>
      kIsWeb ? 'web' : defaultTargetPlatform.name;

  static String _diagnosticError(Object error) => error is CubeConnectionFailure
      ? 'code=${error.code.name}'
      : 'type=${error.runtimeType}';

  static String _friendlyError(Object error) {
    if (error is CubeConnectionFailure) {
      return switch (error.code) {
        CubeConnectionFailureCode.permissionDenied =>
          'Bluetooth permission is required to find your cube. Enable Nearby devices in Android Settings, then scan again.',
        CubeConnectionFailureCode.bluetoothUnavailable =>
          'Turn Bluetooth on, then try scanning again.',
        CubeConnectionFailureCode.unsupportedProtocol => error.message,
        CubeConnectionFailureCode.identityUnavailable =>
          'Crubik could not read this cube identity. Wake it, scan again, and keep it close.',
        CubeConnectionFailureCode.handshakeFailed =>
          'Bluetooth connected, but the cube did not return a valid initial state. Copy the diagnostics below and try again.',
        CubeConnectionFailureCode.packetMalformed =>
          'A cube packet could not be decoded. The live state may need resyncing.',
        CubeConnectionFailureCode.dataLoss =>
          'Some cube moves were missed. Crubik requested the current physical state to resync.',
        CubeConnectionFailureCode.connectionFailed =>
          'Could not connect to the cube. Please wake it and try again.',
      };
    }
    final message = error.toString().toLowerCase();
    if (message.contains('permission')) {
      return 'Bluetooth permission is required to find your cube. Enable Nearby devices in Android Settings, then scan again.';
    }
    if (message.contains('powered') || message.contains('available')) {
      return 'Turn Bluetooth on, then try scanning again.';
    }
    return 'Could not connect to the cube. Please wake it and try again.';
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _scanTimeout?.cancel();
    await _scanSubscription.cancel();
    await _releaseActiveSession();
    await _gateway.close();
    await _eventController.close();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
