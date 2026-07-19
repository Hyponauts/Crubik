import 'package:crubik/core/theme/app_theme.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';
import 'package:crubik/features/practice/presentation/widgets/solve_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders ready, active timer, and finish states in isolation', (
    tester,
  ) async {
    final clock = _FakeSolveClock();
    final practice = PracticeController(clock: clock)..activateDemoInput();
    addTearDown(practice.dispose);

    await tester.pumpWidget(_host(practice));
    expect(find.byKey(const Key('ready-action-label')), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsNothing);

    await tester.tap(find.byKey(const Key('timer-toggle')));
    clock.value = const Duration(seconds: 12);
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byKey(const Key('timer-display')), findsOneWidget);
    expect(find.text('12.00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('timer-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('finish-card')), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsNothing);
    expect(find.text('CONTINUE TO NEXT SCRAMBLE'), findsOneWidget);

    await tester.tap(find.byKey(const Key('continue-after-solve')));
    await tester.pump();
    expect(practice.pendingSolveReview, isNull);
    expect(practice.phase, PracticePhase.manualReady);
    expect(find.byKey(const Key('ready-action-label')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
