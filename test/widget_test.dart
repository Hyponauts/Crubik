import 'dart:async';

import 'package:crubik/app/crubik_app.dart';
import 'package:crubik/features/cube/application/cube_connection_controller.dart';
import 'package:crubik/features/cube/data/adapters/smart_cube_adapter.dart';
import 'package:crubik/features/cube/data/cube_connection_gateway.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/cube/domain/smart_cube_event.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile layout supports the core offline practice flow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final clock = _FakeSolveClock();
    final practice = PracticeController(clock: clock);
    final connection = CubeConnectionController(
      gateway: _SilentCubeConnectionGateway(),
    );
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pump();

    expect(find.byKey(const Key('practice-mobile-layout')), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-reset-view')), findsOneWidget);
    expect(find.byKey(const Key('manual-moves-button')), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(find.text('STOP & SAVE'), findsOneWidget);

    clock.value = const Duration(milliseconds: 12340);
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(practice.solves, hasLength(1));

    await tester.tap(find.byKey(const Key('manual-moves-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cube-move-R')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cube-move-R')));
    await tester.pump();
    expect(practice.currentMoves, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile practice fits a compact landscape viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 360);
    addTearDown(tester.view.reset);

    final practice = PracticeController();
    final connection = CubeConnectionController(
      gateway: _SilentCubeConnectionGateway(),
    );
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pump();

    expect(find.byKey(const Key('practice-mobile-layout')), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsOneWidget);
    expect(find.byKey(const Key('timer-toggle')), findsOneWidget);
    expect(find.byKey(const Key('manual-moves-button')), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
    await tester.tap(find.byKey(const Key('manual-moves-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cube-move-R')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile practice fits at 1.3 text scaling', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final practice = PracticeController();
    final connection = CubeConnectionController(
      gateway: _SilentCubeConnectionGateway(),
    );
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pump();

    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsOneWidget);
    expect(find.byKey(const Key('timer-toggle')), findsOneWidget);
    expect(find.byKey(const Key('manual-moves-button')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('mobile session fixes its summary above a bounded history list', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);

    final clock = _FakeSolveClock();
    var timestamp = DateTime.utc(2026);
    final practice = PracticeController(
      clock: clock,
      now: () => timestamp = timestamp.add(const Duration(seconds: 1)),
    );
    for (var index = 0; index < 8; index++) {
      practice.startSolve();
      clock.value = Duration(seconds: 10 + index);
      practice.stopSolve();
    }
    final connection = CubeConnectionController(
      gateway: _SilentCubeConnectionGateway(),
    );
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.tap(find.text('Session'));
    await tester.pump();

    expect(find.byKey(const Key('export-solves-button')), findsOneWidget);
    expect(find.text('BEST'), findsOneWidget);
    expect(find.text('MEAN'), findsOneWidget);
    expect(find.text('AO5'), findsOneWidget);
    expect(find.byKey(const Key('recent-solves-list')), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    await tester.fling(
      find.byKey(const Key('recent-solves-list')),
      const Offset(0, -300),
      800,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-solves-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop layout presents practice and session side by side', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);

    final practice = PracticeController();
    final gateway = _SilentCubeConnectionGateway();
    final connection = CubeConnectionController(gateway: gateway);
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pump();
    await connection.connect(_supportedGan);

    expect(find.byKey(const Key('practice-desktop-layout')), findsOneWidget);
    expect(find.text('SESSION SNAPSHOT'), findsOneWidget);
    expect(find.text('PRACTICE SCRAMBLE'), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsOneWidget);

    gateway.addEvent(
      SmartCubeMoveEvent(
        move: CubeMove.parse('R'),
        serial: 1,
        receivedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();
    expect(practice.currentMoves.single.notation, 'R');

    gateway.addEvent(
      SmartCubeStateEvent(
        state: CubeState.solved(),
        serial: 1,
        receivedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();
    expect(practice.cubeState.isSolved, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection dialog offers supported scan and demo mode', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final practice = PracticeController();
    final connection = CubeConnectionController(
      gateway: _SilentCubeConnectionGateway(),
    );
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.tap(find.byKey(const Key('connect-cube-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('MVP protocols: GAN Gen2–4 and MoYu AI 2023'),
      findsOneWidget,
    );
    expect(find.text('Scan nearby'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);

    await tester.tap(find.text('Demo'));
    await tester.pumpAndSettle();
    expect(connection.isConnected, isTrue);
    expect(connection.isDemo, isTrue);
  });

  testWidgets('connection dialog groups cubes and other BLE devices', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final practice = PracticeController();
    final gateway = _SilentCubeConnectionGateway();
    final connection = CubeConnectionController(gateway: gateway);
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.tap(find.byKey(const Key('connect-cube-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan nearby'));
    await tester.pump();

    gateway
      ..addDevice(
        const CubeDeviceCandidate(
          id: 'moyu-wcu',
          name: 'WCU_MY32',
          vendor: CubeVendor.moyu,
          protocolFamily: CubeProtocolFamily.moyu32,
          supportStatus: CubeSupportStatus.detectedUnsupported,
          rssi: -35,
          supportMessage:
              'This WCU MoYu cube uses the MoYu32 protocol, which is detected but not supported yet.',
        ),
      )
      ..addDevice(
        const CubeDeviceCandidate(
          id: 'speaker',
          name: 'Desk speaker',
          rssi: -20,
        ),
      );
    await tester.pump();

    expect(find.text('Cubes'), findsOneWidget);
    expect(find.text('Other available devices'), findsOneWidget);
    expect(find.text('WCU_MY32'), findsOneWidget);
    expect(find.text('MOYU · Detected, not supported yet'), findsOneWidget);
    expect(find.textContaining('MoYu32 protocol'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('WCU_MY32')).dy,
      lessThan(tester.getTopLeft(find.text('Other available devices')).dy),
    );

    await tester.drag(
      find.byKey(const Key('discovered-device-list')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(find.text('Desk speaker'), findsOneWidget);
    expect(
      find.textContaining('Not identified as a smart cube'),
      findsOneWidget,
    );
    expect(find.text('Connect'), findsNothing);
    expect(tester.takeException(), isNull);

    await connection.stopScan();
    await tester.pump();
  });

  testWidgets('connection dialog explains unsupported MoYu MHC cubes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final practice = PracticeController();
    final gateway = _SilentCubeConnectionGateway();
    final connection = CubeConnectionController(gateway: gateway);
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.tap(find.byKey(const Key('connect-cube-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan nearby'));
    await tester.pump();

    gateway.addDevice(
      const CubeDeviceCandidate(
        id: 'moyu-v10',
        name: 'MHC-AB12',
        vendor: CubeVendor.moyu,
        protocolFamily: CubeProtocolFamily.moyuMhc,
        supportStatus: CubeSupportStatus.detectedUnsupported,
        rssi: -35,
        supportMessage:
            'MoYu MHC cubes such as the WeiLong V10 AI are detected, but their protocol is not supported yet.',
      ),
    );
    await tester.pump();

    expect(find.text('MHC-AB12'), findsOneWidget);
    expect(find.text('MOYU · Detected, not supported yet'), findsOneWidget);
    expect(find.textContaining('WeiLong V10 AI'), findsOneWidget);
    expect(find.text('Connect'), findsNothing);
    expect(tester.takeException(), isNull);

    await connection.stopScan();
    await tester.pump();
  });
}

final class _FakeSolveClock implements SolveClock {
  Duration value = Duration.zero;

  @override
  Duration get elapsed => value;

  @override
  void reset() => value = Duration.zero;

  @override
  void start() {}

  @override
  void stop() {}
}

const _supportedGan = CubeDeviceCandidate(
  id: 'gan-test',
  name: 'GAN12ui',
  vendor: CubeVendor.gan,
  protocolFamily: CubeProtocolFamily.gan,
  supportStatus: CubeSupportStatus.supported,
  adapterId: 'gan-family',
);

final class _SilentCubeConnectionGateway implements CubeConnectionGateway {
  final _scanController = StreamController<CubeDeviceCandidate>.broadcast();
  final _session = _SilentSmartCubeSession();
  bool _closed = false;

  @override
  Stream<CubeDeviceCandidate> get scanResults => _scanController.stream;

  @override
  Future<SmartCubeSession> connect(CubeDeviceCandidate device) async =>
      _session;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  void addEvent(SmartCubeEvent event) => _session.addEvent(event);

  void addDevice(CubeDeviceCandidate device) => _scanController.add(device);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _scanController.close();
    await _session.close();
  }
}

final class _SilentSmartCubeSession implements SmartCubeSession {
  final _eventController = StreamController<SmartCubeEvent>.broadcast();
  bool _closed = false;

  @override
  CubeCapabilities get capabilities =>
      const CubeCapabilities(initialState: true);

  @override
  Stream<bool> get connectionStates => const Stream.empty();

  @override
  Stream<SmartCubeEvent> get events => _eventController.stream;

  void addEvent(SmartCubeEvent event) => _eventController.add(event);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _eventController.close();
  }
}
