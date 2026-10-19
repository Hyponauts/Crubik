import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/cube_model.dart';
import '../domain/smart_cube_event.dart';
import 'cube_packet_cipher.dart';
import 'packet_bit_view.dart';

// Protocol facts are independently implemented from the MoYu32 wire format
// documented by csTimer. See THIRD_PARTY_NOTICES.md.
const moyu32Service = '0783b03e-7735-b5a0-1760-a305d2795cb0';
const moyu32ReadCharacteristic = '0783b03e-7735-b5a0-1760-a305d2795cb1';
const moyu32WriteCharacteristic = '0783b03e-7735-b5a0-1760-a305d2795cb2';
const moyu32InfoOpcode = 0xa1;
const moyu32StateOpcode = 0xa3;
const moyu32BatteryOpcode = 0xa4;
const moyu32MovesOpcode = 0xa5;

// The pinned csTimer implementation documents A1, A3, A4, and A5, but no A2
// message. Keep A2 unknown until protocol evidence gives it a defined meaning.

final class Moyu32CubeCipher {
  Moyu32CubeCipher({required List<int> macSalt})
    : _cipher = MacSaltedAesCubeCipher(
        key: _moyu32Key,
        iv: _moyu32Iv,
        macSalt: macSalt,
      );

  final MacSaltedAesCubeCipher _cipher;

  Uint8List encrypt(Uint8List data) => _cipher.encrypt(data);

  Uint8List decrypt(Uint8List data) => _cipher.decrypt(data);
}

final class Moyu32DecodedPacket {
  const Moyu32DecodedPacket({
    this.events = const [],
    this.batteryLevel,
    this.dataLoss = false,
    this.missingMoveCount,
  });

  final List<SmartCubeEvent> events;
  final int? batteryLevel;
  final bool dataLoss;
  final int? missingMoveCount;

  Iterable<SmartCubeMoveEvent> get moves => events.whereType();

  Iterable<SmartCubeStateEvent> get states => events.whereType();
}

final class Moyu32PacketDecoder {
  int _lastSerial = -1;
  int _cubeTimestampMs = 0;
  bool _awaitingResync = false;

  Uint8List get requestInfoCommand => Uint8List(20)..[0] = moyu32InfoOpcode;

  Uint8List get requestStateCommand => Uint8List(20)..[0] = moyu32StateOpcode;

  Uint8List get requestBatteryCommand =>
      Uint8List(20)..[0] = moyu32BatteryOpcode;

  Moyu32DecodedPacket decode(
    Uint8List packet,
    DateTime receivedAt, {
    required Duration hostTimestamp,
  }) {
    if (packet.length != 20) {
      throw const FormatException('MoYu32 packets must contain 20 bytes.');
    }
    final bits = PacketBitView(packet, protocolName: 'MoYu32');
    return switch (packet[0]) {
      moyu32StateOpcode => _decodeState(
        packet,
        bits,
        receivedAt,
        hostTimestamp,
      ),
      moyu32BatteryOpcode => _decodeBattery(packet),
      moyu32MovesOpcode => _decodeMoves(
        packet,
        bits,
        receivedAt,
        hostTimestamp,
      ),
      _ => const Moyu32DecodedPacket(),
    };
  }

  Moyu32DecodedPacket _decodeState(
    Uint8List packet,
    PacketBitView bits,
    DateTime receivedAt,
    Duration hostTimestamp,
  ) {
    const protocolFaces = 'FBUDLR';
    const faceOrder = [2, 5, 0, 3, 4, 1];
    final facelets = StringBuffer();
    for (final protocolFace in faceOrder) {
      final faceStart = 8 + protocolFace * 24;
      for (var sticker = 0; sticker < 8; sticker++) {
        final color = bits.read(faceStart + sticker * 3, 3);
        if (color >= protocolFaces.length) {
          throw const FormatException('Invalid MoYu32 facelet color.');
        }
        facelets.write(protocolFaces[color]);
        if (sticker == 3) facelets.write(protocolFaces[protocolFace]);
      }
    }
    final serial = packet[19];
    _lastSerial = serial;
    _awaitingResync = false;
    return Moyu32DecodedPacket(
      events: [
        SmartCubeStateEvent(
          state: CubeState.fromFacelets(facelets.toString()),
          serial: serial,
          receivedAt: receivedAt,
          hostTimestamp: hostTimestamp,
        ),
      ],
    );
  }

  Moyu32DecodedPacket _decodeBattery(Uint8List packet) {
    final batteryLevel = packet[1];
    if (batteryLevel > 100) {
      throw const FormatException('Invalid MoYu32 battery level.');
    }
    return Moyu32DecodedPacket(batteryLevel: batteryLevel);
  }

  Moyu32DecodedPacket _decodeMoves(
    Uint8List packet,
    PacketBitView bits,
    DateTime receivedAt,
    Duration hostTimestamp,
  ) {
    if (_lastSerial == -1 || _awaitingResync) {
      return const Moyu32DecodedPacket();
    }
    final serial = packet[11];
    final difference = (serial - _lastSerial) & 0xff;
    if (difference == 0) return const Moyu32DecodedPacket();

    final count = math.min(difference, 5);
    final moves = <SmartCubeMoveEvent>[];
    var dataLoss = difference > 5;
    final missingMoveCount = dataLoss ? difference - 5 : null;
    if (dataLoss) _cubeTimestampMs = 0;
    for (var index = count - 1; index >= 0; index--) {
      final moveCode = bits.read(96 + index * 5, 5);
      if (moveCode >= 12) {
        dataLoss = true;
        break;
      }
      final face = 'FBUDLR'[moveCode >> 1];
      final move = CubeMove.parse('$face${moveCode.isOdd ? "'" : ''}');
      _cubeTimestampMs += bits.read(8 + index * 16, 16);
      final moveSerial = (serial - index) & 0xff;
      moves.add(
        SmartCubeMoveEvent(
          move: move,
          serial: moveSerial,
          receivedAt: receivedAt,
          hostTimestamp: hostTimestamp,
          cubeTimestamp: Duration(milliseconds: _cubeTimestampMs),
          recovered: index != 0,
        ),
      );
      _lastSerial = moveSerial;
    }
    if (dataLoss) _awaitingResync = true;
    return Moyu32DecodedPacket(
      events: moves,
      dataLoss: dataLoss,
      missingMoveCount: missingMoveCount,
    );
  }
}

const _moyu32Key = <int>[
  21,
  119,
  58,
  92,
  103,
  14,
  45,
  31,
  23,
  103,
  42,
  19,
  155,
  103,
  82,
  87,
];

const _moyu32Iv = <int>[
  17,
  35,
  38,
  37,
  134,
  42,
  44,
  59,
  85,
  6,
  127,
  49,
  126,
  103,
  33,
  87,
];
