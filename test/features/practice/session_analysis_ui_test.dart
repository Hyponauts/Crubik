import 'dart:async';

import 'package:crubik/app/crubik_app.dart';
import 'package:crubik/features/cube/application/cube_connection_controller.dart';
import 'package:crubik/features/cube/application/cube_connection_gateway.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/cube_connection_diagnostics.dart';
import 'package:crubik/features/cube/domain/smart_cube_device.dart';
import 'package:crubik/features/practice/domain/solve_method.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/practice_controller_factory.dart';
import '../../support/practice_test_clock.dart';

void main() {
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

  testWidgets('Analyze expands historical solve without practice summary', (
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
    await tester.tap(find.byKey(Key('solve-row-${solve.id}')));
    await tester.pump();

    expect(find.byKey(const Key('historical-solve-analysis')), findsOneWidget);
    expect(find.byKey(const Key('solve-analysis-panel')), findsOneWidget);
    expect(find.byKey(Key('solve-row-${solve.id}')), findsNothing);
    expect(find.byKey(const Key('back-to-solve-history')), findsOneWidget);
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

    expect(find.text('DELETE SOLVE?'), findsOneWidget);
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

  testWidgets('desktop Analyze uses side-by-side master detail', (
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
    await tester.tap(find.byKey(Key('solve-row-${solve.id}')));
    await tester.pump();

    expect(find.byKey(Key('solve-row-${solve.id}')), findsOneWidget);
    expect(find.byKey(const Key('historical-solve-analysis')), findsOneWidget);
    expect(find.byKey(const Key('back-to-solve-history')), findsNothing);
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
