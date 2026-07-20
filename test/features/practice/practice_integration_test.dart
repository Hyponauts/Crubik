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
    expect(find.byKey(const Key('input-mode-chooser')), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsNothing);
    expect(find.byKey(const Key('cube-3d-canvas')), findsNothing);
    expect(find.byKey(const Key('manual-moves-button')), findsNothing);
    expect(find.byKey(const Key('reset-scramble')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(practice.phase, PracticePhase.manualReady);
    expect(practice.solves, isEmpty);

    await tester.tap(find.text('Session'));
    await tester.pump();
    expect(find.byKey(const Key('export-solves-button')), findsOneWidget);
    await tester.tap(find.text('Practice'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('use-demo-cube-choice')));
    await tester.pump();

    expect(practice.inputMode, PracticeInputMode.demo);
    expect(connection.isConnected, isFalse);
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-reset-view')), findsOneWidget);
    expect(find.byKey(const Key('manual-moves-button')), findsOneWidget);
    expect(find.byKey(const Key('reset-scramble')), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(find.byKey(const Key('scramble-content-scroll')), findsOneWidget);
    expect(find.byKey(const Key('review-details-scroll')), findsNothing);
    expect(find.byKey(const Key('ready-action-label')), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsNothing);
    _expectCubePanelCaptionAnchors(tester);
    final compactScrambleToken = find.descendant(
      of: find.byKey(const Key('scramble-step-0')),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(compactScrambleToken).style?.fontSize, 18);
    expect(tester.takeException(), isNull);

    final completedScramble = practice.scramble.toString();
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(find.text('STOP & SAVE'), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsOneWidget);
    expect(find.byKey(const Key('mobile-focus-layout')), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsNothing);
    expect(find.text('Session'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('timer-display'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('cube-3d-canvas'))).dy),
    );

    clock.value = const Duration(milliseconds: 12340);
    practice.applyMove(CubeMove.parse('R'));
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(practice.solves, hasLength(1));
    expect(find.byKey(const Key('timer-display')), findsNothing);
    expect(find.byKey(const Key('finish-card')), findsOneWidget);
    expect(find.byKey(const Key('mobile-review-layout')), findsOneWidget);
    expect(find.byKey(const Key('review-details-scroll')), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.text('NEXT PRACTICE SCRAMBLE'), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsNothing);
    expect(find.text('DISMISS'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byKey(const Key('manual-moves-button')), findsNothing);
    expect(find.text('Session'), findsOneWidget);
    expect(find.text('12.34'), findsOneWidget);
    expect(find.byKey(const Key('finish-moves')), findsOneWidget);
    expect(find.byKey(const Key('finish-tps')), findsOneWidget);
    expect(find.byKey(const Key('finish-inspection')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('finish-moves'))).data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('finish-tps'))).data,
      '0.1',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('finish-inspection'))).data,
      '—',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('completed-scramble'))).data,
      completedScramble,
    );
    expect(practice.scramble.toString(), isNot(completedScramble));

    await tester.tap(find.byKey(const Key('continue-after-solve')));
    await tester.pump();
    expect(practice.pendingSolveReview, isNull);
    expect(practice.phase, PracticePhase.manualReady);
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsNothing);

    await tester.tap(find.byKey(const Key('manual-moves-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cube-move-R')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cube-move-R')));
    await tester.pump();
    expect(practice.currentMoves, isEmpty);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(practice.phase, PracticePhase.solving);
    expect(find.byKey(const Key('finish-card')), findsNothing);
    expect(find.byKey(const Key('timer-display')), findsOneWidget);
    practice.abortAttempt();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile practice fits a compact landscape viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(640, 360);
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

    expect(find.byKey(const Key('practice-mobile-layout')), findsOneWidget);
    expect(find.byKey(const Key('input-mode-chooser')), findsOneWidget);
    expect(find.byKey(const Key('manual-moves-button')), findsNothing);
    await tester.tap(find.byKey(const Key('use-demo-cube-choice')));
    await tester.pump();
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsOneWidget);
    expect(find.byKey(const Key('timer-toggle')), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsNothing);
    expect(find.byKey(const Key('manual-moves-button')), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(find.byKey(const Key('scramble-content-scroll')), findsOneWidget);
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(
      find.byKey(const Key('mobile-focus-landscape-layout')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('scramble-text')), findsNothing);
    expect(find.byKey(const Key('timer-display')), findsOneWidget);
    expect(find.byKey(const Key('manual-moves-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('finish-card')), findsOneWidget);
    expect(find.byKey(const Key('mobile-review-layout')), findsOneWidget);
    expect(find.text('DISMISS'), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.text('NEXT PRACTICE SCRAMBLE'), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsNothing);
    expect(tester.takeException(), isNull);
    await connection.connect(_supportedGan);
    practice.syncCubeState(CubeState.solved());
    await tester.pump();
    expect(find.byKey(const Key('scramble-guidance')), findsOneWidget);
    expect(find.byKey(const Key('next-scramble-move')), findsOneWidget);
    expect(find.byKey(const Key('timer-toggle')), findsNothing);
    expect(find.byKey(const Key('timer-display')), findsNothing);
    expect(find.byKey(const Key('manual-moves-button')), findsNothing);
    expect(find.byKey(const Key('reset-scramble')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'smart cube completion shows the finish card with the prepared next scramble',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final now = DateTime.utc(2026);
      final clock = _FakeSolveClock();
      final practice = PracticeController(
        clock: clock,
        now: () => now,
        preInspectionDelay: Duration.zero,
        scrambleGenerator: ScrambleGenerator(random: Random(7)),
      );
      final gateway = _SilentCubeConnectionGateway();
      final connection = CubeConnectionController(gateway: gateway);
      addTearDown(practice.dispose);
      addTearDown(connection.dispose);

      await tester.pumpWidget(
        CrubikApp(
          practiceController: practice,
          connectionController: connection,
        ),
      );
      await connection.connect(_supportedGan);
      gateway.addEvent(
        SmartCubeStateEvent(
          state: CubeState.solved(),
          serial: 0,
          receivedAt: now,
        ),
      );
      await tester.pump();

      var serial = 1;
      for (final move in [...practice.scrambleGuidance]) {
        gateway.addEvent(
          SmartCubeMoveEvent(move: move, serial: serial++, receivedAt: now),
        );
        await tester.pump();
      }
      expect(practice.phase, PracticePhase.inspection);
      expect(find.byKey(const Key('mobile-focus-layout')), findsOneWidget);
      expect(find.byKey(const Key('scramble-text')), findsNothing);
      expect(find.byKey(const Key('timer-display')), findsOneWidget);
      expect(find.text('ABORT'), findsOneWidget);
      expect(find.text('Session'), findsNothing);
      final completedScramble = practice.scramble.toString();
      final solution = [...practice.scramble.inverse.moves];

      gateway.addEvent(
        SmartCubeMoveEvent(
          move: solution.first,
          serial: serial++,
          receivedAt: now,
        ),
      );
      await tester.pump();
      clock.value = const Duration(seconds: 8);
      for (final move in solution.skip(1)) {
        gateway.addEvent(
          SmartCubeMoveEvent(move: move, serial: serial++, receivedAt: now),
        );
        await tester.pump();
      }

      expect(practice.phase, PracticePhase.scrambling);
      expect(practice.scramble.toString(), isNot(completedScramble));
      expect(find.byKey(const Key('finish-card')), findsOneWidget);
      expect(find.byKey(const Key('mobile-review-layout')), findsOneWidget);
      expect(find.byKey(const Key('scramble-text')), findsOneWidget);
      expect(find.text('NEXT PRACTICE SCRAMBLE'), findsOneWidget);
      expect(find.byKey(const Key('scramble-guidance')), findsOneWidget);
      expect(find.byKey(const Key('cube-3d-canvas')), findsNothing);
      expect(find.byKey(const Key('timer-display')), findsNothing);
      expect(find.byKey(const Key('timer-toggle')), findsNothing);
      expect(find.byKey(const Key('continue-after-solve')), findsOneWidget);
      expect(find.text('DISMISS'), findsOneWidget);
      expect(find.text('8.00'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('completed-scramble'))).data,
        completedScramble,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'Solve complete\. Time 8\.00\. 20 moves\. TPS 2\.5\.'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('continue-after-solve')));
      await tester.pump();
      expect(practice.pendingSolveReview, isNull);
      expect(practice.phase, PracticePhase.scrambling);
      expect(find.byKey(const Key('scramble-text')), findsOneWidget);
      expect(find.byKey(const Key('cube-3d-canvas')), findsOneWidget);
      expect(find.byKey(const Key('scramble-guidance')), findsOneWidget);

      for (final move in [...practice.scrambleGuidance]) {
        gateway.addEvent(
          SmartCubeMoveEvent(move: move, serial: serial++, receivedAt: now),
        );
        await tester.pump();
      }

      expect(practice.phase, PracticePhase.inspection);
      expect(find.byKey(const Key('finish-card')), findsNothing);
      expect(find.byKey(const Key('timer-display')), findsOneWidget);
      expect(find.text('ABORT'), findsOneWidget);
      practice.abortAttempt();
      await tester.pump();
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

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

    expect(find.byKey(const Key('input-mode-chooser')), findsOneWidget);
    expect(find.byKey(const Key('manual-moves-button')), findsNothing);
    expect(tester.takeException(), isNull);
    final demoChoice = find.byKey(const Key('use-demo-cube-choice'));
    await tester.ensureVisible(demoChoice);
    await tester.tap(demoChoice);
    await tester.pump();
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsOneWidget);
    expect(find.byKey(const Key('timer-toggle')), findsOneWidget);
    expect(find.byKey(const Key('manual-moves-button')), findsOneWidget);
    expect(find.byKey(const Key('scramble-content-scroll')), findsOneWidget);
    expect(find.byKey(const Key('review-details-scroll')), findsNothing);
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('mobile-focus-layout')), findsOneWidget);
    expect(find.byKey(const Key('scramble-content-scroll')), findsNothing);
    expect(find.byKey(const Key('timer-display')), findsOneWidget);
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('finish-card')), findsOneWidget);
    expect(find.byKey(const Key('mobile-review-layout')), findsOneWidget);
    expect(find.byKey(const Key('review-details-scroll')), findsOneWidget);
    expect(find.byKey(const Key('continue-after-solve')), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.text('NEXT PRACTICE SCRAMBLE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile focus and review fit 320px at 2.0 text scaling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final practice = PracticeController()..activateDemoInput();
    final connection = CubeConnectionController(
      gateway: _SilentCubeConnectionGateway(),
    );
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pump();

    expect(find.byKey(const Key('mobile-preparation-layout')), findsOneWidget);
    expect(find.byKey(const Key('scramble-content-scroll')), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsOneWidget);
    expect(find.byKey(const Key('timer-toggle')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();

    expect(find.byKey(const Key('mobile-focus-layout')), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsNothing);
    expect(find.byKey(const Key('timer-display')), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsOneWidget);
    expect(find.byKey(const Key('manual-moves-button')), findsOneWidget);
    expect(find.text('Session'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('timer-toggle'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const Key('manual-moves-button'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getBottomRight(find.byKey(const Key('focus-action-bar'))).dy,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();

    expect(find.byKey(const Key('mobile-review-layout')), findsOneWidget);
    expect(find.byKey(const Key('review-details-scroll')), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.text('NEXT PRACTICE SCRAMBLE'), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsNothing);
    expect(find.byKey(const Key('continue-after-solve')), findsOneWidget);
    expect(
      tester.getBottomRight(find.byKey(const Key('continue-after-solve'))).dy,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('spacebar timing is scoped to the Practice destination', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final practice = PracticeController()..activateDemoInput();
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

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(practice.phase, PracticePhase.manualReady);

    await tester.tap(find.text('Practice'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(practice.phase, PracticePhase.solving);
    expect(find.byKey(const Key('mobile-focus-layout')), findsOneWidget);
    practice.abortAttempt();
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
    practice.activateDemoInput();
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
    expect(find.byKey(const Key('input-mode-chooser')), findsOneWidget);
    expect(find.byKey(const Key('timer-toggle')), findsNothing);
    expect(find.byKey(const Key('manual-moves-button')), findsNothing);
    await connection.connect(_supportedGan);
    await tester.pump();

    expect(find.byKey(const Key('practice-desktop-layout')), findsOneWidget);
    expect(find.text('SESSION SNAPSHOT'), findsOneWidget);
    expect(find.text('PRACTICE SCRAMBLE'), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsOneWidget);
    expect(find.text('MANUAL MOVE INPUT'), findsNothing);
    expect(find.byKey(const Key('reset-scramble')), findsNothing);
    expect(find.text('OFFLINE CUBE LAB'), findsNothing);
    expect(find.text('OFFLINE READY'), findsNothing);
    expect(find.text('OFFLINE · 20 MOVES'), findsNothing);
    expect(find.text('No account or internet needed'), findsNothing);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
    _expectCubePanelCaptionAnchors(tester);

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
    expect(practice.phase, PracticePhase.scrambling);
    expect(find.byKey(const Key('timer-display')), findsNothing);
    expect(find.byKey(const Key('timer-toggle')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial physical cube state is applied during connection', (
    tester,
  ) async {
    final physicalState = CubeState.solved()..apply(CubeMove.parse('R'));
    final practice = PracticeController();
    final gateway = _SilentCubeConnectionGateway(
      initialEvent: SmartCubeStateEvent(
        state: physicalState,
        serial: 0,
        receivedAt: DateTime.utc(2026),
      ),
    );
    final connection = CubeConnectionController(gateway: gateway);
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await connection.connect(_supportedGan);
    await tester.pump();

    expect(practice.inputMode, PracticeInputMode.smartCube);
    expect(practice.cubeState.facelets, physicalState.facelets);
    expect(practice.phase, PracticePhase.needsSolvedCube);
  });

  testWidgets('connected state is replayed when practice attaches later', (
    tester,
  ) async {
    final physicalState = CubeState.solved()..apply(CubeMove.parse('U'));
    final stateEvent = SmartCubeStateEvent(
      state: physicalState,
      serial: 4,
      receivedAt: DateTime.utc(2026),
    );
    final practice = PracticeController();
    final gateway = _SilentCubeConnectionGateway(initialEvent: stateEvent);
    final connection = CubeConnectionController(gateway: gateway);
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await connection.connect(_supportedGan);
    await tester.pump();
    expect(connection.latestStateEvent, same(stateEvent));

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pump();

    expect(practice.inputMode, PracticeInputMode.smartCube);
    expect(practice.cubeState.facelets, physicalState.facelets);
    expect(practice.phase, PracticePhase.needsSolvedCube);
    expect(find.text('Waiting for the physical cube state'), findsNothing);
  });

  testWidgets('desktop demo shows manual controls and can return to chooser', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
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
    await tester.tap(find.byKey(const Key('use-demo-cube-choice')));
    await tester.pump();

    expect(find.text('MANUAL MOVE INPUT'), findsOneWidget);
    expect(find.byKey(const Key('reset-scramble')), findsOneWidget);
    expect(find.text('Demo cube'), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsNothing);
    final desktopScrambleToken = find.descendant(
      of: find.byKey(const Key('scramble-step-0')),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(desktopScrambleToken).style?.fontSize, 20);

    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('scramble-text')), findsNothing);
    expect(find.text('MANUAL MOVE INPUT'), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsOneWidget);
    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('finish-card')), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.text('NEXT PRACTICE SCRAMBLE'), findsOneWidget);
    expect(find.byKey(const Key('cube-3d-canvas')), findsNothing);
    expect(find.text('MANUAL MOVE INPUT'), findsNothing);
    expect(find.byKey(const Key('continue-after-solve')), findsOneWidget);
    expect(find.text('DISMISS'), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('continue-after-solve')));
    await tester.pump();
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.text('MANUAL MOVE INPUT'), findsOneWidget);

    await tester.tap(find.byKey(const Key('connect-cube-button')));
    await tester.pumpAndSettle();
    expect(find.text('Exit demo'), findsOneWidget);
    expect(
      find.text('Manual timer and virtual cube controls active'),
      findsOneWidget,
    );

    await tester.tap(find.text('Exit demo'));
    await tester.pumpAndSettle();
    expect(practice.inputMode, PracticeInputMode.unselected);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('input-mode-chooser')), findsOneWidget);
    expect(find.text('MANUAL MOVE INPUT'), findsNothing);
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
    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.byKey(const Key('next-scramble-move')), findsOneWidget);
    expect(find.byKey(const Key('timer-toggle')), findsNothing);
    expect(find.byKey(const Key('timer-display')), findsNothing);
    expect(find.byKey(const Key('manual-moves-button')), findsNothing);
    expect(find.byKey(const Key('reset-scramble')), findsNothing);

    final first = practice.scramble.moves.first;
    expect(first.turns, 2);
    final initialScrambleRect = tester.getRect(
      find.byKey(const Key('scramble-text')),
    );
    final initialFirstTokenRect = tester.getRect(
      find.byKey(const Key('next-scramble-move')),
    );
    final initialSecondTokenRect = tester.getRect(
      find.byKey(const Key('scramble-step-1')),
    );
    final initialCaptions = _scrambleCaptions(tester);
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
    expect(find.byKey(const Key('partial-scramble-progress')), findsNothing);
    expect(find.text('1/2'), findsNothing);
    expect(_scrambleCaptions(tester), initialCaptions);
    expect(
      tester.getRect(find.byKey(const Key('scramble-text'))),
      initialScrambleRect,
    );
    expect(
      tester.getRect(find.byKey(const Key('next-scramble-move'))),
      initialFirstTokenRect,
    );
    expect(
      tester.getRect(find.byKey(const Key('scramble-step-1'))),
      initialSecondTokenRect,
    );
    final partialStep = tester.widget<Container>(
      find.byKey(const Key('next-scramble-move')),
    );
    final partialDecoration = partialStep.decoration! as BoxDecoration;
    final partialGradient = partialDecoration.gradient! as LinearGradient;
    expect(partialGradient.stops, [0, 0.5, 0.5, 1]);
    expect(find.textContaining('current step 1 of 2 turns'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(
          '${RegExp.escape(first.notation)}, partially completed, '
          '1 of 2 turns',
        ),
      ),
      findsOneWidget,
    );
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
    expect(find.byKey(const Key('practice-desktop-layout')), findsOneWidget);
    expect(find.byKey(const Key('scramble-text')), findsNothing);
    expect(find.byKey(const Key('scramble-guidance')), findsNothing);
    expect(find.text('GET READY'), findsWidgets);
    expect(find.byKey(const Key('timer-display')), findsOneWidget);
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
    expect(
      find.text('Solve the physical cube before scrambling'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection dialog offers supported scan and demo mode', (
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
    await tester.tap(find.byKey(const Key('connect-smart-cube-choice')));
    await tester.pumpAndSettle();

    expect(
      find.text('MVP protocols: GAN Gen2–4, MoYu AI 2023, and MoYu32'),
      findsOneWidget,
    );
    expect(find.text('Scan nearby'), findsOneWidget);
    expect(find.byKey(const Key('use-demo-cube-dialog')), findsOneWidget);
    expect(gateway.startScanCount, 0);
    expect(
      find.text(
        'Cube turns update the live model and timer. Use the demo cube to practice without hardware.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('timer locally'), findsNothing);

    await tester.tap(find.byKey(const Key('use-demo-cube-dialog')));
    await tester.pumpAndSettle();
    expect(practice.inputMode, PracticeInputMode.demo);
    expect(connection.isConnected, isFalse);
    expect(find.byKey(const Key('manual-moves-button')), findsOneWidget);
    expect(find.byKey(const Key('reset-scramble')), findsOneWidget);
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

void _expectCubePanelCaptionAnchors(WidgetTester tester) {
  final cubePanelRect = tester.getRect(find.byKey(const Key('cube-panel')));
  final scramblePanelRect = tester.getRect(
    find.byKey(const Key('scramble-panel')),
  );
  final headerRect = tester.getRect(find.byKey(const Key('cube-stage-header')));
  final labelRect = tester.getRect(find.byKey(const Key('cube-stage-label')));
  final statusRect = tester.getRect(
    find.byKey(const Key('cube-connection-status')),
  );
  final scrambleLabelRect = tester.getRect(find.text('PRACTICE SCRAMBLE'));
  final referenceInset = scrambleLabelRect.left - scramblePanelRect.left;

  expect(headerRect.left - cubePanelRect.left, closeTo(referenceInset, 0.01));
  expect(labelRect.left - cubePanelRect.left, closeTo(referenceInset, 0.01));
  expect(cubePanelRect.right - statusRect.right, closeTo(referenceInset, 0.01));
  expect(labelRect.center.dy, closeTo(statusRect.center.dy, 0.01));
}

List<String> _scrambleCaptions(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('scramble-text')),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data)
    .whereType<String>()
    .toList();

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
  _SilentCubeConnectionGateway({
    this.connectError,
    this.connectGate,
    SmartCubeEvent? initialEvent,
  }) : _session = _SilentSmartCubeSession(stateOnRequest: initialEvent);

  final Object? connectError;
  final Completer<void>? connectGate;
  final _scanController = StreamController<CubeDeviceCandidate>.broadcast();
  final _SilentSmartCubeSession _session;
  bool _closed = false;
  int startScanCount = 0;

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
  Future<void> startScan() async {
    startScanCount++;
  }

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
  _SilentSmartCubeSession({this.stateOnRequest});

  final SmartCubeEvent? stateOnRequest;
  final _eventController = StreamController<SmartCubeEvent>();
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
  Future<void> start() async {
    final event = stateOnRequest;
    if (event != null) _eventController.add(event);
  }

  @override
  Future<void> requestState() async {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _eventController.close();
    await _batteryController.close();
  }
}
