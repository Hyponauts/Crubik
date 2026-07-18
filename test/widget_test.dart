import 'dart:async';
import 'dart:math';

import 'package:crubik/app/crubik_app.dart';
import 'package:crubik/core/theme/app_theme.dart';
import 'package:crubik/features/cube/application/cube_connection_controller.dart';
import 'package:crubik/features/cube/data/adapters/smart_cube_adapter.dart';
import 'package:crubik/features/cube/data/cube_connection_gateway.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/scramble_generator.dart';
import 'package:crubik/features/cube/domain/cube_connection_diagnostics.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/cube/domain/smart_cube_event.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    expect(practice.currentMoves, isEmpty);
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
    practice.setSmartCubeConnected(true);
    practice.syncCubeState(CubeState.solved());
    await tester.pump();
    expect(find.byKey(const Key('scramble-guidance')), findsOneWidget);
    expect(find.byKey(const Key('next-scramble-move')), findsOneWidget);
    expect(tester.takeException(), isNull);
    practice.setSmartCubeConnected(false, demoMode: true);
    await tester.pump();
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
    expect(find.text('OFFLINE CUBE LAB'), findsNothing);
    expect(find.text('OFFLINE READY'), findsNothing);
    expect(find.text('OFFLINE · 20 MOVES'), findsNothing);
    expect(find.text('No account or internet needed'), findsNothing);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);

    gateway.addEvent(
      SmartCubeMoveEvent(
        move: CubeMove.parse('R'),
        serial: 1,
        receivedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();
    expect(practice.currentMoves, isEmpty);

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

  testWidgets('connected mode guides scrambling and starts on the first move', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    var now = DateTime.utc(2026);
    final practice = PracticeController(
      scrambleGenerator: ScrambleGenerator(random: _DoubleTurnRandom()),
      now: () => now,
    );
    final gateway = _SilentCubeConnectionGateway();
    final connection = CubeConnectionController(gateway: gateway);
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await connection.connect(_supportedGan);
    gateway.addEvent(
      SmartCubeStateEvent(
        state: CubeState.solved(),
        serial: 0,
        receivedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();

    expect(practice.phase, PracticePhase.scrambling);
    expect(find.text('FOLLOW SCRAMBLE'), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.byKey(const Key('next-scramble-move')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('timer-toggle')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('manual-moves-button')))
          .onPressed,
      isNull,
    );

    final first = practice.scramble.moves.first;
    expect(first.turns, 2);
    gateway.addEvent(
      SmartCubeMoveEvent(
        move: CubeMove(first.face, turns: 3),
        serial: 1,
        receivedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();

    expect(practice.completedScrambleMoveCount, 0);
    expect(practice.partialScrambleMoveTurnCount, 1);
    expect(practice.guidanceIsCorrection, isFalse);
    expect(practice.nextScrambleMove, CubeMove(first.face, turns: 3));
    expect(find.byKey(const Key('partial-scramble-progress')), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.textContaining('Wrong turn detected'), findsNothing);

    gateway.addEvent(
      SmartCubeMoveEvent(
        move: CubeMove(first.face, turns: 3),
        serial: 2,
        receivedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();

    expect(practice.completedScrambleMoveCount, 1);
    expect(practice.partialScrambleMoveTurnCount, 0);
    expect(find.byKey(const Key('partial-scramble-progress')), findsNothing);
    final completedStep = find.byKey(const Key('scramble-step-0'));
    expect(completedStep, findsOneWidget);
    final completedStepText = tester.widget<Text>(
      find.descendant(of: completedStep, matching: find.byType(Text)),
    );
    expect(completedStepText.style?.decoration, TextDecoration.lineThrough);

    final expectedNext = practice.scrambleGuidance.first;
    final wrong = CubeMove(
      CubeFace.values.firstWhere(
        (face) => face != expectedNext.face && face != first.face,
      ),
    );
    gateway.addEvent(
      SmartCubeMoveEvent(
        move: wrong,
        serial: 3,
        receivedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();

    final secondWrong = CubeMove(
      CubeFace.values.firstWhere(
        (face) =>
            face != expectedNext.face &&
            face != first.face &&
            face != wrong.face,
      ),
    );
    gateway.addEvent(
      SmartCubeMoveEvent(
        move: secondWrong,
        serial: 4,
        receivedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();

    expect(practice.scrambleRecoveryMoves, [
      secondWrong.inverse,
      wrong.inverse,
    ]);
    expect(
      find.text('Wrong turn detected · 2 recovery moves needed'),
      findsOneWidget,
    );
    expect(find.textContaining('CORRECT'), findsNothing);
    expect(practice.completedScrambleMoveCount, 1);
    expect(find.byKey(const Key('scramble-recovery-step-0')), findsOneWidget);
    expect(find.byKey(const Key('scramble-recovery-step-1')), findsOneWidget);

    final inlineMoveText = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('scramble-text')),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(inlineMoveText.take(4), [
      first.notation,
      secondWrong.inverse.notation,
      wrong.inverse.notation,
      expectedNext.notation,
    ]);

    final nextRecovery = tester.widget<Container>(
      find.byKey(const Key('next-scramble-move')),
    );
    final nextRecoveryDecoration = nextRecovery.decoration! as BoxDecoration;
    expect(
      nextRecoveryDecoration.color,
      CrubikColors.warning.withValues(alpha: 0.22),
    );
    expect(nextRecoveryDecoration.border!.top.width, 1.5);
    expect(
      find.bySemanticsLabel(
        RegExp(
          'Wrong turn detected.*Recovery sequence: '
          '${secondWrong.inverse.notation} ${wrong.inverse.notation}',
        ),
      ),
      findsOneWidget,
    );
    semantics.dispose();

    var serial = 5;
    gateway.addEvent(
      SmartCubeMoveEvent(
        move: secondWrong.inverse,
        serial: serial++,
        receivedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();
    expect(practice.scrambleRecoveryMoves, [wrong.inverse]);
    expect(
      find.text('Wrong turn detected · 1 recovery move needed'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('scramble-recovery-step-0')), findsOneWidget);
    expect(find.byKey(const Key('scramble-recovery-step-1')), findsNothing);

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pump();
    expect(find.byKey(const Key('practice-desktop-layout')), findsOneWidget);
    expect(find.byKey(const Key('scramble-recovery-step-0')), findsOneWidget);
    expect(tester.takeException(), isNull);

    gateway.addEvent(
      SmartCubeMoveEvent(
        move: wrong.inverse,
        serial: serial++,
        receivedAt: DateTime.utc(2026),
      ),
    );
    await tester.pump();
    expect(practice.scrambleRecoveryMoves, isEmpty);
    expect(practice.guidanceIsCorrection, isFalse);
    expect(practice.nextScrambleMove, expectedNext);
    expect(find.textContaining('Wrong turn detected'), findsNothing);
    expect(find.byKey(const Key('scramble-recovery-step-0')), findsNothing);
    expect(find.byKey(const Key('next-scramble-move')), findsOneWidget);

    for (final move in [...practice.scrambleGuidance]) {
      gateway.addEvent(
        SmartCubeMoveEvent(
          move: move,
          serial: serial++,
          receivedAt: DateTime.utc(2026),
        ),
      );
      await tester.pump();
    }

    expect(practice.phase, PracticePhase.inspectionDelay);
    expect(practice.completedScrambleMoveCount, practice.scramble.moves.length);
    expect(find.text('GET READY'), findsWidgets);
    expect(
      find.textContaining('inspection starts in 3 seconds'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('timer-toggle')))
          .onPressed,
      isNull,
    );
    now = now.add(PracticeController.defaultPreInspectionDelay);
    await tester.pump(const Duration(milliseconds: 31));

    expect(practice.phase, PracticePhase.inspection);
    expect(find.text('INSPECTION'), findsOneWidget);
    expect(find.text('ABORT'), findsOneWidget);
    expect(practice.currentMoves, isEmpty);

    gateway.addEvent(
      SmartCubeMoveEvent(
        move: CubeMove.parse('R'),
        serial: serial,
        receivedAt: now,
      ),
    );
    await tester.pump();
    expect(practice.phase, PracticePhase.solving);
    expect(practice.currentMoves, [CubeMove.parse('R')]);

    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(practice.solves, isEmpty);
    expect(practice.phase, PracticePhase.needsSolvedCube);
    expect(find.text('SOLVE CUBE FIRST'), findsWidgets);
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
      find.text('MVP protocols: GAN Gen2–4, MoYu AI 2023, and MoYu32'),
      findsOneWidget,
    );
    expect(find.text('Scan nearby'), findsOneWidget);
    expect(find.text('Demo'), findsOneWidget);
    expect(
      find.text(
        'Cube turns update the live model and timer. Use Demo to practice without a smart cube.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('timer locally'), findsNothing);

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
          supportStatus: CubeSupportStatus.supported,
          adapterId: 'moyu32',
          rssi: -35,
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
    expect(find.text('MOYU · -35 dBm'), findsOneWidget);
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
    expect(find.text('Connect'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await connection.stopScan();
    await tester.pump();
  });

  testWidgets('only the selected cube shows a connecting label', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final connectGate = Completer<void>();
    final practice = PracticeController();
    final gateway = _SilentCubeConnectionGateway(connectGate: connectGate);
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
      ..addDevice(_supportedMoyu32)
      ..addDevice(
        const CubeDeviceCandidate(
          id: 'gan-test',
          name: 'GAN12ui',
          vendor: CubeVendor.gan,
          protocolFamily: CubeProtocolFamily.gan,
          supportStatus: CubeSupportStatus.supported,
          adapterId: 'gan-family',
          rssi: -50,
        ),
      );
    await tester.pump();

    await tester.tap(find.byKey(const Key('connect-device-moyu32-test')));
    await tester.pump();

    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(connection.connectingDeviceId, _supportedMoyu32.id);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('connect-device-gan-test')),
          )
          .onPressed,
      isNull,
    );

    connectGate.complete();
    await tester.pumpAndSettle();
    expect(connection.isConnected, isTrue);
    expect(connection.connectingDeviceId, isNull);
  });

  for (final size in [const Size(390, 844), const Size(1200, 800)]) {
    testWidgets(
      'connected MoYu32 battery fits ${size.width.toInt()}px viewport',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);

        final practice = PracticeController();
        final gateway = _SilentCubeConnectionGateway();
        final connection = CubeConnectionController(gateway: gateway);
        addTearDown(practice.dispose);
        addTearDown(connection.dispose);
        await connection.connect(_supportedMoyu32);
        gateway.addBatteryLevel(64);
        await tester.pump();

        await tester.pumpWidget(
          CrubikApp(
            practiceController: practice,
            connectionController: connection,
          ),
        );
        await tester.tap(find.byKey(const Key('connect-cube-button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('BLE link active · 64% battery'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('connection dialog explains unsupported legacy MoYu MHC cubes', (
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
            'Legacy MoYu MHC cubes are detected, but their protocol is not supported yet.',
      ),
    );
    await tester.pump();

    expect(find.text('MHC-AB12'), findsOneWidget);
    expect(find.text('MOYU · Detected, not supported yet'), findsOneWidget);
    expect(find.textContaining('Legacy MoYu MHC'), findsOneWidget);
    expect(find.text('Connect'), findsNothing);
    expect(tester.takeException(), isNull);

    await connection.stopScan();
    await tester.pump();
  });

  testWidgets('failed connection offers redacted diagnostics export', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final practice = PracticeController();
    final gateway = _SilentCubeConnectionGateway(
      connectError: const CubeConnectionFailure(
        CubeConnectionFailureCode.handshakeFailed,
        'Handshake timed out.',
      ),
    );
    final connection = CubeConnectionController(gateway: gateway);
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);
    String? copiedDiagnostics;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedDiagnostics =
                (call.arguments as Map<Object?, Object?>)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.tap(find.byKey(const Key('connect-cube-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan nearby'));
    await tester.pump();
    gateway.addDevice(_supportedMoyu32);
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('did not return a valid initial state'),
      findsOneWidget,
    );
    expect(find.text('Copy diagnostics'), findsOneWidget);
    await tester.tap(find.text('Copy diagnostics'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(copiedDiagnostics, contains('protocol=moyu32'));
    expect(copiedDiagnostics, isNot(contains(_supportedMoyu32.name)));
    expect(find.text('Redacted Bluetooth diagnostics copied'), findsOneWidget);
  });
}

final class _FakeSolveClock implements SolveClock {
  Duration value = Duration.zero;

  @override
  Duration get elapsed => value;

  @override
  void reset() => value = Duration.zero;

  @override
  void start({Duration initialElapsed = Duration.zero}) {
    value = initialElapsed;
  }

  @override
  void stop() {}
}

final class _DoubleTurnRandom implements Random {
  int _faceIndex = 0;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) {
    if (max == CubeFace.values.length) {
      return _faceIndex++ % CubeFace.values.length;
    }
    if (max == 3) return 1;
    return 0;
  }
}

const _supportedGan = CubeDeviceCandidate(
  id: 'gan-test',
  name: 'GAN12ui',
  vendor: CubeVendor.gan,
  protocolFamily: CubeProtocolFamily.gan,
  supportStatus: CubeSupportStatus.supported,
  adapterId: 'gan-family',
);

const _supportedMoyu32 = CubeDeviceCandidate(
  id: 'moyu32-test',
  name: 'WCU_MY32_ABCD',
  vendor: CubeVendor.moyu,
  protocolFamily: CubeProtocolFamily.moyu32,
  supportStatus: CubeSupportStatus.supported,
  adapterId: 'moyu32',
);

final class _SilentCubeConnectionGateway implements CubeConnectionGateway {
  _SilentCubeConnectionGateway({this.connectError, this.connectGate});

  final Object? connectError;
  final Completer<void>? connectGate;
  final _scanController = StreamController<CubeDeviceCandidate>.broadcast();
  final _session = _SilentSmartCubeSession();
  bool _closed = false;

  @override
  Stream<CubeDeviceCandidate> get scanResults => _scanController.stream;

  @override
  Future<SmartCubeSession> connect(
    CubeDeviceCandidate device, {
    CubeDiagnosticSink? onDiagnostic,
  }) async {
    onDiagnostic?.call('adapter.selected', device.adapterId);
    await connectGate?.future;
    final error = connectError;
    if (error != null) throw error;
    return _session;
  }

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  void addEvent(SmartCubeEvent event) => _session.addEvent(event);

  void addBatteryLevel(int batteryLevel) =>
      _session.addBatteryLevel(batteryLevel);

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
  final _batteryController = StreamController<int>.broadcast();
  bool _closed = false;

  @override
  CubeCapabilities get capabilities =>
      const CubeCapabilities(initialState: true, battery: true);

  @override
  Stream<bool> get connectionStates => const Stream.empty();

  @override
  Stream<int> get batteryLevels => _batteryController.stream;

  @override
  Stream<SmartCubeEvent> get events => _eventController.stream;

  void addEvent(SmartCubeEvent event) => _eventController.add(event);

  void addBatteryLevel(int batteryLevel) =>
      _batteryController.add(batteryLevel);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _eventController.close();
    await _batteryController.close();
  }
}
