import 'dart:async';
import 'dart:math';

import 'package:crubik/core/theme/app_theme.dart';
import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/practice/application/practice_controller.dart';
import 'package:crubik/features/practice/presentation/widgets/scramble_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/practice_controller_factory.dart';

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

  for (final viewport in [const Size(320, 568), const Size(1440, 900)]) {
    for (final density in ScramblePanelDensity.values) {
      for (final textScale in [1.0, 1.3, 2.0]) {
        testWidgets('keeps scramble baselines and wrapping stable at '
            '$viewport, $density, text scale $textScale', (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = viewport;
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final scramble = CubeScramble.parse(
            "R U' F2 D L2 B' R2 F U2 L' D2 B U' R F2 D' L B2",
          );
          final practice = PracticeController(nextScramble: () => scramble)
            ..activateSmartCubeInput();
          addTearDown(practice.dispose);

          await tester.pumpWidget(
            MaterialApp(
              theme: CrubikTheme.dark,
              home: Scaffold(
                body: AnimatedBuilder(
                  animation: practice,
                  builder: (context, _) => PracticeScramblePanel(
                    practice: practice,
                    density: density,
                    bounded: true,
                  ),
                ),
              ),
            ),
          );
          final initialLayout = _scrambleTextLayout(tester);
          final initialSize = tester.getSize(
            find.byKey(const Key('scramble-text')),
          );
          expect(initialLayout, hasLength(scramble.moves.length));
          _expectSharedBaselines(initialLayout);

          practice.syncCubeState(CubeState.solved());
          await tester.pump();

          expect(find.byKey(const Key('next-scramble-move')), findsOneWidget);
          expect(_scrambleTextLayout(tester), initialLayout);

          practice.applyMove(
            const CubeMove(CubeFace.down),
            fromSmartCube: true,
          );
          practice.applyMove(
            const CubeMove(CubeFace.left),
            fromSmartCube: true,
          );
          await tester.pump();

          expect(practice.scrambleRecoveryMoves, hasLength(2));
          _expectSharedBaselines(_scrambleTextLayout(tester));

          practice.applyMove(
            const CubeMove(CubeFace.left, turns: 3),
            fromSmartCube: true,
          );
          await tester.pump();
          _expectSharedBaselines(_scrambleTextLayout(tester));

          practice.applyMove(
            const CubeMove(CubeFace.down, turns: 3),
            fromSmartCube: true,
          );
          await tester.pump();
          expect(_scrambleTextLayout(tester), initialLayout);

          for (final move in scramble.moves) {
            final observedMoves = move.turns == 2
                ? [CubeMove(move.face), CubeMove(move.face)]
                : [move];
            for (final observedMove in observedMoves) {
              practice.applyMove(observedMove, fromSmartCube: true);
              await tester.pump();

              expect(_scrambleTextLayout(tester), initialLayout);
              expect(
                tester.getSize(find.byKey(const Key('scramble-text'))),
                initialSize,
              );
              expect(tester.takeException(), isNull);
            }
          }

          expect(find.byKey(const Key('next-scramble-move')), findsNothing);
          expect(practice.phase, PracticePhase.inspectionDelay);
          practice.abortAttempt();
        });
      }
    }
  }

  testWidgets('describes the configured pre-inspection delay', (tester) async {
    final practice = createTestPracticeController(
      scrambleGenerator: TestScrambleGenerator(random: Random(11)),
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
    final practice = createTestPracticeController(
      scrambleGenerator: TestScrambleGenerator(random: Random(7)),
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
      hostTimestamp: Duration.zero,
    );
    await tester.pump();

    expect(find.byKey(const Key('scramble-step-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows preparation progress and retry without a type label', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    final firstAttempt = Completer<CubeScramble>();
    var attempts = 0;
    final practice = PracticeController(
      nextScramble: () {
        if (attempts++ == 0) {
          return firstAttempt.future;
        }
        return CubeScramble.parse('R U');
      },
    );
    addTearDown(practice.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: CrubikTheme.dark,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: practice,
            builder: (context, _) => PracticeScramblePanel(practice: practice),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('scramble-loading')), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump();
    expect(tester.takeException(), isNull);

    firstAttempt.completeError(StateError('solver failed'));
    await tester.pump();

    expect(find.byKey(const Key('scramble-error')), findsOneWidget);
    expect(find.byKey(const Key('retry-scramble')), findsOneWidget);
    expect(find.textContaining('WCA'), findsNothing);

    await tester.tap(find.byKey(const Key('retry-scramble')));
    await tester.pump();

    expect(find.byKey(const Key('scramble-text')), findsOneWidget);
    expect(find.text('R'), findsOneWidget);
    expect(find.text('U'), findsOneWidget);
  });

  testWidgets('does not flash preparation UI for a ready replacement', (
    tester,
  ) async {
    final initial = CubeScramble.parse("R U R' U'");
    final replacement = CubeScramble.parse("F D F' D'");
    var requests = 0;
    final practice = PracticeController(
      nextScramble: () =>
          requests++ == 0 ? initial : Future<CubeScramble>.value(replacement),
    )..activateDemoInput();
    addTearDown(practice.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: CrubikTheme.dark,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: practice,
            builder: (context, _) => PracticeScramblePanel(practice: practice),
          ),
        ),
      ),
    );
    final headerBefore = tester.getRect(find.text('PRACTICE SCRAMBLE'));

    await tester.tap(find.byKey(const Key('new-scramble')));
    await tester.pump();

    expect(practice.scramble, same(replacement));
    expect(find.byKey(const Key('scramble-loading')), findsNothing);
    expect(tester.getRect(find.text('PRACTICE SCRAMBLE')), headerBefore);
  });

  for (final viewport in [const Size(320, 568), const Size(1440, 900)]) {
    testWidgets('keeps its footprint while preparing a scramble at $viewport', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      addTearDown(tester.view.reset);
      final initial = CubeScramble.parse(
        "R U R' U' F2 D L2 B' R2 F U2 L' D2 B U' R F2 D' L B2",
      );
      final next = Completer<CubeScramble>();
      var requests = 0;
      FutureOr<CubeScramble> nextScramble() {
        if (requests++ == 0) return initial;
        return next.future;
      }

      final practice = PracticeController(nextScramble: nextScramble)
        ..activateDemoInput();
      addTearDown(practice.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: CrubikTheme.dark,
          home: Scaffold(
            body: AnimatedBuilder(
              animation: practice,
              builder: (context, _) =>
                  PracticeScramblePanel(practice: practice),
            ),
          ),
        ),
      );
      final readySize = tester.getSize(find.byKey(const Key('scramble-panel')));

      await tester.tap(find.byKey(const Key('new-scramble')));
      await tester.pump();

      expect(find.byKey(const Key('scramble-loading')), findsNothing);
      await tester.pump(const Duration(milliseconds: 149));
      expect(find.byKey(const Key('scramble-loading')), findsNothing);
      await tester.pump(const Duration(milliseconds: 2));
      expect(find.byKey(const Key('scramble-loading')), findsOneWidget);
      expect(practice.displayedScramble, same(initial));
      expect(
        tester.getSize(find.byKey(const Key('scramble-panel'))),
        readySize,
      );

      next.complete(initial);
      await tester.pump();
      expect(find.byKey(const Key('scramble-loading')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

List<({Rect rect, double baseline})> _scrambleTextLayout(WidgetTester tester) {
  final paragraphs = find.descendant(
    of: find.byKey(const Key('scramble-text')),
    matching: find.byType(RichText),
  );

  return [
    for (final paragraph in tester.renderObjectList<RenderParagraph>(
      paragraphs,
    ))
      (
        rect: paragraph.localToGlobal(Offset.zero) & paragraph.size,
        baseline: paragraph
            .localToGlobal(
              Offset(
                0,
                paragraph.getDryBaseline(
                  paragraph.constraints,
                  TextBaseline.alphabetic,
                )!,
              ),
            )
            .dy,
      ),
  ];
}

void _expectSharedBaselines(List<({Rect rect, double baseline})> layout) {
  var rowBottom = double.negativeInfinity;
  var rowBaseline = double.nan;
  for (final text in layout) {
    if (text.rect.top >= rowBottom) {
      rowBottom = text.rect.bottom;
      rowBaseline = text.baseline;
    }
    expect(text.baseline, rowBaseline);
  }
}
