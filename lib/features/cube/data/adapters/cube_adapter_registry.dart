import '../../application/cube_connection_gateway.dart';
import '../../domain/smart_cube_device.dart';
import '../ble/ble_central.dart';
import 'gan/gan_cube_adapter.dart';
import 'moyu/known_moyu_recognizer.dart';
import 'moyu/moyu32_cube_adapter.dart';
import 'smart_cube_adapter.dart';

final class CubeAdapterRegistry {
  factory CubeAdapterRegistry.defaults() => CubeAdapterRegistry(const [
    // Supported adapters must precede detection-only fallbacks for a vendor.
    GanCubeAdapter(),
    Moyu32CubeAdapter(),
    KnownMoyuRecognizer(),
  ]);

  CubeAdapterRegistry(Iterable<CubeDeviceRecognizer> recognizers)
    : this._(List.unmodifiable(recognizers));

  CubeAdapterRegistry._(this._recognizers)
    : _adapters = {
        for (final recognizer in _recognizers)
          if (recognizer is SmartCubeAdapter) recognizer.id: recognizer,
      };

  final List<CubeDeviceRecognizer> _recognizers;
  final Map<String, SmartCubeAdapter> _adapters;

  List<String> get supportedProtocolDisplayNames => List.unmodifiable(
    _adapters.values
        .expand((adapter) => adapter.supportedProtocolDisplayNames)
        .toSet(),
  );

  CubeDeviceCandidate identify(BleAdvertisement advertisement) {
    CubeDeviceMatch? match;
    for (final recognizer in _recognizers) {
      match = recognizer.match(advertisement);
      if (match != null) break;
    }
    return CubeDeviceCandidate(
      id: advertisement.deviceId,
      name: advertisement.displayName,
      vendor: match?.vendor ?? CubeVendor.unknown,
      protocolFamily: match?.protocolFamily ?? CubeProtocolFamily.unknown,
      supportStatus: match?.supportStatus ?? CubeSupportStatus.unidentified,
      adapterId: match?.adapterId,
      rssi: advertisement.rssi,
      protocolIdentity: match?.protocolIdentity,
      supportMessage: match?.supportMessage,
    );
  }

  SmartCubeAdapter adapterFor(CubeDeviceCandidate device) {
    final adapterId = device.adapterId;
    final adapter = adapterId == null ? null : _adapters[adapterId];
    if (adapter == null) {
      throw const CubeConnectionFailure(
        CubeConnectionFailureCode.unsupportedProtocol,
        'This smart-cube protocol is not supported.',
      );
    }
    return adapter;
  }
}
