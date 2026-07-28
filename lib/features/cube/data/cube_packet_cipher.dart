import 'dart:typed_data';

import 'package:pointycastle/export.dart';

final class MacSaltedAesCubeCipher {
  MacSaltedAesCubeCipher({
    required List<int> key,
    required List<int> iv,
    required List<int> macSalt,
  }) {
    if (key.length != 16 || iv.length != 16) {
      throw const FormatException('Cube cipher key and IV must be 16 bytes.');
    }
    if (macSalt.length != 6) {
      throw const FormatException('Cube MAC salt must contain 6 bytes.');
    }
    _key = Uint8List.fromList(key);
    _iv = Uint8List.fromList(iv);
    for (var index = 0; index < macSalt.length; index++) {
      _key[index] = (key[index] + macSalt[index]) % 0xff;
      _iv[index] = (iv[index] + macSalt[index]) % 0xff;
    }
  }

  late final Uint8List _key;
  late final Uint8List _iv;

  Uint8List encrypt(Uint8List data) {
    if (data.length < 16) {
      throw const FormatException(
        'Encrypted cube packets must be at least 16 bytes.',
      );
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
      throw const FormatException(
        'Encrypted cube packets must be at least 16 bytes.',
      );
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

String? normalizeCubeMac(String value) {
  final match = RegExp(
    r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  return value.trim().replaceAll('-', ':').toUpperCase();
}

List<int> cubeMacSalt(String macAddress) {
  final normalized = normalizeCubeMac(macAddress);
  if (normalized == null) {
    throw const FormatException('Invalid cube MAC address.');
  }
  return normalized
      .split(':')
      .reversed
      .map((part) => int.parse(part, radix: 16))
      .toList(growable: false);
}
