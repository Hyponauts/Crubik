import 'dart:async';

import 'package:crubik/app/crubik_app.dart';
import 'package:crubik/features/cube/data/cube_connection_controller.dart';
import 'package:crubik/features/cube/data/gan_cube_protocol.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
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
      transport: _SilentBleTransport(),
    );
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pump();

    expect(find.byKey(const Key('practice-mobile-layout')), findsOneWidget);
    expect(find.text('Offline practice ready'), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(find.text('STOP & SAVE'), findsOneWidget);

    clock.value = const Duration(milliseconds: 12340);
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(practice.solves, hasLength(1));

    await tester.fling(
      find.byType(ListView).first,
      const Offset(0, -900),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cube-move-R')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cube-move-R')));
    await tester.pump();
    expect(practice.currentMoves, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop layout presents practice and session side by side', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);

    final practice = PracticeController();
    final transport = _SilentBleTransport();
    final connection = CubeConnectionController(transport: transport);
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pump();

    expect(find.byKey(const Key('practice-desktop-layout')), findsOneWidget);
    expect(find.text('SESSION SNAPSHOT'), findsOneWidget);
    expect(find.text('PRACTICE SCRAMBLE'), findsOneWidget);

    transport.addMove(
      SmartCubeMoveEvent(
        move: CubeMove.parse('R'),
        serial: 1,
        receivedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();
    expect(practice.currentMoves.single.notation, 'R');

    transport.addState(
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
      transport: _SilentBleTransport(),
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

final class _SilentBleTransport implements BleCubeTransport {
  final _scanController = StreamController<CubeDeviceCandidate>.broadcast();
  final _moveController = StreamController<SmartCubeMoveEvent>.broadcast();
  final _stateController = StreamController<SmartCubeStateEvent>.broadcast();

  @override
  Stream<CubeDeviceCandidate> get scanResults => _scanController.stream;

  @override
  Stream<SmartCubeMoveEvent> get moveEvents => _moveController.stream;

  @override
  Stream<SmartCubeStateEvent> get stateEvents => _stateController.stream;

  @override
  Future<void> connect(CubeDeviceCandidate device) async {}

  @override
  Stream<bool> connectionState(String deviceId) => const Stream.empty();

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  void addMove(SmartCubeMoveEvent event) => _moveController.add(event);

  void addState(SmartCubeStateEvent event) => _stateController.add(event);
}
