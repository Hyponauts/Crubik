import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/cube_connection_diagnostics.dart';
import '../domain/smart_cube_device.dart';
import '../domain/smart_cube_event.dart';
import 'cube_connection_gateway.dart';
import 'remembered_cube_store.dart';

enum CubeConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

enum AutomaticReconnectPhase { inactive, searching, connecting }

final class CubeConnectionController extends ChangeNotifier {
  static const defaultScanTimeout = Duration(seconds: 7);

  factory CubeConnectionController({
    required CubeConnectionGateway gateway,
    RememberedCubeStore? rememberedCubeStore,
    Duration scanTimeout = defaultScanTimeout,
  }) => CubeConnectionController._(gateway, rememberedCubeStore, scanTimeout);

  CubeConnectionController._(
    this._gateway,
    this.rememberedCubeStore,
    this.scanTimeout,
  ) {
    _scanSubscription = _gateway.scanResults.listen(
      _onScanResult,
      onError: _onScanError,
    );
  }

  final CubeConnectionGateway _gateway;
  final RememberedCubeStore? rememberedCubeStore;
  final Duration scanTimeout;
  late final StreamSubscription<CubeDeviceCandidate> _scanSubscription;
  StreamSubscription<SmartCubeEvent>? _sessionEventSubscription;
  StreamSubscription<int>? _batterySubscription;
  StreamSubscription<bool>? _connectionSubscription;
  final StreamController<SmartCubeEvent> _eventController =
      StreamController.broadcast();
  final CubeConnectionDiagnostics _diagnostics = CubeConnectionDiagnostics();
  Future<void> _scanOperations = Future.value();
  Timer? _scanTimeout;
  SmartCubeSession? _session;
  bool _closed = false;
  var _scanAttempt = 0;
  var _connectionAttempt = 0;
  String? _automaticReconnectDeviceId;
  String? _automaticReconnectDeviceName;
  AutomaticReconnectPhase _automaticReconnectPhase =
      AutomaticReconnectPhase.inactive;

  final Map<String, CubeDeviceCandidate> _discovered = {};
  CubeConnectionStatus _status = CubeConnectionStatus.disconnected;
  String? _connectingDeviceId;
  ConnectedCube? _connectedCube;
  SmartCubeStateEvent? _latestStateEvent;
  int? _batteryLevel;
  String? _errorMessage;

  CubeConnectionStatus get status => _status;
  String? get connectingDeviceId => _connectingDeviceId;
  ConnectedCube? get connectedCube => _connectedCube;
  SmartCubeStateEvent? get latestStateEvent => _latestStateEvent;
  int? get batteryLevel => _batteryLevel;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == CubeConnectionStatus.connected;
  AutomaticReconnectPhase get automaticReconnectPhase =>
      _automaticReconnectPhase;
  String? get automaticReconnectDeviceName => _automaticReconnectDeviceName;
  Stream<SmartCubeEvent> get events => _eventController.stream;
  List<String> get supportedProtocolDisplayNames =>
      _gateway.supportedProtocolDisplayNames;
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

  Future<void> reconnectRememberedCube() async {
    final store = rememberedCubeStore;
    if (store == null ||
        _closed ||
        kIsWeb ||
        (_status != CubeConnectionStatus.disconnected &&
            _status != CubeConnectionStatus.error)) {
      return;
    }
    final scanAttempt = ++_scanAttempt;

    RememberedCube? rememberedCube;
    try {
      rememberedCube = await store.load();
    } catch (_) {
      return;
    }
    if (rememberedCube == null ||
        rememberedCube.deviceId.isEmpty ||
        !_isCurrentScanAttempt(scanAttempt)) {
      return;
    }
    final deviceId = rememberedCube.deviceId;

    try {
      final hasPermissions = await _gateway.hasPermissions();
      if (!hasPermissions || !_isCurrentScanAttempt(scanAttempt)) {
        return;
      }
      final bluetoothAvailable = await _gateway.isBluetoothAvailable();
      if (!bluetoothAvailable || !_isCurrentScanAttempt(scanAttempt)) {
        return;
      }
      _automaticReconnectDeviceId = deviceId;
      final rememberedName = rememberedCube.name?.trim();
      _automaticReconnectDeviceName =
          rememberedName == null || rememberedName.isEmpty
          ? null
          : rememberedName;
      _automaticReconnectPhase = AutomaticReconnectPhase.searching;
      _connectingDeviceId = null;
      _errorMessage = null;
      _discovered.clear();
      _status = CubeConnectionStatus.scanning;
      notifyListeners();
      await _startPlatformScan();
      if (!_isCurrentScanAttempt(scanAttempt) ||
          _automaticReconnectDeviceId != deviceId) {
        await _stopLateScanIfUnused();
        return;
      }
      _armScanTimeout();
    } catch (_) {
      if (!_isCurrentScanAttempt(scanAttempt)) return;
      await _stopPlatformScan();
      _clearAutomaticReconnect();
      if (!_closed) {
        _status = CubeConnectionStatus.disconnected;
        notifyListeners();
      }
    }
  }

  Future<void> startScan() async {
    if (_status == CubeConnectionStatus.connecting || _closed) return;
    final scanAttempt = ++_scanAttempt;
    _connectionAttempt++;
    _clearAutomaticReconnect();
    _connectingDeviceId = null;
    _errorMessage = null;
    _discovered.clear();
    _status = CubeConnectionStatus.scanning;
    notifyListeners();

    try {
      var hasPermissions = await _gateway.hasPermissions();
      if (!_isCurrentScanAttempt(scanAttempt)) return;
      if (!hasPermissions) {
        await _gateway.requestPermissions();
        if (!_isCurrentScanAttempt(scanAttempt)) return;
        hasPermissions = await _gateway.hasPermissions();
      }
      if (!_isCurrentScanAttempt(scanAttempt)) return;
      if (!hasPermissions) {
        throw const CubeConnectionFailure(
          CubeConnectionFailureCode.permissionDenied,
          'Bluetooth permission was not granted.',
        );
      }
      await _startPlatformScan();
      if (!_isCurrentScanAttempt(scanAttempt)) {
        await _stopLateScanIfUnused();
        return;
      }
      _armScanTimeout();
    } catch (error) {
      if (!_isCurrentScanAttempt(scanAttempt)) return;
      await _stopPlatformScan();
      _status = CubeConnectionStatus.error;
      _errorMessage = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> stopScan() => _stopScan(cancelAutomaticReconnect: true);

  void _armScanTimeout() {
    _scanTimeout?.cancel();
    _scanTimeout = Timer(scanTimeout, stopScan);
  }

  Future<void> stopAutomaticReconnect() async {
    if (_automaticReconnectPhase != AutomaticReconnectPhase.searching) return;
    await stopScan();
  }

  Future<void> _stopScan({required bool cancelAutomaticReconnect}) async {
    final scanAttempt = ++_scanAttempt;
    _scanTimeout?.cancel();
    _scanTimeout = null;
    if (cancelAutomaticReconnect) {
      _clearAutomaticReconnect();
    } else {
      _automaticReconnectDeviceId = null;
    }
    await _stopPlatformScan();
    if (!_isCurrentScanAttempt(scanAttempt)) return;
    if (_status == CubeConnectionStatus.scanning) {
      _status = CubeConnectionStatus.disconnected;
      notifyListeners();
    }
  }

  bool _isCurrentScanAttempt(int scanAttempt) =>
      !_closed && scanAttempt == _scanAttempt;

  Future<void> _stopLateScanIfUnused() async {
    if (_status == CubeConnectionStatus.scanning) return;
    await _stopPlatformScan();
  }

  Future<void> _startPlatformScan() =>
      _scheduleScanOperation(_gateway.startScan);

  Future<void> _stopPlatformScan() async {
    try {
      await _scheduleScanOperation(_gateway.stopScan);
    } catch (_) {
      // Some platforms report an error when a scan already ended.
    }
  }

  Future<void> _scheduleScanOperation(Future<void> Function() operation) {
    final scheduled = _scanOperations.then((_) => operation());
    _scanOperations = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  Future<void> connect(CubeDeviceCandidate device) =>
      _connect(device, automaticReconnect: false);

  Future<void> _connect(
    CubeDeviceCandidate device, {
    required bool automaticReconnect,
  }) async {
    final connectionAttempt = ++_connectionAttempt;
    await _stopScan(cancelAutomaticReconnect: !automaticReconnect);
    if (_closed || connectionAttempt != _connectionAttempt) return;
    _errorMessage = null;
    _diagnostics.begin(platform: _platformName, device: device);
    if (!device.canConnect) {
      _diagnostics.add('connection.rejected', 'unsupported candidate');
      _status = CubeConnectionStatus.error;
      _clearAutomaticReconnect();
      _errorMessage =
          device.supportMessage ??
          (device.isIdentifiedCube
              ? 'This smart-cube protocol is not supported.'
              : 'This Bluetooth device was not identified as a smart cube.');
      notifyListeners();
      return;
    }
    await _releaseActiveSession();
    if (_closed || connectionAttempt != _connectionAttempt) return;
    _prepareConnection(device);

    SmartCubeSession? openingSession;
    try {
      final session = await _gateway.connect(
        device,
        onDiagnostic: _diagnostics.add,
      );
      openingSession = session;
      if (_closed || connectionAttempt != _connectionAttempt) {
        _clearAutomaticReconnect();
        _diagnostics.add('connection.cancelled', 'request superseded');
        await session.close();
        return;
      }
      _session = session;
      await _bindSession(session);
      await session.start();
      if (_closed ||
          connectionAttempt != _connectionAttempt ||
          !identical(_session, session)) {
        return;
      }
      _finishConnection(device, session);
      await _saveRememberedCube(device);
    } catch (error) {
      if (openingSession != null && !identical(_session, openingSession)) {
        return;
      }
      await _failConnection(error);
    }
  }

  void _prepareConnection(CubeDeviceCandidate device) {
    _clearConnectionSnapshot();
    _connectingDeviceId = device.id;
    _status = CubeConnectionStatus.connecting;
    notifyListeners();
  }

  Future<void> _bindSession(SmartCubeSession session) async {
    await _sessionEventSubscription?.cancel();
    _sessionEventSubscription = session.events.listen((event) {
      if (_closed || !identical(_session, session)) return;
      if (event case final SmartCubeStateEvent stateEvent) {
        _latestStateEvent = stateEvent;
      }
      _eventController.add(event);
    }, onError: _onProtocolError);
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
  }

  void _finishConnection(CubeDeviceCandidate device, SmartCubeSession session) {
    _connectedCube = ConnectedCube.bluetooth(device, session.capabilities);
    _connectingDeviceId = null;
    _status = CubeConnectionStatus.connected;
    _clearAutomaticReconnect();
    _diagnostics.add('connection.ready');
    notifyListeners();
  }

  Future<void> _saveRememberedCube(CubeDeviceCandidate device) async {
    final store = rememberedCubeStore;
    if (store == null) return;
    try {
      await store.save(RememberedCube(deviceId: device.id, name: device.name));
      _diagnostics.add('remembered-device.saved');
    } catch (error) {
      _diagnostics.add(
        'remembered-device.save-failed',
        'type=${error.runtimeType}',
      );
    }
  }

  Future<void> _failConnection(Object error) async {
    _diagnostics.add('connection.failed', _diagnosticError(error));
    await _releaseActiveSession();
    _clearConnectionSnapshot();
    _status = CubeConnectionStatus.error;
    _clearAutomaticReconnect();
    _errorMessage = _friendlyError(error);
    notifyListeners();
  }

  Future<void> disconnect() async {
    _scanAttempt++;
    _connectionAttempt++;
    _clearAutomaticReconnect();
    _clearConnectionSnapshot(clearError: true);
    _status = CubeConnectionStatus.disconnected;
    notifyListeners();
    await _releaseActiveSession();
  }

  Future<void> _handleLinkLoss(SmartCubeSession session) async {
    if (!identical(_session, session)) return;
    _session = null;
    _clearConnectionSnapshot();
    _status = CubeConnectionStatus.disconnected;
    _clearAutomaticReconnect();
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _sessionEventSubscription?.cancel();
    _sessionEventSubscription = null;
    await _batterySubscription?.cancel();
    _batterySubscription = null;
    await session.close();
    if (!_closed) notifyListeners();
  }

  void _clearConnectionSnapshot({bool clearError = false}) {
    _connectingDeviceId = null;
    _connectedCube = null;
    _latestStateEvent = null;
    _batteryLevel = null;
    if (clearError) _errorMessage = null;
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
    final shouldReconnect =
        _automaticReconnectDeviceId == device.id && device.canConnect;
    if (shouldReconnect) {
      _automaticReconnectDeviceId = null;
      _automaticReconnectDeviceName = device.name;
      _automaticReconnectPhase = AutomaticReconnectPhase.connecting;
    }
    notifyListeners();
    if (shouldReconnect) {
      unawaited(_connect(device, automaticReconnect: true));
    }
  }

  void _onScanError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _status = CubeConnectionStatus.error;
    _clearAutomaticReconnect();
    _errorMessage = _friendlyError(error);
    notifyListeners();
  }

  void _onProtocolError(Object error, StackTrace stackTrace) {
    if (_closed) return;
    _diagnostics.add('protocol.error', _diagnosticError(error));
    _errorMessage = _friendlyError(error);
    notifyListeners();
  }

  void _clearAutomaticReconnect() {
    _automaticReconnectDeviceId = null;
    _automaticReconnectDeviceName = null;
    _automaticReconnectPhase = AutomaticReconnectPhase.inactive;
  }

  static int _compareDevices(CubeDeviceCandidate a, CubeDeviceCandidate b) {
    if (a.isIdentifiedCube != b.isIdentifiedCube) {
      return a.isIdentifiedCube ? -1 : 1;
    }
    return (b.rssi ?? -100).compareTo(a.rssi ?? -100);
  }

  static String get _platformName =>
      kIsWeb ? 'web' : defaultTargetPlatform.name;

  static const _permissionMessage =
      'Bluetooth permission is required to find your cube. Enable Nearby devices in Android Settings, then scan again.';
  static const _bluetoothUnavailableMessage =
      'Turn Bluetooth on, then try scanning again.';
  static const _identityUnavailableMessage =
      'Crubik could not read this cube identity. Wake it, scan again, and keep it close.';
  static const _handshakeFailedMessage =
      'Bluetooth connected, but the cube did not return a valid initial state. Copy the diagnostics below and try again.';
  static const _packetMalformedMessage =
      'A cube packet could not be decoded. The live state may need resyncing.';
  static const _dataLossMessage =
      'Some cube moves were missed. Crubik requested the current physical state to resync.';
  static const _connectionFailedMessage =
      'Could not connect to the cube. Please wake it and try again.';

  static String _diagnosticError(Object error) => error is CubeConnectionFailure
      ? 'code=${error.code.name}'
      : 'type=${error.runtimeType}';

  static String _friendlyError(Object error) {
    if (error is CubeConnectionFailure) {
      return _messageForFailure(error);
    }
    final message = error.toString().toLowerCase();
    if (message.contains('permission')) return _permissionMessage;
    if (message.contains('powered') || message.contains('available')) {
      return _bluetoothUnavailableMessage;
    }
    return _connectionFailedMessage;
  }

  static String _messageForFailure(CubeConnectionFailure failure) =>
      switch (failure.code) {
        CubeConnectionFailureCode.permissionDenied => _permissionMessage,
        CubeConnectionFailureCode.bluetoothUnavailable =>
          _bluetoothUnavailableMessage,
        CubeConnectionFailureCode.unsupportedProtocol => failure.message,
        CubeConnectionFailureCode.identityUnavailable =>
          _identityUnavailableMessage,
        CubeConnectionFailureCode.handshakeFailed => _handshakeFailedMessage,
        CubeConnectionFailureCode.packetMalformed => _packetMalformedMessage,
        CubeConnectionFailureCode.dataLoss => _dataLossMessage,
        CubeConnectionFailureCode.connectionFailed => _connectionFailedMessage,
      };

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _scanAttempt++;
    _connectionAttempt++;
    _clearAutomaticReconnect();
    _scanTimeout?.cancel();
    await _scanSubscription.cancel();
    await _stopPlatformScan();
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
