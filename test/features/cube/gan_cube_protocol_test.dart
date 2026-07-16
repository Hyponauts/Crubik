import 'dart:typed_data';

import 'package:crubik/features/cube/data/gan_cube_protocol.dart';
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

    final initial = decoder.decode(facelets, receivedAt);
    expect(initial.states.single.state.isSolved, isTrue);

    final move = Uint8List(20);
    _setBits(move, 0, 4, 0x02);
    _setBits(move, 4, 8, 11);
    _setBits(move, 12, 4, 1);
    _setBits(move, 16, 1, 0);
    _setBits(move, 47, 16, 123);
    final decoded = decoder.decode(move, receivedAt);

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
    decoder.decode(facelets, receivedAt);

    final packet = Uint8List(20);
    _setBits(packet, 0, 4, 0x02);
    _setBits(packet, 4, 8, 13);
    _setBits(packet, 12, 4, 2);
    _setBits(packet, 16, 1, 0);
    _setBits(packet, 17, 4, 0);
    _setBits(packet, 21, 1, 1);
    _setBits(packet, 47, 16, 50);
    _setBits(packet, 63, 16, 40);

    final decoded = decoder.decode(packet, receivedAt);

    expect(decoded.moves.map((event) => event.move.notation), ["U'", 'F']);
    expect(decoded.moves.map((event) => event.recovered), [isTrue, isFalse]);
  });

  test('Gen3 decoder translates a packet into a standard cube move', () {
    final decoder = GanModernPacketDecoder.gen3();
    expect(decoder.requestFaceletsCommand, hasLength(16));
    expect(decoder.requestFaceletsCommand.take(2), [0x68, 0x01]);
    final receivedAt = DateTime.utc(2026);
    final facelets =
        Uint8List(20)
          ..[0] = 0x55
          ..[1] = 0x02
          ..[2] = 0x01
          ..[3] = 10;
    _setSolvedCubies(facelets, 40, 61, 77, 121);
    expect(
      decoder.decode(facelets, receivedAt).states.single.state.isSolved,
      isTrue,
    );

    final packet =
        Uint8List(16)
          ..[0] = 0x55
          ..[1] = 0x01
          ..[2] = 0x08
          ..[3] = 0xe8
          ..[4] = 0x03
          ..[7] = 11
          ..[9] = 32;
    final decoded = decoder.decode(packet, receivedAt);

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
    final facelets =
        Uint8List(20)
          ..[0] = 0xed
          ..[1] = 0x01
          ..[2] = 20;
    _setSolvedCubies(facelets, 32, 53, 69, 113);
    expect(
      decoder.decode(facelets, receivedAt).states.single.state.isSolved,
      isTrue,
    );

    final packet =
        Uint8List(20)
          ..[0] = 0x01
          ..[1] = 0x08
          ..[2] = 0xd0
          ..[3] = 0x07
          ..[6] = 21
          ..[8] = 0x44;
    final decoded = decoder.decode(packet, receivedAt);

    expect(decoded.moves.single.move.notation, "B'");
    expect(decoded.moves.single.serial, 21);
    expect(decoded.moves.single.cubeTimestamp, const Duration(seconds: 2));
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
    target[byteIndex] =
        valueBit == 1 ? target[byteIndex] | mask : target[byteIndex] & ~mask;
  }
}
