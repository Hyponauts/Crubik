import 'dart:typed_data';

/// Reads bounds-checked bit fields from a cube protocol packet.
final class PacketBitView {
  PacketBitView(this._bytes, {required this.protocolName});

  final Uint8List _bytes;
  final String protocolName;

  int read(int startBit, int bitLength, {bool littleEndian = false}) {
    if (startBit < 0 ||
        bitLength <= 0 ||
        startBit + bitLength > _bytes.length * 8) {
      throw FormatException(
        '$protocolName packet field exceeds packet bounds.',
      );
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
      final byte = _bytes[absoluteBit ~/ 8];
      final bit = (byte >> (7 - absoluteBit % 8)) & 1;
      result = (result << 1) | bit;
    }
    return result;
  }
}
