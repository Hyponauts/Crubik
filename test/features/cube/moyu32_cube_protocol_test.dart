import 'dart:typed_data';

import 'package:crubik/features/cube/data/moyu32_cube_protocol.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MoYu32 cipher matches a fixed vector and round-trips packets', () {
    final cipher = Moyu32CubeCipher(macSalt: [6, 5, 4, 3, 2, 1]);
    final plain = Uint8List.fromList(List<int>.generate(20, (index) => index));

    expect(cipher.encrypt(plain), [
      0xa2,
      0x7b,
      0xfd,
      0xe5,
      0x1c,
      0x99,
      0xe8,
      0x82,
      0x69,
      0xad,
      0x82,
      0x39,
      0x67,
      0x5e,
      0x8b,
      0xaf,
      0x20,
      0x33,
      0x0d,
      0x85,
    ]);
    expect(cipher.decrypt(cipher.encrypt(plain)), plain);
  });

  test('decoder exposes info, state, and battery request commands', () {
    final decoder = Moyu32PacketDecoder();

    expect(decoder.requestInfoCommand, hasLength(20));
    expect(decoder.requestInfoCommand.first, moyu32InfoOpcode);
    expect(decoder.requestStateCommand, hasLength(20));
    expect(decoder.requestStateCommand.first, moyu32StateOpcode);
    expect(decoder.requestBatteryCommand, hasLength(20));
    expect(decoder.requestBatteryCommand.first, moyu32BatteryOpcode);
  });

  test('decoder keeps undocumented opcode A2 unknown', () {
    final packet = Uint8List(20)..first = 0xa2;

    final decoded = Moyu32PacketDecoder().decode(packet, DateTime.utc(2026));

    expect(decoded.events, isEmpty);
    expect(decoded.batteryLevel, isNull);
    expect(decoded.dataLoss, isFalse);
  });

  test('decoder maps solved and scrambled facelets into URFDLB state', () {
    final receivedAt = DateTime.utc(2026);
    final solvedDecoder = Moyu32PacketDecoder();
    final solved = solvedDecoder.decode(
      _statePacket(CubeState.solved().facelets, serial: 7),
      receivedAt,
    );

    expect(solved.states.single.state.isSolved, isTrue);
    expect(solved.states.single.serial, 7);

    final expected = CubeState.solved()
      ..applyAll(Scramble.parse("R U F' L2 D B").moves);
    final scrambled = Moyu32PacketDecoder().decode(
      _statePacket(expected.facelets, serial: 31),
      receivedAt,
    );

    expect(scrambled.states.single.state.facelets, expected.facelets);
    expect(scrambled.states.single.serial, 31);
  });

  test('decoder translates every face and direction', () {
    final decoder = Moyu32PacketDecoder();
    final receivedAt = DateTime.utc(2026);
    decoder.decode(
      _statePacket(CubeState.solved().facelets, serial: 0),
      receivedAt,
    );

    var serial = 0;
    for (final notation in [
      'F',
      "F'",
      'B',
      "B'",
      'U',
      "U'",
      'D',
      "D'",
      'L',
      "L'",
      'R',
      "R'",
    ]) {
      serial++;
      final decoded = decoder.decode(
        _movePacket(serial: serial, moves: [notation], offsets: [10]),
        receivedAt,
      );
      expect(decoded.moves.single.move.notation, notation);
      expect(decoded.moves.single.serial, serial);
    }
  });

  test('decoder recovers recent moves with cumulative timestamps', () {
    final decoder = Moyu32PacketDecoder();
    final receivedAt = DateTime.utc(2026);
    decoder.decode(
      _statePacket(CubeState.solved().facelets, serial: 10),
      receivedAt,
    );

    final decoded = decoder.decode(
      _movePacket(serial: 13, moves: ['F', "U'", 'R'], offsets: [30, 20, 10]),
      receivedAt,
    );

    expect(decoded.moves.map((event) => event.move.notation), ['R', "U'", 'F']);
    expect(decoded.moves.map((event) => event.serial), [11, 12, 13]);
    expect(decoded.moves.map((event) => event.recovered), [true, true, false]);
    expect(decoded.moves.map((event) => event.cubeTimestamp), const [
      Duration(milliseconds: 10),
      Duration(milliseconds: 30),
      Duration(milliseconds: 60),
    ]);
  });

  test('decoder ignores duplicates and handles serial wraparound', () {
    final decoder = Moyu32PacketDecoder();
    final receivedAt = DateTime.utc(2026);
    decoder.decode(
      _statePacket(CubeState.solved().facelets, serial: 255),
      receivedAt,
    );
    final packet = _movePacket(serial: 0, moves: ['R'], offsets: [8]);

    expect(decoder.decode(packet, receivedAt).moves.single.serial, 0);
    expect(decoder.decode(packet, receivedAt).events, isEmpty);
  });

  test('decoder retains five moves and requests resync after a larger gap', () {
    final decoder = Moyu32PacketDecoder();
    final receivedAt = DateTime.utc(2026);
    decoder.decode(
      _statePacket(CubeState.solved().facelets, serial: 1),
      receivedAt,
    );

    final decoded = decoder.decode(
      _movePacket(
        serial: 8,
        moves: ['F', 'R', 'U', 'B', 'L'],
        offsets: [5, 5, 5, 5, 5],
      ),
      receivedAt,
    );

    expect(decoded.dataLoss, isTrue);
    expect(decoded.moves, hasLength(5));
    expect(decoded.moves.map((event) => event.serial), [4, 5, 6, 7, 8]);
    expect(
      decoder
          .decode(
            _movePacket(serial: 9, moves: ['D'], offsets: [5]),
            receivedAt,
          )
          .events,
      isEmpty,
    );

    decoder.decode(
      _statePacket(CubeState.solved().facelets, serial: 9),
      receivedAt,
    );
    expect(
      decoder
          .decode(
            _movePacket(serial: 10, moves: ['D'], offsets: [5]),
            receivedAt,
          )
          .moves
          .single
          .move
          .notation,
      'D',
    );
  });

  test('decoder retains valid prefix before an invalid required move', () {
    final decoder = Moyu32PacketDecoder();
    final receivedAt = DateTime.utc(2026);
    decoder.decode(
      _statePacket(CubeState.solved().facelets, serial: 20),
      receivedAt,
    );
    final packet = _movePacket(serial: 22, moves: ['F', 'R'], offsets: [5, 5]);
    _setBits(packet, 96, 5, 31);

    final decoded = decoder.decode(packet, receivedAt);

    expect(decoded.dataLoss, isTrue);
    expect(decoded.moves.single.move.notation, 'R');
    expect(decoded.moves.single.serial, 21);
  });

  test('decoder validates malformed packets, facelets, and battery values', () {
    final decoder = Moyu32PacketDecoder();
    final receivedAt = DateTime.utc(2026);

    expect(
      () => decoder.decode(Uint8List(19), receivedAt),
      throwsFormatException,
    );

    final invalidState = _statePacket(CubeState.solved().facelets, serial: 1);
    _setBits(invalidState, 8, 3, 7);
    expect(
      () => decoder.decode(invalidState, receivedAt),
      throwsFormatException,
    );

    final invalidBattery = Uint8List(20)
      ..[0] = 0xa4
      ..[1] = 101;
    expect(
      () => decoder.decode(invalidBattery, receivedAt),
      throwsFormatException,
    );
  });

  test('decoder publishes valid battery and ignores unknown messages', () {
    final decoder = Moyu32PacketDecoder();
    final receivedAt = DateTime.utc(2026);
    final battery = Uint8List(20)
      ..[0] = 0xa4
      ..[1] = 83;

    expect(decoder.decode(battery, receivedAt).batteryLevel, 83);
    expect(decoder.decode(Uint8List(20), receivedAt).events, isEmpty);
  });
}

Uint8List _statePacket(String facelets, {required int serial}) {
  const protocolFaces = 'FBUDLR';
  const canonicalFaceForProtocolFace = [2, 5, 0, 3, 4, 1];
  const stickerIndexes = [0, 1, 2, 3, 5, 6, 7, 8];
  final packet = Uint8List(20)..[0] = 0xa3;
  for (var protocolFace = 0; protocolFace < 6; protocolFace++) {
    final canonicalFace = canonicalFaceForProtocolFace[protocolFace];
    for (var sticker = 0; sticker < 8; sticker++) {
      final symbol = facelets[canonicalFace * 9 + stickerIndexes[sticker]];
      _setBits(
        packet,
        8 + protocolFace * 24 + sticker * 3,
        3,
        protocolFaces.indexOf(symbol),
      );
    }
  }
  packet[19] = serial;
  return packet;
}

Uint8List _movePacket({
  required int serial,
  required List<String> moves,
  required List<int> offsets,
}) {
  assert(moves.length == offsets.length && moves.length <= 5);
  const protocolFaces = 'FBUDLR';
  final packet = Uint8List(20)
    ..[0] = 0xa5
    ..[11] = serial;
  for (var index = 0; index < moves.length; index++) {
    final move = moves[index];
    final code =
        protocolFaces.indexOf(move[0]) * 2 + (move.endsWith("'") ? 1 : 0);
    _setBits(packet, 8 + index * 16, 16, offsets[index]);
    _setBits(packet, 96 + index * 5, 5, code);
  }
  return packet;
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
