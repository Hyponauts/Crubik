import 'dart:math' as math;

import 'package:crubik/features/cube/domain/cube_model.dart';
import 'package:crubik/features/practice/presentation/widgets/cube_3d_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Cube3DGeometry', () {
    test('selects the correct signed layer for every face', () {
      expect(Cube3DGeometry.layerForFace(CubeFace.right), 1);
      expect(Cube3DGeometry.layerForFace(CubeFace.up), 1);
      expect(Cube3DGeometry.layerForFace(CubeFace.front), 1);
      expect(Cube3DGeometry.layerForFace(CubeFace.left), -1);
      expect(Cube3DGeometry.layerForFace(CubeFace.down), -1);
      expect(Cube3DGeometry.layerForFace(CubeFace.back), -1);
    });

    test('uses model-consistent directions for quarter and half turns', () {
      for (final notation in ['R', 'U', 'F']) {
        expect(
          Cube3DGeometry.rotationRadians(CubeMove.parse(notation)),
          closeTo(-math.pi / 2, 1e-9),
          reason: notation,
        );
      }
      for (final notation in ['L', 'D', 'B']) {
        expect(
          Cube3DGeometry.rotationRadians(CubeMove.parse(notation)),
          closeTo(math.pi / 2, 1e-9),
          reason: notation,
        );
      }
      expect(
        Cube3DGeometry.rotationRadians(CubeMove.parse("R'")),
        closeTo(math.pi / 2, 1e-9),
      );
      expect(
        Cube3DGeometry.rotationRadians(CubeMove.parse('L2')).abs(),
        closeTo(math.pi, 1e-9),
      );

      final rotated = Cube3DGeometry.rotatePoint((
        x: 0,
        y: 1,
        z: 1,
      ), CubeMove.parse('R'));
      expect(rotated.x, closeTo(0, 1e-9));
      expect(rotated.y, closeTo(1, 1e-9));
      expect(rotated.z, closeTo(-1, 1e-9));
    });

    test('maps cubie positions to URFDLB sticker indices', () {
      expect(
        Cube3DGeometry.stickerIndexForCubie(CubeFace.front, x: -1, y: 1, z: 1),
        0,
      );
      expect(
        Cube3DGeometry.stickerIndexForCubie(CubeFace.back, x: -1, y: -1, z: -1),
        8,
      );
      expect(
        Cube3DGeometry.stickerIndexForCubie(CubeFace.right, x: 1, y: 1, z: 1),
        0,
      );
      expect(
        Cube3DGeometry.stickerIndexForCubie(CubeFace.left, x: -1, y: -1, z: 1),
        8,
      );
      expect(
        Cube3DGeometry.stickerIndexForCubie(CubeFace.up, x: -1, y: 1, z: -1),
        0,
      );
      expect(
        Cube3DGeometry.stickerIndexForCubie(CubeFace.down, x: 1, y: -1, z: -1),
        8,
      );
    });
  });

  testWidgets('renders stable solved, scrambled, and pointer-directed views', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 360);
    addTearDown(tester.view.reset);

    final solved = CubeState.solved();
    await tester.pumpWidget(_host(state: solved));
    await tester.pump();
    await expectLater(
      find.byKey(const Key('cube-3d-canvas')),
      matchesGoldenFile('goldens/cube_3d_solved.png'),
    );

    final scrambled = CubeState.solved()
      ..applyAll(Scramble.parse("R U F' L2 D B").moves);
    await tester.pumpWidget(_host(state: scrambled));
    await tester.pump();
    await expectLater(
      find.byKey(const Key('cube-3d-canvas')),
      matchesGoldenFile('goldens/cube_3d_scrambled.png'),
    );

    await tester.drag(
      find.byKey(const Key('cube-3d-gesture')),
      const Offset(0, -40),
    );
    await tester.pump();
    await expectLater(
      find.byKey(const Key('cube-3d-canvas')),
      matchesGoldenFile('goldens/cube_3d_dragged_up.png'),
    );

    await tester.drag(
      find.byKey(const Key('cube-3d-gesture')),
      const Offset(65, 0),
    );
    await tester.pump();
    await expectLater(
      find.byKey(const Key('cube-3d-canvas')),
      matchesGoldenFile('goldens/cube_3d_orbited.png'),
    );
  });

  testWidgets('animates one valid move and exposes a mid-turn golden', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 360);
    addTearDown(tester.view.reset);

    final solved = CubeState.solved();
    await tester.pumpWidget(_host(state: solved));
    final turned = solved.copy()..apply(CubeMove.parse('R'));
    await tester.pumpWidget(
      _host(state: turned, lastMove: CubeMove.parse('R'), moveRevision: 1),
    );
    await tester.pump(const Duration(milliseconds: 70));

    expect(tester.hasRunningAnimations, isTrue);
    await expectLater(
      find.byKey(const Key('cube-3d-canvas')),
      matchesGoldenFile('goldens/cube_3d_mid_turn.png'),
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('snaps for reduced motion, state syncs, and move bursts', (
    tester,
  ) async {
    final solved = CubeState.solved();
    final right = solved.copy()..apply(CubeMove.parse('R'));
    await tester.pumpWidget(_host(state: solved, disableAnimations: true));
    await tester.pumpWidget(
      _host(
        state: right,
        lastMove: CubeMove.parse('R'),
        moveRevision: 1,
        disableAnimations: true,
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(_host(state: solved));
    await tester.pumpWidget(_host(state: right));
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(_host(state: solved));
    await tester.pumpWidget(
      _host(state: right, lastMove: CubeMove.parse('R'), moveRevision: 1),
    );
    expect(tester.hasRunningAnimations, isTrue);

    final burst = right.copy()..apply(CubeMove.parse('U'));
    await tester.pumpWidget(
      _host(state: burst, lastMove: CubeMove.parse('U'), moveRevision: 3),
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('camera controls never mutate cube state', (tester) async {
    final state = CubeState.solved()..applyAll(Scramble.parse('R U F').moves);
    final before = state.facelets;
    await tester.pumpWidget(_host(state: state));

    expect(find.bySemanticsLabel('Interactive 3D cube'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('cube-3d-gesture')),
      const Offset(40, 20),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.tap(find.byKey(const Key('cube-3d-reset-view')));
    await tester.pump();

    expect(state.facelets, before);
    expect(tester.takeException(), isNull);
  });
}

Widget _host({
  required CubeState state,
  CubeMove? lastMove,
  int moveRevision = 0,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Material(
        color: const Color(0xFF101316),
        child: Center(
          child: Cube3DView(
            state: state,
            lastMove: lastMove,
            moveRevision: moveRevision,
          ),
        ),
      ),
    ),
  );
}
