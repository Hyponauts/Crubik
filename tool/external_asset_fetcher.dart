import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

typedef ExternalAssetDownloader = Future<List<int>> Function(Uri uri);

Builder externalAssetFetcher(BuilderOptions options) {
  final config = options.config;
  final inputPath = _requiredOption(config, 'input_path');
  final outputPath = _requiredOption(config, 'output_path');
  final lockedPackage = _optionalOption(config, 'locked_package');
  final timeoutSeconds = _positiveIntOption(
    config,
    'timeout_seconds',
    defaultExternalAssetFetchTimeout.inSeconds,
  );
  final maximumBytes = _positiveIntOption(
    config,
    'maximum_bytes',
    defaultExternalAssetMaximumBytes,
  );

  return ExternalAssetFetcher(
    inputPath: inputPath,
    outputPath: outputPath,
    lockedPackage: lockedPackage,
    timeout: Duration(seconds: timeoutSeconds),
    maximumBytes: maximumBytes,
  );
}

final class ExternalAssetFetcher implements Builder {
  ExternalAssetFetcher({
    required this.inputPath,
    required this.outputPath,
    this.lockedPackage,
    Duration timeout = defaultExternalAssetFetchTimeout,
    int maximumBytes = defaultExternalAssetMaximumBytes,
    ExternalAssetDownloader? downloader,
  }) : _maximumBytes = maximumBytes,
       _downloader =
           downloader ??
           ((uri) => fetchExternalAsset(
             uri,
             timeout: timeout,
             maximumBytes: maximumBytes,
           ));

  static const lockfilePath = 'pubspec.lock';

  final String inputPath;
  final String outputPath;
  final String? lockedPackage;
  final int _maximumBytes;
  final ExternalAssetDownloader _downloader;

  String get _assetName => outputPath.split('/').last;

  @override
  Map<String, List<String>> get buildExtensions => {
    '^$inputPath': [outputPath],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final metadata = _parseMetadata(
      await buildStep.readAsString(buildStep.inputId),
      inputPath: inputPath,
    );

    if (lockedPackage case final package?) {
      final metadataVersion = metadata.version;
      if (metadataVersion == null) {
        throw FormatException(
          '$inputPath must contain a version when locked_package is $package.',
        );
      }
      final lockfileId = AssetId(buildStep.inputId.package, lockfilePath);
      final lockedVersion = _readLockedPackageVersion(
        await buildStep.readAsString(lockfileId),
        package,
      );
      if (metadataVersion != lockedVersion) {
        throw StateError(
          '$_assetName metadata targets $package $metadataVersion, but '
          'pubspec.lock contains $package $lockedVersion. Update $inputPath '
          'with the matching URL and checksum.',
        );
      }
    }

    final bytes = await buildStep.trackStage(
      'fetch $_assetName',
      () => _downloader(metadata.uri),
      isExternal: true,
    );
    if (bytes.length > _maximumBytes) {
      throw StateError(
        'Fetched $_assetName is ${bytes.length} bytes, exceeding the '
        '$_maximumBytes-byte safety limit.',
      );
    }

    final actualDigest = sha256.convert(bytes).toString();
    if (actualDigest != metadata.sha256) {
      throw StateError(
        'Fetched $_assetName failed SHA-256 verification: expected '
        '${metadata.sha256}, got $actualDigest. No output was written.',
      );
    }

    final outputId = AssetId(buildStep.inputId.package, outputPath);
    await buildStep.writeAsBytes(outputId, bytes);
  }
}

const defaultExternalAssetFetchTimeout = Duration(seconds: 60);
const defaultExternalAssetMaximumBytes = 5 * 1024 * 1024;

Future<List<int>> fetchExternalAsset(
  Uri uri, {
  Duration timeout = defaultExternalAssetFetchTimeout,
  int maximumBytes = defaultExternalAssetMaximumBytes,
}) async {
  final stopwatch = Stopwatch()..start();
  final client = HttpClient()..connectionTimeout = timeout;
  StreamIterator<List<int>>? iterator;

  try {
    final request = await _beforeDeadline(
      client.getUrl(uri),
      stopwatch,
      timeout,
    );
    final response = await _beforeDeadline(request.close(), stopwatch, timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Failed to fetch external asset: HTTP ${response.statusCode} '
        '${response.reasonPhrase}',
        uri: uri,
      );
    }

    final bytes = BytesBuilder(copy: false);
    var byteCount = 0;
    iterator = StreamIterator(response);
    while (await _beforeDeadline(iterator.moveNext(), stopwatch, timeout)) {
      final chunk = iterator.current;
      byteCount += chunk.length;
      if (byteCount > maximumBytes) {
        throw StateError(
          'Fetched external asset exceeds the $maximumBytes-byte safety limit.',
        );
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  } on TimeoutException catch (_) {
    throw TimeoutException(
      'Timed out after ${timeout.inSeconds} seconds while fetching external '
      'asset from $uri.',
      timeout,
    );
  } finally {
    await iterator?.cancel();
    client.close(force: true);
  }
}

Future<T> _beforeDeadline<T>(
  Future<T> operation,
  Stopwatch stopwatch,
  Duration timeout,
) {
  final remaining = timeout - stopwatch.elapsed;
  if (remaining <= Duration.zero) {
    throw TimeoutException('The external asset fetch timed out.', timeout);
  }
  return operation.timeout(remaining);
}

_ExternalAssetMetadata _parseMetadata(
  String source, {
  required String inputPath,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    throw FormatException('Invalid $inputPath JSON: ${error.message}');
  }
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(
      'External asset metadata must be a JSON object.',
    );
  }

  final version = _optionalString(decoded, 'version');
  final url = _requiredString(decoded, 'url');
  final expectedSha256 = _requiredString(decoded, 'sha256').toLowerCase();
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
    throw const FormatException(
      'External asset metadata url must be an absolute HTTPS URL.',
    );
  }
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
    throw const FormatException(
      'External asset metadata sha256 must contain 64 hexadecimal characters.',
    );
  }

  return _ExternalAssetMetadata(
    version: version,
    uri: uri,
    sha256: expectedSha256,
  );
}

String _requiredString(Map<String, Object?> metadata, String key) {
  final value = _optionalString(metadata, key);
  if (value == null) {
    throw FormatException(
      'External asset metadata $key must be a non-empty string.',
    );
  }
  return value;
}

String? _optionalString(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException(
      'External asset metadata $key must be a non-empty string.',
    );
  }
  return value.trim();
}

String _readLockedPackageVersion(String source, String package) {
  final Object? lockfile;
  try {
    lockfile = loadYaml(source);
  } on YamlException catch (error) {
    throw FormatException('Invalid pubspec.lock YAML: ${error.message}');
  }

  if (lockfile is! YamlMap || lockfile['packages'] is! YamlMap) {
    throw const FormatException(
      'pubspec.lock does not contain a packages map.',
    );
  }
  final packages = lockfile['packages'] as YamlMap;
  final packageEntry = packages[package];
  if (packageEntry is! YamlMap || packageEntry['version'] is! String) {
    throw FormatException(
      'pubspec.lock does not contain a $package package version.',
    );
  }
  return packageEntry['version'] as String;
}

String _requiredOption(Map<String, dynamic> config, String key) {
  final value = _optionalOption(config, key);
  if (value == null) {
    throw ArgumentError.value(value, key, 'must be a non-empty string');
  }
  return value;
}

String? _optionalOption(Map<String, dynamic> config, String key) {
  final value = config[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError.value(value, key, 'must be a non-empty string');
  }
  return value.trim();
}

int _positiveIntOption(
  Map<String, dynamic> config,
  String key,
  int defaultValue,
) {
  final value = config[key] ?? defaultValue;
  if (value is! int || value <= 0) {
    throw ArgumentError.value(value, key, 'must be a positive integer');
  }
  return value;
}

final class _ExternalAssetMetadata {
  const _ExternalAssetMetadata({
    required this.version,
    required this.uri,
    required this.sha256,
  });

  final String? version;
  final Uri uri;
  final String sha256;
}
