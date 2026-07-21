import 'dart:async';

import '../../application/cube_connection_gateway.dart';
import '../../domain/cube_connection_diagnostics.dart';
import '../ble/ble_central.dart';

Future<R> connectAndSetUpBleDevice<P extends Object, R>({
  required BleCentral central,
  required String deviceId,
  required CubeDiagnosticSink? onDiagnostic,
  required P? Function(List<String> services) resolveProtocol,
  required CubeConnectionFailure Function() unsupportedFailure,
  required FutureOr<R> Function(P protocol) createSession,
}) async {
  onDiagnostic?.call('ble.connect.started', null);
  try {
    await central.connect(deviceId);
    onDiagnostic?.call('ble.connect.succeeded', null);
  } catch (_) {
    onDiagnostic?.call('ble.connect.failed', null);
    rethrow;
  }

  try {
    onDiagnostic?.call('gatt.discovery.started', null);
    final services = await central.discoverServiceUuids(deviceId);
    final protocol = resolveProtocol(services);
    onDiagnostic?.call(
      'gatt.discovery.succeeded',
      'serviceCount=${services.length} protocolMatched=${protocol != null}',
    );
    if (protocol == null) throw unsupportedFailure();
    return await createSession(protocol);
  } catch (_) {
    try {
      await central.disconnect(deviceId);
    } catch (_) {
      // Preserve the original setup error when cleanup also fails.
    }
    rethrow;
  }
}
