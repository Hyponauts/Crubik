import 'dart:typed_data';

import '../domain/cube_model.dart';
import '../domain/smart_cube_event.dart';
import 'cube_packet_cipher.dart';
import 'packet_bit_view.dart';

export 'cube_packet_cipher.dart' show cubeMacSalt, normalizeCubeMac;

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

enum GanPacketKind { state, move, moveHistory, ignored }

final class GanDecodedPacket {
  const GanDecodedPacket({
    required this.kind,
    this.events = const [],
    this.commands = const [],
  });

  final GanPacketKind kind;
  final List<SmartCubeEvent> events;
  final List<Uint8List> commands;

  Iterable<SmartCubeMoveEvent> get moves => events.whereType();

  Iterable<SmartCubeStateEvent> get states => events.whereType();
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

enum GanEncryptionKey { gan, moyuAi2023 }

final class GanCubeCipher {
  GanCubeCipher({
    required List<int> macSalt,
    GanEncryptionKey encryptionKey = GanEncryptionKey.gan,
  }) {
    final material = switch (encryptionKey) {
      GanEncryptionKey.gan => _ganKeyMaterial,
      GanEncryptionKey.moyuAi2023 => _moyuAiKeyMaterial,
    };
    _cipher = MacSaltedAesCubeCipher(
      key: material.key,
      iv: material.iv,
      macSalt: macSalt,
    );
  }

  late final MacSaltedAesCubeCipher _cipher;

  Uint8List encrypt(Uint8List data) => _cipher.encrypt(data);

  Uint8List decrypt(Uint8List data) => _cipher.decrypt(data);
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
  GanProtocolMessageView(Uint8List message)
    : _bits = PacketBitView(message, protocolName: 'GAN');

  final PacketBitView _bits;

  int getBitWord(int startBit, int bitLength, {bool littleEndian = false}) =>
      _bits.read(startBit, bitLength, littleEndian: littleEndian);
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
        kind: GanPacketKind.state,
        events: [
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
      return GanDecodedPacket(
        kind: eventType == 0x02 ? GanPacketKind.move : GanPacketKind.ignored,
      );
    }

    final serial = message.getBitWord(4, 8);
    final difference = ((serial - _lastSerial) & 0xff).clamp(0, 7);
    _lastSerial = serial;
    if (difference == 0) {
      return const GanDecodedPacket(kind: GanPacketKind.move);
    }

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
    return GanDecodedPacket(kind: GanPacketKind.move, events: moves);
  }
}

final class GanModernPacketDecoder implements GanPacketDecoder {
  GanModernPacketDecoder.gen3() : _layout = _ganGen3Layout;

  GanModernPacketDecoder.gen4() : _layout = _ganGen4Layout;

  final _GanModernPacketLayout _layout;
  int _serial = -1;
  int _lastSerial = -1;
  DateTime? _lastLocalTimestamp;
  final List<SmartCubeMoveEvent> _moveBuffer = [];

  @override
  Uint8List get requestFaceletsCommand {
    return Uint8List(_layout.commandLength)..setRange(
      0,
      _layout.faceletsCommandPrefix.length,
      _layout.faceletsCommandPrefix,
    );
  }

  @override
  GanDecodedPacket decode(Uint8List packet, DateTime receivedAt) {
    final message = GanProtocolMessageView(packet);
    final eventType = message.getBitWord(_layout.eventTypeStart, 8);
    final dataLength = message.getBitWord(_layout.dataLengthStart, 8);
    final header = _layout.header;
    if (header != null && message.getBitWord(0, 8) != header) {
      return const GanDecodedPacket(kind: GanPacketKind.ignored);
    }

    if (eventType == 0x01) {
      return _decodeMove(message, receivedAt);
    }
    if (eventType == _layout.moveHistoryEvent) {
      return _decodeMoveHistory(message, dataLength, receivedAt);
    }
    if (eventType == _layout.faceletsEvent) {
      return _decodeFacelets(message, receivedAt);
    }
    return const GanDecodedPacket(kind: GanPacketKind.ignored);
  }

  GanDecodedPacket _decodeMove(
    GanProtocolMessageView message,
    DateTime receivedAt,
  ) {
    if (_lastSerial == -1) {
      return const GanDecodedPacket(kind: GanPacketKind.move);
    }
    _lastLocalTimestamp = receivedAt;
    final base = _layout.dataStart;
    final cubeTimestamp = message.getBitWord(base, 32, littleEndian: true);
    final serial = message.getBitWord(base + 32, 16, littleEndian: true);
    _serial = serial;
    final direction = message.getBitWord(base + 48, 2);
    final faceCode = message.getBitWord(base + 50, 6);
    final face = const [2, 32, 8, 1, 16, 4].indexOf(faceCode);
    if (face < 0 || direction > 1) {
      return const GanDecodedPacket(kind: GanPacketKind.move);
    }

    _moveBuffer.add(
      SmartCubeMoveEvent(
        move: _moveFor(face, direction),
        serial: serial,
        receivedAt: receivedAt,
        cubeTimestamp: Duration(milliseconds: cubeTimestamp),
      ),
    );
    return _evictMoveBuffer(kind: GanPacketKind.move, requestMissing: true);
  }

  GanDecodedPacket _decodeMoveHistory(
    GanProtocolMessageView message,
    int dataLength,
    DateTime receivedAt,
  ) {
    final base = _layout.dataStart;
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
    return _evictMoveBuffer(
      kind: GanPacketKind.moveHistory,
      requestMissing: false,
    );
  }

  GanDecodedPacket _decodeFacelets(
    GanProtocolMessageView message,
    DateTime receivedAt,
  ) {
    _serial = message.getBitWord(_layout.dataStart, 16, littleEndian: true);
    final state = _decodeCubeState(
      message,
      serial: _serial,
      receivedAt: receivedAt,
      cornerPermutationStart: _layout.cornerPermutationStart,
      cornerOrientationStart: _layout.cornerOrientationStart,
      edgePermutationStart: _layout.edgePermutationStart,
      edgeOrientationStart: _layout.edgeOrientationStart,
    );
    if (_lastSerial == -1) {
      _lastSerial = _serial;
      return GanDecodedPacket(kind: GanPacketKind.state, events: [state]);
    }
    final quietFor = receivedAt.difference(_lastLocalTimestamp ?? receivedAt);
    final difference = (_serial - _lastSerial) & 0xff;
    if (difference > 0 && quietFor > const Duration(milliseconds: 500)) {
      final bufferHead = _moveBuffer.firstOrNull;
      final startSerial = bufferHead?.serial ?? ((_serial + 1) & 0xff);
      return GanDecodedPacket(
        kind: GanPacketKind.state,
        events: [state],
        commands: [_requestMoveHistory(startSerial, difference + 1)],
      );
    }
    return GanDecodedPacket(kind: GanPacketKind.state, events: [state]);
  }

  GanDecodedPacket _evictMoveBuffer({
    required GanPacketKind kind,
    required bool requestMissing,
  }) {
    final moves = <SmartCubeMoveEvent>[];
    final commands = <Uint8List>[];
    while (_moveBuffer.isNotEmpty) {
      final head = _moveBuffer.first;
      final difference = _lastSerial == -1
          ? 1
          : (head.serial - _lastSerial) & 0xff;
      if (difference > 1) {
        if (requestMissing) {
          commands.add(_requestMoveHistory(head.serial, difference));
        }
        break;
      }
      moves.add(_moveBuffer.removeAt(0));
      _lastSerial = head.serial;
    }
    return GanDecodedPacket(kind: kind, events: moves, commands: commands);
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
    final command = Uint8List(_layout.commandLength);
    command.setRange(0, 6, [
      ..._layout.moveHistoryCommandPrefix,
      alignedSerial,
      0,
      alignedCount,
      0,
    ]);
    return command;
  }
}

final class _GanModernPacketLayout {
  const _GanModernPacketLayout({
    required this.commandLength,
    required this.faceletsCommandPrefix,
    required this.moveHistoryCommandPrefix,
    required this.eventTypeStart,
    required this.dataLengthStart,
    required this.dataStart,
    required this.moveHistoryEvent,
    required this.faceletsEvent,
    required this.cornerPermutationStart,
    required this.cornerOrientationStart,
    required this.edgePermutationStart,
    required this.edgeOrientationStart,
    this.header,
  });

  final int commandLength;
  final List<int> faceletsCommandPrefix;
  final List<int> moveHistoryCommandPrefix;
  final int eventTypeStart;
  final int dataLengthStart;
  final int dataStart;
  final int moveHistoryEvent;
  final int faceletsEvent;
  final int cornerPermutationStart;
  final int cornerOrientationStart;
  final int edgePermutationStart;
  final int edgeOrientationStart;
  final int? header;
}

const _ganGen3Layout = _GanModernPacketLayout(
  commandLength: 16,
  faceletsCommandPrefix: [0x68, 0x01],
  moveHistoryCommandPrefix: [0x68, 0x03],
  eventTypeStart: 8,
  dataLengthStart: 16,
  dataStart: 24,
  moveHistoryEvent: 0x06,
  faceletsEvent: 0x02,
  cornerPermutationStart: 40,
  cornerOrientationStart: 61,
  edgePermutationStart: 77,
  edgeOrientationStart: 121,
  header: 0x55,
);

const _ganGen4Layout = _GanModernPacketLayout(
  commandLength: 20,
  faceletsCommandPrefix: [0xdd, 0x04, 0x00, 0xed, 0, 0],
  moveHistoryCommandPrefix: [0xd1, 0x04],
  eventTypeStart: 0,
  dataLengthStart: 8,
  dataStart: 16,
  moveHistoryEvent: 0xd1,
  faceletsEvent: 0xed,
  cornerPermutationStart: 32,
  cornerOrientationStart: 53,
  edgePermutationStart: 69,
  edgeOrientationStart: 113,
);

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
  return SmartCubeStateEvent(
    state: CubeState.fromCubieCoordinates(
      cornerPermutation: cornerPermutation,
      cornerOrientations: cornerOrientation,
      edgePermutation: edgePermutation,
      edgeOrientations: edgeOrientation,
    ),
    serial: serial,
    receivedAt: receivedAt,
  );
}
