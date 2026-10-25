import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../features/practice/domain/solve_recording.dart';

/// Encodes versioned raw recording JSON as lossless gzip-compressed UTF-8.
Uint8List encodeSolveRecording(SolveRecording recording) {
  final json = jsonEncode(recording.toJson(includeDerivedTiming: false));
  return const GZipEncoder().encodeBytes(utf8.encode(json));
}

/// Decodes a stored gzip recording, rejecting corrupt or unsupported data.
SolveRecording decodeSolveRecording(Uint8List payload) {
  if (payload.length < 18 ||
      payload[0] != 0x1f ||
      payload[1] != 0x8b ||
      payload[2] != 8) {
    throw const FormatException('Invalid recording gzip header.');
  }

  final bytes = const GZipDecoder().decodeBytes(payload, verify: true);

  // archive's web decoder ignores verify, so check the gzip trailer explicitly.
  final trailer = ByteData.sublistView(payload, payload.length - 8);
  if (trailer.getUint32(0, Endian.little) != getCrc32(bytes) ||
      trailer.getUint32(4, Endian.little) != (bytes.length & 0xffffffff)) {
    throw const FormatException('Invalid recording gzip checksum or size.');
  }

  final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
  return SolveRecording.fromJson(json);
}
