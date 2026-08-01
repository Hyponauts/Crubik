import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build_test/build_test.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/external_asset_fetcher.dart';

void main() {
  group('ExternalAssetFetcher', () {
    test('writes verified bytes for the locked package version', () async {
      final bytes = utf8.encode('verified external asset');
      Uri? requestedUri;
      final result = await testBuilder(
        _fetcher(
          downloader: (uri) async {
            requestedUri = uri;
            return bytes;
          },
        ),
        _sourceAssets(metadata: _metadataFor(bytes)),
        generateFor: const {'crubik|tool/sqlite3_wasm_asset.json'},
        outputs: {'crubik|web/sqlite3.wasm': bytes},
        rootPackage: 'crubik',
      );

      expect(result.succeeded, isTrue);
      expect(requestedUri, Uri.parse(_downloadUri));
    });

    test('rejects a checksum mismatch without writing output', () async {
      final expected = utf8.encode('expected');
      final result = await _runFailingFetcher(
        metadata: _metadataFor(expected),
        downloader: (_) async => utf8.encode('different'),
      );

      expect(result.errors.join('\n'), contains('failed SHA-256 verification'));
      expect(result.outputs, isEmpty);
    });

    test('rejects a lockfile version mismatch before downloading', () async {
      var downloaded = false;
      final bytes = utf8.encode('verified external asset');
      final result = await _runFailingFetcher(
        metadata: _metadataFor(bytes),
        lockedVersion: '2.9.3',
        downloader: (_) async {
          downloaded = true;
          return bytes;
        },
      );

      expect(
        result.errors.join('\n'),
        contains('pubspec.lock contains sqlite3 2.9.3'),
      );
      expect(downloaded, isFalse);
      expect(result.outputs, isEmpty);
    });

    test('rejects a non-HTTPS download URL', () async {
      var downloaded = false;
      final bytes = utf8.encode('verified external asset');
      final result = await _runFailingFetcher(
        metadata: _metadataFor(bytes, url: 'http://example.com/asset.bin'),
        downloader: (_) async {
          downloaded = true;
          return bytes;
        },
      );

      expect(result.errors.join('\n'), contains('absolute HTTPS URL'));
      expect(downloaded, isFalse);
      expect(result.outputs, isEmpty);
    });
  });

  group('fetchExternalAsset', () {
    test('requires an HTTP 200 response', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      });

      try {
        await expectLater(
          fetchExternalAsset(_serverUri(server)),
          throwsA(
            isA<HttpException>().having(
              (error) => error.message,
              'message',
              contains('HTTP 503'),
            ),
          ),
        );
      } finally {
        await server.close(force: true);
      }
    });

    test('enforces the response size limit while streaming', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.add(const [1, 2, 3, 4]);
        await request.response.close();
      });

      try {
        await expectLater(
          fetchExternalAsset(_serverUri(server), maximumBytes: 3),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('3-byte safety limit'),
            ),
          ),
        );
      } finally {
        await server.close(force: true);
      }
    });

    test('enforces the total fetch timeout', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((_) {});

      try {
        await expectLater(
          fetchExternalAsset(
            _serverUri(server),
            timeout: const Duration(milliseconds: 20),
          ),
          throwsA(isA<TimeoutException>()),
        );
      } finally {
        await server.close(force: true);
      }
    });
  });
}

const _inputPath = 'tool/sqlite3_wasm_asset.json';
const _outputPath = 'web/sqlite3.wasm';
const _downloadUri = 'https://example.com/asset.bin';

ExternalAssetFetcher _fetcher({required ExternalAssetDownloader downloader}) =>
    ExternalAssetFetcher(
      inputPath: _inputPath,
      outputPath: _outputPath,
      lockedPackage: 'sqlite3',
      downloader: downloader,
    );

Future<TestBuilderResult> _runFailingFetcher({
  required String metadata,
  required ExternalAssetDownloader downloader,
  String lockedVersion = '2.9.4',
}) {
  return testBuilder(
    _fetcher(downloader: downloader),
    _sourceAssets(metadata: metadata, lockedVersion: lockedVersion),
    generateFor: const {'crubik|tool/sqlite3_wasm_asset.json'},
    rootPackage: 'crubik',
  );
}

Map<String, Object> _sourceAssets({
  required String metadata,
  String lockedVersion = '2.9.4',
}) => {
  'crubik|tool/sqlite3_wasm_asset.json': metadata,
  'crubik|pubspec.lock':
      '''
packages:
  sqlite3:
    version: "$lockedVersion"
''',
};

String _metadataFor(List<int> bytes, {String url = _downloadUri}) => jsonEncode(
  {'version': '2.9.4', 'url': url, 'sha256': sha256.convert(bytes).toString()},
);

Uri _serverUri(HttpServer server) =>
    Uri.parse('http://${server.address.address}:${server.port}/asset.bin');
