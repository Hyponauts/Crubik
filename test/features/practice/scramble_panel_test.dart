import 'dart:math';

import 'package:crubik/core/theme/app_theme.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/cube/domain/scramble_generator.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';
import 'package:crubik/features/practice/presentation/widgets/scramble_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scramble panel densities resolve full, compact, and dense sizes', () {
    expect(
      ScramblePanelDensity.full.layoutSize(dense: 15, compact: 18, full: 20),
      20,
    );
    expect(
      ScramblePanelDensity.compact.layoutSize(dense: 15, compact: 18, full: 20),
      18,
    );
    expect(
      ScramblePanelDensity.dense.layoutSize(dense: 15, compact: 18, full: 20),
      15,
    );
  });

  testWidgets('describes the configured pre-inspection delay', (tester) async {
    final practice = PracticeController(
      scrambleGenerator: ScrambleGenerator(random: Random(11)),
      preInspectionDelay: const Duration(milliseconds: 1500),
    );
    addTearDown(practice.dispose);
    practice.activateSmartCubeInput();
    practice.syncCubeState(CubeState.solved());
    for (final move in practice.scramble.moves) {
      practice.applyMove(move, fromSmartCube: true);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: CrubikTheme.dark,
        home: Scaffold(body: PracticeScramblePanel(practice: practice)),
      ),
    );

    expect(
      find.text('Scramble verified · inspection starts in 1.5 seconds'),
      findsOneWidget,
    );
    practice.abortAttempt();
  });

  testWidgets('renders compact smart-cube scramble progress in isolation', (
    tester,
  ) async {
    final practice = PracticeController(
      scrambleGenerator: ScrambleGenerator(random: Random(7)),
    );
    practice.activateSmartCubeInput();
    practice.syncCubeState(CubeState.solved());
    addTearDown(practice.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: CrubikTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 340,
            height: 180,
            child: AnimatedBuilder(
              animation: practice,
              builder: (context, _) => PracticeScramblePanel(
                practice: practice,
                density: ScramblePanelDensity.dense,
                fillHeight: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.byKey(const Key('next-scramble-move')), findsOneWidget);
    expect(find.byKey(const Key('scramble-guidance')), findsOneWidget);
    expect(find.byKey(const Key('timer-display')), findsNothing);
    final nextMoveText = find.descendant(
      of: find.byKey(const Key('next-scramble-move')),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(nextMoveText).style?.fontSize, 15);

    final firstMove = practice.scramble.moves.first;
    practice.applyMove(
      firstMove,
      fromSmartCube: true,
      occurredAt: DateTime.utc(2026),
    );
    await tester.pump();

    expect(find.byKey(const Key('scramble-step-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
