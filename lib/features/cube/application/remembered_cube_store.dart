final class RememberedCube {
  const RememberedCube({required this.deviceId, this.name});

  final String deviceId;
  final String? name;
}

/// Local preference boundary for automatic smart-cube reconnect.
abstract interface class RememberedCubeStore {
  Future<RememberedCube?> load();

  Future<void> save(RememberedCube cube);
}
