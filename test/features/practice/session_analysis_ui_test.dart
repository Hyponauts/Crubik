import 'dart:async';

import 'package:crubik/app/crubik_app.dart';
import 'package:crubik/features/cube/application/cube_connection_controller.dart';
import 'package:crubik/features/cube/application/cube_connection_gateway.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/cube_connection_diagnostics.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/cube/domain/smart_cube_event.dart';
import 'package:crubik/features/practice/domain/solve_analysis.dart';
import 'package:crubik/features/practice/domain/solve_record.dart';
import 'package:crubik/features/practice/domain/solve_method.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/practice_controller_factory.dart';
import '../../support/practice_test_clock.dart';

void main() {
  testWidgets('connecting a selected cube closes the connection dialog', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final practice = createTestPracticeController();
    final gateway = _SelectableGateway();
    final connection = CubeConnectionController(gateway: gateway);
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);
    addTearDown(gateway.close);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connect-smart-cube-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan nearby'));
    await tester.pump();
    gateway.discover();
    await tester.pump();
    await tester.tap(find.byKey(const Key('connect-device-test-cube')));
    await tester.pumpAndSettle();

    expect(connection.isConnected, isTrue);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('practice-mobile-layout')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GAN state reset requires physical-solve confirmation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final practice = createTestPracticeController();
    final gateway = _SelectableGateway();
    final connection = CubeConnectionController(gateway: gateway);
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);
    addTearDown(gateway.close);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connect-smart-cube-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan nearby'));
    await tester.pump();
    gateway.discover();
    await tester.pump();
    await tester.tap(find.byKey(const Key('connect-device-test-cube')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connect-cube-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reset-cube-state-button')));
    await tester.pumpAndSettle();

    expect(find.text('Reset cube state?'), findsOneWidget);
    expect(gateway.session.resetCount, 0);
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(gateway.session.resetCount, 0);

    await tester.tap(find.byKey(const Key('reset-cube-state-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RESET'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(gateway.session.resetCount, 1);
    expect(connection.latestStateEvent?.serial, 1);
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    expect(connection.diagnosticReport, contains('protocol.reset.confirmed'));
    expect(find.byKey(const Key('reset-cube-state-button')), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('reset-cube-state-button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text('Cube confirmed its solved state.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in const [Size(390, 844), Size(1200, 800)]) {
    testWidgets('Ao stage tabs fit $viewport', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      addTearDown(tester.view.reset);
      final repository = await _repositoryWithAnalysedSolves();
      final practice = createTestPracticeController(repository: repository)
        ..activateDemoInput();
      final connection = CubeConnectionController(gateway: _SilentGateway());
      addTearDown(practice.dispose);
      addTearDown(connection.dispose);

      await tester.pumpWidget(
        CrubikApp(
          practiceController: practice,
          connectionController: connection,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AO5').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('average-history-ao5')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('average-row-ao5:average-solve-5')),
      );
      await tester.pumpAndSettle();
      final detail = find.byKey(
        const Key('average-detail-ao5:average-solve-5'),
      );
      expect(detail, findsOneWidget);
      expect(find.text('OVERVIEW'), findsOneWidget);
      final execution = find.descendant(
        of: detail,
        matching: find.byKey(const Key('execution-segment')),
      );
      final recognition = find.descendant(
        of: detail,
        matching: find.byKey(const Key('recognition-segment')),
      );
      expect(execution, findsOneWidget);
      expect(recognition, findsOneWidget);
      expect(
        tester.getTopLeft(recognition).dy,
        greaterThan(tester.getTopLeft(execution).dy),
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(of: detail, matching: find.text('CROSS')),
            )
            .style
            ?.fontSize,
        9,
      );
      await tester.tap(
        find.descendant(of: detail, matching: find.text('STEPS')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: detail, matching: find.text('REGRIP')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: detail, matching: find.text('TPS')).first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tps-axis')), findsOneWidget);
      expect(find.byKey(const Key('tps-bar-CROSS')), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(of: detail, matching: find.text('CROSS')),
            )
            .style
            ?.fontSize,
        9,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('expanded Ao5 refreshes its stages when a member is deleted', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final repository = await _repositoryWithAnalysedSolves(
      count: 6,
      varyingRecognition: true,
    );
    final practice = createTestPracticeController(repository: repository)
      ..activateDemoInput();
    final connection = CubeConnectionController(gateway: _SilentGateway());
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AO5').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('average-row-ao5:average-solve-6')));
    await tester.pumpAndSettle();
    final detail = find.byKey(const Key('average-detail-ao5:average-solve-6'));
    Finder within(String label) =>
        find.descendant(of: detail, matching: find.text(label));
    await tester.tap(within('STEPS'));
    await tester.pumpAndSettle();
    expect(within('0.40'), findsOneWidget);

    practice.deleteSolve('average-solve-4');
    await tester.pumpAndSettle();
    expect(within('0.33'), findsOneWidget);
    expect(within('0.40'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('average members show trimmed solves and open single history', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final repository = await _repositoryWithAnalysedSolves();
    final practice = createTestPracticeController(repository: repository)
      ..activateDemoInput();
    final connection = CubeConnectionController(gateway: _SilentGateway());
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AO5').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('average-row-ao5:average-solve-5')));
    await tester.pumpAndSettle();
    final detail = find.byKey(const Key('average-detail-ao5:average-solve-5'));
    await tester.tap(
      find.descendant(of: detail, matching: find.text('SOLVES')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('average-member-solves')), findsOneWidget);
    expect(find.text('BEST OUT'), findsOneWidget);
    expect(find.text('WORST OUT'), findsOneWidget);
    await tester.tap(find.byKey(const Key('average-member-average-solve-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('solve-row-average-solve-1')), findsOneWidget);
    expect(find.byKey(const Key('historical-solve-analysis')), findsOneWidget);
    final singleDetail = find.byKey(const Key('historical-solve-analysis'));
    await tester.tap(
      find.descendant(of: singleDetail, matching: find.text('TPS')).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('TPS Ao100'), findsOneWidget);
    expect(find.byKey(const Key('tps-bar-CROSS')), findsOneWidget);

    await tester.tap(find.text('AO5').last);
    await tester.pumpAndSettle();
    expect(detail, findsOneWidget);
    expect(find.byKey(const Key('average-member-solves')), findsOneWidget);

    await tester.tap(find.text('Practice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AO5').last);
    await tester.pumpAndSettle();
    expect(detail, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old Ao100 member is focused in long single history', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final repository = await _repositoryWithAnalysedSolves(count: 100);
    final practice = createTestPracticeController(repository: repository)
      ..activateDemoInput();
    final connection = CubeConnectionController(gateway: _SilentGateway());
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AO100').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('average-row-ao100:average-solve-100')),
    );
    await tester.pumpAndSettle();
    final detail = find.byKey(
      const Key('average-detail-ao100:average-solve-100'),
    );
    await tester.tap(
      find.descendant(of: detail, matching: find.text('SOLVES')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('average-member-average-solve-1')),
      1000,
      scrollable: find
          .descendant(of: detail, matching: find.byType(Scrollable))
          .last,
    );
    await tester.tap(find.byKey(const Key('average-member-average-solve-1')));
    await tester.pumpAndSettle();

    final target = find.byKey(const Key('solve-row-average-solve-1'));
    expect(target, findsOneWidget);
    expect(find.byKey(const Key('historical-solve-analysis')), findsOneWidget);
    expect(tester.getTopLeft(target).dy, greaterThan(0));
    expect(tester.getBottomRight(target).dy, lessThan(844));
    expect(tester.takeException(), isNull);
  });

  testWidgets('session settings changes the selected solve method', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final practice = createTestPracticeController()..activateDemoInput();
    final connection = CubeConnectionController(gateway: _SilentGateway());
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pumpAndSettle();
    final sessionButton = find.byKey(const Key('session-settings-button'));
    expect(
      find.descendant(of: sessionButton, matching: find.text('SpeedSolving')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sessionButton, matching: find.byIcon(Icons.tune)),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('session-settings-button')));
    await tester.pumpAndSettle();

    expect(find.text('SESSION SETTINGS'), findsOneWidget);
    expect(find.text('SpeedSolving'), findsWidgets);
    expect(find.text('CFOP'), findsOneWidget);

    await tester.tap(find.byKey(const Key('solve-method-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Layer by Layer').last);
    await tester.pumpAndSettle();

    expect(
      practice.selectedSession.method.preset,
      SolveMethodPreset.layerByLayer,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom solve stages can be reordered from their drag handles', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final practice = createTestPracticeController()..activateDemoInput();
    final connection = CubeConnectionController(gateway: _SilentGateway());
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('solve-method-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom').last);
    await tester.pumpAndSettle();

    expect(practice.selectedSession.method.stages.take(2), [
      SolveStageKind.cross,
      SolveStageKind.f2lPair1,
    ]);

    final dragHandle = find.byKey(const Key('stage-drag-cross'));
    final thirdStage = find.text('F2L pair 2');
    final gesture = await tester.startGesture(tester.getCenter(dragHandle));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(thirdStage) + const Offset(0, 24));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(practice.selectedSession.method.stages.take(2), [
      SolveStageKind.f2lPair1,
      SolveStageKind.cross,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates a session without disposing dialog dependencies early', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final practice = createTestPracticeController()..activateDemoInput();
    final connection = CubeConnectionController(gateway: _SilentGateway());
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-session-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('create-session-name')),
      'Blind practice',
    );
    await tester.tap(find.byKey(const Key('confirm-create-session')));
    await tester.pumpAndSettle();

    expect(practice.sessions, hasLength(2));
    expect(practice.selectedSession.name, 'Blind practice');
    expect(find.text('Blind practice'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Analyze expands tabs inline without duplicating solve summary', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final clock = PracticeTestClock(wallTime: () => DateTime.utc(2026, 10, 28));
    final practice = createTestPracticeController(
      clock: clock,
      monotonicClock: clock,
      preInspectionDelay: Duration.zero,
    )..activateDemoInput();
    practice.startSolve();
    practice.applyMove(CubeMove.parse('R'));
    clock.value = const Duration(seconds: 12);
    practice.stopSolve();
    final solve = practice.solves.single;
    practice.continueAfterSolve();
    final connection = CubeConnectionController(gateway: _SilentGateway());
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.tap(find.text('Analyze'));
    await tester.pump();
    final expandIcon = find.byKey(Key('solve-expand-${solve.id}'));
    final solvePosition = find.byKey(Key('solve-position-${solve.id}'));
    expect(
      tester.getCenter(expandIcon).dx,
      lessThan(tester.getCenter(solvePosition).dx),
    );
    expect(tester.widget<Icon>(expandIcon).icon, Icons.keyboard_arrow_right);
    await tester.tap(find.byKey(Key('solve-row-${solve.id}')));
    await tester.pump();

    expect(tester.widget<Icon>(expandIcon).icon, Icons.keyboard_arrow_down);
    expect(find.byKey(const Key('historical-solve-analysis')), findsOneWidget);
    expect(find.byKey(const Key('solve-analysis-panel')), findsOneWidget);
    final solveRow = find.byKey(Key('solve-row-${solve.id}'));
    expect(solveRow, findsOneWidget);
    expect(find.byKey(const Key('finish-time')), findsNothing);
    expect(find.text('12.00'), findsOneWidget);
    expect(
      find.descendant(of: solveRow, matching: find.text('TURNS')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: solveRow, matching: find.text('TPS')),
      findsOneWidget,
    );
    expect(find.text('SOLVE COMPLETE'), findsNothing);
    expect(find.byKey(const Key('session-summary-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a solve from history requires confirmation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final clock = PracticeTestClock(wallTime: () => DateTime.utc(2026, 10, 28));
    final practice = createTestPracticeController(
      clock: clock,
      monotonicClock: clock,
      preInspectionDelay: Duration.zero,
    )..activateDemoInput();
    practice.startSolve();
    practice.applyMove(CubeMove.parse('R'));
    clock.value = const Duration(seconds: 12);
    practice.stopSolve();
    practice.continueAfterSolve();
    final connection = CubeConnectionController(gateway: _SilentGateway());
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.tap(find.text('Analyze'));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete solve'));
    await tester.pumpAndSettle();

    expect(find.text('Delete solve?'), findsOneWidget);
    expect(practice.solves, hasLength(1));
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(practice.solves, hasLength(1));

    await tester.tap(find.byTooltip('Delete solve'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-solve')));
    await tester.pumpAndSettle();

    expect(practice.solves, isEmpty);
    expect(find.text('Your first solve starts here'), findsOneWidget);
  });

  testWidgets('opening another solve collapses the previous inline analysis', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final clock = PracticeTestClock(wallTime: () => DateTime.utc(2026, 10, 28));
    final practice = createTestPracticeController(
      clock: clock,
      monotonicClock: clock,
      preInspectionDelay: Duration.zero,
    )..activateDemoInput();
    practice.startSolve();
    practice.applyMove(CubeMove.parse('R'));
    clock.value = const Duration(seconds: 12);
    practice.stopSolve();
    final firstSolve = practice.solves.single;
    practice.continueAfterSolve();
    clock.value = const Duration(seconds: 20);
    practice.startSolve();
    practice.applyMove(CubeMove.parse('R'));
    clock.value = const Duration(seconds: 35);
    practice.stopSolve();
    final secondSolve = practice.solves.first;
    practice.continueAfterSolve();
    final connection = CubeConnectionController(gateway: _SilentGateway());
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.tap(find.text('Analyze'));
    await tester.pump();
    await tester.tap(find.byKey(Key('solve-row-${firstSolve.id}')));
    await tester.pump();

    expect(find.byKey(Key('solve-row-${firstSolve.id}')), findsOneWidget);
    expect(find.byKey(const Key('historical-solve-analysis')), findsOneWidget);
    await tester.tap(find.byKey(Key('solve-row-${secondSolve.id}')));
    await tester.pump();

    expect(find.byKey(Key('solve-row-${firstSolve.id}')), findsOneWidget);
    expect(find.byKey(Key('solve-row-${secondSolve.id}')), findsOneWidget);
    expect(find.byKey(const Key('historical-solve-analysis')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session settings remain available during solve review', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final clock = PracticeTestClock();
    final practice = createTestPracticeController(
      clock: clock,
      monotonicClock: clock,
      preInspectionDelay: Duration.zero,
    )..activateDemoInput();
    practice.startSolve();
    practice.applyMove(CubeMove.parse('R'));
    clock.value = const Duration(seconds: 12);
    practice.stopSolve();
    final connection = CubeConnectionController(gateway: _SilentGateway());
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);

    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session-settings-button')));
    await tester.pumpAndSettle();

    expect(find.text('SESSION SETTINGS'), findsOneWidget);
    expect(practice.pendingSolveReview, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting the reviewed solve’s session closes the review', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final clock = PracticeTestClock(wallTime: () => DateTime.utc(2026, 10, 28));
    final practice = createTestPracticeController(
      clock: clock,
      monotonicClock: clock,
      preInspectionDelay: Duration.zero,
    )..activateDemoInput();
    final connection = CubeConnectionController(gateway: _SilentGateway());
    addTearDown(practice.dispose);
    addTearDown(connection.dispose);
    await tester.pumpWidget(
      CrubikApp(practiceController: practice, connectionController: connection),
    );
    await tester.pumpAndSettle();
    final session = practice.createSession(name: 'Temporary session');
    practice.startSolve();
    practice.applyMove(CubeMove.parse('R'));
    clock.value = const Duration(seconds: 12);
    practice.stopSolve();
    await tester.pumpAndSettle();
    expect(practice.pendingSolveReview?.sessionId, session.id);

    await tester.tap(find.byKey(const Key('session-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-session-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DELETE'));
    await tester.pumpAndSettle();

    expect(practice.sessions, hasLength(1));
    expect(practice.pendingSolveReview, isNull);
    expect(practice.allSolves, isEmpty);
    expect(find.byKey(const Key('finish-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

final class _SilentGateway implements CubeConnectionGateway {
  @override
  Stream<CubeDeviceCandidate> get scanResults => const Stream.empty();

  @override
  List<String> get supportedProtocolDisplayNames => const [];

  @override
  Future<bool> isBluetoothAvailable() async => true;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<SmartCubeSession> connect(
    CubeDeviceCandidate candidate, {
    CubeDiagnosticSink? onDiagnostic,
  }) => throw UnimplementedError();

  @override
  Future<void> close() async {}
}

Future<MemorySolveHistoryRepository> _repositoryWithAnalysedSolves({
  int count = 5,
  bool varyingRecognition = false,
}) async {
  final repository = MemorySolveHistoryRepository();
  final method = SolveMethodConfig.preset(SolveMethodPreset.cfop);
  for (var index = 1; index <= count; index++) {
    final solve = SolveRecord(
      id: 'average-solve-$index',
      scramble: 'R U',
      elapsed: Duration(seconds: index),
      moveCount: 2,
      createdAt: DateTime.utc(2026, 10, 28, 12, 0, index),
      method: method,
    );
    await repository.add(solve);
    await repository.saveAnalysis(
      solve.id,
      SolveAnalysis(
        analyzerVersion: currentSolveAnalyzerVersion,
        method: method,
        protocolFamily: 'gan',
        createdAt: solve.createdAt,
        isComplete: true,
        stages: [
          SolveStageAnalysis(
            kind: SolveStageKind.cross,
            recognitionTime: Duration(
              milliseconds: varyingRecognition ? index * 100 : 500,
            ),
            executionTime: const Duration(milliseconds: 500),
            totalTime: const Duration(seconds: 1),
            moves: [CubeMove.parse('R')],
            regripCount: 1,
            skipped: false,
          ),
        ],
      ),
    );
  }
  return repository;
}

final class _SelectableGateway implements CubeConnectionGateway {
  final _results = StreamController<CubeDeviceCandidate>.broadcast();
  final session = _ImmediateStateSession();

  void discover() => _results.add(
    const CubeDeviceCandidate(
      id: 'test-cube',
      name: 'Test cube',
      vendor: CubeVendor.gan,
      protocolFamily: CubeProtocolFamily.gan,
      supportStatus: CubeSupportStatus.supported,
      adapterId: 'test',
    ),
  );

  @override
  Stream<CubeDeviceCandidate> get scanResults => _results.stream;

  @override
  List<String> get supportedProtocolDisplayNames => const ['Test'];

  @override
  Future<bool> isBluetoothAvailable() async => true;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<SmartCubeSession> connect(
    CubeDeviceCandidate device, {
    CubeDiagnosticSink? onDiagnostic,
  }) async => session;

  @override
  Future<void> close() => _results.close();
}

final class _ImmediateStateSession
    implements SmartCubeSession, ResettableSmartCubeSession {
  final _events = StreamController<SmartCubeEvent>.broadcast();
  int resetCount = 0;

  @override
  CubeCapabilities get capabilities =>
      const CubeCapabilities(initialState: true);

  @override
  Stream<SmartCubeEvent> get events => _events.stream;

  @override
  Stream<int> get batteryLevels => const Stream.empty();

  @override
  Stream<bool> get connectionStates => const Stream.empty();

  @override
  Future<void> start() async {
    _events.add(
      SmartCubeStateEvent(
        state: CubeState.solved(),
        serial: 0,
        receivedAt: DateTime.utc(2026),
        hostTimestamp: Duration.zero,
      ),
    );
  }

  @override
  Future<void> requestState() async {}

  @override
  Future<void> resetStateToSolved() async {
    resetCount++;
    _events.add(
      SmartCubeStateEvent(
        state: CubeState.solved(),
        serial: resetCount,
        receivedAt: DateTime.utc(2026),
        hostTimestamp: Duration.zero,
      ),
    );
  }

  @override
  Future<void> close() => _events.close();
}
