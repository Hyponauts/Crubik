import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

final class BleManufacturerData {
  BleManufacturerData({required this.companyId, required Uint8List payload})
    : payload = Uint8List.fromList(payload);

  final int companyId;
  final Uint8List payload;
}

final class BleAdvertisement {
  BleAdvertisement({
    required this.deviceId,
    required this.name,
    required this.rawName,
    required this.rssi,
    required this.services,
    required this.manufacturerData,
  });

  factory BleAdvertisement.fromDevice(BleDevice device) => BleAdvertisement(
    deviceId: device.deviceId,
    name: device.name,
    rawName: device.rawName,
    rssi: device.rssi,
    services: List.unmodifiable(device.services),
    manufacturerData: List.unmodifiable(
      device.manufacturerDataList.map(
        (data) => BleManufacturerData(
          companyId: data.companyId,
          payload: data.payload,
        ),
      ),
    ),
  );

  final String deviceId;
  final String? name;
  final String? rawName;
  final int? rssi;
  final List<String> services;
  final List<BleManufacturerData> manufacturerData;

  String get displayName {
    final sanitizedName = name?.trim();
    if (sanitizedName != null && sanitizedName.isNotEmpty) {
      return sanitizedName;
    }
    final advertisedName = rawName?.trim();
    if (advertisedName != null && advertisedName.isNotEmpty) {
      return advertisedName;
    }
    return 'Unnamed Bluetooth device';
  }
}

abstract interface class BleCentral {
  Stream<BleAdvertisement> get advertisements;

  Future<bool> hasPermissions();

  Future<void> requestPermissions();

  Future<void> startScan();

  Future<void> stopScan();

  Future<void> connect(String deviceId);

  Future<void> disconnect(String deviceId);

  Stream<bool> connectionState(String deviceId);

  Future<List<String>> discoverServiceUuids(String deviceId);

  Stream<Uint8List> characteristicValues(
    String deviceId,
    String characteristic,
  );

  Future<void> subscribe(
    String deviceId,
    String service,
    String characteristic,
  );

  Future<void> unsubscribe(
    String deviceId,
    String service,
    String characteristic,
  );

  Future<void> write(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
  );

  Future<void> close();
}

final class UniversalBleCentral implements BleCentral {
  UniversalBleCentral() {
    _scanSubscription = UniversalBle.scanStream.listen(
      (device) =>
          _advertisementController.add(BleAdvertisement.fromDevice(device)),
      onError: _advertisementController.addError,
    );
  }

  final StreamController<BleAdvertisement> _advertisementController =
      StreamController.broadcast();
  late final StreamSubscription<BleDevice> _scanSubscription;

  @override
  Stream<BleAdvertisement> get advertisements =>
      _advertisementController.stream;

  @override
  Future<bool> hasPermissions() => UniversalBle.hasPermissions();

  @override
  Future<void> requestPermissions() => UniversalBle.requestPermissions();

  @override
  Future<void> startScan() => UniversalBle.startScan();

  @override
  Future<void> stopScan() => UniversalBle.stopScan();

  @override
  Future<void> connect(String deviceId) => UniversalBle.connect(
    deviceId,
    timeout: const Duration(seconds: 15),
    autoConnect: true,
  );

  @override
  Future<void> disconnect(String deviceId) => UniversalBle.disconnect(deviceId);

  @override
  Stream<bool> connectionState(String deviceId) =>
      UniversalBle.connectionStream(deviceId);

  @override
  Future<List<String>> discoverServiceUuids(String deviceId) async {
    final services = await UniversalBle.discoverServices(
      deviceId,
      timeout: const Duration(seconds: 10),
    );
    return services.map((service) => service.uuid).toList(growable: false);
  }

  @override
  Stream<Uint8List> characteristicValues(
    String deviceId,
    String characteristic,
  ) => UniversalBle.characteristicValueStream(deviceId, characteristic);

  @override
  Future<void> subscribe(
    String deviceId,
    String service,
    String characteristic,
  ) => UniversalBle.subscribeNotifications(
    deviceId,
    service,
    characteristic,
    timeout: const Duration(seconds: 10),
  );

  @override
  Future<void> unsubscribe(
    String deviceId,
    String service,
    String characteristic,
  ) => UniversalBle.unsubscribe(deviceId, service, characteristic);

  @override
  Future<void> write(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
  ) => UniversalBle.write(deviceId, service, characteristic, value);

  @override
  Future<void> close() async {
    await _scanSubscription.cancel();
    await _advertisementController.close();
  }
}
