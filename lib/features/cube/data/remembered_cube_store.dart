final class RememberedCube {
  const RememberedCube({required this.deviceId, this.name});

  final String deviceId;
  final String? name;
}

abstract interface class RememberedCubeStore {
  Future<RememberedCube?> load();

  Future<void> save(RememberedCube cube);
}
