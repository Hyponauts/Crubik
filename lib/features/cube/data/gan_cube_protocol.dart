import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../domain/cube_model.dart';

// Protocol constants and packet layouts are adapted from the MIT-licensed
// gan-web-bluetooth project by Andy Fedotov. See THIRD_PARTY_NOTICES.md.
const ganGen2Service = '6e400001-b5a3-f393-e0a9-e50e24dc4179';
const ganGen2CommandCharacteristic = '28be4a4a-cd67-11e9-a32f-2a2ae2dbcce4';
const ganGen2StateCharacteristic = '28be4cb6-cd67-11e9-a32f-2a2ae2dbcce4';

const ganGen3Service = '8653000a-43e6-47b7-9cb0-5fc21d4ae340';
const ganGen3CommandCharacteristic = '8653000c-43e6-47b7-9cb0-5fc21d4ae340';
const ganGen3StateCharacteristic = '8653000b-43e6-47b7-9cb0-5fc21d4ae340';

const ganGen4Service = '00000010-0000-fff7-fff6-fff5fff4fff0';
const ganGen4CommandCharacteristic = '0000fff5-0000-1000-8000-00805f9b34fb';
const ganGen4StateCharacteristic = '0000fff6-0000-1000-8000-00805f9b34fb';

enum GanProtocolGeneration { gen2, gen3, gen4 }

final class GanProtocolDefinition {
  const GanProtocolDefinition({
    required this.generation,
    required this.service,
    required this.commandCharacteristic,
    required this.stateCharacteristic,
  });

  final GanProtocolGeneration generation;
  final String service;
  final String commandCharacteristic;
  final String stateCharacteristic;
}

const _protocolDefinitions = [
  GanProtocolDefinition(
    generation: GanProtocolGeneration.gen2,
    service: ganGen2Service,
    commandCharacteristic: ganGen2CommandCharacteristic,
    stateCharacteristic: ganGen2StateCharacteristic,
  ),
  GanProtocolDefinition(
    generation: GanProtocolGeneration.gen3,
    service: ganGen3Service,
    commandCharacteristic: ganGen3CommandCharacteristic,
    stateCharacteristic: ganGen3StateCharacteristic,
  ),
  GanProtocolDefinition(
    generation: GanProtocolGeneration.gen4,
    service: ganGen4Service,
    commandCharacteristic: ganGen4CommandCharacteristic,
    stateCharacteristic: ganGen4StateCharacteristic,
  ),
];

GanProtocolDefinition? ganProtocolForServices(Iterable<String> services) {
  final normalized = services.map((service) => service.toLowerCase()).toSet();
  for (final definition in _protocolDefinitions) {
    if (normalized.contains(definition.service)) return definition;
  }
  return null;
}

final class SmartCubeMoveEvent {
  const SmartCubeMoveEvent({
    required this.move,
    required this.serial,
    required this.receivedAt,
    this.cubeTimestamp,
    this.recovered = false,
  });

  final CubeMove move;
  final int serial;
  final DateTime receivedAt;
  final Duration? cubeTimestamp;
  final bool recovered;
}

final class SmartCubeStateEvent {
  const SmartCubeStateEvent({
    required this.state,
    required this.serial,
    required this.receivedAt,
  });

  final CubeState state;
  final int serial;
  final DateTime receivedAt;
}

final class GanDecodedPacket {
  const GanDecodedPacket({
    this.moves = const [],
    this.states = const [],
    this.commands = const [],
  });

  final List<SmartCubeMoveEvent> moves;
  final List<SmartCubeStateEvent> states;
  final List<Uint8List> commands;
}

abstract interface class GanPacketDecoder {
  Uint8List get requestFaceletsCommand;

  GanDecodedPacket decode(Uint8List packet, DateTime receivedAt);
}

GanPacketDecoder createGanPacketDecoder(GanProtocolGeneration generation) {
  return switch (generation) {
    GanProtocolGeneration.gen2 => GanGen2PacketDecoder(),
    GanProtocolGeneration.gen3 => GanModernPacketDecoder.gen3(),
    GanProtocolGeneration.gen4 => GanModernPacketDecoder.gen4(),
  };
}

final class GanCubeCipher {
  GanCubeCipher({required List<int> macSalt, bool useMoyuAiKey = false}) {
    if (macSalt.length != 6) {
      throw const FormatException('GAN cube MAC salt must contain 6 bytes.');
    }
    final material = useMoyuAiKey ? _moyuAiKeyMaterial : _ganKeyMaterial;
    _key = Uint8List.fromList(material.key);
    _iv = Uint8List.fromList(material.iv);
    for (var index = 0; index < macSalt.length; index++) {
      _key[index] = (material.key[index] + macSalt[index]) % 0xff;
      _iv[index] = (material.iv[index] + macSalt[index]) % 0xff;
    }
  }

  late final Uint8List _key;
  late final Uint8List _iv;

  Uint8List encrypt(Uint8List data) {
    if (data.length < 16) {
      throw const FormatException('GAN packets must be at least 16 bytes.');
    }
    final result = Uint8List.fromList(data);
    _transformChunk(result, 0, encrypt: true);
    if (result.length > 16) {
      _transformChunk(result, result.length - 16, encrypt: true);
    }
    return result;
  }

  Uint8List decrypt(Uint8List data) {
    if (data.length < 16) {
      throw const FormatException('GAN packets must be at least 16 bytes.');
    }
    final result = Uint8List.fromList(data);
    if (result.length > 16) {
      _transformChunk(result, result.length - 16, encrypt: false);
    }
    _transformChunk(result, 0, encrypt: false);
    return result;
  }

  void _transformChunk(Uint8List buffer, int offset, {required bool encrypt}) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(encrypt, ParametersWithIV(KeyParameter(_key), _iv));
    final output = Uint8List(16);
    cipher.processBlock(buffer, offset, output, 0);
    buffer.setRange(offset, offset + 16, output);
  }
}

const _ganKeyMaterial = (
  key: <int>[
    0x01,
    0x02,
    0x42,
    0x28,
    0x31,
    0x91,
    0x16,
    0x07,
    0x20,
    0x05,
    0x18,
    0x54,
    0x42,
    0x11,
    0x12,
    0x53,
  ],
  iv: <int>[
    0x11,
    0x03,
    0x32,
    0x28,
    0x21,
    0x01,
    0x76,
    0x27,
    0x20,
    0x95,
    0x78,
    0x14,
    0x32,
    0x12,
    0x02,
    0x43,
  ],
);

const _moyuAiKeyMaterial = (
  key: <int>[
    0x05,
    0x12,
    0x02,
    0x45,
    0x02,
    0x01,
    0x29,
    0x56,
    0x12,
    0x78,
    0x12,
    0x76,
    0x81,
    0x01,
    0x08,
    0x03,
  ],
  iv: <int>[
    0x01,
    0x44,
    0x28,
    0x06,
    0x86,
    0x21,
    0x22,
    0x28,
    0x51,
    0x05,
    0x08,
    0x31,
    0x82,
    0x02,
    0x21,
    0x06,
  ],
);

final class GanProtocolMessageView {
  GanProtocolMessageView(this._message);

  final Uint8List _message;

  int getBitWord(int startBit, int bitLength, {bool littleEndian = false}) {
    if (startBit < 0 ||
        bitLength <= 0 ||
        startBit + bitLength > _message.length * 8) {
      throw const FormatException('GAN packet field exceeds packet bounds.');
    }
    if (littleEndian && (bitLength == 16 || bitLength == 32)) {
      var result = 0;
      for (var byteIndex = 0; byteIndex < bitLength ~/ 8; byteIndex++) {
        result |= _readBits(startBit + byteIndex * 8, 8) << (byteIndex * 8);
      }
      return result;
    }
    return _readBits(startBit, bitLength);
  }

  int _readBits(int startBit, int bitLength) {
    var result = 0;
    for (var index = 0; index < bitLength; index++) {
      final absoluteBit = startBit + index;
      final byte = _message[absoluteBit ~/ 8];
      final bit = (byte >> (7 - absoluteBit % 8)) & 1;
      result = (result << 1) | bit;
    }
    return result;
  }
}

final class GanGen2PacketDecoder implements GanPacketDecoder {
  int _lastSerial = -1;
  int _cubeTimestampMs = 0;
  DateTime? _lastReceivedAt;

  @override
  Uint8List get requestFaceletsCommand => Uint8List(20)..[0] = 0x04;

  @override
  GanDecodedPacket decode(Uint8List packet, DateTime receivedAt) {
    final message = GanProtocolMessageView(packet);
    final eventType = message.getBitWord(0, 4);
    if (eventType == 0x04) {
      _lastSerial = message.getBitWord(4, 8);
      return GanDecodedPacket(
        states: [
          _decodeCubeState(
            message,
            serial: _lastSerial,
            receivedAt: receivedAt,
            cornerPermutationStart: 12,
            cornerOrientationStart: 33,
            edgePermutationStart: 47,
            edgeOrientationStart: 91,
          ),
        ],
      );
    }
    if (eventType != 0x02 || _lastSerial == -1) {
      return const GanDecodedPacket();
    }

    final serial = message.getBitWord(4, 8);
    final difference = ((serial - _lastSerial) & 0xff).clamp(0, 7);
    _lastSerial = serial;
    if (difference == 0) return const GanDecodedPacket();

    final moves = <SmartCubeMoveEvent>[];
    for (var index = difference - 1; index >= 0; index--) {
      final face = message.getBitWord(12 + 5 * index, 4);
      final direction = message.getBitWord(16 + 5 * index, 1);
      if (face >= _faceNames.length) continue;
      var elapsed = message.getBitWord(47 + 16 * index, 16);
      if (elapsed == 0 && index == 0 && _lastReceivedAt != null) {
        elapsed = receivedAt.difference(_lastReceivedAt!).inMilliseconds;
      }
      _cubeTimestampMs += elapsed;
      moves.add(
        SmartCubeMoveEvent(
          move: _moveFor(face, direction),
          serial: (serial - index) & 0xff,
          receivedAt: receivedAt,
          cubeTimestamp: Duration(milliseconds: _cubeTimestampMs),
          recovered: index != 0,
        ),
      );
    }
    _lastReceivedAt = receivedAt;
    return GanDecodedPacket(moves: moves);
  }
}

final class GanModernPacketDecoder implements GanPacketDecoder {
  GanModernPacketDecoder.gen3() : _isGen4 = false;

  GanModernPacketDecoder.gen4() : _isGen4 = true;

  final bool _isGen4;
  int _serial = -1;
  int _lastSerial = -1;
  DateTime? _lastLocalTimestamp;
  final List<SmartCubeMoveEvent> _moveBuffer = [];

  @override
  Uint8List get requestFaceletsCommand {
    if (_isGen4) {
      return Uint8List(20)..setRange(0, 6, [0xdd, 0x04, 0x00, 0xed, 0, 0]);
    }
    return Uint8List(16)..setRange(0, 2, [0x68, 0x01]);
  }

  @override
  GanDecodedPacket decode(Uint8List packet, DateTime receivedAt) {
    final message = GanProtocolMessageView(packet);
    final eventType =
        _isGen4 ? message.getBitWord(0, 8) : message.getBitWord(8, 8);
    final dataLength =
        _isGen4 ? message.getBitWord(8, 8) : message.getBitWord(16, 8);
    if (!_isGen4 && message.getBitWord(0, 8) != 0x55) {
      return const GanDecodedPacket();
    }

    if (eventType == 0x01) {
      return _decodeMove(message, receivedAt);
    }
    if (eventType == (_isGen4 ? 0xd1 : 0x06)) {
      return _decodeMoveHistory(message, dataLength, receivedAt);
    }
    if (eventType == (_isGen4 ? 0xed : 0x02)) {
      return _decodeFacelets(message, receivedAt);
    }
    return const GanDecodedPacket();
  }

  GanDecodedPacket _decodeMove(
    GanProtocolMessageView message,
    DateTime receivedAt,
  ) {
    if (_lastSerial == -1) return const GanDecodedPacket();
    _lastLocalTimestamp = receivedAt;
    final base = _isGen4 ? 16 : 24;
    final cubeTimestamp = message.getBitWord(base, 32, littleEndian: true);
    final serial = message.getBitWord(base + 32, 16, littleEndian: true);
    _serial = serial;
    final direction = message.getBitWord(base + 48, 2);
    final faceCode = message.getBitWord(base + 50, 6);
    final face = const [2, 32, 8, 1, 16, 4].indexOf(faceCode);
    if (face < 0 || direction > 1) return const GanDecodedPacket();

    _moveBuffer.add(
      SmartCubeMoveEvent(
        move: _moveFor(face, direction),
        serial: serial,
        receivedAt: receivedAt,
        cubeTimestamp: Duration(milliseconds: cubeTimestamp),
      ),
    );
    return _evictMoveBuffer(requestMissing: true);
  }

  GanDecodedPacket _decodeMoveHistory(
    GanProtocolMessageView message,
    int dataLength,
    DateTime receivedAt,
  ) {
    final base = _isGen4 ? 16 : 24;
    final startSerial = message.getBitWord(base, 8);
    final count = (dataLength - 1) * 2;
    for (var index = 0; index < count; index++) {
      final faceCode = message.getBitWord(base + 8 + 4 * index, 3);
      final face = const [1, 5, 3, 0, 4, 2].indexOf(faceCode);
      final direction = message.getBitWord(base + 11 + 4 * index, 1);
      if (face < 0) continue;
      _injectRecoveredMove(
        SmartCubeMoveEvent(
          move: _moveFor(face, direction),
          serial: (startSerial - index) & 0xff,
          receivedAt: receivedAt,
          recovered: true,
        ),
      );
    }
    return _evictMoveBuffer(requestMissing: false);
  }

  GanDecodedPacket _decodeFacelets(
    GanProtocolMessageView message,
    DateTime receivedAt,
  ) {
    final serialOffset = _isGen4 ? 16 : 24;
    _serial = message.getBitWord(serialOffset, 16, littleEndian: true);
    final state = _decodeCubeState(
      message,
      serial: _serial,
      receivedAt: receivedAt,
      cornerPermutationStart: _isGen4 ? 32 : 40,
      cornerOrientationStart: _isGen4 ? 53 : 61,
      edgePermutationStart: _isGen4 ? 69 : 77,
      edgeOrientationStart: _isGen4 ? 113 : 121,
    );
    if (_lastSerial == -1) {
      _lastSerial = _serial;
      return GanDecodedPacket(states: [state]);
    }
    final quietFor = receivedAt.difference(_lastLocalTimestamp ?? receivedAt);
    final difference = (_serial - _lastSerial) & 0xff;
    if (difference > 0 && quietFor > const Duration(milliseconds: 500)) {
      final bufferHead = _moveBuffer.firstOrNull;
      final startSerial = bufferHead?.serial ?? ((_serial + 1) & 0xff);
      return GanDecodedPacket(
        states: [state],
        commands: [_requestMoveHistory(startSerial, difference + 1)],
      );
    }
    return GanDecodedPacket(states: [state]);
  }

  GanDecodedPacket _evictMoveBuffer({required bool requestMissing}) {
    final moves = <SmartCubeMoveEvent>[];
    final commands = <Uint8List>[];
    while (_moveBuffer.isNotEmpty) {
      final head = _moveBuffer.first;
      final difference =
          _lastSerial == -1 ? 1 : (head.serial - _lastSerial) & 0xff;
      if (difference > 1) {
        if (requestMissing) {
          commands.add(_requestMoveHistory(head.serial, difference));
        }
        break;
      }
      moves.add(_moveBuffer.removeAt(0));
      _lastSerial = head.serial;
    }
    return GanDecodedPacket(moves: moves, commands: commands);
  }

  void _injectRecoveredMove(SmartCubeMoveEvent move) {
    if (_moveBuffer.isNotEmpty) {
      final head = _moveBuffer.first;
      if (_moveBuffer.any((buffered) => buffered.serial == move.serial)) return;
      if (!_isSerialInRange(_lastSerial, head.serial, move.serial)) return;
      if (move.serial == ((head.serial - 1) & 0xff)) {
        _moveBuffer.insert(0, move);
      }
      return;
    }
    if (_isSerialInRange(_lastSerial, _serial, move.serial, closedEnd: true)) {
      _moveBuffer.insert(0, move);
    }
  }

  bool _isSerialInRange(
    int start,
    int end,
    int serial, {
    bool closedStart = false,
    bool closedEnd = false,
  }) {
    return ((end - start) & 0xff) >= ((serial - start) & 0xff) &&
        (closedStart || ((start - serial) & 0xff) > 0) &&
        (closedEnd || ((end - serial) & 0xff) > 0);
  }

  Uint8List _requestMoveHistory(int serial, int count) {
    var alignedSerial = serial;
    var alignedCount = count;
    if (alignedSerial.isEven) alignedSerial = (alignedSerial - 1) & 0xff;
    if (alignedCount.isOdd) alignedCount++;
    alignedCount = alignedCount.clamp(0, alignedSerial + 1);
    final command = Uint8List(_isGen4 ? 20 : 16);
    command.setRange(
      0,
      6,
      _isGen4
          ? [0xd1, 0x04, alignedSerial, 0, alignedCount, 0]
          : [0x68, 0x03, alignedSerial, 0, alignedCount, 0],
    );
    return command;
  }
}

const _faceNames = 'URFDLB';

CubeMove _moveFor(int face, int direction) {
  return CubeMove.parse('${_faceNames[face]}${direction == 1 ? "'" : ''}');
}

SmartCubeStateEvent _decodeCubeState(
  GanProtocolMessageView message, {
  required int serial,
  required DateTime receivedAt,
  required int cornerPermutationStart,
  required int cornerOrientationStart,
  required int edgePermutationStart,
  required int edgeOrientationStart,
}) {
  final cornerPermutation = <int>[];
  final cornerOrientation = <int>[];
  final edgePermutation = <int>[];
  final edgeOrientation = <int>[];
  for (var index = 0; index < 7; index++) {
    cornerPermutation.add(
      message.getBitWord(cornerPermutationStart + index * 3, 3),
    );
    cornerOrientation.add(
      message.getBitWord(cornerOrientationStart + index * 2, 2),
    );
  }
  cornerPermutation.add(28 - cornerPermutation.fold(0, (a, b) => a + b));
  cornerOrientation.add(
    (3 - (cornerOrientation.fold(0, (a, b) => a + b) % 3)) % 3,
  );
  for (var index = 0; index < 11; index++) {
    edgePermutation.add(
      message.getBitWord(edgePermutationStart + index * 4, 4),
    );
    edgeOrientation.add(message.getBitWord(edgeOrientationStart + index, 1));
  }
  edgePermutation.add(66 - edgePermutation.fold(0, (a, b) => a + b));
  edgeOrientation.add((2 - (edgeOrientation.fold(0, (a, b) => a + b) % 2)) % 2);
  final facelets = _toKociembaFacelets(
    cornerPermutation,
    cornerOrientation,
    edgePermutation,
    edgeOrientation,
  );
  return SmartCubeStateEvent(
    state: CubeState.fromFacelets(facelets),
    serial: serial,
    receivedAt: receivedAt,
  );
}

const _cornerFaceletMap = [
  [8, 9, 20],
  [6, 18, 38],
  [0, 36, 47],
  [2, 45, 11],
  [29, 26, 15],
  [27, 44, 24],
  [33, 53, 42],
  [35, 17, 51],
];

const _edgeFaceletMap = [
  [5, 10],
  [7, 19],
  [3, 37],
  [1, 46],
  [32, 16],
  [28, 25],
  [30, 43],
  [34, 52],
  [23, 12],
  [21, 41],
  [50, 39],
  [48, 14],
];

String _toKociembaFacelets(
  List<int> cornerPermutation,
  List<int> cornerOrientation,
  List<int> edgePermutation,
  List<int> edgeOrientation,
) {
  const faces = 'URFDLB';
  final facelets = List<String>.generate(54, (index) => faces[index ~/ 9]);
  for (var index = 0; index < 8; index++) {
    for (var position = 0; position < 3; position++) {
      facelets[_cornerFaceletMap[index][(position + cornerOrientation[index]) %
              3]] =
          faces[_cornerFaceletMap[cornerPermutation[index]][position] ~/ 9];
    }
  }
  for (var index = 0; index < 12; index++) {
    for (var position = 0; position < 2; position++) {
      facelets[_edgeFaceletMap[index][(position + edgeOrientation[index]) %
              2]] =
          faces[_edgeFaceletMap[edgePermutation[index]][position] ~/ 9];
    }
  }
  return facelets.join();
}
