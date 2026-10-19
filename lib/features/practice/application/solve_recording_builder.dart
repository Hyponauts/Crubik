import 'dart:math' as math;

import '../../cube/domain/smart_cube_device.dart';
import '../../cube/domain/smart_cube_event.dart';
import '../domain/solve_recording.dart';

/// Builds one solve-relative evidence timeline from normalized smart-cube data.
///
/// The caller owns practice lifecycle decisions. This builder owns capture
/// state, event sequencing, pose reduction, and source capability evidence.
final class SolveRecordingBuilder {
  final List<
    ({RecordingGapReason reason, Duration hostTimestamp, int? missingMoveCount})
  >
  _pendingStartGaps = [];
  final List<SolveRecordingEvent> _events = [];

  CubeProtocolFamily _protocolFamily = CubeProtocolFamily.unknown;
  CubeCapabilities _capabilities = const CubeCapabilities();
  Duration? _origin;
  SmartCubeOrientationEvent? _latestOrientation;
  SmartCubeOrientationEvent? _pendingOrientation;
  CubeOrientation? _lastRetainedOrientation;
  SmartCubeOrientationEvent? _lastRetainedOrientationEvent;
  Duration? _lastCubeTimestamp;
  int _nextSequence = 0;

  void configureSource({
    CubeProtocolFamily? protocolFamily,
    CubeCapabilities? capabilities,
  }) {
    if (protocolFamily != null) _protocolFamily = protocolFamily;
    if (capabilities != null) _capabilities = capabilities;
  }

  /// Clears source metadata, pose history, and any in-progress attempt.
  void resetSource() {
    _protocolFamily = CubeProtocolFamily.unknown;
    _capabilities = const CubeCapabilities();
    _latestOrientation = null;
    discardAttempt();
  }

  /// Drops pose samples that cannot be continuous across a disconnection.
  void clearPose() {
    _latestOrientation = null;
    _pendingOrientation = null;
  }

  void observeOrientation(SmartCubeOrientationEvent event) {
    final previous = _latestOrientation?.orientation;
    final orientation = event.orientation.normalized(alignedWith: previous);
    if (orientation == null) return;
    final normalizedEvent = SmartCubeOrientationEvent(
      orientation: orientation,
      angularVelocity: event.angularVelocity,
      receivedAt: event.receivedAt,
      hostTimestamp: event.hostTimestamp,
    );
    _latestOrientation = normalizedEvent;
    if (_origin == null) return;

    final lastRetained = _lastRetainedOrientation;
    if (lastRetained == null) {
      _appendOrientation(normalizedEvent);
      return;
    }

    final previousPending = _pendingOrientation;
    _pendingOrientation = normalizedEvent;
    final angularDistance = lastRetained.angularDistanceRadians(orientation);
    if (angularDistance < math.pi / 180) return;

    if (previousPending != null) _appendOrientation(previousPending);
    _appendOrientation(normalizedEvent);
    _pendingOrientation = null;
  }

  void queueGap(
    RecordingGapReason reason,
    Duration hostTimestamp, {
    int? missingMoveCount,
  }) {
    _pendingStartGaps.add((
      reason: reason,
      hostTimestamp: hostTimestamp,
      missingMoveCount: missingMoveCount,
    ));
  }

  void queueSmartCubeGap(SmartCubeDataGapEvent event) {
    queueGap(
      _recordingGapReason(event.reason),
      event.hostTimestamp,
      missingMoveCount: event.missingMoveCount,
    );
  }

  /// Starts a new timeline and carries forward eligible pre-start evidence.
  void start(Duration origin) {
    _clearCapture();
    _origin = origin;

    final baseline = _latestOrientation;
    if (baseline != null && baseline.hostTimestamp <= origin) {
      _appendOrientation(baseline);
    }
    for (final gap in _pendingStartGaps) {
      recordGap(
        gap.reason,
        gap.hostTimestamp,
        missingMoveCount: gap.missingMoveCount,
      );
    }
    _pendingStartGaps.clear();
  }

  void recordMove(SmartCubeMoveEvent event) {
    final hostTimestamp = event.hostTimestamp;
    final cubeTimestamp = event.cubeTimestamp;
    final origin = _origin;
    if (origin == null) return;
    _forceRetainLatestOrientation();

    final previousCubeTimestamp = _lastCubeTimestamp;
    if (cubeTimestamp != null &&
        previousCubeTimestamp != null &&
        cubeTimestamp < previousCubeTimestamp) {
      recordGap(RecordingGapReason.cubeClockDiscontinuity, hostTimestamp);
    }
    _events.add(
      RecordedMove(
        sequence: _nextSequence++,
        hostOffset: hostTimestamp - origin,
        move: event.move,
        serial: event.serial,
        recovered: event.recovered,
        cubeTimestamp: cubeTimestamp,
      ),
    );
    _lastCubeTimestamp = cubeTimestamp;
  }

  void recordState(SmartCubeStateEvent event) {
    final origin = _origin;
    if (origin == null) return;
    _forceRetainLatestOrientation();
    _events.add(
      RecordedState(
        sequence: _nextSequence++,
        hostOffset: event.hostTimestamp - origin,
        facelets: event.state.facelets,
        serial: event.serial,
      ),
    );
  }

  void recordGap(
    RecordingGapReason reason,
    Duration hostTimestamp, {
    int? missingMoveCount,
  }) {
    final origin = _origin;
    if (origin == null) return;
    _forceRetainLatestOrientation();
    _events.add(
      RecordedDataGap(
        sequence: _nextSequence++,
        hostOffset: hostTimestamp - origin,
        reason: reason,
        missingMoveCount: missingMoveCount,
      ),
    );
  }

  void recordSmartCubeGap(SmartCubeDataGapEvent event) {
    recordGap(
      _recordingGapReason(event.reason),
      event.hostTimestamp,
      missingMoveCount: event.missingMoveCount,
    );
  }

  /// Finalizes the active timeline while retaining the connected cube's pose.
  SolveRecording? finish() {
    if (_origin == null) return null;
    _forceRetainLatestOrientation();
    final events = List<SolveRecordingEvent>.unmodifiable(_events);
    final recording = SolveRecording(
      protocolFamily: _protocolFamily,
      cubeTimestampsAvailable:
          _capabilities.cubeTimestamps ||
          events.whereType<RecordedMove>().any(
            (event) => event.cubeTimestamp != null,
          ),
      orientationAvailable:
          _capabilities.gyroscope ||
          events.any((event) => event is RecordedOrientation),
      events: events,
    );
    _clearCapture();
    return recording;
  }

  /// Discards active and queued attempt evidence but retains source and pose.
  void discardAttempt() {
    _clearCapture();
    _pendingStartGaps.clear();
  }

  void _forceRetainLatestOrientation() {
    if (_origin == null) return;
    final latest = _pendingOrientation ?? _latestOrientation;
    if (latest == null) return;
    _appendOrientation(latest);
    _pendingOrientation = null;
  }

  void _appendOrientation(SmartCubeOrientationEvent event) {
    final origin = _origin;
    if (origin == null || identical(_lastRetainedOrientationEvent, event)) {
      return;
    }
    final orientation = event.orientation.normalized(
      alignedWith: _lastRetainedOrientation,
    );
    if (orientation == null) return;
    _events.add(
      RecordedOrientation(
        sequence: _nextSequence++,
        hostOffset: event.hostTimestamp - origin,
        orientation: orientation,
        angularVelocity: event.angularVelocity,
      ),
    );
    _lastRetainedOrientation = orientation;
    _lastRetainedOrientationEvent = event;
  }

  void _clearCapture() {
    _events.clear();
    _origin = null;
    _pendingOrientation = null;
    _lastRetainedOrientation = null;
    _lastRetainedOrientationEvent = null;
    _lastCubeTimestamp = null;
    _nextSequence = 0;
  }

  static RecordingGapReason _recordingGapReason(
    SmartCubeDataGapReason reason,
  ) => switch (reason) {
    SmartCubeDataGapReason.missedMoves => RecordingGapReason.missedMoves,
    SmartCubeDataGapReason.malformedPacket =>
      RecordingGapReason.malformedPacket,
    SmartCubeDataGapReason.connectionDiscontinuity =>
      RecordingGapReason.connectionDiscontinuity,
    SmartCubeDataGapReason.cubeClockDiscontinuity =>
      RecordingGapReason.cubeClockDiscontinuity,
  };
}
