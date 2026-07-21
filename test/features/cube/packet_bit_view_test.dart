import 'dart:typed_data';

import 'package:crubik/features/cube/data/packet_bit_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads MSB-first fields across byte boundaries', () {
    final bits = PacketBitView(
      Uint8List.fromList([0xb3, 0x5c]),
      protocolName: 'Test',
    );

    expect(bits.read(0, 4), 0xb);
    expect(bits.read(6, 5), 0x1a);
    expect(bits.read(8, 8), 0x5c);
  });

  test('reads supported little-endian words', () {
    final bits = PacketBitView(
      Uint8List.fromList([0x34, 0x12, 0x78, 0x56]),
      protocolName: 'Test',
    );

    expect(bits.read(0, 16, littleEndian: true), 0x1234);
    expect(bits.read(0, 32, littleEndian: true), 0x56781234);
  });

  test('rejects invalid and out-of-bounds fields', () {
    final bits = PacketBitView(Uint8List(1), protocolName: 'Test');

    expect(() => bits.read(-1, 1), throwsFormatException);
    expect(() => bits.read(0, 0), throwsFormatException);
    expect(() => bits.read(7, 2), throwsFormatException);
  });
}
