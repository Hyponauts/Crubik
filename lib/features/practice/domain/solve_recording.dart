import '../../cube/domain/cube_model.dart';
import '../../cube/domain/smart_cube_device.dart';
import '../../cube/domain/smart_cube_event.dart';

const solveRecordingFormatVersion = 1;
const adaptiveQuaternionReduction = 'adaptive_quaternion_1deg_v1';

enum RecordingTimingSource {
  cubeClock('cube_clock'),
  hostReceipt('host_receipt'),
  unavailable('unavailable');

  const RecordingTimingSource(this.serializedValue);

  final String serializedValue;
}

extension CubeProtocolFamilyRecordingValue on CubeProtocolFamily {
  String get recordingSerializedValue => switch (this) {
    CubeProtocolFamily.gan => 'gan',
    CubeProtocolFamily.moyuAi2023 => 'moyu_ai_2023',
    CubeProtocolFamily.moyu32 => 'moyu32',
    CubeProtocolFamily.moyuMhc => 'moyu_mhc',
    CubeProtocolFamily.unknown => 'unknown',
  };
}

CubeProtocolFamily cubeProtocolFamilyFromRecordingValue(String value) =>
    switch (value) {
      'gan' => CubeProtocolFamily.gan,
      'moyu_ai_2023' => CubeProtocolFamily.moyuAi2023,
      'moyu32' => CubeProtocolFamily.moyu32,
      'moyu_mhc' => CubeProtocolFamily.moyuMhc,
      _ => CubeProtocolFamily.unknown,
    };

enum RecordingGapReason {
  missedMoves('missed_moves'),
  malformedPacket('malformed_packet'),
  connectionDiscontinuity('connection_discontinuity'),
  stateTransition('state_transition'),
  cubeClockDiscontinuity('cube_clock_discontinuity');

  const RecordingGapReason(this.serializedValue);

  final String serializedValue;

  static RecordingGapReason fromSerializedValue(String value) {
    return values.firstWhere(
      (reason) => reason.serializedValue == value,
      orElse: () => throw FormatException('Unknown recording gap: $value'),
    );
  }
}

sealed class SolveRecordingEvent {
  const SolveRecordingEvent({required this.sequence, required this.hostOffset});

  final int sequence;
  final Duration hostOffset;

  String get serializedType;

  Map<String, Object?> toJson();

  factory SolveRecordingEvent.fromJson(Map<String, Object?> json) {
    final sequence = json['sequence']! as int;
    final hostOffset = Duration(microseconds: json['host_offset_us']! as int);
    return switch (json['type']) {
      'move' => RecordedMove(
        sequence: sequence,
        hostOffset: hostOffset,
        move: CubeMove.parse(json['move']! as String),
        serial: json['serial']! as int,
        recovered: json['recovered']! as bool,
        cubeTimestamp: switch (json['cube_timestamp_us']) {
          final int microseconds => Duration(microseconds: microseconds),
          _ => null,
        },
      ),
      'state' => RecordedState(
        sequence: sequence,
        hostOffset: hostOffset,
        facelets: json['facelets']! as String,
        serial: json['serial']! as int,
      ),
      'orientation' => RecordedOrientation(
        sequence: sequence,
        hostOffset: hostOffset,
        orientation: CubeOrientation.fromJson(
          json['orientation']! as Map<String, Object?>,
        ),
        angularVelocity: switch (json['angular_velocity']) {
          final Map<String, Object?> velocity => CubeAngularVelocity.fromJson(
            velocity,
          ),
          _ => null,
        },
      ),
      'data_gap' => RecordedDataGap(
        sequence: sequence,
        hostOffset: hostOffset,
        reason: RecordingGapReason.fromSerializedValue(
          json['reason']! as String,
        ),
        missingMoveCount: json['missing_move_count'] as int?,
      ),
      _ => throw FormatException('Unknown recording event: ${json['type']}'),
    };
  }
}

final class RecordedMove extends SolveRecordingEvent {
  const RecordedMove({
    required super.sequence,
    required super.hostOffset,
    required this.move,
    required this.serial,
    required this.recovered,
    this.cubeTimestamp,
  });

  final CubeMove move;
  final int serial;
  final bool recovered;
  final Duration? cubeTimestamp;

  @override
  String get serializedType => 'move';

  @override
  Map<String, Object?> toJson() => {
    'type': serializedType,
    'sequence': sequence,
    'host_offset_us': hostOffset.inMicroseconds,
    'move': move.toString(),
    'serial': serial,
    'recovered': recovered,
    'cube_timestamp_us': cubeTimestamp?.inMicroseconds,
  };
}

final class RecordedState extends SolveRecordingEvent {
  const RecordedState({
    required super.sequence,
    required super.hostOffset,
    required this.facelets,
    required this.serial,
  });

  final String facelets;
  final int serial;

  @override
  String get serializedType => 'state';

  @override
  Map<String, Object?> toJson() => {
    'type': serializedType,
    'sequence': sequence,
    'host_offset_us': hostOffset.inMicroseconds,
    'facelets': facelets,
    'serial': serial,
  };
}

final class RecordedOrientation extends SolveRecordingEvent {
  const RecordedOrientation({
    required super.sequence,
    required super.hostOffset,
    required this.orientation,
    this.angularVelocity,
  });

  final CubeOrientation orientation;
  final CubeAngularVelocity? angularVelocity;

  @override
  String get serializedType => 'orientation';

  @override
  Map<String, Object?> toJson() => {
    'type': serializedType,
    'sequence': sequence,
    'host_offset_us': hostOffset.inMicroseconds,
    'orientation': orientation.toJson(),
    'angular_velocity': angularVelocity?.toJson(),
  };
}

final class RecordedDataGap extends SolveRecordingEvent {
  const RecordedDataGap({
    required super.sequence,
    required super.hostOffset,
    required this.reason,
    this.missingMoveCount,
  });

  final RecordingGapReason reason;
  final int? missingMoveCount;

  @override
  String get serializedType => 'data_gap';

  @override
  Map<String, Object?> toJson() => {
    'type': serializedType,
    'sequence': sequence,
    'host_offset_us': hostOffset.inMicroseconds,
    'reason': reason.serializedValue,
    'missing_move_count': missingMoveCount,
  };
}

final class RecordedMoveInterval {
  const RecordedMoveInterval({required this.duration, required this.source});

  final Duration? duration;
  final RecordingTimingSource source;
}

final class SolveRecording {
  factory SolveRecording({
    required CubeProtocolFamily protocolFamily,
    required bool cubeTimestampsAvailable,
    required bool orientationAvailable,
    required List<SolveRecordingEvent> events,
    int formatVersion = solveRecordingFormatVersion,
    String orientationReduction = adaptiveQuaternionReduction,
  }) {
    var previousSequence = -1;
    for (final event in events) {
      if (event.sequence < 0 || event.sequence <= previousSequence) {
        throw ArgumentError.value(
          event.sequence,
          'events',
          'Recording event sequences must be non-negative and strictly increasing.',
        );
      }
      previousSequence = event.sequence;
    }
    return SolveRecording._(
      protocolFamily: protocolFamily,
      cubeTimestampsAvailable: cubeTimestampsAvailable,
      orientationAvailable: orientationAvailable,
      events: List.unmodifiable(events),
      formatVersion: formatVersion,
      orientationReduction: orientationReduction,
    );
  }

  SolveRecording._({
    required this.protocolFamily,
    required this.cubeTimestampsAvailable,
    required this.orientationAvailable,
    required this.events,
    required this.formatVersion,
    required this.orientationReduction,
  });

  final int formatVersion;
  final CubeProtocolFamily protocolFamily;
  final bool cubeTimestampsAvailable;
  final bool orientationAvailable;
  final String orientationReduction;
  final List<SolveRecordingEvent> events;

  factory SolveRecording.fromJson(Map<String, Object?> json) {
    if (json['format_version'] != solveRecordingFormatVersion) {
      throw FormatException(
        'Unsupported recording version: ${json['format_version']}',
      );
    }
    return SolveRecording(
      protocolFamily: cubeProtocolFamilyFromRecordingValue(
        json['protocol_family']! as String,
      ),
      cubeTimestampsAvailable: json['cube_timestamps_available']! as bool,
      orientationAvailable: json['orientation_available']! as bool,
      orientationReduction: json['orientation_reduction']! as String,
      events: [
        for (final event in json['events']! as List<Object?>)
          SolveRecordingEvent.fromJson(event! as Map<String, Object?>),
      ],
    );
  }

  late final List<RecordedMove> moves = List.unmodifiable(
    events.whereType<RecordedMove>(),
  );
  late final List<RecordedMoveInterval> _moveIntervals = _deriveMoveIntervals();

  RecordedMoveInterval intervalForMove(int moveIndex) {
    if (moveIndex < 0 || moveIndex >= moves.length) {
      throw RangeError.index(moveIndex, moves, 'moveIndex');
    }
    return _moveIntervals[moveIndex];
  }

  RecordedMoveInterval get firstMoveFromSolveStart {
    if (moves.isEmpty ||
        moves.first.recovered ||
        moves.first.hostOffset.isNegative) {
      return const RecordedMoveInterval(
        duration: null,
        source: RecordingTimingSource.unavailable,
      );
    }
    return RecordedMoveInterval(
      duration: moves.first.hostOffset,
      source: RecordingTimingSource.hostReceipt,
    );
  }

  Map<String, Object?> toJson({bool includeDerivedTiming = true}) {
    final intervalsBySequence = <int, RecordedMoveInterval>{
      if (includeDerivedTiming)
        for (var index = 0; index < moves.length; index++)
          moves[index].sequence: _moveIntervals[index],
    };
    return {
      'format_version': formatVersion,
      'protocol_family': protocolFamily.recordingSerializedValue,
      'cube_timestamps_available': cubeTimestampsAvailable,
      'orientation_available': orientationAvailable,
      'orientation_reduction': orientationReduction,
      'events': [
        for (final event in events)
          {
            ...event.toJson(),
            if (intervalsBySequence[event.sequence] case final interval?)
              'interval_us': interval.duration?.inMicroseconds,
            if (intervalsBySequence[event.sequence] case final interval?)
              'interval_source': interval.source.serializedValue,
            if (includeDerivedTiming &&
                moves.firstOrNull?.sequence == event.sequence)
              'time_from_solve_start_us':
                  firstMoveFromSolveStart.duration?.inMicroseconds,
            if (includeDerivedTiming &&
                moves.firstOrNull?.sequence == event.sequence)
              'time_from_solve_start_source':
                  firstMoveFromSolveStart.source.serializedValue,
          },
      ],
    };
  }

  List<RecordedMoveInterval> _deriveMoveIntervals() {
    final intervals = <RecordedMoveInterval>[];
    RecordedMove? previousMove;
    var hasGapSincePreviousMove = false;
    for (final event in events) {
      if (event is RecordedDataGap) {
        hasGapSincePreviousMove = true;
        continue;
      }
      if (event is! RecordedMove) continue;

      final previous = previousMove;
      intervals.add(
        previous == null || hasGapSincePreviousMove
            ? const RecordedMoveInterval(
                duration: null,
                source: RecordingTimingSource.unavailable,
              )
            : _intervalBetween(previous, event),
      );
      previousMove = event;
      hasGapSincePreviousMove = false;
    }
    return List.unmodifiable(intervals);
  }

  static RecordedMoveInterval _intervalBetween(
    RecordedMove previous,
    RecordedMove current,
  ) {
    final currentCubeTimestamp = current.cubeTimestamp;
    final previousCubeTimestamp = previous.cubeTimestamp;
    if (currentCubeTimestamp != null &&
        previousCubeTimestamp != null &&
        currentCubeTimestamp >= previousCubeTimestamp) {
      return RecordedMoveInterval(
        duration: currentCubeTimestamp - previousCubeTimestamp,
        source: RecordingTimingSource.cubeClock,
      );
    }
    if (!current.recovered &&
        !previous.recovered &&
        current.hostOffset >= previous.hostOffset) {
      return RecordedMoveInterval(
        duration: current.hostOffset - previous.hostOffset,
        source: RecordingTimingSource.hostReceipt,
      );
    }
    return const RecordedMoveInterval(
      duration: null,
      source: RecordingTimingSource.unavailable,
    );
  }
}
