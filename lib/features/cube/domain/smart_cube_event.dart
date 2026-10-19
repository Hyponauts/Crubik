import 'dart:math' as math;

import 'cube_model.dart';
import 'smart_cube_device.dart';

final class CubeOrientation {
  const CubeOrientation({
    required this.x,
    required this.y,
    required this.z,
    required this.w,
  });

  final double x;
  final double y;
  final double z;
  final double w;

  factory CubeOrientation.fromJson(Map<String, Object?> json) =>
      CubeOrientation(
        x: (json['x']! as num).toDouble(),
        y: (json['y']! as num).toDouble(),
        z: (json['z']! as num).toDouble(),
        w: (json['w']! as num).toDouble(),
      );

  CubeOrientation? normalized({CubeOrientation? alignedWith}) {
    if (![x, y, z, w].every((component) => component.isFinite)) return null;
    final magnitude = math.sqrt(x * x + y * y + z * z + w * w);
    if (magnitude <= 1e-12) return null;
    var normalized = CubeOrientation(
      x: x / magnitude,
      y: y / magnitude,
      z: z / magnitude,
      w: w / magnitude,
    );
    if (alignedWith != null && normalized.dot(alignedWith) < 0) {
      normalized = CubeOrientation(
        x: -normalized.x,
        y: -normalized.y,
        z: -normalized.z,
        w: -normalized.w,
      );
    }
    return normalized;
  }

  double dot(CubeOrientation other) =>
      x * other.x + y * other.y + z * other.z + w * other.w;

  double angularDistanceRadians(CubeOrientation other) {
    final absoluteDot = dot(other).abs().clamp(0.0, 1.0);
    return 2 * math.acos(absoluteDot);
  }

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'z': z, 'w': w};
}

final class CubeAngularVelocity {
  const CubeAngularVelocity({
    required this.x,
    required this.y,
    required this.z,
    required this.unit,
  });

  final double x;
  final double y;
  final double z;
  final String unit;

  factory CubeAngularVelocity.fromJson(Map<String, Object?> json) =>
      CubeAngularVelocity(
        x: (json['x']! as num).toDouble(),
        y: (json['y']! as num).toDouble(),
        z: (json['z']! as num).toDouble(),
        unit: json['unit']! as String,
      );

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'z': z, 'unit': unit};
}

sealed class SmartCubeEvent {
  const SmartCubeEvent({required this.receivedAt, required this.hostTimestamp});

  final DateTime receivedAt;
  final Duration hostTimestamp;
}

/// A move or authoritative state update that can advance practice.
sealed class SmartCubeUpdate extends SmartCubeEvent {
  const SmartCubeUpdate({
    required super.receivedAt,
    required super.hostTimestamp,
  });
}

final class SmartCubeMoveEvent extends SmartCubeUpdate {
  const SmartCubeMoveEvent({
    required this.move,
    required this.serial,
    required super.receivedAt,
    required super.hostTimestamp,
    this.cubeTimestamp,
    this.recovered = false,
  });

  final CubeMove move;
  final int serial;
  final Duration? cubeTimestamp;
  final bool recovered;
}

final class SmartCubeStateEvent extends SmartCubeUpdate {
  const SmartCubeStateEvent({
    required this.state,
    required this.serial,
    required super.receivedAt,
    required super.hostTimestamp,
  });

  final CubeState state;
  final int serial;
}

final class SmartCubeOrientationEvent extends SmartCubeEvent {
  const SmartCubeOrientationEvent({
    required this.orientation,
    required super.receivedAt,
    required super.hostTimestamp,
    this.angularVelocity,
  });

  final CubeOrientation orientation;
  final CubeAngularVelocity? angularVelocity;
}

final class SmartCubeCapabilitiesEvent extends SmartCubeEvent {
  const SmartCubeCapabilitiesEvent({
    required this.capabilities,
    required super.receivedAt,
    required super.hostTimestamp,
  });

  final CubeCapabilities capabilities;
}

enum SmartCubeDataGapReason {
  missedMoves,
  malformedPacket,
  connectionDiscontinuity,
  cubeClockDiscontinuity,
}

final class SmartCubeDataGapEvent extends SmartCubeEvent {
  const SmartCubeDataGapEvent({
    required this.reason,
    required super.receivedAt,
    required super.hostTimestamp,
    this.missingMoveCount,
  });

  final SmartCubeDataGapReason reason;
  final int? missingMoveCount;
}
