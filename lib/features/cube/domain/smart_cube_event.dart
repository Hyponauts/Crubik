import 'cube_model.dart';

sealed class SmartCubeEvent {
  const SmartCubeEvent({required this.serial, required this.receivedAt});

  final int serial;
  final DateTime receivedAt;
}

final class SmartCubeMoveEvent extends SmartCubeEvent {
  const SmartCubeMoveEvent({
    required this.move,
    required super.serial,
    required super.receivedAt,
    this.cubeTimestamp,
    this.recovered = false,
  });

  final CubeMove move;
  final Duration? cubeTimestamp;
  final bool recovered;
}

final class SmartCubeStateEvent extends SmartCubeEvent {
  const SmartCubeStateEvent({
    required this.state,
    required super.serial,
    required super.receivedAt,
  });

  final CubeState state;
}
