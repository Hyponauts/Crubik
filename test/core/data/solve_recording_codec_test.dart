import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crubik/core/data/solve_recording_codec.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/cube/domain/smart_cube_event.dart';
import 'package:crubik/features/practice/domain/solve_recording.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips all raw event data without losing precision', () {
    final recording = _recording();

    final restored = decodeSolveRecording(encodeSolveRecording(recording));

    expect(
      restored.toJson(includeDerivedTiming: false),
      recording.toJson(includeDerivedTiming: false),
    );
    expect(restored.toJson(), recording.toJson());
  });

  test('compresses a 60-move recording without storing derived timing', () {
    final recording = SolveRecording(
      protocolFamily: CubeProtocolFamily.gan,
      cubeTimestampsAvailable: true,
      orientationAvailable: false,
      events: [
        for (var index = 0; index < 60; index++)
          RecordedMove(
            sequence: index,
            hostOffset: Duration(microseconds: index * 500001),
            move: CubeMove(CubeFace.values[index % 6], turns: index % 3 + 1),
            serial: index,
            recovered: false,
            cubeTimestamp: Duration(microseconds: 600000000 + index * 500001),
          ),
      ],
    );
    final jsonBytes = utf8.encode(
      jsonEncode(recording.toJson(includeDerivedTiming: false)),
    );

    final payload = encodeSolveRecording(recording);
    final storedJson = utf8.decode(const GZipDecoder().decodeBytes(payload));

    expect(payload.take(2), [0x1f, 0x8b]);
    expect(payload.length, lessThan(jsonBytes.length ~/ 2));
    expect(storedJson, isNot(contains('interval_us')));
    expect(storedJson, isNot(contains('interval_source')));
    expect(storedJson, isNot(contains('time_from_solve_start_us')));
  });

  test('storage encoding interoperates with the web gzip codec', () {
    final recording = _recording();
    final json = recording.toJson(includeDerivedTiming: false);
    final jsonBytes = utf8.encode(jsonEncode(json));

    final payload = encodeSolveRecording(recording);
    final webPayload = const GZipEncoderWeb().encodeBytes(jsonBytes);

    expect(
      const GZipDecoderWeb().decodeBytes(payload, verify: true),
      jsonBytes,
    );
    expect(
      decodeSolveRecording(webPayload).toJson(includeDerivedTiming: false),
      json,
    );
  });

  test('rejects a recording with a corrupt gzip checksum', () {
    final payload = encodeSolveRecording(_recording());
    payload[payload.length - 8] ^= 0xff;

    expect(() => decodeSolveRecording(payload), throwsFormatException);
  });

  test('rejects a recording with an incorrect uncompressed size', () {
    final payload = encodeSolveRecording(_recording());
    payload[payload.length - 4] ^= 0xff;

    expect(() => decodeSolveRecording(payload), throwsFormatException);
  });

  test('rejects payloads without a complete gzip header and trailer', () {
    for (final bytes in [
      <int>[],
      [0x1f, 0x8b, 8],
      utf8.encode('{}'),
    ]) {
      expect(
        () => decodeSolveRecording(Uint8List.fromList(bytes)),
        throwsFormatException,
      );
    }
  });

  test('rejects unsupported recording versions after decompression', () {
    final json = _recording().toJson(includeDerivedTiming: false)
      ..['format_version'] = solveRecordingFormatVersion + 1;
    final payload = const GZipEncoder().encodeBytes(
      utf8.encode(jsonEncode(json)),
    );

    expect(() => decodeSolveRecording(payload), throwsFormatException);
  });
}

SolveRecording _recording() => SolveRecording(
  protocolFamily: CubeProtocolFamily.gan,
  cubeTimestampsAvailable: true,
  orientationAvailable: true,
  events: [
    const RecordedOrientation(
      sequence: 0,
      hostOffset: Duration(microseconds: -5432),
      orientation: CubeOrientation(
        x: 0.12345678901234567,
        y: -0.23456789012345678,
        z: 0.34567890123456789,
        w: 0.90123456789012345,
      ),
      angularVelocity: CubeAngularVelocity(
        x: 0.012451171875,
        y: -0.003662109375,
        z: 0.001220703125,
        unit: 'gan_odr_step',
      ),
    ),
    const RecordedMove(
      sequence: 1,
      hostOffset: Duration.zero,
      move: CubeMove(CubeFace.right),
      serial: 255,
      recovered: false,
      cubeTimestamp: Duration(microseconds: 1234567890123),
    ),
    const RecordedMove(
      sequence: 2,
      hostOffset: Duration(microseconds: 54321),
      move: CubeMove(CubeFace.up, turns: 3),
      serial: 0,
      recovered: true,
    ),
    RecordedState(
      sequence: 3,
      hostOffset: const Duration(microseconds: 54321),
      facelets: CubeState.solved().facelets,
      serial: 0,
    ),
    const RecordedDataGap(
      sequence: 4,
      hostOffset: Duration(microseconds: 54322),
      reason: RecordingGapReason.missedMoves,
      missingMoveCount: 2,
    ),
    const RecordedOrientation(
      sequence: 5,
      hostOffset: Duration(microseconds: 54323),
      orientation: CubeOrientation(x: 0, y: 0, z: 0, w: 1),
    ),
  ],
);
