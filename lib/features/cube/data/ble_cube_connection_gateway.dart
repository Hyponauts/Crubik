import 'dart:async';

import '../application/cube_connection_gateway.dart';
import '../domain/cube_connection_diagnostics.dart';
import '../domain/smart_cube_device.dart';
import 'adapters/cube_adapter_registry.dart';
import 'ble/ble_central.dart';

final class BleCubeConnectionGateway implements CubeConnectionGateway {
  BleCubeConnectionGateway({BleCentral? central, CubeAdapterRegistry? registry})
    : _central = central ?? UniversalBleCentral(),
      _registry = registry ?? CubeAdapterRegistry.defaults() {
    _advertisementSubscription = _central.advertisements.listen(
      (advertisement) => _scanController.add(_registry.identify(advertisement)),
      onError: _scanController.addError,
    );
  }

  final BleCentral _central;
  final CubeAdapterRegistry _registry;
  final StreamController<CubeDeviceCandidate> _scanController =
      StreamController.broadcast();
  late final StreamSubscription<BleAdvertisement> _advertisementSubscription;
  bool _closed = false;

  @override
  Stream<CubeDeviceCandidate> get scanResults => _scanController.stream;

  @override
  List<String> get supportedProtocolDisplayNames =>
      _registry.supportedProtocolDisplayNames;

  @override
  Future<bool> isBluetoothAvailable() => _central.isBluetoothAvailable();

  @override
  Future<bool> hasPermissions() => _central.hasPermissions();

  @override
  Future<void> requestPermissions() => _central.requestPermissions();

  @override
  Future<void> startScan() => _central.startScan();

  @override
  Future<void> stopScan() => _central.stopScan();

  @override
  Future<SmartCubeSession> connect(
    CubeDeviceCandidate device, {
    CubeDiagnosticSink? onDiagnostic,
  }) {
    final adapter = _registry.adapterFor(device);
    onDiagnostic?.call('adapter.selected', adapter.id);
    return adapter.connect(_central, device, onDiagnostic: onDiagnostic);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _central.stopScan();
    } catch (_) {
      // The platform can report an error when no scan is active.
    }
    await _advertisementSubscription.cancel();
    await _scanController.close();
    await _central.close();
  }
}
