import 'dart:typed_data';

import 'package:crubik/features/cube/data/gan_cube_protocol.dart';
import 'package:crubik/features/cube/domain/smart_cube_event.dart';
import 'package:crubik/features/practice/application/solve_recording_builder.dart';
import 'package:crubik/features/practice/domain/solve_recording.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'selects GAN Gen2, Gen3, and Gen4 definitions by discovered service',
    () {
      expect(
        ganProtocolForServices([ganGen2Service])?.generation,
        GanProtocolGeneration.gen2,
      );
      expect(
        ganProtocolForServices([ganGen3Service])?.generation,
        GanProtocolGeneration.gen3,
      );
      expect(
        ganProtocolForServices([ganGen4Service])?.generation,
        GanProtocolGeneration.gen4,
      );
      expect(ganProtocolForServices(['unsupported']), isNull);
    },
  );

  test('GAN cipher round-trips 16 and 20 byte packets', () {
    final ganCipher = GanCubeCipher(macSalt: [6, 5, 4, 3, 2, 1]);
    final moyuCipher = GanCubeCipher(
      macSalt: [6, 5, 4, 3, 2, 1],
      encryptionKey: GanEncryptionKey.moyuAi2023,
    );

    for (final length in [16, 20]) {
      final plain = Uint8List.fromList(
        List<int>.generate(length, (index) => index),
      );
      final encrypted = ganCipher.encrypt(plain);

      expect(encrypted, isNot(plain));
      expect(ganCipher.decrypt(encrypted), plain);
      expect(moyuCipher.encrypt(plain), isNot(encrypted));
    }
  });

  test('Gen2 decoder initializes from facelets and decodes live moves', () {
    final decoder = GanGen2PacketDecoder();
    final receivedAt = DateTime.utc(2026);
    final facelets = Uint8List(20);
    _setBits(facelets, 0, 4, 0x04);
    _setBits(facelets, 4, 8, 10);
    _setSolvedCubies(facelets, 12, 33, 47, 91);

    final initial = decoder.decode(
      facelets,
      receivedAt,
      hostTimestamp: Duration.zero,
    );
    expect(initial.states.single.state.isSolved, isTrue);

    final move = Uint8List(20);
    _setBits(move, 0, 4, 0x02);
    _setBits(move, 4, 8, 11);
    _setBits(move, 12, 4, 1);
    _setBits(move, 16, 1, 0);
    _setBits(move, 47, 16, 123);
    final decoded = decoder.decode(
      move,
      receivedAt,
      hostTimestamp: Duration.zero,
    );

    expect(decoded.moves.single.move.notation, 'R');
    expect(decoded.moves.single.serial, 11);
    expect(
      decoded.moves.single.cubeTimestamp,
      const Duration(milliseconds: 123),
    );
    expect(decoded.moves.single.recovered, isFalse);
  });

  test('Gen2 decoder recovers recent moves embedded in the next packet', () {
    final decoder = GanGen2PacketDecoder();
    final receivedAt = DateTime.utc(2026);
    final facelets = Uint8List(20);
    _setBits(facelets, 0, 4, 0x04);
    _setBits(facelets, 4, 8, 11);
    _setSolvedCubies(facelets, 12, 33, 47, 91);
    decoder.decode(facelets, receivedAt, hostTimestamp: Duration.zero);

    final packet = Uint8List(20);
    _setBits(packet, 0, 4, 0x02);
    _setBits(packet, 4, 8, 13);
    _setBits(packet, 12, 4, 2);
    _setBits(packet, 16, 1, 0);
    _setBits(packet, 17, 4, 0);
    _setBits(packet, 21, 1, 1);
    _setBits(packet, 47, 16, 50);
    _setBits(packet, 63, 16, 40);

    final decoded = decoder.decode(
      packet,
      receivedAt,
      hostTimestamp: const Duration(milliseconds: 42),
    );

    expect(decoded.moves.map((event) => event.move.notation), ["U'", 'F']);
    expect(decoded.moves.map((event) => event.recovered), [isTrue, isFalse]);
    expect(decoded.moves.map((event) => event.hostTimestamp), const [
      Duration(milliseconds: 42),
      Duration(milliseconds: 42),
    ]);
  });

  test('Gen2 reports history overflow and does not invent overflow timing', () {
    final decoder = GanGen2PacketDecoder();
    final receivedAt = DateTime.utc(2026);
    final facelets = Uint8List(20);
    _setBits(facelets, 0, 4, 0x04);
    _setBits(facelets, 4, 8, 1);
    _setSolvedCubies(facelets, 12, 33, 47, 91);
    decoder.decode(facelets, receivedAt, hostTimestamp: Duration.zero);

    final packet = Uint8List(20);
    _setBits(packet, 0, 4, 0x02);
    _setBits(packet, 4, 8, 10);
    for (var index = 0; index < 7; index++) {
      _setBits(packet, 12 + 5 * index, 4, index % 6);
      _setBits(packet, 47 + 16 * index, 16, index == 0 ? 0 : 10);
    }

    final decoded = decoder.decode(
      packet,
      receivedAt,
      hostTimestamp: const Duration(milliseconds: 50),
    );
    final gaps = decoded.events.whereType<SmartCubeDataGapEvent>().toList();

    expect(gaps.first.reason, SmartCubeDataGapReason.missedMoves);
    expect(gaps.first.missingMoveCount, 2);
    expect(gaps.last.reason, SmartCubeDataGapReason.cubeClockDiscontinuity);
    expect(decoded.moves.last.cubeTimestamp, isNull);
    expect(decoded.events.map((event) => event.hostTimestamp).toSet(), {
      const Duration(milliseconds: 50),
    });
  });

  test('Gen2 marks invalid moves without losing their clock delta', () {
    final decoder = GanGen2PacketDecoder();
    final receivedAt = DateTime.utc(2026);
    final facelets = Uint8List(20);
    _setBits(facelets, 0, 4, 0x04);
    _setBits(facelets, 4, 8, 10);
    _setSolvedCubies(facelets, 12, 33, 47, 91);
    decoder.decode(facelets, receivedAt, hostTimestamp: Duration.zero);
    final packet = Uint8List(20);
    _setBits(packet, 0, 4, 0x02);
    _setBits(packet, 4, 8, 13);
    for (final (index, face, elapsed) in [
      (2, 1, 50),
      (1, 15, 100),
      (0, 2, 150),
    ]) {
      _setBits(packet, 12 + 5 * index, 4, face);
      _setBits(packet, 47 + 16 * index, 16, elapsed);
    }

    final decoded = decoder.decode(
      packet,
      receivedAt,
      hostTimestamp: const Duration(milliseconds: 300),
    );
    final nextPacket = Uint8List(20);
    _setBits(nextPacket, 0, 4, 0x02);
    _setBits(nextPacket, 4, 8, 14);
    _setBits(nextPacket, 12, 4, 0);
    _setBits(nextPacket, 47, 16, 200);
    final next = decoder.decode(
      nextPacket,
      receivedAt,
      hostTimestamp: const Duration(milliseconds: 500),
    );
    final builder = SolveRecordingBuilder()..start(Duration.zero);
    for (final event in [...decoded.events, ...next.events]) {
      switch (event) {
        case SmartCubeMoveEvent():
          builder.recordMove(event);
        case SmartCubeDataGapEvent():
          builder.recordSmartCubeGap(event);
        case _:
          fail('Unexpected Gen2 event: ${event.runtimeType}');
      }
    }
    final recording = builder.finish()!;

    expect(decoded.events, [
      isA<SmartCubeMoveEvent>(),
      isA<SmartCubeDataGapEvent>(),
      isA<SmartCubeMoveEvent>(),
    ]);
    final gap = decoded.events.whereType<SmartCubeDataGapEvent>().single;
    expect(gap.reason, SmartCubeDataGapReason.malformedPacket);
    expect(gap.missingMoveCount, 1);
    expect(decoded.moves.map((move) => move.serial), [11, 13]);
    expect(decoded.moves.map((move) => move.cubeTimestamp), const [
      Duration(milliseconds: 50),
      Duration(milliseconds: 300),
    ]);
    expect(recording.intervalForMove(1).duration, isNull);
    expect(
      recording.intervalForMove(1).source,
      RecordingTimingSource.unavailable,
    );
    expect(
      recording.intervalForMove(2).duration,
      const Duration(milliseconds: 200),
    );
    expect(
      recording.intervalForMove(2).source,
      RecordingTimingSource.cubeClock,
    );
  });

  test('Gen2 decodes quaternion, sign, velocity, and host receipt time', () {
    final packet = Uint8List(20);
    _setBits(packet, 0, 4, 0x01);
    _setBits(packet, 4, 16, 0x7fff);
    _setBits(packet, 20, 16, 0xbfff);
    _setBits(packet, 36, 16, 0x1fff);
    _setBits(packet, 52, 16, 0);
    _setBits(packet, 68, 4, 0x5);
    _setBits(packet, 72, 4, 0xb);
    _setBits(packet, 76, 4, 0);

    final decoded = GanGen2PacketDecoder().decode(
      packet,
      DateTime.utc(2026),
      hostTimestamp: const Duration(milliseconds: 17),
    );
    final orientation = decoded.events.single as SmartCubeOrientationEvent;

    expect(decoded.kind, GanPacketKind.orientation);
    expect(orientation.orientation.w, 1);
    expect(orientation.orientation.x, closeTo(-0.5, 0.0001));
    expect(orientation.orientation.y, closeTo(0.25, 0.0001));
    expect(orientation.angularVelocity?.x, 5);
    expect(orientation.angularVelocity?.y, -3);
    expect(orientation.angularVelocity?.unit, 'gan_odr_step');
    expect(orientation.hostTimestamp, const Duration(milliseconds: 17));
  });

  test('Gen2 hardware packet reports gyroscope support', () {
    final packet = Uint8List(20);
    _setBits(packet, 0, 4, 0x05);
    _setBits(packet, 104, 1, 1);

    final decoded = GanGen2PacketDecoder().decode(
      packet,
      DateTime.utc(2026),
      hostTimestamp: Duration.zero,
    );
    final capabilities = decoded.events.single as SmartCubeCapabilitiesEvent;

    expect(decoded.kind, GanPacketKind.hardware);
    expect(capabilities.capabilities.gyroscope, isTrue);
  });

  test('Gen3 decoder translates a packet into a standard cube move', () {
    final decoder = GanModernPacketDecoder.gen3();
    expect(decoder.requestFaceletsCommand, hasLength(16));
    expect(decoder.requestFaceletsCommand.take(2), [0x68, 0x01]);
    final receivedAt = DateTime.utc(2026);
    final facelets = Uint8List(20)
      ..[0] = 0x55
      ..[1] = 0x02
      ..[2] = 0x01
      ..[3] = 10;
    _setSolvedCubies(facelets, 40, 61, 77, 121);
    expect(
      decoder
          .decode(facelets, receivedAt, hostTimestamp: Duration.zero)
          .states
          .single
          .state
          .isSolved,
      isTrue,
    );

    final packet = Uint8List(16)
      ..[0] = 0x55
      ..[1] = 0x01
      ..[2] = 0x08
      ..[3] = 0xe8
      ..[4] = 0x03
      ..[7] = 11
      ..[9] = 32;
    final decoded = decoder.decode(
      packet,
      receivedAt,
      hostTimestamp: Duration.zero,
    );

    expect(decoded.moves.single.move.notation, 'R');
    expect(decoded.moves.single.serial, 11);
    expect(decoded.moves.single.cubeTimestamp, const Duration(seconds: 1));
  });

  test('Gen4 decoder translates a packet into a standard cube move', () {
    final decoder = GanModernPacketDecoder.gen4();
    expect(decoder.requestFaceletsCommand, hasLength(20));
    expect(decoder.requestFaceletsCommand.take(6), [
      0xdd,
      0x04,
      0x00,
      0xed,
      0,
      0,
    ]);
    final receivedAt = DateTime.utc(2026);
    final facelets = Uint8List(20)
      ..[0] = 0xed
      ..[1] = 0x01
      ..[2] = 20;
    _setSolvedCubies(facelets, 32, 53, 69, 113);
    expect(
      decoder
          .decode(facelets, receivedAt, hostTimestamp: Duration.zero)
          .states
          .single
          .state
          .isSolved,
      isTrue,
    );

    final packet = Uint8List(20)
      ..[0] = 0x01
      ..[1] = 0x08
      ..[2] = 0xd0
      ..[3] = 0x07
      ..[6] = 21
      ..[8] = 0x44;
    final decoded = decoder.decode(
      packet,
      receivedAt,
      hostTimestamp: Duration.zero,
    );

    expect(decoded.moves.single.move.notation, "B'");
    expect(decoded.moves.single.serial, 21);
    expect(decoded.moves.single.cubeTimestamp, const Duration(seconds: 2));
  });

  test(
    'Gen4 recovery preserves receipts when moves are emitted out of receipt order',
    () {
      final decoder = GanModernPacketDecoder.gen4();
      final receivedAt = DateTime.utc(2026);
      final state = Uint8List(20)
        ..[0] = 0xed
        ..[1] = 1
        ..[2] = 20;
      _setSolvedCubies(state, 32, 53, 69, 113);
      decoder.decode(state, receivedAt, hostTimestamp: Duration.zero);
      final live = Uint8List(20)
        ..[0] = 1
        ..[1] = 8
        ..[6] = 22
        ..[8] = 1;
      final buffered = decoder.decode(
        live,
        receivedAt,
        hostTimestamp: const Duration(seconds: 1),
      );
      expect(buffered.events, isEmpty);
      expect(buffered.commands, isNotEmpty);

      final history = Uint8List(20)
        ..[0] = 0xd1
        ..[1] = 2
        ..[2] = 21
        ..[3] = 0xa0;
      final recovered = decoder.decode(
        history,
        receivedAt,
        hostTimestamp: const Duration(seconds: 2),
      );

      expect(recovered.moves.map((event) => event.serial), [21, 22]);
      expect(recovered.moves.map((event) => event.recovered), [true, false]);
      expect(recovered.moves.map((event) => event.hostTimestamp), const [
        Duration(seconds: 2),
        Duration(seconds: 1),
      ]);
    },
  );

  test('Gen4 decodes gyro packets and hardware capability', () {
    final decoder = GanModernPacketDecoder.gen4();
    final gyro = Uint8List(20)..[0] = 0xec;
    _setBits(gyro, 16, 16, 0x7fff);
    _setBits(gyro, 32, 16, 0x3fff);
    _setBits(gyro, 48, 16, 0);
    _setBits(gyro, 64, 16, 0);
    _setBits(gyro, 80, 4, 0x2);
    _setBits(gyro, 84, 4, 0x9);
    final orientation =
        decoder
                .decode(
                  gyro,
                  DateTime.utc(2026),
                  hostTimestamp: const Duration(milliseconds: 25),
                )
                .events
                .single
            as SmartCubeOrientationEvent;

    final hardware = Uint8List(20)
      ..[0] = 0xfc
      ..[1] = 9
      ..setRange(3, 11, 'GAN12uiM'.codeUnits);
    final capabilities =
        decoder
                .decode(
                  hardware,
                  DateTime.utc(2026),
                  hostTimestamp: Duration.zero,
                )
                .events
                .single
            as SmartCubeCapabilitiesEvent;

    expect(orientation.orientation.w, 1);
    expect(orientation.orientation.x, closeTo(0.5, 0.0001));
    expect(orientation.angularVelocity?.x, 2);
    expect(orientation.angularVelocity?.y, -1);
    expect(orientation.hostTimestamp, const Duration(milliseconds: 25));
    expect(capabilities.capabilities.gyroscope, isTrue);
  });

  test('Gen3 does not invent orientation or gyro capability', () {
    final decoder = GanModernPacketDecoder.gen3();
    final gyroLikePacket = Uint8List(16)
      ..[0] = 0x55
      ..[1] = 0xec;
    final hardware = Uint8List(16)
      ..[0] = 0x55
      ..[1] = 0x07
      ..[2] = 1;

    expect(
      decoder
          .decode(
            gyroLikePacket,
            DateTime.utc(2026),
            hostTimestamp: Duration.zero,
          )
          .events,
      isEmpty,
    );
    final capabilities =
        decoder
                .decode(
                  hardware,
                  DateTime.utc(2026),
                  hostTimestamp: Duration.zero,
                )
                .events
                .single
            as SmartCubeCapabilitiesEvent;
    expect(capabilities.capabilities.gyroscope, isFalse);
  });
}

void _setSolvedCubies(
  Uint8List target,
  int cornerPermutationStart,
  int cornerOrientationStart,
  int edgePermutationStart,
  int edgeOrientationStart,
) {
  for (var index = 0; index < 7; index++) {
    _setBits(target, cornerPermutationStart + index * 3, 3, index);
    _setBits(target, cornerOrientationStart + index * 2, 2, 0);
  }
  for (var index = 0; index < 11; index++) {
    _setBits(target, edgePermutationStart + index * 4, 4, index);
    _setBits(target, edgeOrientationStart + index, 1, 0);
  }
}

void _setBits(Uint8List target, int startBit, int bitLength, int value) {
  for (var index = 0; index < bitLength; index++) {
    final absoluteBit = startBit + index;
    final valueBit = (value >> (bitLength - 1 - index)) & 1;
    final mask = 1 << (7 - absoluteBit % 8);
    final byteIndex = absoluteBit ~/ 8;
    target[byteIndex] = valueBit == 1
        ? target[byteIndex] | mask
        : target[byteIndex] & ~mask;
  }
}
