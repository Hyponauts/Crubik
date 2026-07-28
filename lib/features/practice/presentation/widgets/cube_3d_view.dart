import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../cube/domain/cube_model.dart';

@visibleForTesting
final class Cube3DGeometry {
  const Cube3DGeometry._();

  static int layerForFace(CubeFace face) => switch (face) {
    CubeFace.right || CubeFace.up || CubeFace.front => 1,
    CubeFace.left || CubeFace.down || CubeFace.back => -1,
  };

  static double rotationRadians(CubeMove move) {
    final signedQuarterTurns = move.turns == 3 ? -1 : move.turns;
    return -layerForFace(move.face) * signedQuarterTurns * math.pi / 2;
  }

  static int stickerIndexForCubie(
    CubeFace face, {
    required int x,
    required int y,
    required int z,
  }) => switch (face) {
    CubeFace.front => (1 - y) * 3 + (x + 1),
    CubeFace.back => (1 - y) * 3 + (1 - x),
    CubeFace.right => (1 - y) * 3 + (1 - z),
    CubeFace.left => (1 - y) * 3 + (z + 1),
    CubeFace.up => (z + 1) * 3 + (x + 1),
    CubeFace.down => (1 - z) * 3 + (x + 1),
  };

  static ({double x, double y, double z}) rotatePoint(
    ({double x, double y, double z}) point,
    CubeMove move, {
    double progress = 1,
  }) {
    final rotated = _rotateAroundAxis(
      _Vec3(point.x, point.y, point.z),
      move.axis,
      rotationRadians(move) * progress,
    );
    return (x: rotated.x, y: rotated.y, z: rotated.z);
  }
}

class Cube3DView extends StatefulWidget {
  const Cube3DView({
    required this.state,
    required this.moveRevision,
    super.key,
    this.lastMove,
    this.dimension = 280,
  });

  final CubeState state;
  final CubeMove? lastMove;
  final int moveRevision;
  final double dimension;

  @override
  State<Cube3DView> createState() => _Cube3DViewState();
}

class _Cube3DViewState extends State<Cube3DView>
    with SingleTickerProviderStateMixin {
  static const _initialYaw = -math.pi / 5;
  static const _initialPitch = math.pi / 8;
  static const _cameraStep = math.pi / 24;
  static const _maximumPitch = math.pi * 0.42;

  late final AnimationController _turnController;
  late final FocusNode _focusNode;
  late CubeState _animationStartState;
  late CubeState _targetState;
  late int _handledMoveRevision;
  CubeMove? _activeMove;
  double _yaw = _initialYaw;
  double _pitch = _initialPitch;

  bool get _animationsDisabled =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _turnController = AnimationController(vsync: this)
      ..addStatusListener(_handleAnimationStatus);
    _focusNode = FocusNode(debugLabel: '3D cube view');
    _targetState = widget.state.copy();
    _animationStartState = _targetState.copy();
    _handledMoveRevision = widget.moveRevision;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animationsDisabled && _activeMove != null) {
      _snapTo(_targetState);
    }
  }

  @override
  void didUpdateWidget(Cube3DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextState = widget.state.copy();
    final stateChanged = nextState.facelets != _targetState.facelets;
    final revisionDelta = widget.moveRevision - _handledMoveRevision;

    if (!stateChanged) {
      _handledMoveRevision = widget.moveRevision;
      return;
    }

    final move = widget.lastMove;
    final expectedState = _targetState.copy();
    if (move != null) expectedState.apply(move);
    final canAnimate =
        !_animationsDisabled &&
        revisionDelta == 1 &&
        move != null &&
        expectedState.facelets == nextState.facelets;

    _handledMoveRevision = widget.moveRevision;
    if (!canAnimate) {
      _snapTo(nextState);
      return;
    }

    _turnController.stop();
    _animationStartState = _targetState.copy();
    _targetState = nextState;
    _activeMove = move;
    _turnController.duration = Duration(
      milliseconds: move.turns == 2 ? 190 : 140,
    );
    _turnController.forward(from: 0);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _activeMove = null;
      _animationStartState = _targetState.copy();
    });
  }

  void _snapTo(CubeState state) {
    _turnController.stop();
    _activeMove = null;
    _targetState = state.copy();
    _animationStartState = _targetState.copy();
  }

  void _orbit(Offset delta) {
    setState(() {
      _yaw += delta.dx * 0.009;
      _pitch = (_pitch + delta.dy * 0.009).clamp(-_maximumPitch, _maximumPitch);
    });
  }

  void _rotateCamera({double yaw = 0, double pitch = 0}) {
    setState(() {
      _yaw += yaw;
      _pitch = (_pitch + pitch).clamp(-_maximumPitch, _maximumPitch);
    });
  }

  void _resetCamera() {
    setState(() {
      _yaw = _initialYaw;
      _pitch = _initialPitch;
    });
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _turnController
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Interactive 3D cube',
      hint: 'Drag to orbit. Use arrow keys when focused.',
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _rotateCamera(yaw: -_cameraStep),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _rotateCamera(yaw: _cameraStep),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              _rotateCamera(pitch: -_cameraStep),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              _rotateCamera(pitch: _cameraStep),
          const SingleActivator(LogicalKeyboardKey.home): _resetCamera,
        },
        child: Focus(
          focusNode: _focusNode,
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: GestureDetector(
              key: const Key('cube-3d-gesture'),
              behavior: HitTestBehavior.opaque,
              onTap: _focusNode.requestFocus,
              onPanStart: (_) => _focusNode.requestFocus(),
              onPanUpdate: (details) => _orbit(details.delta),
              child: SizedBox.square(
                dimension: widget.dimension,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        key: const Key('cube-3d-canvas'),
                        child: AnimatedBuilder(
                          animation: _turnController,
                          builder: (context, _) {
                            final move = _activeMove;
                            final progress = move == null
                                ? 1.0
                                : Curves.easeOutCubic.transform(
                                    _turnController.value,
                                  );
                            return CustomPaint(
                              painter: _Cube3DPainter(
                                state: move == null
                                    ? _targetState
                                    : _animationStartState,
                                yaw: _yaw,
                                pitch: _pitch,
                                activeMove: move,
                                turnProgress: progress,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: IconButton(
                        key: const Key('cube-3d-reset-view'),
                        onPressed: _resetCamera,
                        icon: const Icon(Icons.center_focus_strong, size: 18),
                        tooltip: 'Reset cube view',
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cube3DPainter extends CustomPainter {
  const _Cube3DPainter({
    required this.state,
    required this.yaw,
    required this.pitch,
    required this.activeMove,
    required this.turnProgress,
  });

  static const _cubeletHalfSize = 0.46;
  static const _stickerOffset = 0.472;
  static const _stickerHalfSize = 0.375;
  static const _cameraDistance = 6.8;
  // Signed camera-space components point the light left, up, and toward the
  // viewer; the negative x component is intentional direction, not a color.
  static const _lightDirection = _Vec3(-0.32, 0.68, 0.66);
  static const _cubeletShadowColor = Color(0xFF090B0D);
  static const _cubeletHighlightColor = Color(0xFF292F33);
  static const _cubeletAmbientMix = 0.35;
  static const _cubeletDiffuseMix = 0.5;
  static const _stickerAmbientLightnessScale = 0.76;
  static const _stickerDiffuseLightnessScale = 0.28;
  static const _faceNormals = [
    _Vec3(1, 0, 0),
    _Vec3(-1, 0, 0),
    _Vec3(0, 1, 0),
    _Vec3(0, -1, 0),
    _Vec3(0, 0, 1),
    _Vec3(0, 0, -1),
  ];

  final CubeState state;
  final double yaw;
  final double pitch;
  final CubeMove? activeMove;
  final double turnProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final polygons = <_ProjectedPolygon>[];
    final focalLength = size.shortestSide * 1.45;
    final center = Offset(size.width / 2, size.height / 2);

    for (var x = -1; x <= 1; x++) {
      for (var y = -1; y <= 1; y++) {
        for (var z = -1; z <= 1; z++) {
          final cubieCenter = _Vec3(x.toDouble(), y.toDouble(), z.toDouble());
          final turnCubie = _isInTurningLayer(x, y, z);
          for (final normal in _faceNormals) {
            final face = _outerFace(normal, x, y, z);
            if (face != null || turnCubie) {
              _addPolygon(
                polygons,
                center: cubieCenter + normal * _cubeletHalfSize,
                normal: normal,
                halfSize: _cubeletHalfSize,
                color: const Color(0xFF15191C),
                isSticker: false,
                turnCubie: turnCubie,
                focalLength: focalLength,
                projectionCenter: center,
              );
            }
            if (face == null) continue;
            final index = Cube3DGeometry.stickerIndexForCubie(
              face,
              x: x,
              y: y,
              z: z,
            );
            _addPolygon(
              polygons,
              center: cubieCenter + normal * _stickerOffset,
              normal: normal,
              halfSize: _stickerHalfSize,
              color: _stickerColor(state.colorsFor(face)[index]),
              isSticker: true,
              turnCubie: turnCubie,
              focalLength: focalLength,
              projectionCenter: center,
            );
          }
        }
      }
    }

    polygons.sort((a, b) => a.depth.compareTo(b.depth));
    final scale = size.shortestSide / 280;
    for (final polygon in polygons) {
      final path = Path()
        ..moveTo(polygon.points.first.dx, polygon.points.first.dy);
      for (final point in polygon.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = polygon.color
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF07090A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (polygon.isSticker ? 1.5 : 0.65) * scale
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  bool _isInTurningLayer(int x, int y, int z) {
    final move = activeMove;
    if (move == null) return false;
    final coordinate = switch (move.axis) {
      CubeAxis.x => x,
      CubeAxis.y => y,
      CubeAxis.z => z,
    };
    return coordinate == Cube3DGeometry.layerForFace(move.face);
  }

  void _addPolygon(
    List<_ProjectedPolygon> polygons, {
    required _Vec3 center,
    required _Vec3 normal,
    required double halfSize,
    required Color color,
    required bool isSticker,
    required bool turnCubie,
    required double focalLength,
    required Offset projectionCenter,
  }) {
    final (u, v) = _basisFor(normal);
    var vertices = [
      center - u * halfSize - v * halfSize,
      center + u * halfSize - v * halfSize,
      center + u * halfSize + v * halfSize,
      center - u * halfSize + v * halfSize,
    ];
    var transformedNormal = normal;

    if (turnCubie) {
      final move = activeMove!;
      final angle = Cube3DGeometry.rotationRadians(move) * turnProgress;
      vertices = [
        for (final vertex in vertices)
          _rotateAroundAxis(vertex, move.axis, angle),
      ];
      transformedNormal = _rotateAroundAxis(normal, move.axis, angle);
    }

    vertices = [for (final vertex in vertices) _toCamera(vertex)];
    transformedNormal = _toCameraNormal(transformedNormal);
    if (transformedNormal.z <= 0.015) return;

    final points = [
      for (final vertex in vertices)
        _project(vertex, focalLength, projectionCenter),
    ];
    final depth =
        vertices.fold<double>(0, (sum, vertex) => sum + vertex.z) /
        vertices.length;
    polygons.add(
      _ProjectedPolygon(
        points: points,
        depth: depth,
        color: _litColor(color, transformedNormal, isSticker),
        isSticker: isSticker,
      ),
    );
  }

  _Vec3 _toCamera(_Vec3 point) =>
      _rotateAroundX(_rotateAroundY(point, yaw), pitch);

  _Vec3 _toCameraNormal(_Vec3 normal) =>
      _rotateAroundX(_rotateAroundY(normal, yaw), pitch);

  Offset _project(_Vec3 point, double focalLength, Offset center) {
    final perspective = focalLength / (_cameraDistance - point.z);
    return Offset(
      center.dx + point.x * perspective,
      center.dy - point.y * perspective,
    );
  }

  static (_Vec3, _Vec3) _basisFor(_Vec3 normal) {
    if (normal.x != 0) {
      return (const _Vec3(0, 1, 0), const _Vec3(0, 0, 1));
    }
    if (normal.y != 0) {
      return (const _Vec3(1, 0, 0), const _Vec3(0, 0, 1));
    }
    return (const _Vec3(1, 0, 0), const _Vec3(0, 1, 0));
  }

  static CubeFace? _outerFace(_Vec3 normal, int x, int y, int z) {
    if (normal.x == 1 && x == 1) return CubeFace.right;
    if (normal.x == -1 && x == -1) return CubeFace.left;
    if (normal.y == 1 && y == 1) return CubeFace.up;
    if (normal.y == -1 && y == -1) return CubeFace.down;
    if (normal.z == 1 && z == 1) return CubeFace.front;
    if (normal.z == -1 && z == -1) return CubeFace.back;
    return null;
  }

  static Color _litColor(Color color, _Vec3 normal, bool isSticker) {
    final brightness = math.max(0.0, normal.dot(_lightDirection));
    if (!isSticker) {
      return Color.lerp(
        _cubeletShadowColor,
        _cubeletHighlightColor,
        _cubeletAmbientMix + brightness * _cubeletDiffuseMix,
      )!;
    }
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness(
          (hsl.lightness *
                  (_stickerAmbientLightnessScale +
                      brightness * _stickerDiffuseLightnessScale))
              .clamp(0.0, 1.0),
        )
        .toColor();
  }

  static Color _stickerColor(StickerColor color) => switch (color) {
    StickerColor.white => const Color(0xFFF2F3E9),
    StickerColor.red => const Color(0xFFFF4D5F),
    StickerColor.green => const Color(0xFF52D273),
    StickerColor.yellow => const Color(0xFFFFD83D),
    StickerColor.orange => const Color(0xFFFF8A3D),
    StickerColor.blue => const Color(0xFF4C88FF),
  };

  @override
  bool shouldRepaint(_Cube3DPainter oldDelegate) {
    return state.facelets != oldDelegate.state.facelets ||
        yaw != oldDelegate.yaw ||
        pitch != oldDelegate.pitch ||
        activeMove != oldDelegate.activeMove ||
        turnProgress != oldDelegate.turnProgress;
  }
}

final class _ProjectedPolygon {
  const _ProjectedPolygon({
    required this.points,
    required this.depth,
    required this.color,
    required this.isSticker,
  });

  final List<Offset> points;
  final double depth;
  final Color color;
  final bool isSticker;
}

final class _Vec3 {
  const _Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  _Vec3 operator +(_Vec3 other) => _Vec3(x + other.x, y + other.y, z + other.z);

  _Vec3 operator -(_Vec3 other) => _Vec3(x - other.x, y - other.y, z - other.z);

  _Vec3 operator *(double factor) => _Vec3(x * factor, y * factor, z * factor);

  double dot(_Vec3 other) => x * other.x + y * other.y + z * other.z;
}

_Vec3 _rotateAroundAxis(_Vec3 point, CubeAxis axis, double angle) =>
    switch (axis) {
      CubeAxis.x => _rotateAroundX(point, angle),
      CubeAxis.y => _rotateAroundY(point, angle),
      CubeAxis.z => _rotateAroundZ(point, angle),
    };

_Vec3 _rotateAroundX(_Vec3 point, double angle) {
  final cosine = math.cos(angle);
  final sine = math.sin(angle);
  return _Vec3(
    point.x,
    point.y * cosine - point.z * sine,
    point.y * sine + point.z * cosine,
  );
}

_Vec3 _rotateAroundY(_Vec3 point, double angle) {
  final cosine = math.cos(angle);
  final sine = math.sin(angle);
  return _Vec3(
    point.x * cosine + point.z * sine,
    point.y,
    -point.x * sine + point.z * cosine,
  );
}

_Vec3 _rotateAroundZ(_Vec3 point, double angle) {
  final cosine = math.cos(angle);
  final sine = math.sin(angle);
  return _Vec3(
    point.x * cosine - point.y * sine,
    point.x * sine + point.y * cosine,
    point.z,
  );
}
