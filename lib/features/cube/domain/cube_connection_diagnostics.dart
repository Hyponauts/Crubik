import 'smart_cube_device.dart';

typedef CubeDiagnosticSink = void Function(String stage, String? detail);

final class CubeConnectionDiagnostics {
  static const _maxEntries = 200;

  final Stopwatch _clock = Stopwatch();
  final List<CubeConnectionDiagnosticEntry> _entries = [];
  String _platform = 'unknown';

  bool get isNotEmpty => _entries.isNotEmpty;

  void begin({required String platform, required CubeDeviceCandidate device}) {
    _entries.clear();
    _platform = platform;
    _clock
      ..reset()
      ..start();
    add(
      'connection.requested',
      'vendor=${device.vendor.name} protocol=${device.protocolFamily.name} '
          'support=${device.supportStatus.name}',
    );
  }

  void add(String stage, [String? detail]) {
    if (_entries.length == _maxEntries) _entries.removeAt(0);
    _entries.add(
      CubeConnectionDiagnosticEntry(
        elapsed: _clock.elapsed,
        stage: stage,
        detail: detail,
      ),
    );
  }

  String exportReport() {
    final report = StringBuffer()
      ..writeln('Crubik Bluetooth diagnostics v1')
      ..writeln('platform=$_platform')
      ..writeln(
        'privacy=device identifiers, MAC addresses, advertisement payloads, '
        'packet bytes, and solve data omitted',
      );
    for (final entry in _entries) {
      final elapsed = entry.elapsed.inMilliseconds.toString().padLeft(5, '0');
      report
        ..write('+$elapsed ms ${entry.stage}')
        ..writeln(entry.detail == null ? '' : ' ${entry.detail}');
    }
    return report.toString();
  }
}

final class CubeConnectionDiagnosticEntry {
  const CubeConnectionDiagnosticEntry({
    required this.elapsed,
    required this.stage,
    this.detail,
  });

  final Duration elapsed;
  final String stage;
  final String? detail;
}
