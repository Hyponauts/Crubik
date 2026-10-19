import 'package:crubik/core/theme/app_theme.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';
import 'package:crubik/features/practice/presentation/widgets/solve_controls.dart';
import 'package:crubik/features/practice/presentation/sessions_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/practice_test_clock.dart';

void main() {
  testWidgets('renders ready and finish states in isolation', (tester) async {
    final clock = PracticeTestClock();
    final practice = PracticeController(
      clock: clock,
      preInspectionDelay: Duration.zero,
      monotonicClock: clock,
    )..activateDemoInput();
    addTearDown(practice.dispose);

    await tester.pumpWidget(_host(practice));
    expect(find.byKey(const Key('ready-action-label')), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsNothing);

    await tester.tap(find.byKey(const Key('timer-toggle')));
    practice.applyMove(CubeMove.parse('R'));
    clock.value = const Duration(seconds: 12);
    practice.stopSolve();
    await tester.pump();
    expect(find.byKey(const Key('finish-card')), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsNothing);
    expect(find.text('DISMISS'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byKey(const Key('continue-after-solve')));
    await tester.pump();
    expect(practice.pendingSolveReview, isNull);
    expect(practice.phase, PracticePhase.manualReady);
    expect(find.byKey(const Key('ready-action-label')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'unavailable timing stays readable in compact and wide review and history',
    (tester) async {
      final clock = PracticeTestClock(wallTime: () => DateTime.utc(2026));
      final practice = PracticeController(
        monotonicClock: clock,
        preInspectionDelay: Duration.zero,
      );
      addTearDown(practice.dispose);
      addTearDown(tester.view.reset);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      practice.activateSmartCubeInput();
      practice.syncCubeState(CubeState.solved());
      for (final move in practice.scramble.moves) {
        practice.applyMove(move, fromSmartCube: true);
      }
      for (final move in practice.scramble.inverse.moves) {
        practice.applyMove(move, fromSmartCube: true, recovered: true);
      }

      for (final size in [const Size(360, 640), const Size(1440, 900)]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(_host(practice));
        expect(find.text('Timing unavailable'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            theme: CrubikTheme.dark,
            home: Scaffold(
              body: SessionsView(practice: practice, mobile: size.width < 600),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Timing unavailable'), findsOneWidget);
        await tester.tap(find.byKey(const Key('export-solves-button')));
        await tester.pumpAndSettle();
        expect(
          find.text('Solve history copied as Crubik JSON'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}

Widget _host(PracticeController practice) {
  return MaterialApp(
    theme: CrubikTheme.dark,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: AnimatedBuilder(
            animation: practice,
            builder: (context, _) => PracticeAccessoryPanel(
              practice: practice,
              contained: true,
              compact: true,
            ),
          ),
        ),
      ),
    ),
  );
}
